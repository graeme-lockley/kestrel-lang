package kestrel.runtime;

public final class KVNull extends KValue {
    public static final KVNull INSTANCE = new KVNull();

    private KVNull() {}

    @Override
    public int tag() {
        return 0;
    }
}
