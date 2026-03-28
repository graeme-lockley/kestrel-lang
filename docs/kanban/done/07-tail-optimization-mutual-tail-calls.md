# Tail optimization for mutual tail calls

## Sequence: 07
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (unplanned)

## Summary

Extend tail-call optimization beyond direct self recursion to support **mutual tail recursion** across functions, enabling constant-stack execution for state machines and alternation patterns expressed as tail calls.

## Motivation

- Many recursive loop encodings use two or more functions calling each other in tail position.
- Optimizing only self recursion still leaves common patterns vulnerable to stack overflow.
- This story completes a practical TCO model for loop-like recursion without changing source syntax.

## Current State

- **Done (`.kbc` / Zig VM):** Top-level mutual tail calls between sibling functions in the same module are lowered to `STORE_LOCAL` + PC-relative `JUMP` (deferred patching after all function chunks have known `codeOffset`s). Ineligible sites keep `CALL`. JVM backend keeps **self**-tail `GOTO` only; cross-function tail stays `INVOKESTATIC` (documented in 04 §1.5).
- Tests: `tests/unit/tail_mutual_recursion.test.ks`, `compiler/test/unit/mutual-tail-codegen.test.ts`.
- Specs updated: `01-language.md`, `04-bytecode-isa.md`, `05-runtime-model.md`, `06-typesystem.md`, `08-tests.md`.

## Design

- Build on self-TCO infrastructure from sequence 06.
- Eligibility: tail position, callee is another **top-level** `fun` in the same module (by name → function index), argument count equals callee arity, direct `CALL` lowering (not `CALL_INDIRECT`, not imports, not namespace calls, not nested `fun`).
- Deferred jump patching: mutual targets may be emitted later in the module code stream.
- Semantic-preserving; non-eligible calls unchanged.

## Tasks

- [x] Extend `compiler/src/codegen/codegen.ts` with peer map + deferred mutual-tail patches
- [x] Kestrel stress tests + shallow indirect (closure) fallback tests
- [x] Vitest bytecode assertions (no `CALL` in mutual pair; `CALL` when not tail)
- [x] Spec updates (01, 04, 05, 06, 08); JVM comment in `jvm-codegen/codegen.ts`

## Acceptance Criteria

- [x] Tail-call lowering applies to eligible mutual tail calls (same-module top-level siblings, arity match, tail position).
- [x] Zig VM runs eligible mutual tail-recursive cycles without linear frame growth (`even`/`odd`, three-state cycle).
- [x] Non-eligible cases use normal `CALL` / `CALL_INDIRECT` (non-tail partner call; closure/indirect bridge).
- [x] Stress tests: large-depth `even`/`odd` and multi-function cycle.
- [x] Eligibility and JVM limitation documented in specs (no new user diagnostics).
- [x] Specs list supported TCO model and limits (04 §1.5, 05 §1.2).

## Test Expectations

- [x] Kestrel: `isEven`/`isOdd` at 300k; `state0`/`state1`/`state2` cycle at 90k steps.
- [x] Kestrel: closure bridge (`oddViaClosure`) shallow correctness (indirect tail path).
- [x] Compiler: `mutual-tail-codegen.test.ts` (no `Op.CALL` in optimized pair; `CALL` inside non-tail mutual body).

## Spec References

- 01-language.md — tail-position calls to sibling top-level functions
- 04-bytecode-isa.md — TCO rules, JVM caveat
- 05-runtime-model.md — frame reuse for mutual tail
- 06-typesystem.md — TCO is codegen-only
- 08-tests.md — unit test pointers
