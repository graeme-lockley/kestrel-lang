# Epic E02: JVM Reflection Interop and Intrinsic Migration

## Status

Unplanned

## Summary

Introduce a first-class JVM interop standard library surface that allows Kestrel code to bind and call Java classes, constructors, fields, and methods through a reflection-backed interface, so native Java libraries can be used without adding new compiler/runtime intrinsic functions. This epic also migrates existing `__*` builtins to interop-based stdlib implementations (or generated bindings) while preserving runtime efficiency through caching and low-overhead call paths.

## Implementation Approach

The interop surface should be implemented as a JVM-focused stdlib module plus runtime support for reflective invocation. The design should prioritize hot-path performance: resolve symbols once, cache handles per call shape, avoid repeated reflective lookup, minimize boxing/unboxing churn, and keep marshalling rules explicit and predictable. Where reflection overhead remains non-trivial, the implementation should prefer `MethodHandle`-style cached invocation over repeated `Method.invoke` dispatch. Migration of existing `__*` functions should happen incrementally behind compatibility shims until parity and performance goals are verified.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- Epic E01 async runtime foundation completed and stable (Task semantics and virtual-thread execution are required for async host-library calls).
- JVM-only backend direction remains in force (interop is JVM-host specific).
- Existing stdlib/spec baseline in `docs/specs/02-stdlib.md`, `docs/specs/06-typesystem.md`, and `docs/specs/09-tools.md` available to extend.

## Epic Completion Criteria

- A documented JVM interop stdlib module exists with stable APIs for loading Java classes and invoking constructors, static methods, instance methods, and selected field access patterns.
- Interop invocation has deterministic binding behavior (method overload selection, conversion rules, and runtime errors are defined in specs and covered by tests).
- Existing intrinsic-backed `__*` stdlib operations are migrated to interop-backed implementations (or generated equivalent bindings), with compatibility shims removed or explicitly deprecated.
- Compiler/runtime no longer require adding new hardcoded intrinsic entries for standard host-library integration use cases.
- Performance validation demonstrates no unacceptable overhead versus the previous intrinsic path for representative hot operations, with agreed benchmarks and thresholds recorded in story acceptance criteria.
- Conformance, compiler, stdlib, and E2E test suites pass with the interop path enabled as default.
