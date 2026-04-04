// kestrel:stack — format, print (VM primitives); trace via captureTrace (spec 02).
import * as List from "kestrel:list"

export type StackFrame = { file: String, line: Int, function: String }

export type StackTrace<T> = { value: T, frames: List<StackFrame> }

export extern fun format<A>(x: A): String =
  jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
export extern fun print<A>(x: A): Unit =
  jvm("kestrel.runtime.KRuntime#printOne(java.lang.Object)")
export extern fun trace<T>(value: T): StackTrace<T> =
  jvm("kestrel.runtime.KRuntime#captureTrace(java.lang.Object)")
