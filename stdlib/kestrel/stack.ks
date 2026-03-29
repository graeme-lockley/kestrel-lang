// kestrel:stack — format, print (VM primitives); trace via __capture_trace (spec 02).
import * as List from "kestrel:list"

export type StackFrame = { file: String, line: Int, function: String }

export type StackTrace<T> = { value: T, frames: List<StackFrame> }

export fun format(x): String = __format_one(x)
export fun print(x): Unit = __print_one(x)
export fun trace<T>(value: T): StackTrace<T> = __capture_trace(value)
