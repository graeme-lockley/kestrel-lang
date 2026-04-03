// Stress test: module global as only root for a heap value; GC must trace globals (spec 05 §4).
import { Suite, group, eq } from "kestrel:test"

// Only root for this string is the module global; GC must trace globals to keep it alive.
export var globalStr: String = "survived"

fun makeList(n: Int): List<Int> = if (n <= 0) [] else n :: makeList(n - 1)

// Tail-recursive: allocate many lists to exceed GC threshold (~1MB) without stack overflow
fun repeatAlloc(count: Int): Unit = if (count <= 0) () else { val _ = makeList(1000); repeatAlloc(count - 1) }

export async fun run(s: Suite): Task<Unit> =
  group(s, "gc globals", (s1: Suite) => {
    repeatAlloc(35)
    eq(s1, "global unchanged after GC", globalStr, "survived")
  })
