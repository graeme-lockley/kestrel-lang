// kestrel:stack — format, print (wrap VM primitives); trace deferred until __capture_trace exists (spec 02).
export fun format(x): String = __format_one(x)
export fun print(x): Unit = __print_one(x)
// trace(T): StackTrace<T> — TODO: requires __capture_trace and StackTrace type
