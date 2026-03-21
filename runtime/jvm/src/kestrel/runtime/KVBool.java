package kestrel.runtime;

public final class KVBool extends KValue {
    public final boolean value;

    public KVBool(boolean value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 1;
    }

    @Override
    public Object[] payload() {
        return new Object[] { Boolean.valueOf(value) };
    }
}
