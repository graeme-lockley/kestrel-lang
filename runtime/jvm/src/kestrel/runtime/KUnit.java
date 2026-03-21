package kestrel.runtime;

/** Kestrel Unit value — singleton. */
public final class KUnit {
    public static final KUnit INSTANCE = new KUnit();

    private KUnit() {}

    @Override
    public String toString() {
        return "()";
    }
}
