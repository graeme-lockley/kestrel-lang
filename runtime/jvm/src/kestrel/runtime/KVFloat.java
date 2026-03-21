package kestrel.runtime;

public final class KVFloat extends KValue {
    public final double value;

    public KVFloat(double value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 3;
    }

    @Override
    public Object[] payload() {
        return new Object[] { Double.valueOf(value) };
    }
}
