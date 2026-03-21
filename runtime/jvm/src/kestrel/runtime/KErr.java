package kestrel.runtime;

/** Result Err(value). */
public final class KErr extends KResult {
    public final Object value;

    public KErr(Object value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 0;
    }

    @Override
    public Object[] payload() {
        return new Object[] { value };
    }
}
