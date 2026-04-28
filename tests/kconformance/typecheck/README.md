# kconformance/typecheck — self-hosted typecheck conformance

Self-hosted counterpart of `tests/conformance/typecheck/`.

Each `.ks` file in this directory must **compile without type errors** when compiled
via `./kestrel-self build <file>` (exit 0).

Run by `./scripts/test-kestrel.sh` (typecheck tier).

See also: [../parse/README.md](../parse/README.md), [../runtime/README.md](../runtime/README.md).
