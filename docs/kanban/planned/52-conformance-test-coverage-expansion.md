# Conformance Test Coverage Expansion

## Sequence: 52
## Tier: 5 — Test coverage and quality
## Former ID: 19

## Summary

Spec 08 defines comprehensive conformance test requirements. The current test suite covers many features but has gaps. This story tracks expanding test coverage to match the spec's requirements across all categories.

## Current State

### Parse conformance (`tests/conformance/parse/`)
- Only a small number of valid files; few or no invalid files.
- Spec 08 §2.1 requires "every production in the grammar covered by at least one test."
- **Harness:** There is no Vitest integration for `tests/conformance/parse/` (unlike `typecheck-conformance.test.ts` for typecheck). Adding parse corpus without a runner does not protect CI.

### Typecheck conformance (`tests/conformance/typecheck/`)
- Multiple valid and invalid files; gaps remain.
- **Harness:** `compiler/test/integration/typecheck-conformance.test.ts` runs `valid/` and `invalid/` (optional `// EXPECT:` on first line of invalid files).

### Runtime conformance (`tests/conformance/runtime/`)
- Few files (e.g. async_await, exception, gc_stress).
- Spec 08 §2.4–2.5 requires tests for each instruction, calling convention, tagged values, heap objects.
- **Harness:** `tests/conformance/runtime/README.md` refers to `run-e2e.sh` / `test-all.sh`, but **`scripts/run-e2e.sh` does not execute `tests/conformance/runtime/`**. New runtime `.ks` files need an explicit runner (Vitest integration or script) or they are documentation-only.

### Kestrel unit tests (`tests/unit/`)
- Many test files covering major features; some gaps.

### Gaps (examples)
- Parse invalid: may have no or few test files.
- Missing conformance for: string interpolation parsing, shebang handling, record vs block disambiguation, pipeline parsing, cons operator precedence.
- Missing conformance for: closure capture semantics (by-value vs by-reference), mutual recursion at block level, export var assignment.
- Missing runtime conformance for: SPREAD, closure GC, multi-module execution.

## Relationship to other stories

- **[51 — Negative E2E test suite](51-negative-e2e-test-suite.md)** (same tier, planned): expands **full CLI → compiler → VM** failure scenarios under `tests/e2e/scenarios/`. This story expands **conformance corpora** under `tests/conformance/` and compiler integration tests. Complementary; neither replaces the other.
- **None** blocking: no language or VM feature work is required unless a chosen scenario is impossible (then narrow acceptance or split a follow-up story).

## Goals

1. Meet the story’s **acceptance criteria** (minimum new files per layer) with programs that are small, named for intent, and stable.
2. **Wire parse and runtime conformance into `cd compiler && npm test`** (or an equivalent documented, CI-used path) so new files are not dead weight.
3. Keep **spec 08** and conformance READMEs accurate about layout, conventions (`// EXPECT:`, in-file stdout expectations after `println`), and how each suite is executed.

## Acceptance Criteria

- [ ] **Parse valid** (at least 10 more): shebang, string interpolation, all operator precedences, record literal, list literal with spread, lambda, nested match, type annotations, generic types, exception declaration.
- [ ] **Parse invalid** (at least 5): unclosed string, missing `=>` in match, unclosed block, reserved word as identifier, invalid integer literal.
- [ ] **Typecheck invalid** (at least 3 more): assignment to immutable field, await in non-async, mutual recursion type mismatch.
- [ ] **Runtime valid** (at least 5 more): SPREAD instruction, closure capture (by-value `val`, by-reference `var`), multi-module call, deep recursion, string interpolation at runtime.
- [ ] All new tests pass.

## Spec References

- [`docs/specs/08-tests.md`](../../specs/08-tests.md) — entire spec, especially §2 test categories and §3.5 coverage goals
- [`docs/specs/01-language.md`](../../specs/01-language.md) — grammar targets for parse coverage
- [`docs/specs/05-runtime-model.md`](../../specs/05-runtime-model.md) — runtime conformance intent

## Risks / Notes

- **Scope vs spec 08 §2.1:** Full “every production” coverage is larger than this story’s numeric minima; acceptance is **floor**, not exhaustive grammar closure. Further expansion can be a follow-up or rolled into future stories.
- **Harness first:** Without parse/runtime runners, reviewers cannot rely on CI for new `.ks` files. Prefer landing runners (or extending an existing script) before or alongside the bulk of new files.
- **Flakiness:** GC stress and timing-sensitive tests should stay bounded and deterministic where possible.
- **Duplication:** Spec 08 already points at `tests/unit/records.test.ks` for SPREAD; runtime conformance may add a **minimal** duplicate or a cross-reference in comments if the goal is an explicit `tests/conformance/runtime/` scenario.

