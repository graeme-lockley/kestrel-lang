package kestrel.runtime;

import java.util.Map;

public final class KVObject extends KValue {
    public final Map<String, Object> value;

    public KVObject(Map<String, Object> value) {
        this.value = value;
    }

    @Override
    public int tag() {
        return 6;
    }

    @Override
    public Object[] payload() {
        return new Object[] { value };
    }
}
