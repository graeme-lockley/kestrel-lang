package kestrel.runtime;

import java.util.List;

public final class KVArray extends KValue {
    public final List<Object> value;

    public KVArray(List<Object> value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 5;
    }

    @Override
    public Object[] payload() {
        return new Object[] { value };
    }
}
