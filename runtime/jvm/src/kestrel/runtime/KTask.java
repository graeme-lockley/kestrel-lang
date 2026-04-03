package kestrel.runtime;

import java.lang.reflect.InvocationTargetException;
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
        while (current != null) {
            if ((current instanceof ExecutionException || current instanceof CompletionException || current instanceof InvocationTargetException) && current.getCause() != null) {
                current = current.getCause();
                continue;
            }
            if (current.getClass().equals(RuntimeException.class) && current.getCause() != null) {
                current = current.getCause();
                continue;
            }
            return current;
        }
        return new RuntimeException("Unknown async task failure");
    }

    public Object get() {
        try {
            return future.get();
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
            throw new RuntimeException(failure);
        }
    }
}
