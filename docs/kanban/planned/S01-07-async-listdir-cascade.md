# Async listDir — Signature, Callers, and Cascade

## Sequence: S01-07
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-05, S01-06, S01-08, S01-09

## Summary

Promote the stale `listDir` migration story to a build-ready plan that matches the current repository. The original story assumed a pre-S01-04 world where `Fs.listDir` still returned `Task<List<String>>`; the repo has already moved beyond that point. Today the public API is `Task<Result<List<String>, FsError>>`, the JVM runtime exposes `KRuntime.listDirAsync`, and the known Kestrel callers already `await` and pattern-match on the result. This story now scopes the remaining work to auditing that end-to-end path, filling any listDir-specific regression gaps, and removing documentation drift without regressing the final Result-based surface.

## Current State

- **stdlib/kestrel/fs.ks** — `export async fun listDir(path: String): Task<Result<List<String>, FsError>>` awaits `__list_dir(path)` and maps raw string error codes into `FsError`.
- **compiler/src/typecheck/check.ts** — `__list_dir` is typed as `(String) -> Task<Result<List<String>, String>>`; the intrinsic exposes runtime error codes as `String`, and the stdlib wrapper upgrades them to the public `FsError` ADT.
- **compiler/src/jvm-codegen/codegen.ts** — `__list_dir` lowers to `INVOKESTATIC KRuntime.listDirAsync(Object): KTask`.
- **runtime/jvm/src/kestrel/runtime/KRuntime.java** — `listDirAsync()` submits directory scanning to the virtual-thread executor and completes the task with `KOk(KList)` on success or `KErr(fsErrorCode)` on failure.
- **Callers already migrated**:
  - `stdlib/kestrel/fs.test.ks` awaits `Fs.listDir(...)` for both success and missing-directory cases.
  - `scripts/run_tests.ks` awaits `listDir(...)` through `listDirOrExit()` while discovering `tests/unit/*.test.ks` and `stdlib/kestrel/*.test.ks`.
- **Coverage gap**: JVM integration coverage in `compiler/test/integration/runtime-stdlib.test.ts` currently exercises `Fs.readText(...)` but does not provide a listDir-specific success/error regression.

## Relationship to other stories

- **Depends on S01-02 and S01-03**: `listDirAsync()` relies on the `KTask` runtime and virtual-thread executor already delivered there.
- **Depends on S01-04**: This story must preserve the final `Task<Result<List<String>, FsError>>` surface introduced by typed async error handling. It must not regress to the provisional exception-based or bare-`Task<List<String>>` design captured in the stale unplanned draft.
- **Parallel with S01-08 and S01-09**: `scripts/run_tests.ks` is shared fallout across the async fs/process migrations, so changes here must not conflict with the `writeText` and `runProcess` cascades.
- **Interacts with S01-10**: The test-runner script is already async for discovery helpers, but suite invocation remains a separate harness concern handled by S01-10.
- **Follows S01-06**: Canonical specs already describe the async `Result` model; this story is now about aligning implementation coverage and story records with those specs.

## Goals

1. **Keep the final public surface**: `Fs.listDir(path)` remains `Task<Result<List<String>, FsError>>`; callers `await` and pattern-match rather than relying on sentinel empty lists or thrown I/O exceptions.
2. **Verify intrinsic alignment**: The compiler type checker, JVM codegen, JVM runtime, and stdlib wrapper all agree on the `__list_dir` contract and payload shape.
3. **Preserve caller behavior**: `stdlib/kestrel/fs.test.ks` and `scripts/run_tests.ks` continue to work with awaited `listDir` results and deterministic error handling.
4. **Close listDir-specific coverage gaps**: Add or extend automated tests so success and missing-directory behavior are covered at the JVM integration and Kestrel harness layers without depending on directory iteration order.
5. **Remove planning drift**: The story text, spec references, and follow-up notes reflect the current post-S01-04 implementation instead of the obsolete provisional migration plan.

## Acceptance Criteria

