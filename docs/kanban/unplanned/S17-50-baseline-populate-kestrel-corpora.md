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

- [ ] `tests/kconformance/parse/`, `tests/kconformance/typecheck/`, `tests/kconformance/runtime/valid/`
      are populated with all currently-passing files from their TS counterparts.
- [ ] `tests/kunit/` is populated with any currently-passing unit test files (may be empty
      if `kestrel:dev/test` is not yet self-hostable — this is an acceptable outcome).
- [ ] `./scripts/test-kestrel.sh` exits 0 over the populated baseline.
- [ ] Baseline counts are recorded in each `tests/k*/README.md`.
- [ ] `scripts/seed-kestrel-tests.sh` is not present in the final commit.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

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
