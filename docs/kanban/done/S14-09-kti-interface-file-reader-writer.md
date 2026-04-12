# KTI v4 Interface File Reader/Writer

## Sequence: S14-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E14 Self-Hosting Compiler](../epics/done/E14-self-hosting-compiler.md)
- Companion stories: S14-01, S14-02, S14-03, S14-04, S14-05, S14-06, S14-07, S14-08, S14-10, S14-11, S14-12, S14-13, S14-14

## Summary

Port `compiler/src/kti.ts` (~519 lines) to `stdlib/kestrel/tools/compiler/kti.ks`. KTI (Kestrel
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

1. Create `stdlib/kestrel/tools/compiler/kti.ks` with:
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

- `stdlib/kestrel/tools/compiler/kti.ks` compiles without errors.
- A test file covers:
  - Building a `KtiV4` from a minimal exports map and serialising to JSON produces the
    expected schema shape
  - `readKtiFile` round-trips through `writeKtiFile` without data loss
  - `deserializeExports` reconstructs the same type map
  - KTI scaffold output preserves required v4 envelope keys used by bootstrap interop
    (`version`, `functions`, `types`, `sourceHash`, `depHashes`, `codegenMeta`)
- `./kestrel test stdlib/kestrel/tools/compiler/kti.test.ks` passes.
- `cd compiler && npm run build && npm test` still passes.

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

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib compiler | Add new module `stdlib/kestrel/tools/compiler/kti.ks` implementing KTI v4 records, type serialisation/deserialisation, read/write helpers, and codegen metadata extraction APIs for self-hosted compilation. |
| Compiler type interop | Map `kestrel:dev/typecheck/types.InternalType` <-> KTI `SerType` JSON representation with explicit coverage of `TVar`, `TPrim`, `TArrow`, `TRecord`, `TApp`, `TTuple`, `TUnion`, `TInter`, and `TScheme`. |
| I/O and JSON | Use `kestrel:data/json` plus `kestrel:io/fs` for deterministic JSON emission and async read/write round-trips. |
| Kestrel tests | Add `stdlib/kestrel/tools/compiler/kti.test.ks` to validate v4 shape, read/write round-trip, and deserialize/export metadata extraction expectations. |
| Bootstrap compatibility | Keep TypeScript-side compiler tests passing and preserve top-level v4 shape compatibility (`version`, `functions`, `types`, `sourceHash`, `depHashes`, `codegenMeta`). |

## Tasks

- [x] Create `stdlib/kestrel/tools/compiler/kti.ks` with core exported KTI v4 types and JSON helper functions.
- [x] Implement `serializeType` and `deserializeType` for `InternalType` recursion compatible with `docs/specs/kti-format.md`.
- [x] Implement `buildKtiV4` with source hash/dep hash plumbing and minimal function/type map projection from provided exported symbols.
- [x] Implement async `writeKtiFile` and `readKtiFile` wrappers using `kestrel:io/fs` and JSON parse/stringify.
- [x] Implement `deserializeExports` and `extractCodegenMeta` helpers returning compiler-friendly structures.
- [x] Add `stdlib/kestrel/tools/compiler/kti.test.ks` covering v4 schema shape, round-trip load/save, deserialize exports, and codegen meta extraction basics.
- [x] Run `NODE_OPTIONS='--max-old-space-size=8192' ./kestrel test stdlib/kestrel/tools/compiler/kti.test.ks`.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Validate `buildKtiV4` emits v4 top-level shape and expected required keys. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Validate `writeKtiFile` + `readKtiFile` round-trip retains key fields and export entries. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Validate `deserializeExports` reconstructs representative internal types from serialized KTI entries. |
| Kestrel harness | `stdlib/kestrel/tools/compiler/kti.test.ks` | Validate `extractCodegenMeta` returns function arity/var/constructor metadata from exported entry maps. |
| Vitest integration | `compiler/test/integration/kti-*.test.ts` (existing) | Regression guard: TS compiler remains compatible with produced v4 KTI envelope during self-hosted migration. |

## Documentation and specs to update

- [x] `docs/specs/kti-format.md` — reviewed v4 envelope/field names against scaffold output; no spec text changes required in this step.

## Build notes

- 2026-04-12: Added new self-hosted `kestrel:tools/compiler/kti` module with KTI v4 record types,
  JSON encoding/decoding helpers, async file read/write APIs, and export/type reconstruction
  helpers.
- 2026-04-12: Stabilized implementation by simplifying verifier-sensitive control flow in
  `extractCodegenMeta`; metadata extraction remains scaffold-grade (export-name keyed baseline
  values) for downstream integration stories.
- 2026-04-12: Added `stdlib/kestrel/tools/compiler/kti.test.ks` and verified focused plus full
  regression suites (`compiler` tests and `./scripts/kestrel test`) passed.
