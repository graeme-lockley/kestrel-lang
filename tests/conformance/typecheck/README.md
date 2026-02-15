# Typecheck conformance tests (spec 08 §2.2, §3.2)

- **valid/** — `.ks` programs that must typecheck successfully.
- **invalid/** — `.ks` programs that must fail typecheck. Optional first-line comment `// EXPECT: substring` asserts that at least one error message contains the given substring.

The compiler test suite runs these under `compiler/test/integration/typecheck-conformance.test.ts`.
