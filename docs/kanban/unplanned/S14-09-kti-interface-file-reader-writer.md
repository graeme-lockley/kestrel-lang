# KTI v4 Interface File Reader/Writer

## Sequence: S14-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/unplanned/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/kti.ts` (~519 lines) to `stdlib/kestrel/compiler/kti.ks`. KTI (Kestrel
Type Interface) files are JSON-based interface files that store module exports (types, functions,
constructors) and codegen metadata so dependent modules can be compiled without re-reading
or re-typechecking the source. The reader and writer must stay bit-compatible with the
TypeScript compiler during the bootstrap transition.

## Current State

`compiler/src/kti.ts` provides:
- `KtiV4` interface — the full JSON schema (functions, types, sourceHash, depHashes, codegenMeta)
- `buildKtiV4(program, exports, ...)` — construct a KTI object from typecheck results
- `writeKtiFile(path, kti)` — serialise and write atomically
- `readKtiFile(path)` — parse and validate
- `deserializeExports(kti)` — reconstruct `Map<string, InternalType>` for the type-checker
- `extractCodegenMeta(kti)` — extract arities, async names, var names, ADT constructors

The KTI format is documented in `docs/specs/kti-format.md`.

## Relationship to other stories

- **Depends on**: S14-02 (InternalType — for serialisation/deserialisation), S14-04 (Typecheck result types for `buildKtiV4`)
- **Blocks**: S14-11 (driver reads/writes KTI after each module compilation)

## Goals

1. Create `stdlib/kestrel/compiler/kti.ks` with:
   - `KtiV4` record mirroring the schema
   - `KtiFunctionEntry`, `KtiValEntry`, `KtiVarEntry`, `KtiConstructorEntry`, `KtiExportEntry` ADTs
   - `KtiTypeEntry` record, `KtiCodegenMeta` record, `KtiAdtConstructorGroup` record
   - `buildKtiV4(prog, exports, typeAliases, typeVisibility, constructors, codegenMeta, sourceHash, depHashes): KtiV4`
   - `writeKtiFile(path: String, kti: KtiV4): Unit` (async, uses `kestrel:io/fs`)
   - `readKtiFile(path: String): Result<KtiV4, String>` (async)
   - `deserializeExports(kti: KtiV4): Dict<String, InternalType>`
   - `extractCodegenMeta(kti: KtiV4): CodegenMeta`
   - JSON serialisation via `kestrel:data/json` (or hand-rolled if needed)

## Acceptance Criteria

- `stdlib/kestrel/compiler/kti.ks` compiles without errors.
- A test file covers:
  - Building a `KtiV4` from a minimal exports map and serialising to JSON produces the
    expected schema shape
  - `readKtiFile` round-trips through `writeKtiFile` without data loss
  - `deserializeExports` reconstructs the same type map
  - KTI files written by the self-hosted compiler are parseable by the TypeScript compiler
    (cross-compatible format)
- `./kestrel test stdlib/kestrel/compiler/kti.test.ks` passes.
- `cd compiler && npm test` still passes.

## Spec References

- `compiler/src/kti.ts`
- `docs/specs/kti-format.md` — full v4 schema

## Risks / Notes

- `kestrel:data/json` may need to support round-tripping of all KTI types; if `Json` does not
  support arbitrary record serialisation, a hand-written JSON serialiser may be needed.
- Hash computation uses SHA-256 (`kestrel:sys/crypto` or `Crypto.hash` from E13 stdlib).
- Atomic writes (`Fs.writeBytesAtomic`) from E13 should be used for `writeKtiFile` to avoid
  partial files on crash.
- The KTI format stores `InternalType` as a JSON tree; the serialiser must handle all type
  variants (Var, Prim, Arrow, Record, App, Tuple) recursively.
