package kestrel.runtime;

import java.util.concurrent.CompletableFuture;

/**
 * Runtime representation of Task<T> on the JVM.
 *
 * S01-01 supports completed tasks only; suspension for incomplete tasks is
 * introduced in S01-02.
 */
public final class KTask {
    private final CompletableFuture<Object> future;

    private KTask(CompletableFuture<Object> future) {
        this.future = future;
    }

    public static KTask completed(Object value) {
        return new KTask(CompletableFuture.completedFuture(value));
    }

    public Object get() {
        if (future.isDone()) {
            return future.join();
        }
        throw new RuntimeException("TODO: virtual thread suspension (S01-02)");
    }
}
