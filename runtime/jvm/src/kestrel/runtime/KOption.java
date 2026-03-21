package kestrel.runtime;

/** Kestrel Option ADT — None | Some(value). */
public abstract class KOption extends KAdt {
    @Override
    public abstract int tag();
}
