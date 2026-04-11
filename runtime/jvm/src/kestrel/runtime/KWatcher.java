package kestrel.runtime;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

import static java.nio.file.StandardWatchEventKinds.*;

/**
 * Wraps a {@link WatchService} with debouncing and recursive directory registration.
 * Consumed by {@link KRuntime#watchDirAsync}, {@link KRuntime#watcherNextAsync}, and
 * {@link KRuntime#watcherCloseAsync}.
 */
public final class KWatcher {

    private final WatchService watchService;
    private final int debounceMs;
    private final AtomicBoolean closed = new AtomicBoolean(false);

    // Maps WatchKey -> directory Path so we can reconstruct full paths.
    private final Map<WatchKey, Path> keyToDir = new ConcurrentHashMap<>();

    // Queue of debounced batches delivered to watcherNext callers.
    private final BlockingQueue<List<String>> batches = new LinkedBlockingQueue<>();

    // Background collector thread.
    private final Thread collectorThread;

    private KWatcher(WatchService watchService, int debounceMs) throws IOException {
        this.watchService = watchService;
        this.debounceMs = debounceMs;
        this.collectorThread = Thread.ofVirtual().start(this::collect);
    }

    /**
     * Create a watcher on {@code root}. Returns {@code null} if the path does not exist
     * (callers should return {@code Err("not_found")} in that case).
     */
    public static KWatcher create(String root, int debounceMs) throws IOException {
        Path dir = Paths.get(root);
        if (!Files.isDirectory(dir)) {
            return null; // caller maps to Err("not_found")
        }
        WatchService ws = FileSystems.getDefault().newWatchService();
        KWatcher w = new KWatcher(ws, debounceMs);
        w.registerTree(dir);
        return w;
    }

    private void registerTree(Path dir) throws IOException {
        Files.walkFileTree(dir, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult preVisitDirectory(Path d, BasicFileAttributes attrs) throws IOException {
                register(d);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private void register(Path dir) throws IOException {
        WatchKey key = dir.register(watchService, ENTRY_CREATE, ENTRY_MODIFY, ENTRY_DELETE);
        keyToDir.put(key, dir);
    }

    /** Background thread: collect events with debouncing. */
    private void collect() {
        Set<String> pending = new LinkedHashSet<>();
        while (!closed.get()) {
            WatchKey key;
            try {
                // Wait for the first event (blocking).
                key = watchService.take();
            } catch (InterruptedException | ClosedWatchServiceException e) {
                break;
            }
            processKey(key, pending);
            // Debounce: collect additional events for debounceMs.
            long deadline = System.currentTimeMillis() + debounceMs;
            while (true) {
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) break;
                WatchKey extra;
                try {
                    extra = watchService.poll(remaining, TimeUnit.MILLISECONDS);
                } catch (InterruptedException | ClosedWatchServiceException e) {
                    break;
                }
                if (extra == null) break;
                processKey(extra, pending);
            }
            if (!pending.isEmpty()) {
                batches.add(new ArrayList<>(pending));
                pending.clear();
            }
        }
        // Deliver empty sentinel so waiters aren't stuck forever.
        batches.add(Collections.emptyList());
    }

    private void processKey(WatchKey key, Set<String> pending) {
        Path dir = keyToDir.get(key);
        if (dir == null) {
            key.reset();
            return;
        }
        for (WatchEvent<?> event : key.pollEvents()) {
            WatchEvent.Kind<?> kind = event.kind();
            if (kind == OVERFLOW) continue;
            @SuppressWarnings("unchecked")
            WatchEvent<Path> pathEvent = (WatchEvent<Path>) event;
            Path abs = dir.resolve(pathEvent.context());
            pending.add(abs.toString());
            // Auto-register newly created sub-directories.
            if (kind == ENTRY_CREATE && Files.isDirectory(abs)) {
                try {
                    registerTree(abs);
                } catch (IOException ignored) { /* best-effort */ }
            }
        }
        key.reset();
    }

    /**
     * Block until the next batch of events and return their paths.
     * Returns an empty list if the watcher has been closed.
     */
    public List<String> nextBatch() throws InterruptedException {
        return batches.take();
    }

    /** Close the underlying watch service. */
    public void close() {
        if (closed.compareAndSet(false, true)) {
            try { watchService.close(); } catch (IOException ignored) { /* best-effort */ }
            collectorThread.interrupt();
        }
    }
}
