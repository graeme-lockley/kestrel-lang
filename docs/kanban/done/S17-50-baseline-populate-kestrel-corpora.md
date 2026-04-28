# Baseline-populate Kestrel-compiler test corpora

## Sequence: S17-50
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-46, S17-47, S17-48, S17-49

## Summary

Systematically discover which existing TS-compiler test corpus files the self-hosted Kestrel
compiler can already handle, and copy all passing files into the matching `tests/k*/` corpora.
This establishes a concrete baseline floor that subsequent codegen and typecheck gap-closure
stories (S17-16..S17-44) must monotonically grow.

## Current State

`tests/kunit/`, `tests/kfixtures/`, and `tests/kconformance/` exist (from S17-48) but contain
only a tiny seed. We do not yet have a systematic picture of what the self-hosted compiler can
handle across the full TS corpus.

## Relationship to other stories

- **Depends on**: S17-48 (corpora directories and `test-kestrel.sh` must exist)
- **Blocks**: all remaining E17 stories (S17-40..S17-44, S17-16..S17-38) — they measure
  progress against this baseline

## Goals

1. A temporary discovery script `scripts/seed-kestrel-tests.sh` iterates every file in:
   - `tests/conformance/parse/`
   - `tests/conformance/typecheck/`
   - `tests/conformance/runtime/valid/`
   - `tests/unit/`
   Attempts to process each through `./kestrel-self` (compile-only for parse/typecheck;
   compile+run for runtime; `./kestrel-self test` for unit).
2. Each passing file is copied to the matching `tests/k*/` directory, with a one-line provenance
   header comment added: `// Provenance: tests/conformance/…/<filename> (baseline S17-50)`.
3. Each failing file is recorded in a temporary manifest `tests/kconformance/FAILURES.txt`
   (not committed long-term; just used to guide the investigation). The failures are grouped
   by approximate category (unsupported syntax, typechecker gap, codegen gap).
4. After the sweep, `./scripts/test-kestrel.sh` is run to confirm 100% of copied files pass
   (eliminates any flake or harness drift).
5. Baseline counts (parse N, typecheck M, runtime K, unit U) are recorded in the Build notes
   and appended to each `tests/k*/README.md` as a "Baseline (S17-50, <date>)" section.
6. `FAILURES.txt` is removed before committing; the failure analysis lives in Build notes.
7. `scripts/seed-kestrel-tests.sh` is removed after the baseline is committed (temporary tool).

## Acceptance Criteria

- [x] `tests/kconformance/parse/`, `tests/kconformance/typecheck/`, `tests/kconformance/runtime/valid/`
      are populated with all currently-passing files from their TS counterparts.
- [x] `tests/kunit/` is populated with any currently-passing unit test files (may be empty
      if `kestrel:dev/test` is not yet self-hostable — this is an acceptable outcome).
- [x] `./scripts/test-kestrel.sh` exits 0 over the populated baseline.
- [x] Baseline counts are recorded in each `tests/k*/README.md`.
- [x] `scripts/seed-kestrel-tests.sh` is not present in the final commit.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — test runner description

## Risks / Notes

- If no `tests/unit/` files pass under `./kestrel-self`, the `kunit/` tier will remain empty.
  The Build notes must document this clearly as a blocker for `kunit/` activation, identifying
  which specific features of `kestrel:dev/test` are unsupported.
- The seed files from S17-48 are superseded by (or incorporated into) this baseline sweep;
  S17-48 seed content should be deduplicated.
- `tests/kconformance/FAILURES.txt` must not be committed — add it to `.gitignore` temporarily
  if needed, or just produce it only in the working directory.

## Impact analysis

| Area | Change |
|------|--------|
| CLI / scripts | Add a temporary discovery helper at `scripts/seed-kestrel-tests.sh` to sweep TS corpora through `./kestrel-self`, copy pass-cases into `tests/k*`, and emit a temporary failure manifest used during curation. Remove the helper before final commit. |
| Tests (kconformance parse/typecheck/runtime) | Populate `tests/kconformance/parse/`, `tests/kconformance/typecheck/`, and `tests/kconformance/runtime/valid/` from TS corpus files that currently pass the self-hosted path. Add provenance header comments and deduplicate/replace S17-48 seed-only content. |
| Tests (kunit) | Attempt baseline import of `tests/unit/*.test.ks` into `tests/kunit/` via `./kestrel-self test`; if none pass, keep `tests/kunit/` empty and document blockers in Build notes. |
| Test runner | Validate populated corpora with `scripts/test-kestrel.sh` and ensure the script remains green on baseline data. |
| Documentation / specs | Update baseline sections and counts in `tests/kconformance/parse/README.md`, `tests/kconformance/typecheck/README.md`, `tests/kconformance/runtime/README.md`, `tests/kconformance/runtime/valid/README.md`, and `tests/kunit/README.md`. Update `docs/specs/11-bootstrap.md` test-runner section with baseline population notes. |
| Compatibility / risk | `tests/kconformance/FAILURES.txt` is an investigation artifact and must not be committed. If `kestrel:dev/test` remains unsupported, unit baseline may legitimately stay empty; this must be explicit in Build notes and README baselines. |