- [ ] `stdlib/kestrel/fs.ks` continues to export `listDir(path: String): Task<Result<List<String>, FsError>>` and maps runtime error codes to `FsError` consistently with the other fs APIs.
- [ ] `compiler/src/typecheck/check.ts` `__list_dir` binding remains aligned with the runtime contract: `(String) -> Task<Result<List<String>, String>>` at the intrinsic layer, with stdlib mapping to `FsError` at the public layer.
- [ ] `compiler/src/jvm-codegen/codegen.ts` emits the async intrinsic call to `KRuntime.listDirAsync(Object): KTask` for `__list_dir`.
- [ ] `runtime/jvm/src/kestrel/runtime/KRuntime.java` `listDirAsync()` dispatches to the virtual-thread executor and returns `KOk(entries)` / `KErr(code)` rather than silently falling back to an empty list.
- [ ] `stdlib/kestrel/fs.test.ks` covers a successful listing and a missing-directory error with order-independent assertions.
- [ ] `scripts/run_tests.ks` continues to await both directory scans used for default test discovery and preserves current non-zero exit behavior when discovery fails.
- [ ] `compiler/test/integration/runtime-stdlib.test.ts` includes listDir-specific JVM integration coverage for success and missing-directory failure.
- [ ] Canonical specs and related docs do not describe stale synchronous or pre-Result `listDir` behavior.
- [ ] Verification passes: `cd compiler && npm run build && npm test`, `cd runtime/jvm && bash build.sh`, `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Spec References

- `docs/specs/02-stdlib.md` (`kestrel:fs` — `listDir` contract)
- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/06-typesystem.md` §6 (typing of `await` over `Task<Result<...>>`)
- `docs/specs/09-tools.md` §2.4 (`kestrel test` discovery via `scripts/run_tests.ks`)

## Risks / Notes

- **Story drift is material**: The original unplanned file no longer matches the repo. Implementation work must preserve the current Result-based API, not the obsolete `Task<List<String>>` midpoint.
- **Intrinsic/public boundary differs by design**: The intrinsic returns `String` error codes while the public stdlib surface returns `FsError`. Compiler, runtime, and stdlib changes must stay synchronized or callers will see mismatched error semantics.
- **Shared runner fallout**: `scripts/run_tests.ks` is also touched by S01-08 and S01-09. Keep this story scoped to listDir discovery and avoid accidental cross-story churn.
- **Directory order is host-defined**: Tests must assert membership or counts, not entry order.
- **Legacy docs may still drift**: The canonical specs are current, but non-canonical docs such as `docs/Kestrel_v1_Language_Specification.md` should be audited if they are still user-facing.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler typecheck | Audit `compiler/src/typecheck/check.ts` so the `__list_dir` intrinsic stays `Task<Result<List<String>, String>>` and remains consistent with runtime error-code payloads. Compatibility risk: compile-time breakage if the intrinsic and wrapper drift; rollback is straightforward by restoring the prior intrinsic signature. |
| JVM codegen | Audit `compiler/src/jvm-codegen/codegen.ts` lowering for `__list_dir` to ensure it still targets `KRuntime.listDirAsync` with the correct descriptor. Risk is isolated to JVM backend runtime wiring. |
| JVM runtime | Audit or adjust `runtime/jvm/src/kestrel/runtime/KRuntime.java` `listDirAsync()` so success returns `KOk(KList)` and failures return `KErr(code)` from a virtual-thread task with no sentinel empty-list fallback. This is user-visible behavior; rollback risk is medium because it affects async fs semantics. |
| Stdlib | Verify `stdlib/kestrel/fs.ks` continues to expose the public `FsError`-typed API and that `mapFsError` stays aligned with runtime codes. This is the compatibility boundary callers depend on. |
| Scripts | Verify `scripts/run_tests.ks` discovery helpers keep awaiting `listDir` results and preserve current failure messaging. Shared-risk note: this file is also changed by S01-08/S01-09, so keep edits narrowly scoped. |
| Kestrel harness tests | Extend `stdlib/kestrel/fs.test.ks` only if current assertions miss entry-shape or missing-directory regression coverage. Tests must remain deterministic by avoiding directory-order assumptions. |
| Vitest integration | Add listDir-specific cases to `compiler/test/integration/runtime-stdlib.test.ts` so compiled JVM execution covers both success and missing-directory behavior, not just `readText`. |
| Specs and docs | Confirm `docs/specs/02-stdlib.md`, `docs/specs/01-language.md`, `docs/specs/06-typesystem.md`, and `docs/specs/09-tools.md` do not contradict the current async Result surface; audit legacy docs if needed. |

