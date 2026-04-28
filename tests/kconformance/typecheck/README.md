# kconformance/typecheck — self-hosted typecheck conformance

Self-hosted counterpart of `tests/conformance/typecheck/`.

Each `.ks` file in this directory must **compile without type errors** when compiled
via `./kestrel-self build <file>` (exit 0).

Run by `./scripts/test-kestrel.sh` (typecheck tier).

## Baseline (S17-50, 2026-04-28)

- Files: 37
- Source sweep: `tests/conformance/typecheck/**/*.ks`
- Pass criterion: `./kestrel-self build --clean <file>` exits 0
- Provenance: each copied file includes a leading `// Provenance: ... (baseline S17-50)` line

See also: [../parse/README.md](../parse/README.md), [../runtime/README.md](../runtime/README.md).
