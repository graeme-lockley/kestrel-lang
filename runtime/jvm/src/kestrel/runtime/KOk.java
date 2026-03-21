package kestrel.runtime;

/** Result Ok(value). */
public final class KOk extends KResult {
    public final Object value;

    public KOk(Object value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 1;
    }

    @Override
    public Object[] payload() {
        return new Object[] { value };
    }
}
