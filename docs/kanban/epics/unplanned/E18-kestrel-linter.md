# Epic E18: Kestrel Linter

## Status

Unplanned

## Summary

Adds a static analysis (linting) pass to the Kestrel compiler that reports
`warning`-severity diagnostics after the typecheck phase. The linter walks the
typed AST to detect common problems — unused bindings, unused imports, shadowed
variables, dead match arms, and missing doc-comments on exported declarations —
that are correct programs but likely mistakes or style gaps. A new `kestrel lint`
CLI subcommand exposes the linter; `--strict` makes warnings fatal for CI.
The existing diagnostic reporter, error codes, and JSON output format are reused
unchanged. A `warn:*` error-code namespace is introduced to hold all warning codes.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- E14 (Self-hosting compiler) — linter is a post-typecheck AST pass; requires a
  stable typed AST representation.
- E16 (Kestrel CLI in Kestrel) — `kestrel lint` subcommand routes through the
  self-hosted CLI; requires the CLI infrastructure to be in place.

## Epic Completion Criteria

- `kestrel lint <file.ks>` runs without error on all stdlib files and reports
  no false-positive warnings.
- The following warning codes are implemented and tested: `warn:unused_variable`,
  `warn:unused_import`, `warn:unused_parameter`, `warn:shadow`,
  `warn:unreachable_match_arm`, `warn:missing_doc`.
- `--strict` flag makes any warning a non-zero exit code (CI-ready).
- JSON diagnostic output (`--format json`) includes warnings with the same
  structure as errors.
- The `warn:*` namespace is documented in `docs/specs/10-compile-diagnostics.md`.
- Conformance tests cover both expected-warning and expected-no-warning cases
  for every implemented rule.
- `scripts/lint-all.sh` runs `kestrel lint --strict` over the stdlib and exits 0.
