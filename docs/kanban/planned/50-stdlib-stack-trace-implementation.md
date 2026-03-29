# Stdlib kestrel:stack trace() Implementation

## Sequence: 50
## Tier: 4 — Stdlib and test harness
## Former ID: 17

## Summary

The `kestrel:stack` module provides `format()` and `print()` but `trace()` is deferred. Spec 02 requires `trace(T) -> StackTrace<T>` which captures a stack trace for a thrown value. This requires a VM primitive (`__capture_trace`) and a `StackTrace<T>` type definition.

## Current State

- `stdlib/kestrel/stack.ks` exports `format()` (via `__format_one`) and `print()` (via `__print_one`).
- `trace()` is not implemented — no VM primitive, no `StackTrace` type.
- The bytecode debug section (see completed work in `docs/kanban/done/`) provides code-offset-to-line mapping; stack traces should use it where available.
- The VM already walks `call_frames` and uses `lookupDebugLine` for uncaught exceptions (`printUncaughtException` in `vm/src/exec.zig`); `CallFrame` currently stores `pc`, `module`, `saved_sp`, and `discard_return` — no function-name field.

## Relationship to other stories

- **Follows** `docs/kanban/done/46-stdlib-stack-implementation.md` (format/print shipped; trace explicitly deferred).
- **Independent of** later roadmap items (51–64); no hard ordering dependency beyond normal stdlib/compiler/VM sequencing.
- **May reuse patterns from** existing E2E negative coverage (`tests/e2e/scenarios/negative/uncaught_exception.ks`) for stderr stack traces; this story adds **caught** exception + programmatic `trace()` verification.

## Goals

1. Deliver **`trace(value)`** on `kestrel:stack` per `docs/specs/02-stdlib.md`, returning a **`StackTrace<T>`** that pairs the thrown value with a structured list of frames.
2. Implement **`__capture_trace`** (or agreed name) in the **reference VM** so capture uses the **same frame walk and debug mapping** as uncaught-exception reporting where the debug section is present.
3. Provide **human-readable** output via **`format`** on the trace (extend existing `format` polymorphism, or add `formatTrace` / overload — resolved during implementation to match spec wording).
4. Keep **JVM backend** behaviour aligned with the VM for programs that use `kestrel:stack` (parity for `trace` / formatting).

## Acceptance Criteria

