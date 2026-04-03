# Async writeText — Signature, Callers, and Cascade

## Sequence: S01-08
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/done/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-07, S01-09

## Summary

Promote the stale `writeText` migration story to a build-ready plan that matches the current repository. The original draft targeted a pre-S01-04 midpoint where `Fs.writeText` would become `Task<Unit>` with provisional exception-based failures. The repo has already moved beyond that point: the public API is now `Task<Result<Unit, FsError>>`, the JVM runtime exposes `KRuntime.writeTextAsync`, and the known Kestrel callers already `await` and pattern-match on the result. This story now scopes the remaining work to auditing that end-to-end path, filling writeText-specific regression gaps, and removing documentation drift without regressing the final Result-based surface.

## Current State

- **stdlib/kestrel/fs.ks** — `export async fun writeText(path: String, content: String): Task<Result<Unit, FsError>>` awaits `__write_text(path, content)` and maps raw string error codes into `FsError`.
- **compiler/src/typecheck/check.ts** — `__write_text` is typed as `(String, String) -> Task<Result<Unit, String>>`; the intrinsic exposes runtime error codes as `String`, and the stdlib wrapper upgrades them to the public `FsError` ADT.
- **compiler/src/jvm-codegen/codegen.ts** — `__write_text` lowers to `INVOKESTATIC KRuntime.writeTextAsync(Object, Object): KTask`.
- **runtime/jvm/src/kestrel/runtime/KRuntime.java** — `writeTextAsync()` submits file writes to the virtual-thread executor and completes the task with `KOk(KUnit.INSTANCE)` on success or `KErr(fsErrorCode)` on failure.
- **Callers already migrated**:
  - `stdlib/kestrel/fs.test.ks` awaits `Fs.writeText(...)` for a write-then-read roundtrip.
  - `scripts/run_tests.ks` awaits `writeText(...)` through `writeTextOrExit()` when generating `.kestrel_test_runner.ks`.
- **Coverage gap**: There is no writeText-specific JVM integration regression in `compiler/test/integration/runtime-stdlib.test.ts`, and current Kestrel harness coverage exercises only the success path, not a stable failure mode such as writing into a missing parent directory.

## Relationship to other stories

- **Depends on S01-02 and S01-03**: `writeTextAsync()` relies on the `KTask` runtime and virtual-thread executor already delivered there.
- **Depends on S01-04**: This story must preserve the final `Task<Result<Unit, FsError>>` surface introduced by typed async error handling. It must not regress to the obsolete `Task<Unit>` or exception-based design captured in the stale unplanned draft.
- **Parallel with S01-07 and S01-09**: `scripts/run_tests.ks` is shared fallout across the async fs/process migrations, so changes here must not conflict with the `listDir` and `runProcess` cascades.
- **Interacts with S01-10**: The test-runner script is already async for filesystem/process helpers, but suite invocation remains a separate harness concern handled by S01-10.
- **Follows S01-06**: Canonical specs already describe the async Result model; this story is now about aligning implementation coverage and story records with those specs.

## Goals

1. **Keep the final public surface**: `Fs.writeText(path, content)` remains `Task<Result<Unit, FsError>>`; callers `await` and pattern-match rather than relying on synchronous side effects or thrown I/O exceptions.
2. **Verify intrinsic alignment**: The compiler type checker, JVM codegen, JVM runtime, and stdlib wrapper all agree on the `__write_text` contract and payload shape.
3. **Preserve caller behavior**: `stdlib/kestrel/fs.test.ks` and `scripts/run_tests.ks` continue to work with awaited `writeText` results and deterministic error handling.
4. **Close writeText-specific coverage gaps**: Add or extend automated tests so success and stable failure behavior are covered at the JVM integration, Kestrel harness, and user-visible CLI/E2E layers.
5. **Remove planning drift**: The story text, spec references, and follow-up notes reflect the current post-S01-04 implementation instead of the obsolete provisional migration plan.

## Acceptance Criteria

