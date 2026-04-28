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

- [ ] All four directory trees exist with `README.md` in each.
- [ ] `scripts/test-kestrel.sh` is executable and discovers corpus files.
- [ ] `./scripts/test-kestrel.sh` exits 0 over the seeded files and prints tier counts.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

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
