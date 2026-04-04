# Replace Placeholder Assertions in `await-behavior-validation.test.ks`

## Sequence: S01-22
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

`tests/unit/await-behavior-validation.test.ks` was written to answer specific in-development questions about the async feature. Its test body consists almost entirely of `isTrue(s, "description", 1 == 1)` placeholder assertions — predicates that always pass regardless of runtime behaviour. These consume test-suite capacity and give false confidence without providing any actual regression coverage. This story replaces the placeholder assertions with real behavioral tests.

## Current State

Examples from the file:
```kestrel
isTrue(s1, "non-async lambda await is type error (conformance test exists)", 1 == 1);
isTrue(s2, "conformance invalid case exists for await outside async", 1 == 1);
isTrue(s3, "specs document await at top-level", 1 == 1);
```

The file has four test groups but only one real assertion:
```kestrel
eq(s2, "await works inside async run", asyncAddResult, 8);
```

## Relationship to other stories

- Standalone; no dependencies.
- May want to coordinate with S01-12 (block-local async fun) and S01-13 (Task combinators) when those land — add tests for them in this file or in dedicated test files.

## Goals

1. Remove all `isTrue(_, _, 1 == 1)` assertions.
2. Replace each with a real behavioral assertion that would fail if the described property were broken.
3. The test groups should cover: correct `await` results, rejection of `await` in non-async lambdas (via typecheck conformance already exists — remove the duplicate runtime assertion or convert it to a meaningful runtime check), and async helper composition.
4. Optionally add new groups for edge cases not covered elsewhere (e.g. `await` on an already-completed task, `await` on a failed task with `try/catch`).

## Acceptance Criteria

- No `isTrue(_, _, 1 == 1)` or equivalent always-true predicates remain in the file.
- All new assertions can fail (i.e. they test real runtime state).
- `./scripts/kestrel test tests/unit/await-behavior-validation.test.ks` passes.
- `cd compiler && npm test` passes.

## Spec References

- No spec changes needed.

## Risks / Notes

- Some of the placeholder groups describe compile-time errors ("non-async lambda await is type error"). A runtime test file cannot verify compile-time errors directly — those belong in the conformance typecheck negatives (which already exist). Remove the runtime placeholder instead of trying to replicate compile-time checks at runtime.
- Keep the file focused on behavioral coverage that isn't already in `async_virtual_threads.test.ks` or the conformance suite to avoid duplication.
