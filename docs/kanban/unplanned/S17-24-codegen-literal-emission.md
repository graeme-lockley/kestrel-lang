# Self-hosted codegen: complete `ELit` emission (string, char, float, unit)

## Sequence: S17-24
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-25 through S17-38 (sibling codegen gap stories), S17-42 (E2E)

## Summary

The self-hosted `emitExpr` in `codegen.ks` correctly emits integer and boolean literals but
pushes `null` for every other literal type. `ELit("string", raw)`, `ELit("char", raw)`,
`ELit("float", raw)`, and `ELit("unit", _)` all fall to the default `pushNull` branch. This
makes string constants, character values, floating-point numbers, and the unit value
unreachable at runtime in any program compiled by the self-hosted codegen.

## Current State

`codegen.ks` `emitExpr`:
- `ELit("int", raw)` — correctly emits a `Long.valueOf(n)` via `LDC2_W` + `INVOKESTATIC`.
- `ELit("bool"/"true"/"false", _)` — correctly emits `Boolean.TRUE`/`Boolean.FALSE`.
- All other `ELit` kinds — fall to `pushNull`.

TS reference (`compiler/src/jvm-codegen/codegen.ts` lines ~1337–1395):
- `"float"` — emits `Double.valueOf(d)` via `LDC2_W` + `INVOKESTATIC`.
- `"string"` — emits `LDC_W` with a constant-pool string entry.
- `"char"` — emits `Integer.valueOf(codePoint)` via `LDC_W` + `INVOKESTATIC`.
- `"unit"` — emits `GETSTATIC KUnit.INSTANCE`.

## Relationship to other stories

- **Depends on**: nothing (literals are leaf nodes).
- **Feeds**: the first real execution tranche (S17-25 + S17-37) and the operator/call stories
      immediately after it. This story should stay complete before broader runtime-sensitive E2E
      re-enable begins.
- **Blocks**: S17-42 (E2E). Without correct literal emission, any string constant, character
  comparison, floating-point computation, or unit return in self-hosted code is broken.
- **Companion**: S17-25..S17-38.

## Goals

1. Add `"float"` arm: parse raw string with `Str.toFloat`, emit `LDC2_W` double constant +
   `INVOKESTATIC Double.valueOf(D)Ljava/lang/Double;`.
2. Add `"string"` arm: emit `LDC_W` with the constant-pool string for the decoded value.
3. Add `"char"` arm: decode the char literal to a Unicode code point, emit `LDC_W` int
   constant + `INVOKESTATIC Integer.valueOf(I)Ljava/lang/Integer;`.
4. Add `"unit"` arm: emit `GETSTATIC kestrel/runtime/KUnit.INSTANCE`.
5. Keep the existing int and bool arms unchanged.

## Acceptance Criteria

- [ ] A program that returns a string literal compiles and produces the correct string at
      runtime when compiled by the self-hosted driver.
- [ ] A program using a character literal compiles correctly.
- [ ] A program returning a float literal compiles and the runtime value is numerically
      correct.
- [ ] A function returning `()` (unit) compiles correctly.
- [ ] New codegen unit tests in `codegen-expr.test.ks` (or equivalent) cover each literal
      kind and assert the emitted bytecode contains the expected constant-pool entry and
      opcode sequence.
- [ ] `cd compiler && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/01-language.md` — literal expressions
- `docs/specs/11-bootstrap.md` — self-hosted codegen responsibilities

## Risks / Notes

- The `classfile.ks` API must expose `cfConstantString`, `cfConstantDouble`, and
  `cfConstantInt` pool-entry helpers. Verify these exist; add them if needed (they likely
  mirror what `classfile.ts` already exposes).
- Char literal decoding must handle escape sequences (`'\n'`, `'\t'`, `'\u1234'` etc.) the
  same way the TS compiler's `charLiteralCodePoint` does.
