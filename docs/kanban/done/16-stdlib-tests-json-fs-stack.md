# Stdlib Tests for json, fs, and stack Modules

## Sequence: 16
## Tier: 4 — Stdlib and test harness
## Former ID: 111

## Summary

Three stdlib modules — `kestrel:json`, `kestrel:fs`, and `kestrel:stack` — have implementations but no colocated `*.test.ks` suites. Adding tests documents real VM behaviour (including error and stub paths), prevents regressions, and satisfies the stdlib coverage goals in spec **08**. **`kestrel:fs`** exports `writeText` and `listDir` in source, but **02-stdlib** currently documents only `readText`; this story includes bringing the spec in line with the public API.

## Current State

- `stdlib/kestrel/json.ks`: `parse` and `stringify` exported (`(String) -> Value`, `(Value) -> String` per **02**); no `json.test.ks`.
- `stdlib/kestrel/fs.ks`: `readText` → `Task<String>`, `writeText`, `listDir` exported; **02** documents only `readText`; no `fs.test.ks`.
- `stdlib/kestrel/stack.ks`: `format` and `print` exported (`trace` is deferred to sequence **17** — `docs/kanban/unplanned/17-stdlib-stack-trace-implementation.md`); no `stack.test.ks`.
- **Reference VM behaviour (for test expectations):**
  - **`parse`:** On failure, returns the `Value` **`Null`** constructor (same tag as JSON `null`), not `Result` — so invalid input is **not** distinguishable from the literal JSON `"null"` without additional API changes. `stringify` of `Object` is a stub (`{}` only); **`parse` of objects** yields an `Object` value with **empty** key–value payload (object entries are not yet preserved end-to-end).
  - **`readText`:** Missing or unreadable paths complete as a `Task` whose result is an **empty string** in the current Zig implementation (not a distinct error type in the surface API).
  - **`listDir`:** Returns `List<String>` entries shaped as `"{path}/{name}\tfile"` or `"...\tdir"`; open failures yield an **empty** list.

## Acceptance Criteria

### Documentation (must ship with the tests)

- [x] **`docs/specs/02-stdlib.md` — `kestrel:fs`:** Document **`writeText`** and **`listDir`** with signatures and descriptions consistent with `stdlib/kestrel/fs.ks` and the reference VM (including that `readText` is `Task<String>` and async-shaped).
- [x] **`docs/specs/02-stdlib.md` — `kestrel:json` (if still silent on errors):** Add a short **implementor / observable behaviour** note for `parse` on invalid input (reference VM: failed parse yields `Null`; ambiguity with JSON `null` until a future error channel exists). Adjust wording if the implementation changes during the story.
- [x] **`docs/specs/08-tests.md` — §2.7 Stdlib suites:** Extend the bullet list of `stdlib/kestrel/*.test.ks` modules to include **`kestrel:json`**, **`kestrel:fs`**, and **`kestrel:stack`** once those files exist, so the conformance plan matches the tree.

### Test layout and harness

- [x] **`json.test.ks`**, **`fs.test.ks`**, **`stack.test.ks`** live under `stdlib/kestrel/`, colocated with their modules.
- [x] Each file follows the same pattern as existing stdlib suites (`string.test.ks`, `list.test.ks`, …): `import { Suite, group, eq, … } from "kestrel:test"`, **`export fun run(s: Suite): Unit`** (or **`export async fun run(s: Suite): Task<Unit>`** where `await readText` is required), nested **`group`** labels for each concern. No harness changes are required if naming matches `*.test.ks` (see `scripts/run_tests.ks`).

### Exhaustiveness and quality bar (applies to all three modules)

