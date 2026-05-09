# Self-hosted corpus expansion after codegen/KTI closure

## Sequence: S17-51
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)

## Summary

Capture and execute the next large expansion wave for self-hosted test corpora after the remaining
codegen and KTI correctness stories land. The goal is to preserve detailed expansion scope now,
while sequencing implementation so new corpus cases validate the true self-hosted path instead of
the temporary TypeScript runtime fallback.

## Current State

- Self-hosted corpora currently include:
  - `tests/kconformance/parse`: 12 files
  - `tests/kconformance/typecheck`: 38 files
  - `tests/kconformance/runtime/valid`: 13 files
- Main conformance corpus currently includes:
  - `tests/conformance/parse`: 20 files
  - `tests/conformance/typecheck`: 69 files
  - `tests/conformance/runtime/valid`: 53 files
- Runtime gap remains broad: 41 runtime-valid scenarios from `tests/conformance/runtime/valid`
  are not yet mirrored in `tests/kconformance/runtime/valid`.
- `scripts/test-kestrel.sh` currently runs runtime files through `./kestrel` (TS compiler path),
  not `./kestrel-self`, pending completion of remaining self-hosted codegen stories.
- `tests/kunit/` and `tests/kfixtures/` remain empty and therefore inactive as self-hosted
  validation layers.

## Relationship to other stories

- Depends on:
  - `S17-36` (tail-call optimization)
  - `S17-37` (global lazy init)
  - `S17-38` (is/never/options codegen)
  - `S17-39`, `S17-40`, `S17-41` (KTI correctness trilogy)
- Should execute before or alongside final validation in `S17-44` so no-Node confidence includes
  stronger self-hosted corpora.
- Follows foundational corpus scaffolding and baseline stories `S17-48` and `S17-50`.

## Goals

1. Expand self-hosted corpora with executable, deterministic tests that run code and assert
   behavior rather than bytecode shape.
2. Raise runtime parity by promoting high-value scenarios from
   `tests/conformance/runtime/valid` into `tests/kconformance/runtime/valid` in prioritized
   batches.
3. Activate currently empty `tests/kunit/` and `tests/kfixtures/` with meaningful seed coverage.
4. Improve self-hosted parse/typecheck confidence with additional curated corpus cases,
   including negative/error-shape checks where appropriate.
5. Ensure corpus growth remains maintainable via clear runner/docs updates and reproducible gates.

## Acceptance Criteria

- [ ] Runtime tier in `scripts/test-kestrel.sh` runs through `./kestrel-self` (self-hosted path)
      for corpus execution once prerequisite stories are complete.
- [ ] Corpus size targets are met (or exceeded):
  - `tests/kconformance/runtime/valid`: 13 -> >= 30 files
  - `tests/kconformance/parse`: 12 -> >= 16 files
  - `tests/kconformance/typecheck`: 38 -> >= 50 files
- [ ] Runtime parity target is met: `tests/kconformance/runtime/valid` reaches >= 55% of
  `tests/conformance/runtime/valid` file count at merge time.
- [ ] Every runtime corpus file has deterministic behavioral assertions (`// =>`) for all
  meaningful output lines (no bytecode-shape-only assertions).
- [ ] Runtime language-feature scenario coverage includes at least one executable file for each
  bucket below, and at least 2 files for buckets marked `high-priority`:
  - `high-priority` function calls: direct, indirect, namespace, and multi-module calls
  - `high-priority` closures: capture, local fun, self recursion, mutual recursion
  - `high-priority` control flow: if/else, while, break/continue
  - `high-priority` match/patterns: ADT, Option/Result, tuple/list/cons variants
  - records and mutable field updates (including spread scenarios)
  - exceptions: throw/catch and nested unwinding/rethrow
  - async/task semantics: await, async lambdas/funs, task combinator slices
  - stdlib runtime behavior slices: fs/process plus at least one of crypto/http/socket/web
  - collections/string/number runtime semantics (list/array/string/float/int ops)
  - deep recursion / stack-sensitive behavior
- [ ] `tests/kunit` is no longer inactive (contains at least one real self-hosted unit suite).
- [ ] `tests/kfixtures` contains reusable fixtures referenced by new self-hosted tests.
- [ ] Parse/typecheck corpus expectations are documented and satisfied:
  - parse corpus includes both success and failure-shape coverage categories
  - typecheck corpus includes both success and failure-shape coverage categories
  - README-level notes describe which categories are intentionally deferred (if any)
- [ ] `./scripts/test-kestrel.sh` exits 0 with the expanded corpus.
- [ ] Batch gating is enforced: each expansion batch is <= 12 files and every batch keeps
  `./scripts/test-all.sh` green before the next batch begins.

## Spec References

- `docs/specs/08-tests.md`
- `docs/specs/11-bootstrap.md`
- `docs/specs/12-agent-enablement-and-knowledge.md`

## Risks / Notes

- Expanding runtime corpus before codegen/KTI closure can produce false confidence because runtime
  currently executes through the TS compiler path.
- Large one-shot promotions are hard to debug; expansion should happen in small, themed batches
  with full-suite validation after each batch.
- Some main conformance scenarios rely on environment/network assumptions that may need filtering
  or adaptation for deterministic self-hosted corpus use.
- Keep corpus intent explicit in READMEs so self-hosted and TS corpora remain complementary,
  not divergent without rationale.