- [ ] Define `StackTrace<T>` type (ADT or record) in the stdlib — e.g. `{ value: T, frames: List<{ file: String, line: Int, function: String }> }`.
- [ ] Implement `__capture_trace` VM primitive that captures the current call stack (using debug section data if available).
- [ ] `trace(value)` in `stack.ks` calls the primitive and returns a `StackTrace`.
- [ ] `format(trace)` or a `formatTrace` function produces a human-readable stack trace string.
- [ ] E2E test: throw an exception, catch it, call `trace()`, verify it contains frame information.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:stack`: `trace(T) -> StackTrace<T>`, `StackTrace<T>` in standard types
- `docs/specs/05-runtime-model.md` §5 — Stack traces: runtime / `trace`, debug section mapping
- `docs/specs/03-bytecode-format.md` §8 — Debug section maps code offsets to file/line
- `docs/specs/04-bytecode-isa.md` §7 — Built-in primitive `CALL` ids (`0xFFFFFF00` range); new id must be documented and kept in sync with VM / JVM

## Risks / Notes

- **Function names in frames:** `CallFrame` does not currently carry a function name; spec 05 allows (file, line) or (module, function, offset). Until the loader exposes per-frame function symbols, **`function` may be a placeholder** (e.g. empty string or `"<unknown>"`) while **file/line** come from the debug section — document the choice in spec 02/05 if it diverges from the table in acceptance.
- **Value representation:** The primitive must build heap values (record/list/ADT) that **GC can trace**; avoid dangling pointers when the exception value is stored inside `StackTrace`.
- **Generics:** `StackTrace<T>` and `__capture_trace` need a **sound prelude typing** in `compiler/src/typecheck/check.ts` (similar to `__format_one` / `__print_one`).
- **Primitive ID:** Next free host id after `0xFFFFFF26` is **`0xFFFFFF27`** (extend the inclusive range in VM dispatch, `vm_bytecode_tests.zig` if applicable, and spec 04 §7).
- **JVM:** Add a `KRuntime` (or equivalent) path mirroring VM capture + formatting expectations; JVM tests if the project covers stack intrinsics there.

## Impact analysis

| Area | What changes |
|------|----------------|
| **Stdlib** | `stdlib/kestrel/stack.ks`: define `StackTrace` shape, export `trace`, optional `formatTrace` / extend `format` usage; update `stdlib/kestrel/stack.test.ks`. |
| **VM** | `vm/src/exec.zig`: extend primitive id range; implement capture (reuse `lookupDebugLine` / frame walk logic shared with `printUncaughtException` where possible). `vm/src/primitives.zig` (or adjacent): allocate/list/record values for frames + paired value. |
| **Compiler typecheck** | `compiler/src/typecheck/check.ts`: prelude entries for `__capture_trace` and possibly `StackTrace` if the typechecker must know the shape for `format`/`trace` clients. |
| **Compiler codegen** | `compiler/src/codegen/codegen.ts`: emit `CALL` with new primitive id for `__capture_trace` (arity 1: exception value). |
| **Compiler JVM** | `compiler/src/jvm-codegen/codegen.ts`: map `__capture_trace` to runtime helper(s) consistent with VM semantics. |
| **Specs** | `02-stdlib.md`: nail down `StackTrace` field meanings and `format` behaviour for traces; `04-bytecode-isa.md` §7: new row for `__capture_trace`; `05-runtime-model.md` §5: clarify placeholder `function` if used. |
| **Tests** | `tests/unit` / E2E: new `.ks` coverage; Zig tests if bytecode or dispatch changes require hand-crafted opcodes. |
| **Rollback** | Revert primitive + prelude + stdlib; old programs without `trace` remain valid. |

## Tasks

- [ ] **Spec alignment:** Update `docs/specs/02-stdlib.md` (and `05-runtime-model.md` / `04-bytecode-isa.md` as needed) so `StackTrace<T>`, frame fields, and `format(trace)` behaviour are unambiguous before or alongside code.
- [ ] **VM:** Implement `__capture_trace` at new primitive id (`0xFFFFFF27`): pop arity-1 argument, push a `StackTrace`-compatible heap value built from current `frame_sp`, `call_frames`, `current_module`, and `instr_pc` semantics consistent with “current stack at call site”.
- [ ] **VM:** Extend primitive dispatch upper bound from `0xFFFFFF26` to `0xFFFFFF27`; keep `operandStackOverflowReport` / error paths consistent.
- [ ] **Stdlib:** Define `StackTrace<T>` (record or ADT) and `trace(value)` calling `__capture_trace`; implement string formatting for traces (via `format` extension or dedicated function).
- [ ] **Compiler:** Add `__capture_trace` to prelude with correct polymorphic type; add codegen lowering in `codegen.ts`.
- [ ] **JVM:** Implement capture/format parity in JVM backend and any `KRuntime` helpers.
- [ ] **Tests:** Add/update unit tests per **Tests to add**; run full verification (compiler, VM, `./scripts/kestrel test`, E2E if touched).

## Tests to add

| Layer | Intent |
|-------|--------|
| **`stdlib/kestrel/stack.test.ks`** | `trace` after a caught throw: assert non-empty frame list when debug info exists; assert `format`/`formatTrace` output contains expected file substring or line-like content for a known throw site. |
| **`tests/unit/*.test.ks`** | If clearer in isolation: minimal module with nested calls + `try`/`catch` + `kestrel:stack` `trace` (avoid duplicating stdlib tests unnecessarily). |
| **`compiler/test/` (Vitest)** | If typecheck or codegen gains branches: tests for `__capture_trace` typing and/or emitted primitive id. |
| **`vm/` (`zig build test`)** | If hand-crafted bytecode tests cover primitive table: add case for `0xFFFFFF27` or integration test for capture shape. |
| **E2E** | New or extended scenario: catch exception, call `trace()`, assert observable frame data (matches acceptance). |

## Documentation and specs to update

- `docs/specs/02-stdlib.md` — `kestrel:stack`, `StackTrace<T>` definition, `trace`, formatting rules
- `docs/specs/04-bytecode-isa.md` §7 — new primitive id and arity/semantics for `__capture_trace`
- `docs/specs/05-runtime-model.md` §5 — stack trace capture / `trace` wording if implementation uses placeholder function names
- `docs/IMPLEMENTATION_PLAN.md` — if it still lists `__capture_trace` as future-only; align with shipped behaviour

## Notes

- Prefer **sharing** debug lookup and frame iteration with `printUncaughtException` via extracted helpers in `exec.zig` to avoid drift between stderr traces and `StackTrace` contents.
- Confirm **order** of frames (innermost-first vs outermost-first) in spec and tests; match uncaught stderr order for user familiarity.
