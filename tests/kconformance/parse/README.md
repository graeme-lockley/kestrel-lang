# kconformance/parse — self-hosted parse conformance

Self-hosted counterpart of `tests/conformance/parse/`.

Each `.ks` file in this directory must **tokenize and parse** successfully when compiled
via `./kestrel-self build <file>` (exit 0).

Run by `./scripts/test-kestrel.sh` (parse tier).

See also: [../typecheck/README.md](../typecheck/README.md), [../runtime/README.md](../runtime/README.md).
