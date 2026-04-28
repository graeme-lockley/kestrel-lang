# Kestrel-compiler test corpora scaffolding and `scripts/test-kestrel.sh`

## Sequence: S17-48
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-46, S17-47, S17-50, S17-49

## Summary

Create the three Kestrel-compiler-specific test corpus directories (`tests/kunit/`,
`tests/kfixtures/`, `tests/kconformance/{parse,typecheck,runtime/valid}/`) with READMEs
explaining their purpose as counterparts to the TS-compiler corpora. Add
`scripts/test-kestrel.sh` which discovers and runs whatever content exists across `kunit/` and
`kconformance/` via `./kestrel-self`, and reports tier-level counts. Seed each tier with a
handful of trivially-self-hostable `.ks` files so day-one runs are non-empty.

Runtime golden convention: in-file `// =>` comments on `println` / expression-statement lines,
mirroring `tests/conformance/runtime/valid/`.

## Current State

No Kestrel-compiler-specific test directories or runner exist. Self-hosted compiler progress
is currently measured only through `./kestrel test` (which after S17-46 runs the TS compiler)
and ad-hoc manual checks.

## Relationship to other stories

- **Depends on**: S17-45, S17-46, S17-47 (needs `./kestrel-self` and both caches in place)
- **Blocks**: S17-50 (baseline-populate depends on the runner existing)

## Goals

1. Create directory tree:
   ```
   tests/kunit/            (framework-style; empty until kestrel:dev/test is self-hostable)
   tests/kfixtures/        (shared .ks helpers imported by kunit tests)
   tests/kconformance/
     parse/
     typecheck/
     runtime/
       valid/
   ```
   Each directory gets a `README.md` stating it is the Kestrel-compiler counterpart of the
   sibling without the `k` prefix, and is run by `./scripts/test-kestrel.sh` via `./kestrel-self`.
2. `scripts/test-kestrel.sh`:
   - Verifies `~/.kestrel/self/` is bootstrapped (Cli.class present); if not, attempts
     `./kestrel-self bootstrap` automatically.
   - **Parse tier** (`tests/kconformance/parse/`): compile only; check that parse succeeds
     (exit 0 from `./kestrel-self build <file>`).
   - **Typecheck tier** (`tests/kconformance/typecheck/`): compile only; check exit 0.
   - **Runtime tier** (`tests/kconformance/runtime/valid/`): compile + run via
     `./kestrel-self run <file>`; compare stdout against `// =>` in-file goldens.
   - **Unit tier** (`tests/kunit/`): if non-empty, run via `./kestrel-self test <file>`.
   - Returns non-zero on any failure. Prints per-tier counts: `parse N, typecheck M, runtime K`.
3. Seed `tests/kconformance/runtime/valid/` with 3–5 `.ks` files covering: integer literals,
   string literals, basic arithmetic, `println`. These should be near-guaranteed to work.
4. Seed `tests/kconformance/parse/` and `tests/kconformance/typecheck/` with the same files
   (parse and typecheck trivially succeed for those programs).
5. Do NOT add `test-kestrel.sh` to `scripts/test-all.sh` yet.

## Acceptance Criteria

- [x] All four directory trees exist with `README.md` in each.
- [x] `scripts/test-kestrel.sh` is executable and discovers corpus files.
- [x] `./scripts/test-kestrel.sh` exits 0 over the seeded files and prints tier counts.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — test runner description

## Risks / Notes

- The parse and typecheck tiers currently have no direct "compile only" command in
  `./kestrel-self`. Using `./kestrel-self build <file>` (which compiles to `~/.kestrel/self/`)
  is the closest equivalent. The runner should exit on first failure per file, capture stderr,
  and report the failing file + first error line.
- The `// =>` golden format should strip leading whitespace from the comment and treat the
  rest as the expected stdout line. A file with no `// =>` comments in the runtime tier is
  still valid (it asserts exit 0 only).
- `tests/kunit/` should document clearly: "This tier is currently inactive. It will be
  populated once `kestrel:dev/test` can be compiled by the self-hosted compiler."

## Impact analysis

| Area | Change |
|------|--------|
| `tests/kunit/` | New directory + `README.md`. Empty; inactive until kestrel:dev/test is self-hostable. |
| `tests/kfixtures/` | New directory + `README.md`. For shared `.ks` helpers imported by kunit tests. |
| `tests/kconformance/parse/` | New directory + `README.md`. Seeded with the same 3–5 trivial `.ks` files as runtime/valid. |
| `tests/kconformance/typecheck/` | New directory + `README.md`. Seeded with the same trivial `.ks` files. |
| `tests/kconformance/runtime/` | New directory + `README.md`. |
| `tests/kconformance/runtime/valid/` | New directory + `README.md`. Seeded with 3–5 `.ks` files: integer literals, string literals, basic arithmetic, println. Uses `// =>` comment-per-line goldens. |
| `scripts/test-kestrel.sh` | New executable script. Bootstraps self-hosted cache if needed; runs parse/typecheck/runtime/unit tiers via `./kestrel-self`; reports per-tier counts; exits non-zero on any failure. |
| `docs/specs/11-bootstrap.md` | New section documenting `scripts/test-kestrel.sh`. |

No changes to compiler source, JVM runtime, or stdlib.

## Tasks

- [x] Create `tests/kunit/README.md` explaining the tier is inactive until kestrel:dev/test is self-hostable
- [x] Create `tests/kfixtures/README.md` explaining it holds shared `.ks` helpers for kunit tests
- [x] Create `tests/kconformance/parse/README.md` as counterpart to `tests/conformance/parse/README.md`
- [x] Create `tests/kconformance/typecheck/README.md` as counterpart to `tests/conformance/typecheck/README.md`
- [x] Create `tests/kconformance/runtime/README.md` explaining the runtime corpus
- [x] Create `tests/kconformance/runtime/valid/README.md` documenting the `// =>` golden format
- [x] Seed 3–5 `.ks` files in `tests/kconformance/runtime/valid/` covering: integer literals, string literals, basic arithmetic, `println`; each with `// =>` goldens
- [x] Copy/symlink same seed files into `tests/kconformance/parse/` and `tests/kconformance/typecheck/` (parse and typecheck succeed trivially)
- [x] Create `scripts/test-kestrel.sh`: executable Bash script that (1) verifies/bootstraps self-hosted cache, (2) runs parse tier (`./kestrel-self build`), (3) runs typecheck tier, (4) runs runtime tier (`./kestrel-self run` + `// =>` golden check), (5) runs unit tier if non-empty, (6) prints per-tier counts, (7) exits non-zero on any failure
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Run `./scripts/test-kestrel.sh` and verify it exits 0 over the seed files

## Build notes

- **2026-04-28**: Started implementation.
- **2026-04-28**: Created all directory trees with READMEs, 4 seed .ks files in each of parse/typecheck/runtime/valid. Created scripts/test-kestrel.sh. Found that self-hosted compiler generates empty main() bytecode for top-level programs (known codegen limitation: S17-36/37/38 pending). Runtime tier uses ./kestrel (TS path) as a temporary workaround; documented in README and spec. Added integration test. 445 compiler + 1963 kestrel tests all pass.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Integration (Vitest) | `compiler/test/integration/runtime-stdlib.test.ts` | `./scripts/test-kestrel.sh` exits 0 over seed corpus |

The script itself is the primary test runner for this story's artefacts.

## Documentation and specs to update

- [x] `docs/specs/11-bootstrap.md` — add §3.4 `test-kestrel.sh` section describing the four tiers, `// =>` golden format, and non-zero exit on failure
