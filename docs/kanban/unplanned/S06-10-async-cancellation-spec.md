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

## Risks / Notes

- This is a pure documentation story; no runtime changes required.
- Must be coordinated with S06-06, S06-07, S06-08 so the spec reflects post-fix behavior, not the current buggy behavior.
- Recommend sequencing after S06-06 – S06-09 are complete.
