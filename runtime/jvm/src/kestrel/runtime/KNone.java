package kestrel.runtime;

/** Option None. */
public final class KNone extends KOption {
    public static final KNone INSTANCE = new KNone();

    private KNone() {}

    @Override
    public int tag() {
        return 0;
    }

    @Override
    public String toString() {
        return "None";
    }
}
