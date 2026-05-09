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
  - `tests/kconformance/typecheck`: 37 files
  - `tests/kconformance/runtime/valid`: 17 files
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
  - **`S17-52`** (fix self-hosted codegen StackMapTable generation — runtime execution blocker)
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

## Impact analysis

| Area | Change |
|------|--------|
| Parser | No parser implementation changes in `compiler/src/parser/**`. Expand self-hosted parse corpus coverage in `tests/kconformance/parse/` and (if needed for failure-shape categories) add parse-negative handling in `scripts/test-kestrel.sh` plus matching `tests/kconformance/parse/README.md` guidance. |
| Typecheck | No checker implementation changes in `compiler/src/typecheck/**`. Expand `tests/kconformance/typecheck/` with additional success cases and add a deterministic negative/error-shape tier (`invalid/` + `// EXPECT:`-style checks) in the self-hosted runner and docs. |
| Codegen (bytecode) | No TS bytecode backend changes in `compiler/src/codegen/**` are expected. This story validates already-landed codegen work by adding runtime corpus programs with deterministic stdout assertions. |
| Codegen (JVM) | No TS JVM codegen implementation changes in `compiler/src/jvm-codegen/**` are expected. Runtime corpus promotions should deliberately cover call/closure/control-flow/match/exceptions/async buckets to guard JVM codegen behaviour. |
| JVM runtime | No direct Java runtime implementation changes in `runtime/jvm/src/**`. Expanded runtime corpus acts as behavioural regression coverage against existing runtime semantics. |
| Stdlib | No required API changes in `stdlib/kestrel/**`. Promote/adapt runtime scenarios that use stdlib modules (`fs`, `process`, and at least one of `crypto/http/socket/web`) with deterministic assertions and environment-safe behaviour. |
| Scripts / CLI | Update `scripts/test-kestrel.sh` runtime tier to run via `./kestrel-self` after prerequisite stories are complete, add parse/typecheck invalid-tier handling if introduced, and enforce per-batch gating workflow (<=12 promoted files per batch, full-suite checks each batch). Keep `scripts/test-all.sh` green after every batch. |
| Tests and corpora | Add batched corpus promotions in `tests/kconformance/runtime/valid/`, `tests/kconformance/parse/`, and `tests/kconformance/typecheck/`; activate `tests/kunit/` with at least one real self-hosted suite; add reusable helpers under `tests/kfixtures/`; keep runtime files using `// =>` golden assertions for meaningful output lines. |
| Docs / specs | Update `tests/kconformance/**/README.md`, `tests/kunit/README.md`, and `tests/kfixtures/README.md` to reflect active status, category policy, and deferred categories. Update spec docs listed in this story to keep runtime-tier runner semantics and agent/test expectations authoritative. |

Compatibility and rollback notes:

- Switching runtime tier to `./kestrel-self` changes the effective compiler path for self-hosted runtime corpus execution; rollback is a single-script revert in `scripts/test-kestrel.sh`.
- Large promotions increase debugging blast radius; this plan keeps the existing risk note by requiring themed batches of <=12 files and a green `./scripts/test-all.sh` gate per batch.
- Some main-corpus runtime files are nondeterministic or environment-sensitive; adaptations must keep deterministic outcomes and document intentional exclusions.

## Tasks

