// kestrel:string — length, slice, indexOf, equals, toUpperCase per spec 02 (VM string primitives).
export fun length(s: String): Int = __string_length(s)
export fun slice(s: String, start: Int, end: Int): String = __string_slice(s, start, end)
export fun indexOf(s: String, sub: String): Int = __string_index_of(s, sub)
export fun equals(a: String, b: String): Bool = __string_equals(a, b)
export fun toUpperCase(s: String): String = __string_upper(s)
