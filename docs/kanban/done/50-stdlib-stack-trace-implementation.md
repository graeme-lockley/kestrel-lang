# Stdlib kestrel:stack trace() Implementation

## Sequence: 50
## Tier: 4 — Stdlib and test harness
## Former ID: 17

## Summary

The `kestrel:stack` module provides `format()` and `print()` but `trace()` is deferred. Spec 02 requires `trace(T) -> StackTrace<T>` which captures a stack trace for a thrown value. This requires a VM primitive (`__capture_trace`) and a `StackTrace<T>` type definition.

## Current State

- **Shipped (2026-03-29):** `stdlib/kestrel/stack.ks` exports `format`, `print`, and **`trace`**; **`StackTrace<T>`** is a record `{ value, frames }`; VM primitive **`__capture_trace`** at **`0xFFFFFF27`**; **`format(trace)`** is multi-line (value then `  at file:line` lines). **`lookupDebugLine`** lives in `vm/src/load.zig` and is shared with uncaught reporting and capture.
- JVM: **`__print_one`** and **`__capture_trace`** lower to **`KRuntime`**; **`stack.test.ks`** passes **`./scripts/kestrel test-both`**.
- `CallFrame` still has no function-name field; frame **`function`** may be a placeholder per spec 05 until symbols exist.

## Relationship to other stories

- **Follows** `docs/kanban/done/46-stdlib-stack-implementation.md` (format/print shipped; trace explicitly deferred).
- **Independent of** later roadmap items (51–64); no hard ordering dependency beyond normal stdlib/compiler/VM sequencing.
- **May reuse patterns from** existing E2E negative coverage (`tests/e2e/scenarios/negative/uncaught_throw.ks`, `E2E_EXPECT_STACK_TRACE`) for stderr stack traces; **caught** exception + programmatic `trace()` should be covered primarily by **`./scripts/kestrel test`** (stdlib / unit harness). Optional **positive** E2E under `tests/e2e/scenarios/positive/` (with `.expected`) also exercises `./scripts/run-e2e.sh` if the team wants that layer.

## Goals

1. Deliver **`trace(value)`** on `kestrel:stack` per `docs/specs/02-stdlib.md`, returning a **`StackTrace<T>`** that pairs the thrown value with a structured list of frames.
2. Implement **`__capture_trace`** (or agreed name) in the **reference VM** so capture uses the **same frame walk and debug mapping** as uncaught-exception reporting where the debug section is present.
3. Provide **human-readable** output via **`format`** on the trace (extend existing `format` polymorphism, or add `formatTrace` / overload — resolved during implementation to match spec wording).
4. Keep **JVM backend** behaviour aligned with the VM for programs that use `kestrel:stack` (parity for `trace`, formatting, and **`print`** lowering).

## Acceptance Criteria

