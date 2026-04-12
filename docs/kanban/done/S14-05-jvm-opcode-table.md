# JVM Opcode Table

## Sequence: S14-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/jvm-codegen/opcodes.ts` (~190 lines) to
`stdlib/kestrel/tools/compiler/opcodes.ks`. This small module defines the JVM opcode byte
constants, access-flag constants, and JVM type-descriptor helper functions used by both the
classfile writer (S14-06) and the code generator (S14-07/S14-08).

## Current State

`compiler/src/jvm-codegen/opcodes.ts` exports:
- `JvmOp` enum with ~80 opcode byte values (`NOP`, `ALOAD_0`, `INVOKEVIRTUAL`, etc.)
- Access-flag constants: `ACC_PUBLIC`, `ACC_STATIC`, `ACC_PRIVATE`, `ACC_FINAL`, etc.
- `descriptorForType(t: InternalType): string` — JVM type descriptor string for a given type
- `methodDescriptor(params, returnType)` — builds `(Lpkg/Class;...)Rettype;` strings
- `jvmSlotSize(t: InternalType): number` — slot width (1 for most types, 2 for long/double)

## Relationship to other stories

- **Depends on**: S14-02 (InternalType — for `descriptorForType`)
- **Blocks**: S14-06 (classfile writer uses opcode constants), S14-07/S14-08 (codegen uses opcodes)
- Independent of S14-01 (diagnostics), S14-03 (unify), S14-04 (typecheck)

## Goals

1. Create `stdlib/kestrel/tools/compiler/opcodes.ks` with:
   - `JvmOp` record or a set of exported `val` constants for each opcode byte value
   - Access-flag constants (`accPublic`, `accStatic`, etc.)
   - `descriptorForType(t: InternalType): String`
   - `methodDescriptor(params: List<InternalType>, ret: InternalType): String`
   - `jvmSlotSize(t: InternalType): Int`

## Acceptance Criteria

- `stdlib/kestrel/tools/compiler/opcodes.ks` compiles without errors.
- A test file `stdlib/kestrel/tools/compiler/opcodes.test.ks` verifies:
  - a selection of opcode constants have the correct byte values (e.g. `NOP = 0`, `ARETURN = 0xB0`)
  - `descriptorForType(tInt)` returns `"J"` (JVM long)
  - `descriptorForType(tBool)` returns `"Ljava/lang/Boolean;"`
  - `methodDescriptor([tInt], tString)` returns `"(J)Ljava/lang/String;"`
  - `jvmSlotSize(tInt)` returns `2` (long → 2 slots)
- `./kestrel test stdlib/kestrel/tools/compiler/opcodes.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/jvm-codegen/opcodes.ts`
- JVM spec Chapter 6 (opcode table)

## Risks / Notes

- TypeScript uses a `const enum`, which erases to numeric literals; Kestrel does not have
  enums so use exported `val` constants of type `Int`.
- Access flags use bitwise OR composition in the codegen; ensure Kestrel's bitwise operators
  (`land`, `lor`, etc. or `&`, `|`) are used correctly — Kestrel uses `&` and `|` for bitwise ops on Int.
- `descriptorForType` must match exactly what the TypeScript compiler produces for interoperability
  during the bootstrap transition period.
- `descriptorForType` is NOT in `opcodes.ts` in the TypeScript codebase — it's an `externReturnDescriptorForType`
  in `codegen.ts`. For the self-hosted version we create a canonical `descriptorForType` that maps
  `InternalType` primitives to raw JVM descriptors (Int→J, Float→D, Char/Rune→I, everything else boxed).

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib | Add `stdlib/kestrel/tools/compiler/opcodes.ks` with ~80 JVM opcode `val` constants, 18 access-flag constants, and three helpers: `descriptorForType`, `methodDescriptor`, `jvmSlotSize`. |
| Stdlib deps | Imports `kestrel:tools/compiler/types` for `InternalType` (S14-02). |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/opcodes.test.ks` verifying selected opcode values, descriptor generation, and slot sizes. |
| Docs | Update `docs/guide.md` with `kestrel:tools/compiler/opcodes` module table row. |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/opcodes.ks` with all ~80 JVM opcode `val` constants mirroring `compiler/src/jvm-codegen/opcodes.ts`.
- [x] Add 18 access-flag constants (`accPublic`, `accPrivate`, `accProtected`, `accStatic`, `accFinal`, `accSuper`, `accSynchronized`, `accVolatile`, `accBridge`, `accTransient`, `accVarargs`, `accNative`, `accInterface`, `accAbstract`, `accStrict`, `accSynthetic`, `accAnnotation`, `accEnum`).
- [x] Implement `descriptorForType(t: InternalType): String` mapping `TPrim` names to JVM primitive/boxed descriptors, everything else to `"Ljava/lang/Object;"`.
- [x] Implement `methodDescriptor(params: List<InternalType>, ret: InternalType): String` building complete `(...)R` method descriptor strings.
- [x] Implement `jvmSlotSize(t: InternalType): Int` returning 2 for Int and Float (long/double), 1 for all others.
- [x] Add `stdlib/kestrel/tools/compiler/opcodes.test.ks` with tests covering: `nop=0`, `areturn=176`, `invokevirtual=182`, `accPublic=1`, `descriptorForType(tInt)="J"`, `descriptorForType(tBool)="Ljava/lang/Boolean;"`, `methodDescriptor([tInt], tString)`, and `jvmSlotSize(tInt)=2`.
- [x] Run `cd compiler && npm test`.
- [x] Run `./kestrel test stdlib/kestrel/tools/compiler/opcodes.test.ks`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/opcodes.test.ks` | Verify key opcode constants have correct byte values (NOP=0, ARETURN=0xB0, INVOKEVIRTUAL=0xB6). |
| Kestrel harness | `stdlib/kestrel/tools/compiler/opcodes.test.ks` | Verify `descriptorForType` for primitives: Int→J, Bool→Ljava/lang/Boolean;, String→Ljava/lang/String;. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/opcodes.test.ks` | Verify `methodDescriptor` builds correct `(...)R` string. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/opcodes.test.ks` | Verify `jvmSlotSize` returns 2 for Int/Float, 1 for Bool/String. |

## Documentation and specs to update

- [x] `docs/guide.md` — add `kestrel:tools/compiler/opcodes` row to the compiler dev module table.

## Build notes

- 2026-04-11: Started implementation.
- 2026-04-11: Kestrel does not support hex integer literals — `0xb0` evaluates to `0`. All opcode byte values must be written in decimal (e.g., `areturn = 176`, `invokevirtual = 182`). This is a Kestrel language limitation to document.
- 2026-04-11: Kestrel boolean OR is `|` not `||`. Using `||` causes a parse error. Was caught when writing `jvmSlotSize`'s condition `name == "Int" || name == "Float"` — fixed to `name == "Int" | name == "Float"`.
- 2026-04-11: Pattern-matching on imported ADT constructors (e.g., `Ty.TPrim(name)` in a match arm) is not valid Kestrel syntax. Furthermore, bare constructor names from imports are not in scope. A parse error from this triggers catastrophic error recovery consuming 4 GB+ of Node.js heap and crashing with OOM. Fixed by adding `primName()` and `varId()` accessor helpers to `types.ks` and using if/else logic in `opcodes.ks`.
- 2026-04-11: Individual `export val` declarations for ~160 constants caused quadratic compiler overhead. Switched to a single record-based export (`export val JvmOp = { nop = 0, ... }`). Callers access via `Op.JvmOp.nop`. Opcode count: 160 opcode constants; 18 access-flag constants. Tests: 25/25 passing. TypeScript compiler: 436 tests passing.
