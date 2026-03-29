# Conformance Test Coverage Expansion

## Sequence: 52
## Tier: 5 — Test coverage and quality
## Former ID: 19

## Summary

Spec 08 defines comprehensive conformance test requirements. The current test suite covers many features but has gaps. This story tracks expanding test coverage to match the spec's requirements across all categories.

## Current State

### Parse conformance (`tests/conformance/parse/`)
- **Today:** Two valid files (`simple_val.ks`, `fun_and_if.ks`); no `invalid/` directory yet.
- Spec 08 §2.1 requires "every production in the grammar covered by at least one test."
- **Harness:** There is no Vitest integration for `tests/conformance/parse/` (unlike `typecheck-conformance.test.ts` for typecheck). Adding parse corpus without a runner does not protect CI.
- **Parser API:** `parse(tokens)` returns `Program | { ok: false; errors: ParseErrorEntry[] }` (see `compiler/src/parser/parse.ts`). A parse-conformance harness must treat `{ ok: false }` as failure; valid files must yield a `Program` (not an error bundle).

### Typecheck conformance (`tests/conformance/typecheck/`)
- Multiple valid and invalid files; gaps remain.
- **Harness:** `compiler/test/integration/typecheck-conformance.test.ts` runs `valid/` and `invalid/` (optional `// EXPECT:` on first line of invalid files).
- **Avoid duplicates:** Before adding new invalid cases, check existing `tests/conformance/typecheck/invalid/*.ks` (e.g. `await_outside_async.ks`, `narrowing_impossible.ks`, `break_outside_loop.ks`, etc.).

### Runtime conformance (`tests/conformance/runtime/`)
- Several files (`async_await`, `exception_*`, `gc_stress`, `while_count`, `float_ops`).
- Spec 08 §2.4–2.5 requires tests for each instruction, calling convention, tagged values, heap objects (this story adds **floor** coverage via named scenarios, not full ISA closure).
- **Harness:** `tests/conformance/runtime/README.md` claims execution via `run-e2e.sh` / `test-all.sh`, but **`scripts/run-e2e.sh` does not execute `tests/conformance/runtime/`** (verified: no `conformance` references in that script). Existing `.ks` files are therefore not enforced by CI until a runner lands.
- **In-file goldens:** Valid runtime files use **`println`** and expected stdout lines in `//` comments on the following lines (see `while_count.ks`). The runtime README incorrectly says `print(...)`; fix when updating docs.

### Kestrel unit tests (`tests/unit/`)
- Many test files covering major features; some gaps.

### Gaps (examples)
- Parse invalid: no corpus yet.
- Missing conformance for: string interpolation parsing, shebang handling, record vs block disambiguation, pipeline parsing, cons operator precedence.
- Missing conformance for: closure capture semantics (by-value vs by-reference), mutual recursion at block level, export var assignment.
- Missing runtime conformance for: SPREAD, closure GC, multi-module execution.

## Relationship to other stories

- **[51 — Negative E2E test suite](51-negative-e2e-test-suite.md)** (same tier, planned): expands **full CLI → compiler → VM** failure scenarios under `tests/e2e/scenarios/`. This story expands **conformance corpora** under `tests/conformance/` and compiler integration tests. Complementary; neither replaces the other.
- **None** blocking: no language or VM feature work is required unless a chosen scenario is impossible (then narrow acceptance or split a follow-up story).

## Goals

1. Meet the story’s **acceptance criteria** (minimum new files per layer) with programs that are small, named for intent, and stable.
2. **Wire parse and runtime conformance into `cd compiler && npm test`** (or an equivalent documented, CI-used path) so new files are not dead weight. **`./scripts/test-all.sh` already runs `cd compiler && npm test`**, so new Vitest modules are picked up without changing that script unless we choose otherwise.
3. Keep **spec 08**, **09-tools** cross-references, **AGENTS.md**, and conformance READMEs accurate about layout, conventions (`// EXPECT:`, in-file stdout expectations after `println`), and how each suite is executed.

## Acceptance Criteria

