package kestrel.runtime;

/** Kestrel exception — wraps an ADT payload. */
public class KException extends RuntimeException {
    private final Object payload;

    public KException(Object payload) {
        super("Uncaught exception: " + KRuntime.formatOne(payload));
        this.payload = payload;
    }

    public Object getPayload() {
        return payload;
    }
}
