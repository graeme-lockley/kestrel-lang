# kconformance/runtime — self-hosted runtime conformance

Self-hosted counterpart of `tests/conformance/runtime/`.

- **valid/** — `.ks` programs that must compile, execute on the JVM runtime with exit code 0,
  and produce stdout that matches `// =>` golden lines in the source file.

Run by `./scripts/test-kestrel.sh` (runtime tier).

## Baseline (S17-50, 2026-04-28)

- Files in `valid/`: 0
- Source sweep: `tests/conformance/runtime/valid/*.ks`
- Pass criterion during sweep: `./kestrel run --clean <file>` exits 0
- Current status: no runtime conformance files met the baseline pass criterion yet; the
    tier remains active but empty until self-hosted codegen stories raise coverage.

See also: [../parse/README.md](../parse/README.md), [../typecheck/README.md](../typecheck/README.md).
