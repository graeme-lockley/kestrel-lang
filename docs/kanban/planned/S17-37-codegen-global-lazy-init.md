# Self-hosted codegen: global `val`/`var` lazy initialisation (`$init` pattern)

## Sequence: S17-37
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-36, S17-38, S17-44

## Summary

Module-level `val` and `var` declarations in Kestrel use a lazy-initialisation pattern: each
module class has a `static $init()V` method that initialises all module globals exactly once
(guarded by a boolean lock field). Consumers of imported globals call `$init()` before
accessing the field. Without this pattern, imported globals read uninitialized JVM static
fields (Java defaults: `null` for objects, `0` for primitives). This delivery slice also needs
to retire the temporary self-hosted `main(String[])` shim and switch module startup back to a
real codegen path that runs compiled top-level logic.

## Current State

`emitVal` and `emitVar` in `codegen.ks` emit a private `init$<name>()Object` method and a
static field, but do NOT emit a module-level `$init()` method or the lock-field / guard
idiom. `EIdent` resolution for imported globals also does not emit `INVOKESTATIC $init`.

To keep the pipeline runnable while codegen stories are still in progress, the self-hosted
compiler currently emits a temporary no-op `main(String[])` shim and `run-e2e.sh` skips all
runtime-sensitive negative scenarios plus the positive scenarios already marked
`E2E_SKIP_PENDING_CODEGEN`. That workaround keeps CI green but does not prove real module
startup, global initialization, or runtime execution.

TS reference:
- Emits a `static boolean $initialized` lock field.
- Emits a `static $init()V` method that checks `$initialized`, returns if `true`, sets it,
  then calls `init$<name>()` for each `val`/`var` and stores the result into the static
  field.
- Every `EIdent` that refers to an imported `val`/`var` emits `INVOKESTATIC Class.$init()`
  before the `GETSTATIC`.

## Relationship to other stories

- **Depends on**: S17-25 (`EIdent` resolution — needs to call `$init` for imported names).
  It should be implemented in the same tranche so imported/global reads and module startup are
  fixed together.
- **Blocks**: re-enabling the runtime-negative E2E scenarios currently skipped behind
  `E2E_SKIP_PENDING_CODEGEN`.
- **Blocks**: S17-44 (E2E / no-Node validation). Every program that uses any module-level value
  (which is all of them) will read `null` or fail to execute meaningful top-level code without
  `$init` and a real entrypoint.

## Goals

1. In `jvmCodegen`, after emitting all declarations, emit a `static $initialized` field.
2. Emit a `static $init()V` method that:
   a. Reads `$initialized`; if `true`, returns immediately.
   b. Sets `$initialized = true`.
   c. For each `val`/`var` declaration in the program: calls `INVOKESTATIC init$<name>()`
      and stores the result in `PUTSTATIC <name>`.
3. In `EIdent` resolution (S17-25), for any imported `val`/`var`, emit
   `INVOKESTATIC ImportedClass.$init()V` before the `GETSTATIC`.
4. Verify that the lock check is thread-safe enough for the single-threaded init path used
   by Kestrel programs.
5. Replace the temporary no-op `main(String[])` shim with a real startup path that triggers
  module initialization and executes compiled top-level behavior.
6. Remove the temporary runtime-negative E2E skip markers added while the stub `main` path was
  in place, once those scenarios pass again under real execution.

## Acceptance Criteria

- [ ] A program with `val greeting = "Hello"` exports `greeting` and an importing module
      reads `"Hello"`, not `null`.
