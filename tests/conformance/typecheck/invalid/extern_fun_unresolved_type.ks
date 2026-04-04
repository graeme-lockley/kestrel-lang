// EXPECT: Unknown type
extern fun bad(x: MissingType): Int = jvm("kestrel.runtime.KRuntime#stringLength(java.lang.Object)")
