# JVM Classfile Binary Writer

## Sequence: S14-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-07, S14-08, S14-09, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/jvm-codegen/classfile.ts` (~601 lines) to
`stdlib/kestrel/tools/compiler/classfile.ks`. This module is the low-level JVM `.class` file
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

1. Create `stdlib/kestrel/tools/compiler/classfile.ks` with:
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

- `stdlib/kestrel/tools/compiler/classfile.ks` compiles without errors.
- A test file `stdlib/kestrel/tools/compiler/classfile.test.ks` verifies:
  - A minimal `Hello` class with a `main` method emits the correct 4-byte magic (`0xCAFEBABE`)
  - Constant pool indices are assigned and looked up correctly
  - `backpatch` resolves a forward branch label to the correct offset
  - `toBytes` produces a `ByteArray` of expected length for a trivial class (hand-calculated)
- The emitted bytecode is verified by invoking `java -cp <tmpdir> Hello` (or via `javap -p`) on
  a dynamically generated "Hello World" class if the JVM is available.
- `./kestrel test stdlib/kestrel/tools/compiler/classfile.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/jvm-codegen/classfile.ts`
- JVM spec §4 (Class File Format)

## Risks / Notes

- TypeScript uses `Buffer` (Node.js); Kestrel uses `Array<Int>` as the working byte buffer,
  converted to `ByteArray` at the end via `BA.fromList(Arr.toList(buf))`.
- Forward-branch patching requires indexed Array access (set at a known offset). Use `Arr.set`.
- StackMapTable generation is complex; test it thoroughly before depending on it in S14-07/S14-08.
- The constant pool is 1-indexed in JVM; ensure indices start at 1 and `long`/`double` entries
  occupy two slots.
- Kestrel `Int` is JVM `long` (64-bit), so `0xCAFEBABE` fits naturally; bitwise shifts and masks
  work without signed-32-bit tricks.
- TypeScript `bigint` for `constantLong`: use plain Kestrel `Int` (also 64-bit).
- Float bit patterns: use `java.lang.Float.floatToRawIntBits` via `extern fun` for `constantFloat`.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/compiler/classfile.ks` | New file — complete JVM classfile binary emitter |
| `stdlib/kestrel/tools/compiler/classfile.test.ks` | New test file — constant pool, method emission, backpatch, toBytes |
| `docs/kanban/epics/unplanned/E14-self-hosting-compiler.md` | Mark S14-06 complete |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/classfile.ks`
  - [x] Add constants: CP tag values, JVM magic/version, StackMap frame type constants
  - [x] Add `StackMapFrameState` record type and `paramOnlyFrame` helper
  - [x] Add `ExcEntry` (exception table row) and `FieldEntry` types
  - [x] Define `MethodState` mutable record (code: `Array<Int>`, branchTargets, etc.)
  - [x] Define `ClassFileState` mutable record (constantPool, utf8Cache, methods, etc.)
  - [x] Export opaque `ClassFileBuilder` and `MethodBuilder` types backed by the above
  - [x] Implement byte-buffer helpers: `bufU8`, `bufU16`, `bufU32`, `bufAppend`
  - [x] Implement modified UTF-8 encoder `encodeUtf8Bytes`
  - [x] Implement constant pool helpers: `cfUtf8`, `cfClassRef`, `cfNameAndType`,
        `cfFieldref`, `cfMethodref`, `cfIfaceMethodref`, `cfString`, `cfConstantInt`,
        `cfConstantLong`, `cfConstantFloat`, `cfConstantDouble`
  - [x] Implement `cfAddField`, `cfAddInterface`, `cfGetClassName`
  - [x] Implement `cfAddMethod` — flushes previous method, creates new `MethodState`
  - [x] Implement `newClassFile` constructor
  - [x] Implement `MethodBuilder` API:
        `mbEmit1`, `mbEmit1b`, `mbEmit1s`, `mbEmit1i`,
        `mbPushByte`, `mbPushShort`, `mbLength`, `mbGetCode`,
        `mbAddException`, `mbAddBranchTarget`, `mbGetParamCount`, `mbSetMaxs`
  - [x] Implement `cfFlushLastMethod`
  - [x] Implement `countMethodParams` (count parameter slots from JVM descriptor)
  - [x] Implement `buildStackMapTable` (generate StackMapTable bytes)
  - [x] Implement `cfToBytes` — full class file serializer
- [x] Create `stdlib/kestrel/tools/compiler/classfile.test.ks`
  - [x] Test: constant pool utf8 deduplication (same string → same index)
  - [x] Test: classRef, methodref indices are correct
  - [x] Test: `cfToBytes` of a trivial class starts with `CAFEBABE` magic bytes
  - [x] Test: `mbLength` counts emitted bytes correctly
  - [x] Test: backpatch via `Arr.set` in method code array
- [x] Run `NODE_OPTIONS='--max-old-space-size=8192' ./kestrel test stdlib/kestrel/tools/compiler/classfile.test.ks`
- [x] Run `cd compiler && npm test`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./kestrel test`
- [x] Remove stale duplicate `docs/kanban/unplanned/S14-06-jvm-classfile-binary-writer.md` to keep one canonical story phase.

## Build notes

- 2026-04-12: Started implementation. Port of `compiler/src/jvm-codegen/classfile.ts` to Kestrel. Using `Array<Int>` as the mutable byte buffer (supports push/get/set/length), with `ByteArray.fromList` for final output.
- 2026-04-12: Verified story-specific tests, compiler build/tests, and full `./kestrel test` pass while resuming from doing.
- 2026-04-12: Cleaned duplicate story phase file in `unplanned/` to avoid future E14 phase resolution ambiguity.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel | `stdlib/kestrel/tools/compiler/classfile.test.ks` | Constant pool, method builder, magic bytes, backpatch |

## Documentation and specs to update

- [x] `docs/kanban/epics/unplanned/E14-self-hosting-compiler.md` — mark S14-06 complete
