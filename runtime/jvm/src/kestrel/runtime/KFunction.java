package kestrel.runtime;

/** Kestrel function reference or closure — call via apply. */
public interface KFunction {
    Object apply(Object[] args);
}
