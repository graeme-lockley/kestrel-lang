# JVM Opcode Table

## Sequence: S14-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-06, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/jvm-codegen/opcodes.ts` (~190 lines) to
`stdlib/kestrel/compiler/opcodes.ks`. This small module defines the JVM opcode byte
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

1. Create `stdlib/kestrel/compiler/opcodes.ks` with:
   - `JvmOp` record or a set of exported `val` constants for each opcode byte value
   - Access-flag constants (`accPublic`, `accStatic`, etc.)
   - `descriptorForType(t: InternalType): String`
   - `methodDescriptor(params: List<InternalType>, ret: InternalType): String`
   - `jvmSlotSize(t: InternalType): Int`

## Acceptance Criteria

- `stdlib/kestrel/compiler/opcodes.ks` compiles without errors.
- A test file `stdlib/kestrel/compiler/opcodes.test.ks` verifies:
  - a selection of opcode constants have the correct byte values (e.g. `NOP = 0`, `ARETURN = 0xB0`)
  - `descriptorForType(tInt)` returns `"J"` (JVM long)
  - `descriptorForType(tBool)` returns `"Ljava/lang/Boolean;"`
  - `methodDescriptor([tInt], tString)` returns `"(J)Ljava/lang/String;"`
  - `jvmSlotSize(tInt)` returns `2` (long → 2 slots)
- `./kestrel test stdlib/kestrel/compiler/opcodes.test.ks` passes.
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