## Tasks

- [ ] Audit `compiler/src/typecheck/check.ts` `__list_dir` typing so the intrinsic contract remains `Task<Result<List<String>, String>>` and matches the runtime payload shape.
- [ ] Audit `compiler/src/jvm-codegen/codegen.ts` `__list_dir` lowering to `KRuntime.listDirAsync(Ljava/lang/Object;)Lkestrel/runtime/KTask;` and fix any descriptor or intrinsic-name drift.
- [ ] Audit `runtime/jvm/src/kestrel/runtime/KRuntime.java` `listDirAsync()` for virtual-thread dispatch, `KOk`/`KErr` payload shape, and no silent empty-list fallback; tighten resource or error handling if needed.
- [ ] Audit `stdlib/kestrel/fs.ks` `listDir` wrapper and `mapFsError` so the public surface remains `Task<Result<List<String>, FsError>>` and matches runtime error-code conventions.
- [ ] Audit `stdlib/kestrel/fs.test.ks` listDir coverage and extend it only if success-entry shape or missing-directory error assertions are incomplete.
- [ ] Audit `scripts/run_tests.ks` `listDirOrExit()` and default discovery flow so both directory scans remain awaited and failure messaging stays unchanged.
- [ ] Add or extend `compiler/test/integration/runtime-stdlib.test.ts` with listDir success and missing-directory JVM integration regressions.
- [ ] Update canonical specs and any still-user-facing docs that describe stale sync or pre-Result `listDir` behavior.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `cd runtime/jvm && bash build.sh`
- [ ] Run `./scripts/kestrel test`
- [ ] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/runtime-stdlib.test.ts` | Compile and run JVM programs that `await Fs.listDir(...)`, asserting `Ok(entries)` for a known fixture directory and `Err(NotFound)` for a missing directory. |
| Kestrel harness | `stdlib/kestrel/fs.test.ks` | Keep listDir success and missing-directory coverage deterministic; extend only if needed to assert `\tfile` / `\tdir` entry shape or constructor-specific error behavior without relying on order. |
| E2E positive | `tests/e2e/scenarios/positive/async-listdir-result.ks` | Optional direct regression for the public `Fs.listDir` surface that prints stable aggregated facts from a known fixture directory and a missing-directory error path. |

## Documentation and specs to update

- [ ] `docs/specs/02-stdlib.md` — confirm the `kestrel:fs` `listDir` row describes the final `Task<Result<List<String>, FsError>>` contract and current entry format.
- [ ] `docs/specs/01-language.md` — keep the async/task model wording consistent with failure-as-data stdlib operations so this story does not reintroduce exception-based wording.
- [ ] `docs/specs/06-typesystem.md` — confirm the `await` typing examples remain accurate for `Task<Result<...>>` fs APIs.
- [ ] `docs/specs/09-tools.md` — verify `kestrel test` discovery still matches the async `scripts/run_tests.ks` implementation.
- [ ] `docs/Kestrel_v1_Language_Specification.md` — audit or update any stale fs signatures if this aggregate document is still intended to be user-facing.

## Notes

- The repository already appears to satisfy most of the original story mechanically. `build-story` should treat this as an audit-and-closeout task: add only the missing listDir-specific regression coverage and docs cleanup that remain after verification.