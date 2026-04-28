# kconformance/parse — self-hosted parse conformance

Self-hosted counterpart of `tests/conformance/parse/`.

Each `.ks` file in this directory must **tokenize and parse** successfully when compiled
via `./kestrel-self build <file>` (exit 0).

Run by `./scripts/test-kestrel.sh` (parse tier).

## Baseline (S17-50, 2026-04-28)

- Files: 12
- Source sweep: `tests/conformance/parse/**/*.ks`
- Pass criterion: `./kestrel-self build --clean <file>` exits 0
- Provenance: each copied file includes a leading `// Provenance: ... (baseline S17-50)` line

See also: [../typecheck/README.md](../typecheck/README.md), [../runtime/README.md](../runtime/README.md).
