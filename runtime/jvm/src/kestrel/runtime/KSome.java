package kestrel.runtime;

/** Option Some(value). */
public final class KSome extends KOption {
    public final Object value;

    public KSome(Object value) {
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
