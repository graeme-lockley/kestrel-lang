package kestrel.runtime;

public final class KVString extends KValue {
    public final String value;

    public KVString(String value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 4;
    }

    @Override
    public Object[] payload() {
        return new Object[] { value };
    }
}