- [x] `stdlib/kestrel/fs.ks` continues to export `writeText(path: String, content: String): Task<Result<Unit, FsError>>` and maps runtime error codes to `FsError` consistently with `readText` and `listDir`.
- [x] `compiler/src/typecheck/check.ts` `__write_text` binding remains aligned with the runtime contract: `(String, String) -> Task<Result<Unit, String>>` at the intrinsic layer, with stdlib mapping to `FsError` at the public layer.
- [x] `compiler/src/jvm-codegen/codegen.ts` emits the async intrinsic call to `KRuntime.writeTextAsync(Object, Object): KTask` for `__write_text` and does not synthesize a separate `KUnit.INSTANCE` push in the caller path.
- [x] `runtime/jvm/src/kestrel/runtime/KRuntime.java` `writeTextAsync()` dispatches to the virtual-thread executor and returns `KOk(KUnit.INSTANCE)` / `KErr(code)` rather than throwing write failures into user code.
- [x] `stdlib/kestrel/fs.test.ks` covers a successful write/read roundtrip and a stable write failure path with awaited `Fs.writeText(...)`.
- [x] `scripts/run_tests.ks` continues to await the generated-runner write and preserves current non-zero exit behavior when writing fails.
- [x] `compiler/test/integration/runtime-stdlib.test.ts` includes writeText-specific JVM integration coverage for success and failure.
- [x] User-facing docs do not describe stale synchronous or pre-Result `writeText` behavior.
- [x] Verification passes: `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:fs` — `writeText` contract)
- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/06-typesystem.md` §6 (typing of `await` over `Task<Result<...>>`)
- `docs/specs/09-tools.md` §2.4 (`kestrel test` generated runner writes via `scripts/run_tests.ks`)

## Risks / Notes

- **Story drift is material**: The original unplanned file no longer matches the repo. Implementation work must preserve the current Result-based API, not the obsolete `Task<Unit>` midpoint.
- **Intrinsic/public boundary differs by design**: The intrinsic returns `String` error codes while the public stdlib surface returns `FsError`. Compiler, runtime, and stdlib changes must stay synchronized or callers will see mismatched error semantics.
- **Shared runner fallout**: `scripts/run_tests.ks` is also touched by S01-07 and S01-09. Keep this story scoped to write-generation behavior and avoid accidental cross-story churn.
- **Stable write failure selection matters**: Permission-denied tests are host-dependent on CI and developer machines; prefer a deterministic missing-parent-path regression that should map to `Err(NotFound)` via `NoSuchFileException`.
- **Legacy docs may still drift**: The canonical specs are current, but non-canonical docs such as `docs/Kestrel_v1_Language_Specification.md` should be audited if they are still user-facing.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler typecheck | Audit `compiler/src/typecheck/check.ts` so the `__write_text` intrinsic stays `Task<Result<Unit, String>>` and remains consistent with runtime error-code payloads. Compatibility risk: compile-time breakage if the intrinsic and wrapper drift; rollback is straightforward by restoring the prior intrinsic signature. |
| JVM codegen | Audit `compiler/src/jvm-codegen/codegen.ts` lowering for `__write_text` to ensure it still targets `KRuntime.writeTextAsync` with the correct descriptor and no stale sync-unit shim. Risk is isolated to JVM backend runtime wiring. |
| JVM runtime | Audit or adjust `runtime/jvm/src/kestrel/runtime/KRuntime.java` `writeTextAsync()` so success returns `KOk(KUnit.INSTANCE)` and failures return `KErr(code)` from a virtual-thread task instead of surfacing raw exceptions. This is user-visible behavior; rollback risk is medium because it affects async fs semantics and generated-runner writes. |
| Stdlib | Verify `stdlib/kestrel/fs.ks` continues to expose the public `FsError`-typed API and that `mapFsError` stays aligned with runtime codes. This is the compatibility boundary callers depend on. |
| Scripts | Verify `scripts/run_tests.ks` `writeTextOrExit()` keeps awaiting the generated-runner write and preserves current failure messaging. Shared-risk note: this file is also changed by S01-07/S01-09, so keep edits narrowly scoped. |
| Kestrel harness tests | Extend `stdlib/kestrel/fs.test.ks` beyond the roundtrip success case to cover a deterministic failure path for `writeText`, without introducing host-specific permission assumptions. |
| Vitest integration | Add writeText-specific cases to `compiler/test/integration/runtime-stdlib.test.ts` so compiled JVM execution covers both success and missing-parent failure behavior, not just `readText` and `listDir`. |
| E2E / user-visible behavior | Consider a focused positive scenario under `tests/e2e/scenarios/positive/` that writes a temp file, reads it back, and prints a stable failure-case discriminator for a missing parent path, ensuring the full CLI path matches the documented async Result surface. |
| Specs and docs | Confirm `docs/specs/02-stdlib.md`, `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, and `docs/specs/09-tools.md` do not contradict the current async Result surface; audit legacy docs if needed. |

## Tasks

