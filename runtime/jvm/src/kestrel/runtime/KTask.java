package kestrel.runtime;

import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CancellationException;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutionException;

/**
 * Runtime representation of Task<T> on the JVM.
 *
 * S01-01 supports completed tasks only; suspension for incomplete tasks is
 * introduced in S01-02.
 */
public final class KTask {
    private final CompletableFuture<Object> future;

    /** Maximum unwrapping depth in unwrapFailure() — prevents infinite loops on pathological chains. */
    private static final int MAX_UNWRAP_DEPTH = 64;

    private KTask(CompletableFuture<Object> future) {
        this.future = future;
    }

    public static KTask completed(Object value) {
        return new KTask(CompletableFuture.completedFuture(value));
    }

    static KTask fromFuture(CompletableFuture<Object> future) {
        return new KTask(future);
    }

    static Throwable unwrapFailure(Throwable failure) {
        Throwable current = failure;
        int depth = 0;
        while (current != null && depth < MAX_UNWRAP_DEPTH) {
            if ((current instanceof ExecutionException || current instanceof CompletionException || current instanceof InvocationTargetException) && current.getCause() != null) {
                current = current.getCause();
                depth++;
                continue;
            }
            if (current.getClass().equals(RuntimeException.class) && current.getCause() != null) {
                current = current.getCause();
                depth++;
                continue;
            }
            return current;
        }
        return current != null ? current : new RuntimeException("Unknown async task failure");
    }

    public Object get() {
        try {
            return future.get();
        } catch (CancellationException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Interrupted while awaiting task", e);
        } catch (ExecutionException e) {
            Throwable failure = unwrapFailure(e.getCause());
            if (failure instanceof RuntimeException) {
                throw (RuntimeException) failure;
            }
            if (failure instanceof Error) {
                throw (Error) failure;
            }
            throw new KException(failure);
        }
    }

    /**
     * Task.cancel: request cancellation of the underlying future.
     * Calls CompletableFuture.cancel(true) — best-effort I/O interruption.
     * Cancelling an already-completed task is a no-op.
     */
    public static void cancel(Object taskObj) {
        KTask task = (KTask) taskObj;
        task.future.cancel(true);
    }

    /**
     * Task.map: transform the result of a task without blocking.
     * Returns a new Task&lt;B&gt; that applies f when the source task completes.
     * Cancelling the returned task also cancels the source task, so that
     * any underlying resource (e.g. an OS process) is released promptly.
     */
    public static KTask taskMap(Object taskObj, Object fn) {
        KTask source = (KTask) taskObj;
        KFunction f = (KFunction) fn;
        // Subclass to propagate cancel() back to the source future.
        CompletableFuture<Object> mapped = new CompletableFuture<>() {
            @Override
            public boolean cancel(boolean mayInterruptIfRunning) {
                source.future.cancel(mayInterruptIfRunning);
                return super.cancel(mayInterruptIfRunning);
            }
        };
        source.future.whenComplete((v, ex) -> {
            if (ex != null) {
                mapped.completeExceptionally(ex);
            } else {
                try {
                    mapped.complete(f.apply(new Object[]{v}));
                } catch (Throwable t) {
                    mapped.completeExceptionally(t);
                }
            }
        });
        return new KTask(mapped);
    }

    /**
     * Task.all: wait for all tasks in a List&lt;Task&lt;T&gt;&gt; to complete.
     * Returns Task&lt;List&lt;T&gt;&gt;. Fails fast if any task fails.
     */
    @SuppressWarnings("unchecked")
    public static KTask taskAll(Object listObj) {
        List<KTask> tasks = new ArrayList<>();
        Object current = listObj;
        while (current instanceof KCons) {
            KCons cons = (KCons) current;
            tasks.add((KTask) cons.head);
            current = cons.tail;
        }
        if (tasks.isEmpty()) {
            return KTask.completed(KNil.INSTANCE);
        }
        CompletableFuture<Object>[] futures = tasks.stream()
            .map(t -> t.future)
            .toArray(CompletableFuture[]::new);
        final List<KTask> tasksCopy = tasks;
        CompletableFuture<Object> combined = CompletableFuture.allOf(futures)
            .thenApply(ignored -> {
                KList list = KNil.INSTANCE;
                for (int i = tasksCopy.size() - 1; i >= 0; i--) {
                    list = new KCons(tasksCopy.get(i).future.join(), list);
                }
                return (Object) list;
            });
        return new KTask(combined);
    }

    /**
     * Task.race: return the result of the first task in a List&lt;Task&lt;T&gt;&gt; to complete.
     * Losing tasks are cancelled after the winner completes.
     */
    @SuppressWarnings("unchecked")
    public static KTask taskRace(Object listObj) {
        List<KTask> tasks = new ArrayList<>();
        Object current = listObj;
        while (current instanceof KCons) {
            KCons cons = (KCons) current;
            tasks.add((KTask) cons.head);
            current = cons.tail;
        }
        if (tasks.isEmpty()) {
            CompletableFuture<Object> failed = new CompletableFuture<>();
            failed.completeExceptionally(new KException("no tasks provided"));
            return new KTask(failed);
        }
        CompletableFuture<Object>[] futures = tasks.stream()
            .map(t -> t.future)
            .toArray(CompletableFuture[]::new);
        final List<KTask> tasksCopy = tasks;
        CompletableFuture<Object> winner = CompletableFuture.anyOf(futures);
        winner.thenRun(() -> {
            for (KTask t : tasksCopy) {
                if (!t.future.isDone()) {
                    t.future.cancel(true);
                }
            }
        });
        return new KTask(winner);
    }
}
