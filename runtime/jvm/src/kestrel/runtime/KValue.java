package kestrel.runtime;

/** Kestrel JSON Value ADT — Null | Bool | Int | Float | String | Array | Object. */
public abstract class KValue extends KAdt {
    @Override
    public abstract int tag();
}