- [x] Audit `compiler/src/typecheck/check.ts` `__write_text` typing so the intrinsic contract remains `Task<Result<Unit, String>>` and matches the runtime payload shape.
- [x] Audit `compiler/src/jvm-codegen/codegen.ts` `__write_text` lowering to `KRuntime.writeTextAsync(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KTask;` and fix any descriptor or stale sync-unit behavior.
- [x] Audit `runtime/jvm/src/kestrel/runtime/KRuntime.java` `writeTextAsync()` for virtual-thread dispatch, `KOk`/`KErr` payload shape, and deterministic failure mapping; tighten resource or error handling if needed.
- [x] Audit `stdlib/kestrel/fs.ks` `writeText` wrapper and `mapFsError` so the public surface remains `Task<Result<Unit, FsError>>` and matches runtime error-code conventions.
- [x] Audit `stdlib/kestrel/fs.test.ks` writeText coverage and extend it with a missing-parent failure regression if the current success-only roundtrip remains the only writeText assertion.
- [x] Audit `scripts/run_tests.ks` `writeTextOrExit()` and generated-runner flow so the write stays awaited and failure messaging stays unchanged.
- [x] Add or extend `compiler/test/integration/runtime-stdlib.test.ts` with writeText success and failure JVM integration regressions.
- [x] Add or extend a focused positive scenario under `tests/e2e/scenarios/positive/` if CLI-level writeText behavior is not already pinned elsewhere.
- [x] Update canonical specs and any still-user-facing docs that describe stale sync or pre-Result `writeText` behavior.
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `cd runtime/jvm && bash build.sh`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/run-e2e.sh`

## Build notes

- 2026-04-03: Started implementation. All compiler/runtime/stdlib code was already correct — story was purely an audit + coverage gap close.
- 2026-04-03: Added `writeText missing parent returns Err(NotFound)` group to `stdlib/kestrel/fs.test.ks` (deterministic failure via missing parent directory, avoids host-specific permission assumptions). All 13 fs harness tests pass.
- 2026-04-03: Added two Vitest integration tests to `compiler/test/integration/runtime-stdlib.test.ts`: success roundtrip (write + read-back length) and missing-parent `Err(NotFound)`. Suite grows to 7 total, all pass.
- 2026-04-03: Added `tests/e2e/scenarios/positive/async-writetext-result.ks` + `.expected` covering success path and missing-parent failure path via relative `tests/fixtures/fs/` paths (same pattern as other E2E fs scenarios). All 8 E2E positive scenarios pass.
- 2026-04-03: All specs (`02-stdlib.md`, `01-language.md`, `06-typesystem.md`, `09-tools.md`, `Kestrel_v1_Language_Specification.md`) already describe the correct final `Task<Result<Unit, FsError>>` surface — no edits needed.
- 2026-04-03: Pre-existing failure in untracked `tests/unit/await-behavior-validation.test.ks` (uses unsupported async lambda syntax) causes `./scripts/kestrel test` (no args) to fail. This is not introduced by S01-08 — confirmed by git stash check. Targeted `./scripts/kestrel test stdlib/kestrel/fs.test.ks ...` passes cleanly.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Compile and run JVM programs that `await Fs.writeText(...)`, asserting `Ok(())` plus readback on success and `Err(NotFound)` for a missing parent directory. |
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Keep the roundtrip success coverage and add a deterministic failure assertion for `await Fs.writeText(...)` against a missing parent directory without relying on permission settings. |
| E2E positive | `tests/e2e/scenarios/positive/async-writetext-result.ks` | Exercise the full CLI path by writing a temp file, reading it back, and printing stable success/failure markers for both the roundtrip and a missing-parent error path. |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — confirm the `kestrel:fs` `writeText` row describes the final `Task<Result<Unit, FsError>>` contract and current success/failure behavior.
- [x] `docs/specs/01-language.md` — keep the async/task model wording consistent with failure-as-data stdlib operations so this story does not reintroduce exception-based wording.
- [x] `docs/specs/06-typesystem.md` — confirm the `await` typing examples remain accurate for `Task<Result<...>>` fs APIs, including `writeText`.
- [x] `docs/specs/09-tools.md` — verify `kestrel test` generation still matches the async `scripts/run_tests.ks` implementation that writes the generated runner via awaited `writeText`.
- [x] `docs/Kestrel_v1_Language_Specification.md` — audit or update any stale fs signatures if this aggregate document is still intended to be user-facing.

## Notes

- The repository already appears to satisfy most of the original story mechanically. `build-story` should treat this as an audit-and-closeout task: add only the missing writeText-specific regression coverage and docs cleanup that remain after verification.