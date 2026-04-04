package kestrel.runtime;

/**
 * Kestrel built-in mutable array — contiguous Object[] storage with explicit length and capacity.
 * Used as the runtime representation of Array&lt;T&gt;.
 */
public final class KArray {
    public Object[] elements;
    public int length;
    public int capacity;

    public KArray(int capacity) {
        this.capacity = capacity <= 0 ? 8 : capacity;
        this.elements = new Object[this.capacity];
        this.length = 0;
    }
}
