# Self-hosted codegen: global `val`/`var` lazy initialisation (`$init` pattern)

## Sequence: S17-37
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-24 through S17-36, S17-38, S17-42

## Summary

Module-level `val` and `var` declarations in Kestrel use a lazy-initialisation pattern: each
module class has a `static $init()V` method that initialises all module globals exactly once
(guarded by a boolean lock field). Consumers of imported globals call `$init()` before
accessing the field. Without this pattern, imported globals read uninitialized JVM static
fields (Java defaults: `null` for objects, `0` for primitives).

## Current State

`emitVal` and `emitVar` in `codegen.ks` emit a private `init$<name>()Object` method and a
static field, but do NOT emit a module-level `$init()` method or the lock-field / guard
idiom. `EIdent` resolution for imported globals also does not emit `INVOKESTATIC $init`.

TS reference:
- Emits a `static boolean $initialized` lock field.
- Emits a `static $init()V` method that checks `$initialized`, returns if `true`, sets it,
  then calls `init$<name>()` for each `val`/`var` and stores the result into the static
  field.
- Every `EIdent` that refers to an imported `val`/`var` emits `INVOKESTATIC Class.$init()`
  before the `GETSTATIC`.

## Relationship to other stories

- **Depends on**: S17-25 (`EIdent` resolution — needs to call `$init` for imported names).
  Should be implemented alongside S17-25 or immediately after.
- **Blocks**: S17-42 (E2E). Every program that uses any module-level value (which is all of
  them) will read `null` without `$init`.

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

## Acceptance Criteria

- [ ] A program with `val greeting = "Hello"` exports `greeting` and an importing module
      reads `"Hello"`, not `null`.
- [ ] A module imported by two modules only initialises its globals once (lock check).
- [ ] Circular module dependencies (already handled by the driver's dependency ordering)
      do not cause infinite `$init` recursion.
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
