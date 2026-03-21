package kestrel.runtime;

/** Base for Kestrel ADT values. Subclasses represent constructors. */
public abstract class KAdt {
    /** Constructor tag (0-based). */
    public abstract int tag();

    /** Payload as array (for constructors with fields). Default empty. */
    public Object[] payload() {
        return new Object[0];
    }
}
