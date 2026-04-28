# kconformance/runtime — self-hosted runtime conformance

Self-hosted counterpart of `tests/conformance/runtime/`.

- **valid/** — `.ks` programs that must compile, execute on the JVM runtime with exit code 0,
  and produce stdout that matches `// =>` golden lines in the source file.

Run by `./scripts/test-kestrel.sh` (runtime tier).

See also: [../parse/README.md](../parse/README.md), [../typecheck/README.md](../typecheck/README.md).
