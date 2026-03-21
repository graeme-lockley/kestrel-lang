package kestrel.runtime;

/** Empty list. */
public final class KNil extends KList {
    public static final KNil INSTANCE = new KNil();

    private KNil() {}

    @Override
    public int tag() {
        return 0;
    }

    @Override
    public String toString() {
        return "[]";
    }
}