- [x] **Parse valid** (at least 10 **new** files): between them, cover shebang, string interpolation, operator precedences (including cons / pipeline as applicable), record literal, list literal with spread, lambda, nested match, type annotations, generic types, exception declaration (can be split across files; names should reflect intent).
- [x] **Parse invalid** (at least 5 **new** files): unclosed string, missing `=>` in match, unclosed block, reserved word as identifier, invalid integer literal; use `// EXPECT:` where diagnostic substrings are stable (same convention as typecheck invalid).
- [x] **Typecheck invalid** (at least 3 **new** files): must **not** duplicate existing `tests/conformance/typecheck/invalid/*.ks` scenarios. Target themes: assignment to immutable record field; **mutual recursion** between two bindings with a **type conflict**; a third distinct type error (e.g. invalid generic instantiation, row/pipeline/type-argument mismatch—choose one that is not already covered). Use `// EXPECT:` where helpful.
- [x] **Runtime valid** (at least 5 **new** files): SPREAD instruction, closure capture (**`val`** by-value vs **`var`** by-reference), multi-module call, deep recursion, string interpolation at runtime; use in-file `//` lines after each **`println`** for expected stdout (same pattern as `while_count.ks`).
- [x] **Harnesses:** `parse-conformance.test.ts` and the runtime conformance Vitest module are merged and run as part of **`cd compiler && npm test`** (Vitest discovery).
- [x] **Documentation:** Items under **Documentation and specs to update** are completed so spec 08, AGENTS.md, 09-tools (test-related cross-refs), and conformance READMEs match reality (including correcting the stale runtime README claim about `run-e2e.sh`).
- [x] All new and existing tests pass per the **Tasks** verification list.

## Spec References

- [`docs/specs/08-tests.md`](../../specs/08-tests.md) — entire spec, especially §2 test categories and §3 layout / execution / coverage goals
- [`docs/specs/01-language.md`](../../specs/01-language.md) — grammar targets for parse coverage (authoritative; update only if the story intentionally records a new testing convention in spec—otherwise reference-only)
- [`docs/specs/05-runtime-model.md`](../../specs/05-runtime-model.md) — runtime conformance intent (reference-only unless behaviour is clarified for a test)
- [`docs/specs/09-tools.md`](../../specs/09-tools.md) — CLI and toolchain cross-references to how tests are run (update where 08 is cited)

## Risks / Notes

- **Scope vs spec 08 §2.1:** Full “every production” coverage is larger than this story’s numeric minima; acceptance is **floor**, not exhaustive grammar closure. Further expansion can be a follow-up or rolled into future stories.
- **Harness first:** Without parse/runtime runners, reviewers cannot rely on CI for new `.ks` files. Prefer landing runners (or extending an existing script) before or alongside the bulk of new files.
- **Flakiness:** GC stress and timing-sensitive tests should stay bounded and deterministic where possible.
- **Duplication:** Spec 08 already points at `tests/unit/records.test.ks` for SPREAD; runtime conformance may add a **minimal** focused scenario under `tests/conformance/runtime/valid/` and/or a cross-reference in comments if the goal is an explicit corpus path.
- **Typecheck invalid:** Grep `tests/conformance/typecheck/invalid/` before adding files so acceptance counts are **net new** scenarios.

## Impact analysis

| Area | Impact |
|------|--------|
| **Compiler (TS)** | New `compiler/test/integration/parse-conformance.test.ts` and `compiler/test/integration/runtime-conformance.test.ts` (names may match this story); optional small shared helper for stdout golden extraction. No production compiler changes expected unless a test exposes a bug (fix then in scope). |
| **VM (Zig)** | None unless a new runtime scenario exposes a VM defect. |
| **Stdlib** | None expected for this story. |
| **Scripts** | Default: **no** `scripts/run-e2e.sh` change; runtime conformance lives in Vitest (consistent with typecheck). If the team later folds runtime into shell for symmetry, that would be a follow-up. |
| **Tests** | New `.ks` under `tests/conformance/parse/valid|invalid/`, `typecheck/invalid/`, `runtime/valid/`; create `parse/invalid/` if missing. Optional `tests/unit/*.test.ks` only if acceptance cannot be met via conformance alone. |
| **Docs** | `docs/specs/08-tests.md`, `docs/specs/09-tools.md` (test/conformance cross-refs), `AGENTS.md`, `tests/conformance/parse/README.md` (new), `tests/conformance/runtime/README.md`, `tests/conformance/typecheck/README.md` (short pointer to sibling suites). |
| **Risk / rollback** | Test-only changes; rollback is revert PR. |

## Tasks

