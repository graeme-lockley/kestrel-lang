# Typecheck conformance tests (spec 08 §2.2, §3.2)

- **valid/** — `.ks` programs that must typecheck successfully.
- **invalid/** — `.ks` programs that must fail typecheck. Optional first-line comment `// EXPECT: substring` asserts that at least one error message contains the given substring.

The compiler test suite runs these under `compiler/test/integration/typecheck-conformance.test.ts`.

## Relationship to compiler unit tests (Vitest)

**Decision:** Keep **both** conformance `.ks` files and **TypeScript** unit/integration tests under `compiler/test/`. They are complementary, not redundant.

| Layer | Role |
|-------|------|
| **`compiler/test/unit/` and `compiler/test/integration/*.test.ts`** | Strong, explicit assertions in TS; shared helpers; multiple cases per test; detailed regression when internals change. |
| **`tests/conformance/typecheck/**/*.ks`** | Small, readable Kestrel programs as a **curated corpus**; easy to add without editing TS; optional `// EXPECT:` pins error substrings on invalid cases. |

Both use the same pipeline for typecheck conformance (`tokenize → parse → typecheck`). Conformance is **data-driven** documentation of expected pass/fail programs; unit tests encode **how** we assert and combine scenarios.

Do **not** drop conformance in favour of TS-only tests unless the project explicitly migrates to a single style and replaces the corpus workflow.
