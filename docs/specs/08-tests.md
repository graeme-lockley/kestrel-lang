# 08 – Conformance and Golden Test Plan

Version: 1.0

---

This document describes how to validate that a Kestrel implementation conforms to the language and JVM runtime specifications. It covers compiler, JVM runtime, and end-to-end behaviour using **conformance tests** (pass/fail and expected-error checks) and **golden tests** (locked observable output for regression).

---

## 1. Scope of Conformance

A conforming implementation must:

- Accept all programs that satisfy the grammar and typing rules in [01-language.md](01-language.md) and [06-typesystem.md](06-typesystem.md), and reject programs that violate them with defined error behaviour.
- Produce JVM classfiles that execute with language semantics defined by [01-language.md](01-language.md) and [06-typesystem.md](06-typesystem.md).
- Execute compiled output so that runtime behaviour matches the JVM runtime implementation and the semantics implied by the type system and language spec.
- Resolve modules according to [07-modules.md](07-modules.md).
- Expose the standard library contract in [02-stdlib.md](02-stdlib.md) with the specified signatures and observable behaviour.

---

## 2. Test Categories

### 2.1 Parser and Lexer

- **Valid programs:** Every production in the grammar (see [01-language.md](01-language.md)) is covered by at least one test that parses successfully.
- **Invalid programs:** Malformed tokens, invalid keyword/identifier use, and syntax errors produce clear parse/lex errors (no crash, no silent accept). Tests in `invalid/` may pair each source file with an expected error output (e.g. a substring that must appear in the compiler’s stderr or error message) so that the *kind* of error is asserted, not only that parsing failed.
- **Literals:** All literal forms (integers in all bases, strings with interpolation, chars, runes, unit, booleans) parse and are preserved in AST or IR.

### 2.2 Type Checker

- **Inference:** Programs that should type-check (including polymorphic and row-polymorphic functions) are accepted; inferred types match expected principal types where specified.
- **Rejection:** Programs that violate the type rules (e.g. wrong arity, missing cases in match, unification failures, row conflicts) are rejected with a type error. Tests in `typecheck/invalid/` may assert that a specific type error (or error substring) is produced.
- **Tuple `match`:** `tests/unit/match.test.ks` exercises tuple destructuring, nested tuples, wildcards, literal slots, and catch-all arms. `tests/conformance/typecheck/valid/tuple_pattern_match.ks` and `tests/conformance/typecheck/invalid/tuple_*.ks` cover typing and exhaustiveness for tuple patterns.
- **Unions and narrowing (`is`):** Compiler: `compiler/test/unit/typecheck/is-narrowing.test.ts` (then/else/`while`, Option, unions, ADTs, records, impossible narrow); `compiler/test/integration/parse.test.ts` (grammar/precedence). Conformance: `tests/conformance/typecheck/valid/narrowing_option.ks`, `narrowing_union.ks`; invalid `tests/conformance/typecheck/invalid/narrowing_impossible.ks` with `// EXPECT:`. Runtime harness: `tests/unit/narrowing.test.ks`. Intersection **`A & B`** typing remains covered by the general typecheck suite where applicable.
- **Union / intersection subtyping (call, return, assignment):** `compiler/test/unit/typecheck/unify.test.ts` (`unifySubtype`); conformance `tests/conformance/typecheck/valid/union_intersection_subtyping.ks`, invalid `union_not_subtype_of_int_param.ks`; runtime `tests/unit/union_intersection.test.ks`.

### 2.3 Exceptions and Async

- **Exceptions:** Declaring, throwing, and catching exceptions (including pattern matching in `catch`) behave as in [01-language.md](01-language.md). When no catch case matches, the exception is rethrown (01 §4). Stack traces are available via the Stack module; a conforming implementation must provide some representation of the call stack when `Stack.trace` is used (05 §5).
- **Async:** `async`/`await` and `Task<T>` semantics (including suspension and resumption) are tested; `await` outside async context is rejected. Tests for independent tasks must assert aggregated outcomes without depending on completion order.

### 2.4 Bytecode and Runtime

- **Format:** Emitted `.class` files load and execute on the JVM runtime.
- **Instructions:** Runtime-sensitive features are covered end-to-end through compiler + runtime tests (record spread, narrowing, async/await, exceptions).
- **Calling convention:** Calls with multiple arguments and returns follow left-to-right argument order and single return value.

### 2.5 Runtime Model

- **Values:** Primitive and heap values behave consistently with language semantics on the JVM runtime. Closure values preserve lexical capture semantics for both capturing and non-capturing functions.
- **Integer overflow and division by zero:** `tests/unit/overflow_divzero.test.ks` asserts that 61-bit `Int` overflow on `+`, `-`, `*` and divide/mod by zero throw catchable exceptions (`ArithmeticOverflow`, `DivideByZero`) defined in the same module, including when tests run as an imported module.
- **GC:** Programs that allocate many short-lived objects complete without leaks; no use-after-free when the GC is enabled.

