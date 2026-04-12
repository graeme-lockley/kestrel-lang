# JVM Classfile Binary Writer

## Sequence: S14-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/jvm-codegen/classfile.ts` (~601 lines) to
`stdlib/kestrel/compiler/classfile.ks`. This module is the low-level JVM `.class` file
binary emitter: it manages the constant pool, field/method tables, attributes (Code, StackMapTable,
LineNumberTable), and serialises the complete class structure to a `ByteArray` for writing to disk.

## Current State

`compiler/src/jvm-codegen/classfile.ts` provides:
- `ClassFileBuilder` class — accumulates constant pool, fields, methods
  - `addUtf8(s)`, `addClass(name)`, `addNameAndType(...)`, `addMethodref(...)`, etc.
  - `startMethod(...)` / `endMethod()` returns a `MethodBuilder`
  - `toBuffer()` returns `Buffer` (the raw .class bytes)
- `MethodBuilder` class — per-method bytecode accumulator
  - `emit(opcode)`, `emitByte(b)`, `emitShort(n)`, `emitInt(n)` — opcode emission
  - `emitLabel()`, `backpatch(label)` — forward-branch patching
  - `emitStackMapFrame(...)` — StackMap table management
  - `maxStack`, `maxLocals` tracking
  - `toCode()` — serialise instruction sequence
- `StackMapFrameState` type used to track stack map for JVM verifier

The TypeScript `Buffer` is replaced by `ByteArray` from `kestrel:data/bytearray`.

## Relationship to other stories

- **Depends on**: S14-05 (opcode constants used throughout), S14-02 (InternalType for descriptors)
- **Blocks**: S14-07, S14-08 (codegen drives ClassFileBuilder to emit bytecode)

## Goals

1. Create `stdlib/kestrel/compiler/classfile.ks` with:
   - `ClassFileBuilder` opaque type backed by mutable list/array fields
   - `newClassFile(name: String, superName: String, accessFlags: Int): ClassFileBuilder`
   - Constant-pool helpers: `addUtf8`, `addClass`, `addNameAndType`, `addFieldref`, `addMethodref`, `addInterfaceMethodref`, `addString`, `addLong`, `addDouble`
   - `startMethod(name, descriptor, accessFlags): MethodBuilder`
   - `addField(name, descriptor, accessFlags): Unit`
   - `toBytes(b: ClassFileBuilder): ByteArray`
   - `MethodBuilder` opaque type with bytecode accumulation
   - `emit(m: MethodBuilder, op: Int): Unit` and multi-byte variants
   - `emitLabel(m: MethodBuilder): Int` / `backpatch(m: MethodBuilder, label: Int): Unit`
   - `emitStackMapFrame(m: MethodBuilder, state: StackMapFrameState): Unit`
   - `StackMapFrameState` record type
   - `methodToCode(m: MethodBuilder): ByteArray`

## Acceptance Criteria

- `stdlib/kestrel/compiler/classfile.ks` compiles without errors.
- A test file `stdlib/kestrel/compiler/classfile.test.ks` verifies:
  - A minimal `Hello` class with a `main` method emits the correct 4-byte magic (`0xCAFEBABE`)
  - Constant pool indices are assigned and looked up correctly
  - `backpatch` resolves a forward branch label to the correct offset
  - `toBytes` produces a `ByteArray` of expected length for a trivial class (hand-calculated)
- The emitted bytecode is verified by invoking `java -cp <tmpdir> Hello` (or via `javap -p`) on
  a dynamically generated "Hello World" class if the JVM is available.
- `./kestrel test stdlib/kestrel/compiler/classfile.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/jvm-codegen/classfile.ts`
- JVM spec §4 (Class File Format)

## Risks / Notes

- TypeScript uses `Buffer` (Node.js); Kestrel uses `ByteArray` from `kestrel:data/bytearray`.
  All multi-byte writes (u16, u32) must manually encode big-endian byte order.
- Forward-branch patching requires a two-pass approach or backpatch slots; replicate the label
  mechanism from the TypeScript implementation carefully.
- StackMapTable generation is complex; test it thoroughly before depending on it in S14-07/S14-08.
- The constant pool is 1-indexed in JVM; ensure indices start at 1 and `long`/`double` entries
  occupy two slots.
