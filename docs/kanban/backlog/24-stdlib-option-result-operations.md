# Stdlib Option and Result Operations Completeness

## Priority: 24 (Medium)

## Summary

The `kestrel:option` and `kestrel:result` modules provide basic helpers (`getOrElse`, `isSome`/`isNone`, `isOk`/`isErr`) but lack the common functional combinators that make these types ergonomic: `map`, `flatMap`, `withDefault`, `toResult`, `fromResult`, etc.

## Current State

- `stdlib/kestrel/option.ks`: `getOrElse(o, default)`, `isNone(o)`, `isSome(o)`.
- `stdlib/kestrel/result.ks`: `getOrElse(r, default)`, `isOk(r)`, `isErr(r)`.
- Tests exist for the current functions.

## Acceptance Criteria

### Option
- [ ] `map(o: Option<T>, f: (T) -> U): Option<U>` -- apply f to Some, pass through None.
- [ ] `flatMap(o: Option<T>, f: (T) -> Option<U>): Option<U>` -- monadic bind.
- [ ] `orElse(o: Option<T>, alternative: Option<T>): Option<T>` -- return o if Some, else alternative.
- [ ] `toResult(o: Option<T>, err: E): Result<T, E>` -- convert Some to Ok, None to Err(err).

### Result
- [ ] `map(r: Result<T, E>, f: (T) -> U): Result<U, E>` -- apply f to Ok, pass through Err.
- [ ] `flatMap(r: Result<T, E>, f: (T) -> Result<U, E>): Result<U, E>` -- monadic bind.
- [ ] `mapErr(r: Result<T, E>, f: (E) -> F): Result<T, F>` -- transform the error.
- [ ] `toOption(r: Result<T, E>): Option<T>` -- Ok to Some, Err to None.

- [ ] Kestrel tests for each new function.

## Spec References

- 02-stdlib (Option, Result: constructors and functions are implementation-defined)
