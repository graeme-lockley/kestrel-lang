# 08 – Conformance and Golden Test Plan

Version: 1.0

---

This document describes how to validate that a Kestrel implementation conforms to the language and VM specifications. It covers compiler, VM, and end-to-end behaviour using **conformance tests** (pass/fail and expected-error checks) and **golden tests** (locked observable output for regression).

---

## 1. Scope of Conformance

A conforming implementation must:

- Accept all programs that satisfy the grammar and typing rules in [01-language.md](01-language.md) and [06-typesystem.md](06-typesystem.md), and reject programs that violate them with defined error behaviour.
- Produce bytecode that conforms to [03-bytecode-format.md](03-bytecode-format.md) and uses only instructions and semantics defined in [04-bytecode-isa.md](04-bytecode-isa.md).
- Execute bytecode so that runtime behaviour matches [05-runtime-model.md](05-runtime-model.md) and the semantics implied by the type system and language spec.
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
- **Unions and narrowing:** `is` narrowing and use of values in `A | B` and `A & B` are tested for both valid and invalid usage.

### 2.3 Exceptions and Async

- **Exceptions:** Declaring, throwing, and catching exceptions (including pattern matching in `catch`) behave as in [01-language.md](01-language.md). When no catch case matches, the exception is rethrown (01 §4). Stack traces are available via the Stack module; a conforming implementation must provide some representation of the call stack when `Stack.trace` is used (05 §5).
- **Async:** `async`/`await` and `Task<T>` semantics (including suspension and resumption) are tested; `await` outside async context is rejected.

### 2.4 Bytecode and VM

- **Format:** Emitted `.kbc` files have valid header, section offsets, and section layout per [03-bytecode-format.md](03-bytecode-format.md). Invalid or truncated files are rejected by the VM.
- **Instructions:** Each instruction in [04-bytecode-isa.md](04-bytecode-isa.md) is covered by at least one test that executes it and checks stack/result.
- **Calling convention:** Calls with multiple arguments and returns follow left-to-right argument order and single return value.

### 2.5 Runtime Model

- **Values:** Tagged values (INT, BOOL, UNIT, CHAR, PTR) and heap objects (FLOAT, STRING, RECORD, ADT, TASK, CLOSURE) behave as in [05-runtime-model.md](05-runtime-model.md). Closure values are fn_ref (non-capturing) or PTR to CLOSURE (capturing); see 04 §1.10, 05 §2. No undefined layout assumptions that contradict the spec.
- **GC:** Programs that allocate many short-lived objects complete without leaks; no use-after-free when the GC is enabled.

### 2.6 Modules

- **Resolution:** Local path imports and (where supported) URL imports resolve deterministically; lockfile and cache behaviour match [07-modules.md](07-modules.md).
- **Re-export and conflicts:** Re-exports and name conflicts are tested; conflicts produce compile errors unless renamed.

### 2.7 Standard Library

- **Presence:** Every function in [02-stdlib.md](02-stdlib.md) is present and callable with the specified signature.
- **Contract tests:** Optional “contract” tests that check minimal behaviour (e.g. `string.length("") == 0`, `string.slice(s, 0, n)` returns a string of at most `n` characters) without overspecifying implementation.

---

## 3. Golden Test Plan

### 3.1 Purpose

Golden tests lock observable output (stdout, stderr, return code, or selected VM state) for a fixed source program. They catch unintended changes in compiler or VM behaviour and document expected results.

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
    runtime/       # .ks files run by VM; compare stdout/stderr/exit
  e2e/
    scenarios/     # .ks files; expected stdout in-file as // under each print
  golden/          # optional: separate expected files if not in-source
    source/        # .ks files
    expected/      # .stdout, .stderr, .exit (or one combined .golden per test)
  fixtures/        # Shared .ks modules used by tests
```

Expected output may be stored either in separate golden files (`expected/<name>.stdout`, etc.) or **in-file**: in the Kestrel implementation, E2E scenarios keep expected stdout in the same file as the test by placing a comment line (e.g. `// <expected value>`) immediately after each `print(...)`; the runner collects those lines and compares them to actual stdout so that each scenario and its expected output live in one file.

### 3.3 Running Golden Tests

- **Compile** the source (and dependencies) to bytecode.
- **Run** the bytecode in the VM with defined stdin (e.g. empty or fixed).
- **Capture** stdout, stderr, and exit code.
- **Compare** to golden files (byte-for-byte or normalized). Diff on mismatch fails the test. Tests should use fixed stdin and, where possible, a deterministic environment (e.g. no reliance on wall-clock time or random) so that goldens are stable across runs.

### 3.4 Updating Goldens

When behaviour is intentionally changed, goldens must be updated (e.g. `UPDATE_GOLDEN=1 ./run_tests.sh` or similar). Version control should track golden files so that regressions are visible.

### 3.5 Coverage Goals

- **Core language:** At least one golden (or conformance) test per major feature: literals (all bases, strings with interpolation, chars), conditionals, match (including exhaustiveness), try/catch, lambdas, **nested functions and closures** (block-local `fun`, capture of block/function scope, CALL_INDIRECT, LOAD_FN, MAKE_CLOSURE; recursive nested fun with full signature, by-reference capture of `var`, return-type checking and expected type error for mismatch, chained call of returned closure e.g. `makeAdd(2)(3)`; see [functions.test.ks](../../tests/unit/functions.test.ks) and compiler typecheck/parse tests such as typecheck-conformance and nested_fun_return_type_mismatch), **top-level recursion** (self-recursion and mutual recursion: top-level functions calling each other regardless of declaration order), records, ADTs, pipelines (`|>`/`<|`), async/await.
- **Stdlib:** At least one test that calls each standard module’s main entry points (e.g. string ops, stack trace, http server start/stop, json parse/stringify, fs read).
- **Errors:** Golden or conformance tests for expected compile and runtime errors (e.g. type error message, uncaught exception, overflow).

---

## 4. CI and Conformance Statement

- **CI:** Run the full conformance and golden suite on every commit (or on every PR). Fail the build if any test fails or if goldens differ unless explicitly updated. The “official conformance suite” is the canonical set of tests (layout and cases as described in §2–§3) that may be published alongside the spec; until then, implementors use this document as the test plan.
- **Conformance statement:** Implementations may claim “Kestrel v1 conformant” only if they pass the official conformance suite (when published) and do not contradict the contracts in specs 01–08. Implementations may extend behaviour where the specs allow it (e.g. additional stdlib modules or functions per 02).

---

## 5. Relation to Other Specs

- [01-language.md](01-language.md) – Grammar and language features under test
- [02-stdlib.md](02-stdlib.md) – Stdlib contract tests
- [03-bytecode-format.md](03-bytecode-format.md), [04-bytecode-isa.md](04-bytecode-isa.md) – Bytecode/VM tests
- [05-runtime-model.md](05-runtime-model.md) – Runtime and GC behaviour
- [06-typesystem.md](06-typesystem.md) – Type-checker tests
- [07-modules.md](07-modules.md) – Module resolution tests
- [09-tools.md](09-tools.md) – `kestrel` CLI (user-facing run/build; E2E harness uses compiler/VM directly)
