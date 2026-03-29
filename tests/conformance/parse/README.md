# Parse conformance (spec 08 §2.1, §3.2)

- **valid/** — `.ks` sources that must **tokenize and parse** to a full `Program` (no `{ ok: false }` parse bundle).
- **invalid/** — sources that must fail parsing (`{ ok: false }` with at least one error). Optional first-line `// EXPECT: substring` asserts that at least one parse error message contains the substring (same idea as typecheck invalid).

Vitest driver: `compiler/test/integration/parse-conformance.test.ts` (runs under `cd compiler && npm test`).

See also: [../typecheck/README.md](../typecheck/README.md), [../runtime/README.md](../runtime/README.md).