- [x] **Parse harness:** Add `compiler/test/integration/parse-conformance.test.ts`: for each `tests/conformance/parse/valid/*.ks`, `tokenize` + `parse` must yield a successful `Program` (not `{ ok: false }`). For each `invalid/*.ks`, parsing must fail with `{ ok: false }`; optional first-line `// EXPECT:` substring must appear in at least one of the reported error messages (mirror typecheck convention).
- [x] **Runtime harness:** Add `compiler/test/integration/runtime-conformance.test.ts` (or equivalent): for each `tests/conformance/runtime/valid/*.ks`, compile to `.kbc` (same compiler entry as other integration tests / `dist/cli.js`), run **`vm/zig-out/bin/kestrel`** (build VM ReleaseSafe or match `run-e2e.sh`), assert exit code 0, compare stdout to expected lines derived from `//` comments after each **`println`** (document the exact extraction rule in the test module and README). Ensure `npm test` runs it.
- [x] **Parse README:** Add `tests/conformance/parse/README.md` (mirror typecheck README: `valid/` vs `invalid/`, `EXPECT` for invalid, Vitest path).
- [x] **Runtime README:** Update `tests/conformance/runtime/README.md`: correct **`println`** / `//` convention; state that CI runs these via **`cd compiler && npm test`** (not `run-e2e.sh` unless implementation changes).
- [x] **Typecheck README:** Add a short “Other conformance trees” blurb linking to parse and runtime READMEs and their Vitest drivers.
- [x] **Parse valid:** Add at least 10 new `tests/conformance/parse/valid/*.ks` covering the acceptance list (split across files as needed; names reflect intent).
- [x] **Parse invalid:** Add `tests/conformance/parse/invalid/` if needed; add at least 5 new `.ks` files per acceptance (with `// EXPECT:` where stable).
- [x] **Typecheck invalid:** Add at least 3 new `tests/conformance/typecheck/invalid/*.ks` per acceptance (no duplicates of existing files; grep first).
- [x] **Runtime valid:** Add at least 5 new `tests/conformance/runtime/valid/*.ks` per acceptance (in-file stdout expectations after `println`).
- [x] **Specs and repo docs:** Update `docs/specs/08-tests.md` (§3.2–§3.3 and §4 CI wording as needed), `docs/specs/09-tools.md` (relation / pointers to conformance + `npm test`), and `AGENTS.md` (conformance section lists parse + runtime + typecheck).
- [x] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/test-all.sh` from repo root (confirms compiler stage picks up new tests); `./scripts/kestrel test`; `cd vm && zig build test`; `./scripts/run-e2e.sh` if any E2E-relevant behaviour is touched (unlikely for pure conformance).

## Tests to add

### Vitest — parse conformance (`compiler/test/integration/parse-conformance.test.ts`)

- Discover all `tests/conformance/parse/valid/*.ks` and `invalid/*.ks` (sorted); skip gracefully if a directory is empty (same pattern as `typecheck-conformance.test.ts`).
- **Valid:** After `tokenize(source)` and `parse(tokens)`, assert result is a `Program` (narrow with a type guard or `ok` check—`ParseResult` is not discriminated by a literal `ok` field on success; implement `isParseOk(result): result is Program` or equivalent).
- **Invalid:** Assert `parse` returns `{ ok: false }` with non-empty `errors` (or document if any invalid fixture fails earlier in the lexer; adjust fixture or assertion if so).
- **Optional `// EXPECT:`** on the first line of invalid files: assert some `errors[i].message` (or joined text) contains the substring, aligned with typecheck semantics.
- **Regression:** Existing typecheck conformance tests remain unchanged and still pass.

### Vitest — runtime conformance (`compiler/test/integration/runtime-conformance.test.ts`)

- Discover all `tests/conformance/runtime/valid/*.ks` (sorted).
- **Compile:** Emit bytecode to a temp/output dir using the same CLI or programmatic compile path used by E2E / integration tests; fail fast with clear diagnostics on compile error.
- **Run:** Execute the Zig VM binary on the `.kbc`; capture stdout and stderr; assert exit code **0** (document policy for stderr—typically empty for these scenarios).
- **Golden stdout:** Parse each source file for the **`println` + following `//` line** convention (match behaviour of existing `while_count.ks` and siblings; if multiple `println` calls exist, define order of expected chunks—usually concatenate lines with newlines as the VM prints).
- **Multi-module:** If a scenario imports another module, place deps under `tests/fixtures/` (or existing fixture layout) and pass compiler flags / working directory consistent with other integration tests—document in the test module.
- **Determinism:** Avoid wall-clock or randomness; keep GC/async scenarios bounded like existing files.

### Conformance corpora (`.ks` files)

| Directory | Minimum new files | Intent |
|-----------|-------------------|--------|
| `tests/conformance/parse/valid/` | ≥10 | Acceptance themes (shebang, interpolation, precedence, record, list+spread, lambda, nested match, annotations, generics, exception decl). |
| `tests/conformance/parse/invalid/` | ≥5 | Lex/parse failures; stable `// EXPECT:` where possible. |
| `tests/conformance/typecheck/invalid/` | ≥3 | Net-new invalid scenarios per acceptance; grep existing invalid dir first. |
| `tests/conformance/runtime/valid/` | ≥5 | SPREAD, closure val vs var capture, multi-module, deep recursion, runtime string interpolation; `println` + `//` goldens. |

### Kestrel unit (`tests/unit/*.test.ks`)

- **Only if** a scenario cannot be expressed as a conformance file (module boundaries, harness limits). Prefer conformance first; note any exception in **Build notes** when implementing.

### CI / aggregate verification

- `cd compiler && npm run build && npm test` — must include parse, typecheck, and runtime conformance modules.
- `./scripts/test-all.sh` — compiler step above must run; no silent skip of new suites.
- `./scripts/kestrel test` — unchanged expectation: still green unless a corpus file somehow affects shared behaviour (unlikely).
- `cd vm && zig build test` — required if bytecode emission or VM invocation paths change.

## Documentation and specs to update

- [x] [`docs/specs/08-tests.md`](../../specs/08-tests.md) — §3.2 layout (confirm `parse/` and `runtime/`); §3.3 **Running**: state explicitly that **parse** and **runtime** conformance execute under **`cd compiler && npm test`** alongside typecheck conformance; remove or correct any implication that `run-e2e.sh` drives `tests/conformance/runtime/`; §3.5 / §4: align CI wording with actual commands (`test-all.sh` → `npm test` includes conformance).
- [x] [`docs/specs/09-tools.md`](../../specs/09-tools.md) — Relation / “See also” bullets: mention conformance corpora and that compiler Vitest (`npm test`) runs parse + typecheck + runtime conformance, while `run-e2e.sh` covers `tests/e2e/scenarios/*` (orthogonal).
- [x] [`AGENTS.md`](../../../AGENTS.md) — Extend the conformance bullet to list **`tests/conformance/parse/`**, **`typecheck/`**, **`runtime/`** and their Vitest drivers (file names as implemented).
- [x] `tests/conformance/parse/README.md` — **New:** layout, conventions, `// EXPECT:` for invalid, pointer to Vitest file.
- [x] `tests/conformance/runtime/README.md` — Fix **`println`** / `//` golden description; correct CI execution path (Vitest via `npm test`, not `run-e2e.sh`).
- [x] `tests/conformance/typecheck/README.md` — Add short pointer to parse and runtime trees and shared `npm test` story.

## Notes

- If implementing runtime conformance in Vitest, consider extracting shared “expected stdout from `//` lines after `println`” logic into a small helper (under `compiler/test/` or `compiler/test/integration/helpers/`) to avoid duplicating conventions.
- E2E positive scenarios use sibling `*.expected` files; runtime conformance uses **in-file** `//` lines—keep that distinction explicit in READMEs and spec 08 to avoid contributor confusion.

## Build notes

- 2026-03-29: Story reviewed against `docs/kanban/README.md` **planned** exit criteria (impact analysis including stdlib/scripts, concrete tasks, exhaustive test plan, full doc/spec list, acceptance aligned with docs). Promoted **planned → doing** for implementation.
- 2026-03-29: Landed `parse-conformance.test.ts`, `runtime-conformance.test.ts`, and `helpers/runtime-stdout-goldens.ts`. Runtime compile uses a per-run `KESTREL_CACHE` whose paths mirror `scripts/kestrel` (`cacheRoot + absDir + basename.kbc`) so multi-module entry programs load linked deps; emitting only to `/tmp/foo.kbc` was insufficient for imports.
- 2026-03-29: **Typecheck fix:** `AssignStmt` inside `BlockExpr` previously unified like `IdentExpr` assignment and skipped immutable record-field checks; aligned with top-level `AssignStmt` handling (`compiler/src/typecheck/check.ts`). Regression: `compiler/test/integration/typecheck-integration.test.ts` and `tests/conformance/typecheck/invalid/record_immutable_field_assign.ks`.
- 2026-03-29: `async_await.ks` updated to `Task<Int>` return type; `float_ops.ks` gained `//` goldens. Multimodule runtime scenario: `conform_multimodule_caller.ks` + sibling `conform_callee.ks`.