### 2.6 Modules

- **Resolution:** Local path imports and (where supported) URL imports resolve deterministically; lockfile and cache behaviour match [07-modules.md](07-modules.md).
- **Re-export and conflicts:** Re-exports and name conflicts are tested; conflicts produce compile errors unless renamed.
- **Namespace imports and ADT constructors:** `import * as M from "…"` exposes exported **non-opaque** ADT constructors as `M.Ctor` / `M.Ctor(…)` with correct typing and runtime interop (same ADT identity as construction in the exporter). Coverage includes nullary, unary, and multi-argument constructors; opaque constructor rejection; wrong name, arity, and argument types. See `tests/unit/namespace_import.test.ks` and `tests/fixtures/opaque_pkg/`.

### 2.7 Standard Library

- **Presence:** Every function in [02-stdlib.md](02-stdlib.md) is present and callable with the specified signature.
- **Contract tests:** Optional “contract” tests that check minimal behaviour (e.g. `string.length("") == 0`, `string.slice(s, 0, n)` returns a string of at most `n` characters) without overspecifying implementation.
- **Stdlib suites:** `stdlib/kestrel/*.test.ks` (picked up by `./scripts/kestrel test`) hold broader behaviour tests for `kestrel:string`, `kestrel:list`, `kestrel:tuple`, `kestrel:char`, `kestrel:basics`, `kestrel:option`, `kestrel:result`, `kestrel:dict`, `kestrel:set`, `kestrel:json`, `kestrel:fs`, `kestrel:stack`, and **`kestrel:test`** (`stdlib/kestrel/test.test.ks` colocated with `stdlib/kestrel/test.ks`). Each suite module must export `async fun run(s: Suite): Task<Unit>`, and the generated harness runner invokes every suite with `await` in sequence. The `kestrel:test` module exports `Suite`, `outputVerbose` / `outputCompact` / `outputSummary` (Int mode constants for `Suite.output`), `group`, `eq`, `neq`, `isTrue`, `isFalse`, `gt`, `lt`, `gte`, `lte` (ordering on `Int` only), `throws` (`(Unit) -> Unit` thunk), and `printSummary`; see the **kestrel:test** section in [02-stdlib.md](02-stdlib.md). Empty lists in assertions may use `join`/`List.length` instead of `eq([], [])` where list equality is not reliable in the harness.

---

## 3. Golden Test Plan

### 3.1 Purpose

Golden tests lock observable output (stdout, stderr, return code, or selected runtime state) for a fixed source program. They catch unintended changes in compiler or JVM runtime behaviour and document expected results.

### 3.2 Layout

Recommended layout:

```
tests/
  conformance/
    parse/
      valid/       # .ks files that must parse
      invalid/     # .ks files that must fail with expected error snippet
    typecheck/
      valid/
      invalid/
    runtime/       # .ks files run by JVM runtime; compare stdout/stderr/exit
  e2e/
    scenarios/
      negative/    # .ks files: compile failure OR JVM runtime non-zero; optional E2E_EXPECT_STACK_TRACE stderr checks
      positive/    # .ks files with sibling *.expected stdout goldens
  golden/          # optional: separate expected files if not in-source
    source/        # .ks files
    expected/      # .stdout, .stderr, .exit (or one combined .golden per test)
  fixtures/        # Shared .ks modules used by tests
```

Expected output may be stored either in separate golden files (`expected/<name>.stdout`, etc.) or **in-file**: for **positive** E2E under `tests/e2e/scenarios/positive/`, expected stdout lives in a sibling `*.expected` file; the runner compares runtime stdout to that file.

**Negative E2E** (`tests/e2e/scenarios/negative/`): `./scripts/run-e2e.sh` compiles each top-level `*.ks` with `node compiler/dist/cli.js` and, if compilation succeeds, executes the compiled `.class` files on the JVM runtime. The scenario passes if compilation fails **or** the JVM runtime exits non-zero. Selected scenarios may include `E2E_EXPECT_STACK_TRACE` in a top comment so the harness asserts stderr shape (uncaught exception / stack trace, operand stack overflow, or call-depth limit) — see `scripts/run-e2e.sh`.

### 3.3 Running Golden Tests

