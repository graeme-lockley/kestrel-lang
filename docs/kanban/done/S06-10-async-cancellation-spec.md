# Document Async Cancellation Semantics in Spec

## Sequence: S06-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)

## Summary

The async/await specification is silent on several important runtime behaviors introduced during the E01 async epic: the `Cancelled` exception, `Task.cancel` semantics, `Task.map` cancel propagation, and the edge-case behavior of `Task.all` and `Task.race`. This story adds the missing documentation to `docs/specs/`.

## Current State

- `docs/specs/01-language.md` describes `async`/`await` syntax and basic semantics but does not mention the `Cancelled` exception or cancellation behavior.
- `docs/specs/02-stdlib.md` has a `Task` section but omits: `Task.cancel` return value, what happens to `await`-ing code when a task is cancelled, `Task.map` cancel propagation, `Task.all` behavior when one task fails, and `Task.race` behavior with zero tasks.
- `docs/specs/06-typesystem.md` notes `Task<T>` as a structural async type but does not reference cancellation.

## Relationship to other stories

- S06-06, S06-07, S06-08: runtime fixes whose observable semantics should be captured here.
- S06-11: test coverage that exercises the documented edge cases.

## Goals

- Every public async feature has a spec entry covering its normal and error behavior.
- New developers can read the spec to understand what `Task.cancel` does, when `Cancelled` is raised, and what edge inputs to `Task.all`/`Task.race` produce.

## Acceptance Criteria

1. `docs/specs/01-language.md` documents the `Cancelled` exception and what happens when `await` is called on a cancelled task.
2. `docs/specs/02-stdlib.md` `Task` section documents:
   - `Task.cancel` — return value (`Bool`), effect on awaiting callers
   - `Task.map` — cancel propagation to source task
   - `Task.all` — behavior when one or more tasks fail (first failure wins, remaining cancelled)
   - `Task.race` — behavior when input list is empty (Kestrel exception raised)
   - `Task.race` — behavior when all tasks fail
3. `docs/specs/06-typesystem.md` `Task<T>` entry cross-references the cancellation model.
4. All spec text is consistent with the actual runtime behavior (verified against `KTask.java` and `KRuntime.java`).

## Spec References

- `docs/specs/01-language.md` — async/await section
- `docs/specs/02-stdlib.md` — Task section
- `docs/specs/06-typesystem.md` — structural typing / Task entry

## Impact Analysis

- `docs/specs/01-language.md` §5 Task combinators bullet points — three clarifications.
- `docs/specs/02-stdlib.md` kestrel:task Functions table — four row updates and an expanded Implementation notes paragraph.
- `docs/specs/06-typesystem.md` §6 async rules — one cross-reference sentence added.

## Tasks

- [x] Add cancel-propagation note to `Task.map` in `01-language.md` §5
- [x] Add remaining-tasks-not-cancelled clarification to `Task.all` in `01-language.md` §5
- [x] Clarify catchable-Kestrel-exception and all-fail behavior in `Task.race` in `01-language.md` §5; add quiescence-timeout note to process-lifetime sentence
- [x] Update `map` row in `02-stdlib.md` kestrel:task table
- [x] Update `all` row in `02-stdlib.md` kestrel:task table
- [x] Update `race` row in `02-stdlib.md` kestrel:task table
- [x] Update `cancel` row in `02-stdlib.md` kestrel:task table; add quiescence timeout note to Implementation notes
- [x] Add cancellation cross-reference to `06-typesystem.md` §6

## Build notes

2026-03-07: All spec edits are pure documentation; no runtime code changed.

- AC2 states `Task.cancel` return value is `Bool` — the actual `task.ks` stub has return type `Unit` and the JVM side is `void`. Documented as `Unit` to match reality; the story acceptance criterion was incorrect.
- `Task.all` fail-fast: remaining tasks are **not** cancelled (Java `CompletableFuture.allOf` does not cancel siblings on failure). Documented accurately; the story AC saying "remaining cancelled" is wrong.
- `Task.race` empty-list: raises `KException("no tasks provided")` (catchable from Kestrel) — documented as "catchable Kestrel exception with payload `"no tasks provided"`".

## Tests to add

None — pure documentation story.

## Docs to update

- `docs/specs/01-language.md`
- `docs/specs/02-stdlib.md`
- `docs/specs/06-typesystem.md`

## Risks / Notes

- This is a pure documentation story; no runtime changes required.
- All changes must reflect post-S06-06/07/08/09 behavior (verified against KTask.java and KRuntime.java).
- `Task.cancel` returns `Unit` (not `Bool`) — the acceptance criterion that says `Bool` is incorrect; the actual stub in task.ks is `Unit`.
