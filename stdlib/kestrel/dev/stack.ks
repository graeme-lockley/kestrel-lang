//! Runtime formatting and stack-trace capture helpers.
//!
//! Wraps VM/runtime primitives for formatting values, printing, and capturing
//! stack frames for diagnostics and testing.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Stk from "kestrel:dev/stack"
//!
//! val text = Stk.format({ name = "kestrel" })
//! val trace = Stk.trace("boom")
//! Stk.print(text)
//! ```

import * as List from "kestrel:data/list"

export type StackFrame = { file: String, line: Int, function: String }

export type StackTrace<T> = { value: T, frames: List<StackFrame> }

export extern fun format<A>(x: A): String =
  jvm("kestrel.runtime.KRuntime#formatOne(java.lang.Object)")
export extern fun print<A>(x: A): Unit =
  jvm("kestrel.runtime.KRuntime#printOne(java.lang.Object)")
export extern fun trace<T>(value: T): StackTrace<T> =
  jvm("kestrel.runtime.KRuntime#captureTrace(java.lang.Object)")
