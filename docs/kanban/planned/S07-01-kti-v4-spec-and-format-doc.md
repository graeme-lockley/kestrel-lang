# .kti v4 Spec: `sourceHash`, `depHashes`, and `codegenMeta`

## Sequence: S07-01
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E07 Incremental Compilation](../epics/unplanned/E07-incremental-compilation.md)
- Companion stories: S07-02 (writer), S07-03 (reader + freshness routing), S07-04 (--clean flag)

## Summary

The `.kti` types-file format is specified in `docs/specs/07-modules.md §5` (currently version 3) and described in detail in a `kti-format.md` document referenced by the spec — but that document does not yet exist. This story creates `docs/specs/kti-format.md` with the full concrete JSON encoding of the v3 format, then extends it to v4 by adding three new top-level fields needed for incremental compilation: `sourceHash` (SHA-256 of the source file used to produce this `.kti`), `depHashes` (SHA-256 hashes of the direct dependencies' source files, used for transitive invalidation), and `codegenMeta` (JVM codegen metadata currently inlined in the parsed Program AST, needed so a dep loaded from `.kti` does not require re-parsing). It updates `07-modules.md §5` to reference v4 and document the freshness/invalidation algorithm.

## Current State

- `docs/specs/07-modules.md §5` describes the `.kti` format at version 3 and links to `kti-format.md` for the concrete encoding, but `kti-format.md` does not exist in `docs/specs/`.
- The `.kti` v3 format carries: `version`, `functions` (export entries), `types` (type declarations).
- No `sourceHash`, `depHashes`, or codegen metadata fields exist anywhere in the spec.
- `compile-file-jvm.ts` currently extracts the following from a dep's parsed `Program` AST (needed by JVM codegen for each dep):
  - Function arities (`getFunArity`) — `importedFunArities`, `namespaceFunArities`
  - Async function names (`isAsyncFun`) — `importedAsyncFunNames`, `namespaceAsyncFunNames`
  - Value/variable status (`isValOrVar`, `isVar`) — `importedValVarToClass`, `importedVarNames`
  - ADT constructor → inner-class map (walking `TypeDecl` with `ADTBody`) — `importedAdtClasses`, `namespaceAdtConstructors`
  - Exception declarations (walking `ExceptionDecl`) — `importedAdtClasses`
  - Var field names (walking `VarDecl`) — `namespaceVarFields`

## Relationship to other stories

- **Must be done before S07-02 (writer)**: the writer implements what is specced here.
- **Must be done before S07-03 (reader)**: the reader parses the format specced here.
- S07-04 (--clean) is independent of this story.

## Goals

- Create a canonical, concrete reference for the `.kti` format in `docs/specs/kti-format.md`.
- Define the v4 additions (`sourceHash`, `depHashes`, `codegenMeta`) precisely enough that a writer and reader can be implemented without ambiguity.
- Document the freshness/invalidation algorithm and its three-step logic (mtime gate → hash guard → cache miss) in `07-modules.md §5`.
- Ensure the spec clarifies that a v4 `.kti` produced by one compiler version must be rejected by a reader that does not support v4, and that a v3 `.kti` falling back from v4 is acceptable under a migration note.

## Acceptance Criteria

- `docs/specs/kti-format.md` exists and contains:
  - The full JSON encoding for v3 (all `kind` values: `function`, `val`, `var`, `constructor`, `"type"`).
  - The `SerType` encoding for all `InternalType` variants (prim, arrow, record, app, tuple, union, inter, scheme, typevar).
  - New v4 fields: `sourceHash` (hex SHA-256 of source bytes), `depHashes` (object mapping dep file path to hex SHA-256 of that dep's source), `codegenMeta` (object with sub-fields as defined below).
  - `codegenMeta` sub-fields specified:
    - `funArities`: `{ [exportedName: string]: number }` — arity of each exported function/extern fun.
    - `asyncFunNames`: `string[]` — exported function names that are async.
    - `varNames`: `string[]` — exported `var` declaration names.
    - `valOrVarNames`: `string[]` — exported `val` and `var` declaration names.
    - `adtConstructors`: `{ typeName: string, constructors: { name: string, params: number }[] }[]` — for each exported non-opaque ADT type, its name and constructor list (param count per constructor).
    - `exceptionDecls`: `{ name: string, arity: number }[]` — exported exception declarations with field count.
- `docs/specs/07-modules.md §5` is updated to:
  - State the current format version is **4** (a minor revision of v3; readers must reject unsupported versions).
  - Link to `kti-format.md` with a note that both v3 and v4 are described there.
  - Add a **Freshness / Invalidation** subsection documenting the three-step algorithm: mtime gate (check `stat(.kti).mtime > stat(source).mtime` AND dep hashes match in-process cache), hash guard (read source, compute SHA-256, compare stored hash), cache miss (recompile and write fresh `.kti`).

## Impact analysis

| Area | Change |
|------|--------|
| `docs/specs/kti-format.md` | New file — full concrete JSON encoding for v3 and v4 `.kti` format |
| `docs/specs/07-modules.md §5.1` | Version reference updated from 3 → 4; link to `kti-format.md` strengthened; new **Freshness / Invalidation** subsection added |
| `compiler/` code | No code changes in this story — pure specification work |
| Tests | No new test files — spec-only story; existing compiler tests run after to confirm no regressions |

## Tasks

- [ ] Create `docs/specs/kti-format.md`:
  - Section **1. Overview** — purpose, file extension, versioning policy (reject unsupported version), relationship to `07-modules.md §5`
  - Section **2. Top-level structure** — JSON object with fields `version`, `functions`, `types`, and (v4) `sourceHash`, `depHashes`, `codegenMeta`
  - Section **3. Export entry kinds** — complete table of all `kind` values: `function`, `val`, `var`, `constructor`, `type`; field-by-field description for each; `function_index`, `setter_index`, `arity`, `adt_id`, `ctor_index`
  - Section **4. SerType encoding** — map each `InternalType` variant to its JSON representation: `var` (type variable `{ "k": "v", "id": N }`), `prim`, `arrow`, `record` (with optional `row`), `app`, `tuple`, `union`, `inter`, `scheme`, `namespace` (note: `namespace` only appears in scope, not exported); include worked example
  - Section **5. v4 additions** — `sourceHash` (hex SHA-256 of source bytes), `depHashes` (object of absPath→hex), `codegenMeta` (all sub-fields with types and semantics)
  - Section **6. codegenMeta sub-fields** — `funArities`, `asyncFunNames`, `varNames`, `valOrVarNames`, `adtConstructors`, `exceptionDecls`; include minimal example object
  - Section **7. Full example** — complete v4 `.kti` JSON for a small module with a function, a var, and an ADT
  - Section **8. Version history** — table of version → what was added (v1–v4)
- [ ] Update `docs/specs/07-modules.md §5.1`:
  - Change `version` description to say "reference implementation uses **4**" (was "3")
  - Add sentence: "v4 adds `sourceHash`, `depHashes`, and `codegenMeta` for incremental compilation. Readers must reject `.kti` with unsupported `version` values."
  - Add sub-section **5.2 Freshness / Invalidation** documenting the three-step algorithm:
    1. **mtime gate** (fast-path): if `stat(.kti).mtime > stat(source).mtime` AND every `depHashes[path]` value equals the `sourceHash` from that dep's already-loaded `.kti` in the in-process cache → load from `.kti`, no source read
    2. **hash guard** (slow-path): source mtime ≥ `.kti` mtime → read source, compute SHA-256, compare against `sourceHash` AND re-check `depHashes` → load from `.kti` if all hashes match
    3. **cache miss**: `.kti` absent, version mismatch, hash mismatch, or parse error → full recompile; write fresh `.kti` after successful compile
- [ ] Run `cd compiler && npm run build && npm test` to confirm no regressions

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| (none) | — | Pure spec story — no new test files required |

## Documentation and specs to update

- [ ] `docs/specs/kti-format.md` — create with full v3+v4 encoding (primary deliverable of this story)
- [ ] `docs/specs/07-modules.md §5.1` — bump version to 4, add §5.2 freshness algorithm

## Spec References

- `docs/specs/07-modules.md §5` — types file format
- `docs/specs/09-tools.md` — tools reference (no change in this story; `--clean` is S07-04)

## Risks / Notes

- `codegenMeta.adtConstructors` must include *every* exported non-opaque ADT (not just the ones explicitly listed in `functions` as `constructor` entries), because the JVM codegen needs to build inner-class names like `ClassName$TypeName$CtorName`. The `functions` map carries type-level constructor entries; `codegenMeta.adtConstructors` is the codegen-level companion.
- The `depHashes` map keys must be **absolute paths** (the same form used as keys in the in-process `cache` Map in `compile-file-jvm.ts`), so the reader can look up an already-loaded dep's hash without path normalization ambiguity.
- Version bump from 3 → 4 is additive (new top-level fields); readers can treat a missing `codegenMeta` field as absent and fall through to a full recompile rather than hard-erroring (but must still reject `version < 4` for incremental use).
