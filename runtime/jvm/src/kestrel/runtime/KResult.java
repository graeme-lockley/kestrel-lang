package kestrel.runtime;

/** Kestrel Result ADT — Err(value) | Ok(value). */
public abstract class KResult extends KAdt {
    @Override
    public abstract int tag();
}
