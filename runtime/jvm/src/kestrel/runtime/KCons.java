package kestrel.runtime;

/** Cons cell. */
public final class KCons extends KList {
    public final Object head;
    public final KList tail;

    public KCons(Object head, KList tail) {
        this.head = head;
        this.tail = tail;
    }

    @Override
    public int tag() {
        return 1;
    }

    @Override
    public Object[] payload() {
        return new Object[] { head, tail };
    }
}