- [x] **Per-export coverage:** At least one **meaningful** test per **exported** function in `json.ks`, `fs.ks`, and `stack.ks` (not only smoke tests).
- [x] **Granularity:** Match the style of existing stdlib tests: **separate `group`s** per feature (e.g. parse vs stringify, read vs write vs list), and **distinct cases** for different inputs/outcomes (valid vs invalid, empty vs non-empty, typical vs edge), not a single mega-test per module.
- [x] **Determinism:** File-system tests use **dedicated paths** under the repo (e.g. `tests/fixtures/fs/…` or a subdirectory created for the test) and avoid depending on **iteration order** for `listDir` (assert **set membership** of basenames or path fragments, not list position).
- [x] **`readText`:** Tests use **`await`** (signature is `Task<String>`).
- [x] **CI:** `./scripts/kestrel test`, `cd compiler && npm test`, and `cd vm && zig build test` all pass after the change.

### `kestrel:json` — behavioural coverage

- [x] **`parse` — valid JSON:** Cover **null, bool, string, integer, float, array** (including nested array and empty `[]`). Cover **object** with the **actual** reference semantics (e.g. non-empty JSON object still produces an `Object` value whose payload is empty until object support is complete — assert that so regressions are visible).
- [x] **`stringify` + `parse` round-trip** for every **JSON kind the VM fully round-trips** today; where round-trip is impossible (e.g. object contents dropped), assert **documented** `stringify(parse(x))` or `parse(stringify(v))` behaviour instead of pretending full fidelity.
- [x] **`parse` — invalid / malformed input:** Assert **observable** reference behaviour (failed parse → **`Null`** per current VM) and document the **ambiguity** with JSON `"null"` in a comment or in **02** as above.
- [x] **Strings:** At least one test with escapes or non-ASCII if the primitive supports them (e.g. `\n`, Unicode) to lock UTF-8 / escaping behaviour.

### `kestrel:fs` — behavioural coverage

- [x] **`readText`:** Success — read a **known fixture** file and compare contents.
- [x] **`readText`:** Missing file (or unreadable path) — assert **current** completed-`Task` / string behaviour (see Current State).
- [x] **`writeText`:** Write then **`readText`** round-trip (use a path under a test-controlled directory; clean up or use a unique name to avoid flakes).
- [x] **`listDir`:** Directory with **known** entries — assert each expected name appears **somewhere** in the result (format includes `\tfile` / `\tdir` per VM); include **empty directory** or **failed open → empty list** if a stable fixture exists.

### `kestrel:stack` — behavioural coverage

- [x] **`format`:** Several **distinct** types or values (e.g. `Int`, `String`, `Bool`, `Unit`, and at least one composite if `__format_one` supports it) — assert **non-empty** strings where the formatted form is stable enough to assert substring or length bounds.
- [x] **`print`:** Smoke test that calls do **not** throw; optional strict stdout check only if the harness makes it reliable.

## Spec References

- **02-stdlib** — `kestrel:json`, `kestrel:fs`, `kestrel:stack` (update **fs** table; optional **json** parse-error note).
- **08-tests** — stdlib suites list §2.7; coverage goals §3.5 (stdlib entry points).
- **05-runtime-model** §5 — stack traces (`trace` remains story **17**; this story only covers `format` / `print`).
- **07-modules** — stdlib specifiers for these modules (no change expected unless names conflict).

## Tasks

- [x] Add `json.test.ks`, `fs.test.ks`, `stack.test.ks` and `tests/fixtures/fs/*` fixtures
- [x] Update `docs/specs/02-stdlib.md` (fs API, json parse note) and `docs/specs/08-tests.md` §2.7
- [x] Fix test harness generator (`scripts/run_tests.ks`: avoid `run${idx}` / fragile template interpolation; build runner source with `__string_concat`)
- [x] Enable `export async fun` / async `Task` return (parser, typecheck, VM `taskReturnUnit`, JVM `AwaitExpr`) and align `readText` error path with empty `String` (VM + JVM)
- [x] Run `./scripts/kestrel test`, `cd compiler && npm test`, `cd vm && zig build test`, `./scripts/run-e2e.sh`