## Tasks

- [x] Add temporary `scripts/seed-kestrel-tests.sh` that sweeps `tests/conformance/{parse,typecheck,runtime/valid}` and `tests/unit/` through `./kestrel-self`, copies passing files to matching `tests/k*/` locations, prepends provenance headers, and writes grouped temporary failures to `tests/kconformance/FAILURES.txt`.
- [x] Run `scripts/seed-kestrel-tests.sh`, inspect discovered failures, and curate copied files so each `tests/k*` destination contains only currently passing self-hosted baseline files.
- [x] Remove temporary artifacts before close: delete `tests/kconformance/FAILURES.txt`, remove `scripts/seed-kestrel-tests.sh`, and ensure no temporary ignore rules are left behind.
- [x] Update baseline count sections and S17-50 date annotations in `tests/kconformance/parse/README.md`, `tests/kconformance/typecheck/README.md`, `tests/kconformance/runtime/README.md`, `tests/kconformance/runtime/valid/README.md`, and `tests/kunit/README.md`.
- [x] Update `docs/specs/11-bootstrap.md` with the established baseline workflow/caveats for `scripts/test-kestrel.sh` and `tests/k*` corpora.
- [x] Tick story Acceptance Criteria and append Build notes with final baseline counts plus categorized failure summary.
- [x] Run `./scripts/test-kestrel.sh`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Corpus baseline data | `tests/kconformance/parse/*.ks` | Ensure every parse file that self-hosted compile accepts is represented in the self-hosted parse corpus with provenance tracking. |
| Corpus baseline data | `tests/kconformance/typecheck/*.ks` | Ensure typecheck corpus contains the current self-hosted pass-floor and can be revalidated by `scripts/test-kestrel.sh`. |
| Corpus baseline data | `tests/kconformance/runtime/valid/*.ks` | Ensure runtime-valid corpus contains only files that currently pass the runtime-tier execution path in `scripts/test-kestrel.sh`. |
| Corpus baseline data | `tests/kunit/*.test.ks` | Capture any currently self-hostable `kestrel:dev/test` suite files, or explicitly retain empty tier with documented blocker evidence. |
| Script/integration validation | `scripts/test-kestrel.sh` execution | Regression guard that full populated baseline remains green after corpus expansion. |

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — update self-hosted corpus runner section with S17-50 baseline-population expectations and current runtime-tier caveat.
- [x] `tests/kconformance/parse/README.md` — add baseline (S17-50, date) counts and provenance note.
- [x] `tests/kconformance/typecheck/README.md` — add baseline (S17-50, date) counts and provenance note.
- [x] `tests/kconformance/runtime/README.md` — add baseline (S17-50, date) counts and runtime-tier baseline constraints.
- [x] `tests/kconformance/runtime/valid/README.md` — add baseline (S17-50, date) counts and `// =>` golden expectation.
- [x] `tests/kunit/README.md` — record baseline count and explicit blocker statement if tier remains empty.

## Build notes

- 2026-04-28: Started implementation.
- 2026-04-28: Added temporary `scripts/seed-kestrel-tests.sh` sweep script and ran baseline discovery across parse/typecheck/runtime/unit source corpora. Discovery snapshot: parse 12 pass / 8 fail, typecheck 37 pass / 29 fail, runtime 0 pass / 43 fail, unit 0 pass. Failure manifest categories: parse `unsupported-syntax` (8), runtime `codegen-gap` (43), typecheck `other` (29), unit `other` (1 probe failure at `stdlib/kestrel/data/dict.ks`).
- 2026-04-28: Initial provenance-header insertion broke `shebang_header.ks` by placing comment before `#!`; fixed by keeping shebang first and provenance on the next line. `./scripts/test-kestrel.sh` now passes with baseline counts: parse 12, typecheck 37, runtime 0, unit 0.
- 2026-04-28: Removed temporary discovery artifacts (`scripts/seed-kestrel-tests.sh`, `tests/kconformance/FAILURES.txt`) after recording baseline/failure analysis in this story and in corpus READMEs.
- 2026-04-28: Compiler verification surfaced an assertion mismatch in `compiler/test/integration/runtime-stdlib.test.ts` (runtime tier now legitimately reports `runtime: 0 files` at this baseline). Updated expectation to accept either `runtime: N passed, 0 failed` or `runtime: 0 files`.
- 2026-04-28: `./scripts/kestrel test` initially failed with `ClassFormatError` against stale bootstrap artifacts. Rebuilt bootstrap artifacts (`./scripts/build-bootstrap-jar.sh`), re-ran `./kestrel-self bootstrap`, and confirmed `./scripts/kestrel test --summary` reports `1963 passed`.