- [x] **Specs/docs:** Every file listed under **Documentation and specs to update** is updated (or explicitly deferred in **Build notes** with a tracked follow-up), and **02 / 04 / 05 / 08** remain mutually consistent on `StackTrace`, frame fields, primitive id, and test expectations.
- [x] Define **`StackTrace<T>`** in the stdlib (ADT or record) — e.g. `{ value: T, frames: List<{ file: String, line: Int, function: String }> }` or the shape finally nailed down in spec 02.
- [x] Implement **`__capture_trace`** VM primitive at **`0xFFFFFF27`**: pop arity-1 argument (the exception/value to pair), push a **`StackTrace`-compatible** heap value built from the **current** call stack at the call site (`frame_sp`, `call_frames`, `current_module`, `instr_pc` / PC semantics), **GC-safe** (all heap parts traced).
- [x] **`trace(value)`** in `stack.ks` calls the primitive and returns `StackTrace<T>`.
- [x] **`format(trace)`** or a dedicated **`formatTrace`** produces a human-readable multi-line (or single-line) string; spec 02 documents which applies.
- [x] **Frame order** matches **uncaught stderr** order (document **innermost-first vs outermost-first** in 02/05 and assert in tests).
- [x] **Debug section absent or sparse:** Frames still form a valid list; **file/line** may be placeholders (e.g. empty or `"?"`) per spec 05; **`function`** may be placeholder until symbols exist (see Risks).
- [x] **Caught exception:** In a `try`/`catch`, `trace(caughtValue)` yields a non-empty **frames** list when `.kbc` is built with debug mapping and nested calls are used; **`.value`** (or equivalent) corresponds to the caught value.
- [x] **Compiler:** Prelude typing for `__capture_trace` (polymorphic like `__format_one` / `__print_one`); **`compiler/src/codegen/codegen.ts`** emits **`CALL`** with **`0xFFFFFF27`** for `__capture_trace`.
- [x] **JVM:** `__capture_trace` maps to **`KRuntime`** (or equivalent) with semantics aligned to VM; **`__print_one`** is lowered so **`kestrel:stack`** compiles on **`--target jvm`**.
- [x] **Verification (per [AGENTS.md](../../../AGENTS.md)):** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `cd vm && zig build test`; **`./scripts/kestrel test-both`** on touched stdlib tests; **`./scripts/run-e2e.sh`** after any E2E scenario or integration-visible behaviour change.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:stack`: `trace(T) -> StackTrace<T>`, `StackTrace<T>` in standard types
- `docs/specs/05-runtime-model.md` §5 — Stack traces: runtime / `trace`, debug section mapping
- `docs/specs/03-bytecode-format.md` §8 — Debug section maps code offsets to file/line (authoritative layout for `lookupDebugLine`)
- `docs/specs/04-bytecode-isa.md` §7 — Built-in primitive `CALL` ids (`0xFFFFFF00` range); new id must be documented and kept in sync with VM / JVM
- `docs/specs/08-tests.md` — Conformance language for exceptions / `Stack.trace` and stdlib test expectations
- `docs/specs/01-language.md` — §4 exception rethrow note points at 02 for stack traces (keep cross-links accurate)

## Risks / Notes

- **Function names in frames:** `CallFrame` does not currently carry a function name; spec 05 allows (file, line) or (module, function, offset). Until the loader exposes per-frame function symbols, **`function` may be a placeholder** (e.g. empty string or `"<unknown>"`) while **file/line** come from the debug section — document the choice in spec 02/05 if it diverges from the table in acceptance.
- **Value representation:** The primitive must build heap values (record/list/ADT) that **GC can trace**; avoid dangling pointers when the exception value is stored inside `StackTrace`.
- **Generics:** `StackTrace<T>` and `__capture_trace` need a **sound prelude typing** in `compiler/src/typecheck/check.ts` (similar to `__format_one` / `__print_one`).
- **Primitive ID:** Next free host id after `0xFFFFFF26` is **`0xFFFFFF27`** (extend the inclusive range in VM dispatch in `vm/src/exec.zig`, and spec 04 §7). Update **`vm_bytecode_tests.zig`** or add a focused Zig test **if** the project introduces or extends hand-checked primitive coverage for this range.
- **JVM:** Add a `KRuntime` path mirroring VM capture + formatting expectations; ensure **`stack.ks`** JVM compilation succeeds (**`__print_one`** + new primitive).
- **E2E vs unit:** `tests/e2e/README.md` currently states E2E is negative-only, but **`scripts/run-e2e.sh`** also runs **positive** scenarios under `tests/e2e/scenarios/positive/`. If this story adds a positive trace scenario, refresh that README to avoid contradicting the harness.

## Impact analysis

| Area | What changes |
|------|----------------|
| **Stdlib** | `stdlib/kestrel/stack.ks`: define `StackTrace` shape, export `trace`, extend `format` (or add `formatTrace`); update `stdlib/kestrel/stack.test.ks`. |
| **VM** | `vm/src/exec.zig`: extend primitive id range to **`0xFFFFFF27`**; implement **`__capture_trace`** (reuse / extract helpers shared with **`printUncaughtException`** / **`lookupDebugLine`**). Heap allocation for frames + value may live in **`vm/src/primitives.zig`** or **`exec.zig`** depending on existing patterns. |
| **Compiler typecheck** | `compiler/src/typecheck/check.ts`: prelude entries for **`__capture_trace`** (and `StackTrace` shape only if the typechecker must know it for `format`/`trace` clients). |
| **Compiler codegen** | `compiler/src/codegen/codegen.ts`: emit **`CALL`** with **`0xFFFFFF27`** for **`__capture_trace`** (arity 1). |
| **Compiler JVM** | `compiler/src/jvm-codegen/codegen.ts`: map **`__capture_trace`** to runtime helper(s); add **`__print_one`** → **`KRuntime`** (e.g. **`printOne`**) so **`kestrel:stack`** compiles. |
| **Runtime (JVM)** | `runtime/jvm/src/kestrel/runtime/KRuntime.java`: **`captureTrace`** (or equivalent), **`printOne`** if added, formatting for trace values consistent with VM / **`formatOne`**. |
| **Specs** | `02-stdlib.md`: `StackTrace` fields, `trace`, **`format(trace)`** rules; `04-bytecode-isa.md` §7: new row **`__capture_trace`** + JVM mapping note; `05-runtime-model.md` §5: placeholder **`function`**, frame order, debug-off behaviour; `08-tests.md`: stack / `Stack.trace` coverage wording. |
| **Tests** | `stdlib/kestrel/stack.test.ks`; optional `tests/unit/*.test.ks`; `compiler/test/` Vitest if prelude/codegen branches need assertions; VM **`zig build test`** if new Zig coverage is added; optional **`tests/e2e/scenarios/positive/`** + `.expected` for **`run-e2e.sh`**. |
| **Scripts** | **`scripts/run-e2e.sh`**: no change unless a new positive/negative scenario is added; then run script in verification. |
| **Docs (non-spec)** | **`tests/e2e/README.md`** if positive E2E is used or README is corrected to match **`run-e2e.sh`**. |
| **Rollback** | Revert primitive + prelude + stdlib; old programs without `trace` remain valid. |

## Tasks

- [x] **Spec alignment:** Update `docs/specs/02-stdlib.md`, `04-bytecode-isa.md` §7, `05-runtime-model.md` §5, and `docs/specs/08-tests.md` so `StackTrace<T>`, frame fields, primitive id, `format(trace)` behaviour, frame order, and test expectations are unambiguous **before or alongside** code.
- [x] **VM:** Implement **`__capture_trace`** at **`0xFFFFFF27`**: pop arity-1 argument, push a `StackTrace`-compatible heap value from current **`frame_sp`**, **`call_frames`**, **`current_module`**, and PC semantics consistent with “current stack at call site”; share logic with uncaught trace printing where possible.
- [x] **VM:** Extend primitive dispatch upper bound from **`0xFFFFFF26`** to **`0xFFFFFF27`**; keep **`operandStackOverflowReport`** / error paths consistent.
- [x] **Stdlib:** Define **`StackTrace<T>`** and **`trace(value)`** calling **`__capture_trace`**; implement string formatting for traces (via **`format`** extension or dedicated function).
- [x] **Compiler:** Add **`__capture_trace`** to prelude with correct polymorphic type; add codegen lowering in **`codegen.ts`**.
- [x] **JVM:** Implement capture/format parity in **`KRuntime`** and **`jvm-codegen/codegen.ts`**; add **`__print_one`** lowering so **`stdlib/kestrel/stack.ks`** JVM compilation succeeds.
- [x] **Tests:** Add/update tests per **Tests to add**; run full verification (compiler, VM, **`./scripts/kestrel test`**, **`./scripts/kestrel test-both`** on affected stdlib tests, **`./scripts/run-e2e.sh`** when E2E assets change).

## Tests to add

| Layer | What to cover |
|-------|----------------|
| **`stdlib/kestrel/stack.test.ks`** | **`trace` after catch:** nested calls + `throw` + `catch`; assert **`frames`** non-empty when debug info is present; assert **frame order** matches spec (same as uncaught ordering). **`value` field:** paired value matches caught exception (e.g. same ADT / visible **`format`**). **`format` / `formatTrace`:** output contains expected **file substring** and/or **line-like** content for a known throw site; smoke that **`format(trace)`** is non-empty and stable enough for assertions. **Without relying on a specific line number** where possible, use substring checks so minor source edits do not flake (or use stable marker paths). **Regression:** existing **`format`** / **`print`** groups still pass. |
| **`tests/unit/*.test.ks`** | **Optional:** only if a scenario is clearer outside stdlib (e.g. multi-module import of **`kestrel:stack`**); avoid duplicating **`stack.test.ks`** unless it adds a distinct angle (top-level `trace`, rethrow, etc.). |
| **`compiler/test/` (Vitest)** | **Prelude / typecheck:** unit or integration test that a module calling **`__capture_trace`** (or **`trace`** via a tiny fixture) typechecks with a fresh type variable for the argument and **`StackTrace`-shaped** result if exposed. **Codegen:** assert emitted **`CALL`** uses **`fn_id == 0xFFFFFF27`** (and arity **1**) for **`__capture_trace`** — add **`compiler/test/integration/`** or **`compiler/test/unit/`** case as appropriate to project patterns. **JVM:** if feasible, assert **`__capture_trace`** and **`__print_one`** lower to **`KRuntime`** invokes (mirror existing **`__format_one`** tests pattern if extended). |
| **`vm/` (`zig build test`)** | Add or extend coverage **if** the change introduces a testable seam: e.g. helper that builds frame list from synthetic **`call_frames`**, or a bytecode snippet that invokes **`0xFFFFFF27`** and inspects heap shape. **If** no Zig harness exists for host **`CALL`** ids, document in **Build notes** and rely on Kestrel-level tests — prefer at least one **VM-level** test when allocation/GC interaction is non-obvious. |
| **E2E (`./scripts/run-e2e.sh`)** | **Optional:** **`tests/e2e/scenarios/positive/stack_trace_caught.ks`** + **`stack_trace_caught.expected`** — program catches an exception, prints **`format(trace(ex))`**, stdout matched to golden. **Not required** if **`stack.test.ks`** already provides equivalent full pipeline coverage; if added, update **`tests/e2e/README.md`** to describe positive scenarios consistently with **`run-e2e.sh`**. |
| **`./scripts/kestrel test-both`** | After JVM changes, run on **`stdlib/kestrel/stack.test.ks`** (or full stdlib suite) so VM and JVM both exercise **`print`**, **`format`**, and new **`trace`**. |

## Documentation and specs to update

- `docs/specs/02-stdlib.md` — `kestrel:stack`: concrete **`StackTrace<T>`** fields, **`trace`**, **`format(trace)`** (or **`formatTrace`**) rules
- `docs/specs/04-bytecode-isa.md` §7 — extend range to **`0xFFFFFF27`**; new row **`__capture_trace`**: arity, stack effect, JVM **`KRuntime`** mapping (and note VM-only exceptions if any)
- `docs/specs/05-runtime-model.md` §5 — programmatic capture vs uncaught stderr: shared mapping rules, placeholder **`function`**, behaviour without debug lines, **frame order**
- `docs/specs/08-tests.md` — exceptions / **`Stack.trace`** / stdlib **`kestrel:stack`** coverage; reference **`stack.test.ks`** and optional E2E positive scenario
- `docs/specs/01-language.md` — §4 cross-link to 02 remains accurate once **`trace`** ships (wording tweak only if needed)
- `tests/e2e/README.md` — **if** positive E2E is added or docs should match **`run-e2e.sh`** (positive + negative)

## Notes

- Prefer **sharing** debug lookup and frame iteration with **`printUncaughtException`** via extracted helpers in **`exec.zig`** to avoid drift between stderr traces and **`StackTrace`** contents.
- Confirm **order** of frames (innermost-first vs outermost-first) in spec and tests; match uncaught stderr order for user familiarity.

## Build notes

- 2026-03-29: Moved from **planned** to **doing** after completing planned exit criteria (impact, tasks, tests, documentation list, acceptance criteria aligned).
- 2026-03-29: **Done.** VM primitive `0xFFFFFF27` (`__capture_trace`), stdlib `trace`/`StackTrace`, `format` for trace records, prelude/codegen/JVM parity (`__print_one`, `KRuntime`). `lookupDebugLine` shared via `load.zig`. **Regression:** if the VM binary is stale (no handler for `0xFFFFFF27`), `CALL` falls through and `trace` appears as `()` — rebuild with `cd vm && zig build -Doptimize=ReleaseSafe` (or `./scripts/kestrel build`). Verification: `npm run build && npm test` (compiler), `zig build test` (vm), `./scripts/kestrel test`, `./scripts/kestrel test-both stdlib/kestrel/stack.test.ks`, `./scripts/run-e2e.sh`.
