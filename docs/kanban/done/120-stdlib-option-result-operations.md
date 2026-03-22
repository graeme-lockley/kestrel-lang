# Stdlib Option and Result Operations Completeness

## Priority: 120 (Medium)

## Summary

The `kestrel:option` and `kestrel:result` modules provide basic helpers (`getOrElse`, `isSome`/`isNone`, `isOk`/`isErr`) but lack the common functional combinators that make these types ergonomic: `map`, `flatMap`, `withDefault`, `toResult`, `fromResult`, etc.

## Current State

- `stdlib/kestrel/option.ks`: `getOrElse(o, default)`, `isNone(o)`, `isSome(o)`.
- `stdlib/kestrel/result.ks`: `getOrElse(r, default)`, `isOk(r)`, `isErr(r)`.
- Tests exist for the current functions.

## Acceptance Criteria

### Option
- [x] `map(o: Option<T>, f: (T) -> U): Option<U>` -- apply f to Some, pass through None.
- [x] `andThen(o: Option<T>, f: (T) -> Option<U>): Option<U>` -- monadic bind (spec uses `andThen`).
- [x] `withDefault` -- return o if Some, else default value.
- [x] `map2`–`map5` -- combine multiple Options.

### Result
- [x] `map(r: Result<T, E>, f: (T) -> U): Result<U, E>` -- apply f to Ok, pass through Err.
- [x] `andThen(r: Result<T, E>, f: (T) -> Result<U, E>): Result<U, E>` -- monadic bind.
- [x] `mapError(r: Result<T, E>, f: (E) -> F): Result<T, F>` -- transform the error.
- [x] `toOption(r: Result<T, E>): Option<T>` -- Ok to Some, Err to None.
- [x] `fromOption(o: Option<T>, err: E): Result<T, E>` -- Some to Ok, None to Err.

- [x] Kestrel tests for each function.

## Completion Note

All spec functions for both Option and Result are implemented and tested. The spec uses `andThen` rather than `flatMap`. Moved to done.

## Spec References

- 02-stdlib (Option, Result: constructors and functions are implementation-defined)