- [ ] A module imported by two modules only initialises its globals once (lock check).
- [ ] Circular module dependencies (already handled by the driver's dependency ordering)
      do not cause infinite `$init` recursion.
- [ ] The temporary no-op `main(String[])` shim is removed and compiled modules execute through
  real generated startup behavior.
- [ ] The runtime-negative E2E scenarios skipped during the temporary shim period are restored
  and pass again.
- [ ] New codegen unit tests cover the `$init` emission and the importing-module read
      path.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/07-modules.md` — module initialisation order
- `docs/specs/11-bootstrap.md` — JVM class layout

## Risks / Notes

- The `$init` method must be idempotent — re-entrant calls from circular imports (which
  should not happen after topological ordering in the driver, but may occur at the JVM
  level) must not cause a second initialisation.
- Land the `main`/startup replacement in the same build as the `$init` implementation; removing
  the shim earlier would break executability, while keeping it afterwards would continue to mask
  runtime failures in E2E.

## Impact analysis

| Area | Change |
|------|--------|
| Parser (`compiler/src/parser/`) | No parser grammar/AST change expected. Validate current top-level decl forms already carry enough information for module-global init generation. |
| Typecheck (`compiler/src/typecheck/check.ts`, self-hosted typecheck) | No type-system rule change expected. Confirm existing typechecked program and inferred-type callback used by self-hosted codegen is sufficient for global initializer expression emission. |
| Codegen (bytecode TS reference) (`compiler/src/jvm-codegen/codegen.ts`) | Read-only reference point for parity: confirm `$initialized` field, `$init()` guard shape, imported-name pre-init calls, and entrypoint behavior to mirror in self-hosted implementation. |
| Codegen (self-hosted JVM) (`stdlib/kestrel/tools/compiler/codegen.ks`) | Replace `emitMainStub` with real startup path, emit `static $initialized` field plus guarded `static $init()V`, update global `val`/`var` declaration emission so `init$<name>()` computes initializer expressions, and ensure imported/global reads invoke `$init` before field access. |
| JVM runtime (`runtime/jvm/src/`) | No runtime API change expected. Verify existing `runInProcess`/entrypoint invocation behavior still matches generated `main(String[])` and `$init` sequencing. |
| Stdlib / compiler driver (`stdlib/kestrel/tools/compiler/driver.ks`, `stdlib/kestrel/tools/compiler/cli-main.ks`) | Wire real startup execution path through generated module code (not no-op shim), and ensure self-hosted compile/run path exercises `$init` on first module use. |
| Scripts (`scripts/run-e2e.sh`, `scripts/test-kestrel.sh`) | No new skip mechanism should be introduced. Validate runtime-sensitive scenarios remain enabled and passing under real execution once startup shim is removed. |
| Tests | Extend self-hosted compiler unit coverage for `$init` emission and startup behavior; add/refresh runtime-facing scenarios proving imported globals initialize exactly once and are visible across modules. |
| Docs/specs | Update module/bootstrap specs to document concrete `$init`/`$initialized` class layout and startup flow now that no-op `main` shim is retired. |

Compatibility and rollback notes:

- Compatibility: generated class layout changes (`$initialized` + non-stub `$init`) affect self-hosted compiler output; parity with TS codegen is required so mixed-cache/bootstrap scenarios remain interoperable.
- Rollback: reverting this story requires restoring `emitMainStub` and pre-story global init behavior together; partial rollback (startup only or `$init` only) risks runtime regressions.
- Risk carry-forward from story notes: idempotent/re-entrant `$init` guard must be preserved to avoid circular-import initialization loops.

## Tasks

- [ ] Parser: confirm no AST/schema change is required for module-level `val`/`var` lazy init and startup emission (document decision in Build notes if unchanged).
- [ ] Typecheck: confirm self-hosted codegen has access to the initializer expression/type info it needs; add minimal plumbing only if required by `init$<name>()` emission.
- [ ] Self-hosted JVM codegen (`stdlib/kestrel/tools/compiler/codegen.ks`): implement/finish initializer method generation so `emitVal`/`emitVar` compile their initializer expression into `init$<name>()` return value rather than `aconst_null` stubs.
- [ ] Self-hosted JVM codegen (`stdlib/kestrel/tools/compiler/codegen.ks`): emit module-level `static boolean $initialized` field on each module class.
- [ ] Self-hosted JVM codegen (`stdlib/kestrel/tools/compiler/codegen.ks`): emit guarded `static $init()V` that returns immediately when initialized, sets `$initialized = true`, then calls each `init$<name>()` and stores into corresponding static field.
- [ ] Self-hosted JVM codegen (`stdlib/kestrel/tools/compiler/codegen.ks`): ensure imported/global identifier load paths call `INVOKESTATIC <Class>.$init()V` before `GETSTATIC`/function-ref use (parity check with S17-25 behavior).
- [ ] Self-hosted JVM codegen (`stdlib/kestrel/tools/compiler/codegen.ks`): replace temporary `emitMainStub` path with real generated startup path that triggers module init and executes compiled top-level behavior.
- [ ] Driver/CLI wiring (`stdlib/kestrel/tools/compiler/driver.ks`, `stdlib/kestrel/tools/compiler/cli-main.ks`): confirm self-hosted run/build flow invokes generated entrypoint and no longer depends on shim semantics.
- [ ] Tests (`stdlib/kestrel/tools/compiler/codegen-decl.test.ks`, `stdlib/kestrel/tools/compiler/codegen-expr.test.ks`, self-hosted runtime corpus): add/update tests listed below for `$init` lock semantics, imported global reads, and startup execution behavior.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.
- [ ] Run `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness (self-hosted compiler unit) | `stdlib/kestrel/tools/compiler/codegen-decl.test.ks` | Assert emitted module class contains `$initialized` field and `$init` method shape; assert `init$<name>()` for `val`/`var` includes initializer expression bytecode, not null stub. |
| Kestrel harness (self-hosted compiler unit) | `stdlib/kestrel/tools/compiler/codegen-expr.test.ks` | Assert imported/global identifier paths emit `INVOKESTATIC $init` before `GETSTATIC`/function ref; include regression for alias import (`import { x as y }`). |
| Kestrel unit corpus | `tests/unit/export_var.test.ks` (or new `tests/unit/global_lazy_init.test.ks`) | Verify cross-module `val`/`var` reads return initialized values and not JVM defaults; include two-importer case proving single initialization side effect. |
| Kestrel fixtures | `tests/fixtures/lazy_side_a.ks`, `tests/fixtures/lazy_side_b.ks` (or new fixture pair) | Add fixture pair that prints init side effects and exports globals to prove `$init` runs once even with multiple importers. |
| E2E positive | `tests/e2e/scenarios/positive/lazy_loading.ks` (and `.expected`) | Extend/refresh lazy-loading scenario to assert initialized exported values are visible and init side effects occur once per module. |
| E2E negative | `tests/e2e/scenarios/negative/runtime_catch_no_match_rethrow.ks` and `tests/e2e/scenarios/negative/uncaught_throw.ks` | Regression guard that runtime-sensitive negative scenarios still execute under real generated startup path after shim removal. |

## Documentation and specs to update

- [ ] `docs/specs/07-modules.md` — update module initialization section to describe generated `$initialized` lock + `$init()V` guard semantics and imported-global pre-init behavior.
- [ ] `docs/specs/11-bootstrap.md` — update JVM class layout/startup flow notes to remove temporary no-op `main(String[])` shim language and document real generated startup path.
