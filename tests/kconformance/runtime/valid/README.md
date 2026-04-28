# kconformance/runtime/valid — self-hosted runtime conformance (valid programs)

Each `.ks` file here must compile and run to exit 0 via `./kestrel-self run <file>`.

## Golden stdout format

Expected stdout is embedded directly in the source file as `// =>` line comments:

```
println(42)
// => 42
println("hello")
// => hello
```

- Each `// =>` comment documents the expected output of the preceding expression.
- The `=>` arrow distinguishes golden lines from ordinary documentation comments.
- Leading whitespace after `=> ` is preserved but the marker itself is stripped.
- A file with no `// =>` comments asserts exit 0 only (no stdout check).

## CI execution

Driven by `./scripts/test-kestrel.sh` (runtime tier).

**Note:** Until the self-hosted compiler's code generation for top-level programs is complete
(pending codegen stories S17-36/S17-37/S17-38), the runtime tier runs files via
`./kestrel` (TypeScript compiler path). Once self-hosted codegen is functional,
the tier will switch to `./kestrel-self`.

## Baseline (S17-50, 2026-04-28)

- Files: 0
- Baseline source sweep evaluated `tests/conformance/runtime/valid/*.ks`
- Golden format remains `// =>` when runtime files are promoted into this corpus

See also: [../README.md](../README.md), [../../parse/README.md](../../parse/README.md).
