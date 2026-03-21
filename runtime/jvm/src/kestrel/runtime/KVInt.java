package kestrel.runtime;

public final class KVInt extends KValue {
    public final long value;

    public KVInt(long value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 2;
    }

    @Override
    public Object[] payload() {
        return new Object[] { Long.valueOf(value) };
    }
}
