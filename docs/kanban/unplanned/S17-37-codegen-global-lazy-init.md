# Self-hosted codegen: global `val`/`var` lazy initialisation (`$init` pattern)

## Sequence: S17-37
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-36, S17-38, S17-41

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
- **Blocks**: S17-41 (E2E / no-Node validation). Every program that uses any module-level value
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