- [ ] Parser: expand `tests/kconformance/parse/` to at least 16 files, grouped by explicit success and failure-shape categories; preserve provenance comments on promoted files.
- [ ] Parser: if parse failure-shape coverage is added, extend `scripts/test-kestrel.sh` with a parse-invalid tier that asserts deterministic expected-error substrings for each invalid file.
- [ ] Typecheck: expand `tests/kconformance/typecheck/` to at least 50 files with additional high-value positive cases (including narrowing/match/async/module combinations).
- [ ] Typecheck: add typecheck failure-shape category support (directory layout + expected-error assertion format + runner wiring) and seed representative invalid cases.
- [ ] Codegen: curate runtime candidate set from `tests/conformance/runtime/valid/` and related fixtures by feature bucket, excluding nondeterministic/environment-coupled files unless adapted.
- [ ] JVM codegen: promote runtime files in themed batches (<=12 files per batch) into `tests/kconformance/runtime/valid/` until file-count and >=55% parity targets are met.
- [ ] JVM runtime: ensure every promoted runtime file has deterministic behavioural assertions (`// =>`) for all meaningful output lines; avoid bytecode-shape-only checks.
- [ ] Stdlib: add/promote runtime scenarios that exercise `fs` and `process` plus at least one of `crypto/http/socket/web`, with deterministic/no-network defaults unless explicitly gated.
- [ ] CLI/scripts: switch runtime tier in `scripts/test-kestrel.sh` from `./kestrel` to `./kestrel-self` once S17-36/S17-37/S17-38 prerequisites are satisfied; remove stale fallback note.
- [ ] CLI/scripts: extend `scripts/test-kestrel.sh` output summary to print parse/typecheck/runtime parity counts and batch metadata (batch id/size) used during this expansion wave.
- [ ] Tests: add at least one real self-hosted unit suite under `tests/kunit/*.test.ks` and shared helper module(s) under `tests/kfixtures/*.ks`; wire imports so `kunit` is no longer inactive.
- [ ] Docs: update `tests/kconformance/parse/README.md`, `tests/kconformance/typecheck/README.md`, `tests/kconformance/runtime/README.md`, `tests/kconformance/runtime/valid/README.md`, `tests/kunit/README.md`, and `tests/kfixtures/README.md` with new counts, category taxonomy, and deferred-category rationale.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `./scripts/kestrel test`
- [ ] Run `./scripts/run-e2e.sh`
- [ ] Run `./scripts/test-kestrel.sh`
- [ ] Run `./scripts/test-all.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel self-hosted parse conformance | `tests/kconformance/parse/*.ks` and `tests/kconformance/parse/invalid/*.ks` | Raise parse corpus to >=16 files and assert both parse-success coverage and deterministic failure-shape diagnostics for malformed syntax classes. |
| Kestrel self-hosted typecheck conformance | `tests/kconformance/typecheck/*.ks` and `tests/kconformance/typecheck/invalid/*.ks` | Raise typecheck corpus to >=50 files and assert both acceptance of valid typing scenarios and rejection with stable error-shape expectations for invalid programs. |
| Kestrel self-hosted runtime conformance | `tests/kconformance/runtime/valid/*.ks` | Raise runtime corpus to >=30 files with deterministic `// =>` assertions, hitting all listed feature buckets and preserving exit-0 behaviour under `./kestrel-self run`. |
| Kestrel self-hosted unit harness | `tests/kunit/*.test.ks` | Activate kunit with at least one real suite that exercises self-hosted-only behaviour slices and imports reusable helpers. |
| Kestrel self-hosted fixtures | `tests/kfixtures/*.ks` | Provide reusable helper modules (multi-module call/capture/fixture setup) consumed by new `tests/kunit/*.test.ks` and selected kconformance programs. |
| Script-level regression | `scripts/test-kestrel.sh` (plus fixture files under `tests/kconformance/**`) | Add/extend harness assertions so invalid tiers, runtime compiler-path switch, and batch metadata behaviour are exercised by deterministic fixture-driven scenarios. |

## Documentation and specs to update

- [ ] `docs/specs/08-tests.md` — document expanded self-hosted corpus categories (success + failure-shape), runtime deterministic-golden requirements, and batch-gating expectations.
- [ ] `docs/specs/11-bootstrap.md` — update `scripts/test-kestrel.sh` runtime-tier runner from temporary TS fallback to self-hosted path and refresh tier/corpus status text.
- [ ] `docs/specs/12-agent-enablement-and-knowledge.md` — reflect strengthened self-hosted validation surface and corpus/runner expectations agents should rely on.
- [ ] `tests/kconformance/parse/README.md` — record updated counts, category split, and pass/fail expectation format.
- [ ] `tests/kconformance/typecheck/README.md` — record updated counts, category split, and expected-error-shape policy.
- [ ] `tests/kconformance/runtime/README.md` — refresh runtime corpus count and parity tracking notes.
- [ ] `tests/kconformance/runtime/valid/README.md` — remove temporary fallback wording and document required `./kestrel-self` execution/golden conventions.
- [ ] `tests/kunit/README.md` — move from inactive baseline to active-suite guidance with seed suite scope.
- [ ] `tests/kfixtures/README.md` — document fixture conventions and import usage in activated kunit suites.