- **Compile** the source (and dependencies) to `.class` files.
- **Run** the `.class` files on the JVM runtime with defined stdin (e.g. empty or fixed).
- **Capture** stdout, stderr, and exit code.
- **Compare** to golden files (byte-for-byte or normalized). Diff on mismatch fails the test. Tests should use fixed stdin and, where possible, a deterministic environment (e.g. no reliance on wall-clock time or random) so that goldens are stable across runs.
- **Conformance corpora in CI (compiler Vitest):** From the repo root, `cd compiler && npm run build && npm test` runs:
  - **Parse** corpus under `tests/conformance/parse/` (`parse-conformance.test.ts`).
  - **Typecheck** corpus under `tests/conformance/typecheck/` (`typecheck-conformance.test.ts`).
  - **Runtime (JVM)** corpus under `tests/conformance/runtime/valid/` (`runtime-conformance.test.ts`), compiling with `dist/cli.js` and executing on the JVM runtime, comparing stdout to in-file `//` golden lines after each `println` (see `tests/conformance/runtime/README.md`).
- **E2E runner:** From the repo root, `./scripts/run-e2e.sh` runs all `tests/e2e/scenarios/negative/*.ks` as above, then all `tests/e2e/scenarios/positive/*.ks` against their `*.expected` files. `./scripts/test-all.sh` includes this step after compiler and runtime tests. **`run-e2e.sh` does not execute `tests/conformance/runtime/`**; runtime conformance is covered by the compiler Vitest module above.

### 3.4 Updating Goldens

When behaviour is intentionally changed, goldens must be updated (e.g. `UPDATE_GOLDEN=1 ./run_tests.sh` or similar). Version control should track golden files so that regressions are visible.

### 3.5 Coverage Goals

- **Core language:** At least one golden (or conformance) test per major feature: literals (all bases, strings with interpolation, chars), conditionals, **`is` type tests and narrowing** (`tests/unit/narrowing.test.ks`, conformance `narrowing_*.ks`), **blocks in statement vs expression context** (01 §3.3: e.g. implicit **Unit** after the last `:=` / `val` / `var` / `fun` in `while` bodies and top-level expression statements; parse rejection when the same shape appears in expression position—see compiler `parse.test.ts`), match (including exhaustiveness), try/catch, lambdas, **nested functions and closures** (block-local `fun`, capture of block/function scope, CALL_INDIRECT, LOAD_FN, MAKE_CLOSURE; recursive nested fun with full signature, by-reference capture of `var`, return-type checking and expected type error for mismatch, chained call of returned closure e.g. `makeAdd(2)(3)`; see [functions.test.ks](../../tests/unit/functions.test.ks) and compiler typecheck/parse tests such as typecheck-conformance and nested_fun_return_type_mismatch), **top-level recursion** (self-recursion and mutual recursion: top-level functions calling each other regardless of declaration order), **tail-call optimization** on the VM (deep self-tail in [tail_self_recursion.test.ks](../../tests/unit/tail_self_recursion.test.ks); mutual tail and indirect fallback in [tail_mutual_recursion.test.ks](../../tests/unit/tail_mutual_recursion.test.ks); compiler bytecode checks in `compiler/test/unit/mutual-tail-codegen.test.ts`), records, ADTs, pipelines (`|>`/`<|`), async/await.
- **Stdlib:** At least one test that calls each standard module’s main entry points (e.g. string ops, **`kestrel:stack`** `format` / `print` / **`trace`** with a caught exception — see **`stdlib/kestrel/stack.test.ks`**; http server start/stop; `kestrel:json` `parse` / `stringify` / `Result` error paths; fs read).
- **Errors:** Conformance and unit tests cover expected compile and runtime errors (e.g. type error messages via `tests/conformance/typecheck/invalid/`). **Negative E2E** under `tests/e2e/scenarios/negative/` adds full **compiler emit → `.class` → JVM runtime** checks for representative failures (compile rejections and non-zero runtime exits), with optional stderr assertions for uncaught-exception-style output where marked.

---

## 4. CI and Conformance Statement

- **CI:** Run the full conformance and golden suite on every commit (or on every PR). Fail the build if any test fails or if goldens differ unless explicitly updated. **`./scripts/test-all.sh`** runs compiler tests (`cd compiler && npm test`, which includes parse, typecheck, and runtime conformance per §3.3), JVM runtime unit tests, E2E (`run-e2e.sh`), and Kestrel harness tests as defined in the project scripts. The "official conformance suite" is the canonical set of tests (layout and cases as described in §2–§3) that may be published alongside the spec; until then, implementors use this document as the test plan.
- **Conformance statement:** Implementations may claim “Kestrel v1 conformant” only if they pass the official conformance suite (when published) and do not contradict the contracts in specs 01–08. Implementations may extend behaviour where the specs allow it (e.g. additional stdlib modules or functions per 02).

---

## 5. Relation to Other Specs

- [01-language.md](01-language.md) – Grammar and language features under test
- [02-stdlib.md](02-stdlib.md) – Stdlib contract tests
- [06-typesystem.md](06-typesystem.md) – Type-checker tests
- [07-modules.md](07-modules.md) – Module resolution tests
- [09-tools.md](09-tools.md) – `kestrel` CLI (user-facing run/build; E2E harness uses compiler/JVM runtime directly)
