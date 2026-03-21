package kestrel.runtime;

import java.util.HashMap;
import java.util.Map;

/** Kestrel record — structural record with named fields. */
public class KRecord {
    private final Map<String, Object> fields;

    public KRecord() {
        this.fields = new HashMap<>();
    }

    public KRecord(Map<String, Object> initial) {
        this.fields = new HashMap<>(initial);
    }

    public Object get(String name) {
        return fields.get(name);
    }

    public void set(String name, Object value) {
        fields.put(name, value);
    }

    /** Copy this record and overlay with another (for spread). */
    public KRecord copy() {
        return new KRecord(fields);
    }

    /** Copy this record and put all entries from other, then put overrides. Used for { ...r, x = v }. */
    public static KRecord spread(KRecord base, Map<String, Object> overrides) {
        KRecord r = base.copy();
        if (overrides != null) {
            r.fields.putAll(overrides);
        }
        return r;
    }

    public Map<String, Object> getFields() {
        return fields;
    }
}