## Impact analysis

| Area | Impact |
|------|--------|
| **Compiler (TS)** | New or extended `compiler/test/integration/*-conformance.test.ts` for parse-only and compile+run+stdout checks; no production compiler changes expected unless a test exposes a bug (then fix is in scope). |
| **VM (Zig)** | None unless a new runtime scenario exposes a VM defect. |
| **Scripts** | Optional: if runtime conformance is implemented in shell for parity with E2E, touch `scripts/`; otherwise keep in Vitest to match typecheck conformance. |
| **Tests** | New `.ks` files under `tests/conformance/parse/`, `typecheck/invalid/`, `runtime/valid/`; optional `tests/unit/*.test.ks` only if acceptance cannot be met via conformance alone. |
| **Docs** | `docs/specs/08-tests.md`, conformance READMEs under `tests/conformance/`. |
| **Risk / rollback** | Test-only changes; rollback is revert PR. |

## Tasks

- [ ] **Parse harness:** Add `compiler/test/integration/parse-conformance.test.ts`: `tests/conformance/parse/valid/*.ks` must tokenize+parse successfully; `invalid/*.ks` must fail at parse (optional first-line `// EXPECT:` substring in diagnostic message, matching typecheck convention).
- [ ] **Runtime harness:** Add automated execution for `tests/conformance/runtime/valid/*.ks` (Vitest preferred for consistency): compile to `.kbc`, run reference VM, compare stdout to in-file `//` lines after each `println` (same convention as existing runtime files such as `while_count.ks`). Ensure `npm test` runs it.
- [ ] **Parse README:** Add `tests/conformance/parse/README.md` (mirror typecheck README: valid vs invalid, `EXPECT` for invalid).
- [ ] **Runtime README:** Update `tests/conformance/runtime/README.md` so execution instructions match the implemented runner (remove or correct stale `run-e2e.sh` claim if still wrong).
- [ ] **Parse valid:** Add at least 10 new `tests/conformance/parse/valid/*.ks` covering: shebang, string interpolation, operator precedence cases, record literal, list with spread, lambda, nested match, type annotations, generic types, exception declaration (can be split across files; names should reflect intent).
- [ ] **Parse invalid:** Add at least 5 new `tests/conformance/parse/invalid/*.ks`: unclosed string, missing `=>` in match, unclosed block, reserved word as identifier, invalid integer literal (with `// EXPECT:` where messages are stable).
- [ ] **Typecheck invalid:** Add at least 3 new `tests/conformance/typecheck/invalid/*.ks`: immutable field assignment, `await` outside async, mutual recursion type mismatch (use `// EXPECT:` where helpful).
- [ ] **Runtime valid:** Add at least 5 new `tests/conformance/runtime/valid/*.ks`: SPREAD, closure `val` vs `var` capture, multi-module call, deep recursion, string interpolation at runtime (with in-file stdout expectations).
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test` from repo root; `cd vm && zig build test` if VM or bytecode emission changes; `./scripts/run-e2e.sh` if any E2E-relevant behaviour is touched.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| Vitest | `compiler/test/integration/parse-conformance.test.ts` | Parse-only pass/fail for `tests/conformance/parse/**`. |
| Vitest | New runtime conformance test module (e.g. `runtime-conformance.test.ts`) | Compile+run+stdout goldens for `tests/conformance/runtime/valid/*.ks`. |
| Conformance | `tests/conformance/parse/valid/*.ks` (≥10 new) | Spec 08 §2.1 valid coverage per acceptance list. |
| Conformance | `tests/conformance/parse/invalid/*.ks` (≥5 new) | Parse errors with optional message pinning. |
| Conformance | `tests/conformance/typecheck/invalid/*.ks` (≥3 new) | Type errors per acceptance. |
| Conformance | `tests/conformance/runtime/valid/*.ks` (≥5 new) | VM/runtime behaviour per acceptance. |
| Kestrel unit | `tests/unit/*.test.ks` | Only if a scenario is unsuitable for conformance layout; prefer conformance first. |

## Documentation and specs to update

- [ ] `docs/specs/08-tests.md` — §3.2 layout / execution: document parse conformance runner and runtime conformance runner once they exist; align §3.5 examples with new files if useful.
- [ ] `tests/conformance/parse/README.md` — new file describing directories and conventions.
- [ ] `tests/conformance/runtime/README.md` — correct how tests are run in CI.

## Notes

- If implementing runtime conformance in Vitest, consider extracting shared “expected stdout from `//` lines after println” logic into a small helper to avoid duplicating E2E conventions elsewhere.
