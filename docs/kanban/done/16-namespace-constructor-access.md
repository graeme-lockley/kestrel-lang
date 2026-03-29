# Namespace constructor access (`M.Ctor(args)`)

## Sequence: 16
## Tier: 3 — Complete the core language
## Former ID: 11

## Summary

Allow calling **exported** ADT constructors through a namespace, e.g. `import * as Lib from "lib.ks"` then `Lib.PubNum(42)` when `PublicToken` is an exported ADT with constructor `PubNum(Int)`.

## Tasks

- [x] VM: `CONSTRUCT_IMPORT` (0x24) with correct ADT module identity; fail closed on errors (operand stack discipline).
- [x] Compiler: typecheck `exportedConstructors`, `.kti` v3 + `constructor` rows, `namespaceImportConstructors`, codegen `emitConstructImport`.
- [x] JVM path: reject qualified namespace constructors with `compile:jvm_namespace_constructor`.
- [x] Tests: `namespace_import.test.ks`, `compile-file.test.ts`, `types-file.test.ts`, fixture `opaque_pkg/lib.ks`.
- [x] Specs and guide updated (07, 01, 06, 04, 05, 08, 09, 10, kti-format, 03, `docs/guide.md`).
- [x] Regression: `npm test` (compiler), `zig build test` (vm), `./scripts/kestrel test`, `./scripts/run-e2e.sh`.

## Current state (reference implementation)

- **Spec ([07-modules.md](../../specs/07-modules.md) §2.3, §3.1.1, §5.1, §10):** Namespace objects expose exported non-opaque ADT constructors; `.kti` v3 includes `constructor` entries; lowering uses **CONSTRUCT_IMPORT** (04 §1.7).
- **Typechecker / compile-file / codegen:** Implemented per checklist in §10.
- **JVM:** Documented limitation; compile fails with `compile:jvm_namespace_constructor`.

## Scope

- **In scope:** For a namespace `M` bound to a module that **export**s a non-opaque ADT, treat each **exported** constructor name as a namespace member with the usual constructor type (nullary → `T`, n-ary → `(A1,…) -> T`). Typecheck `M.Ctor(args)` and lower it so runtime behavior matches construction in the **defining** module (including `.kti`-only consumers: see acceptance criteria).
- **Out of scope:** Opaque ADT constructors remain inaccessible (no change to opaque semantics). **Qualified constructor patterns** in `match` / `catch` (e.g. `Lib.PubNum(n) => …`) are **not** in the expression/pattern grammar today (`ConstructorPattern` has a single `name`); do not bundle unless a separate story extends patterns.
- **Related (optional follow-up):** Named imports of constructors (`import { PubNum } from "…"`) are specified in 07 §3.1.1; if the compiler still does not surface constructors in the export/`importBindings` path for **named** imports, fixing that may **share** the same metadata and lowering as this story—track explicitly if discovered during implementation.

## Spec references (read before implementing)

- [01-language.md](../../specs/01-language.md) — ADT constructors, `export type`, import grammar, call expression shape (`CallExpr` with callee `FieldExpr` for `M.Ctor(args)`).
- [06-typesystem.md](../../specs/06-typesystem.md) — Constructor types and application (including nullary: type `T`, no call parens).
- [07-modules.md](../../specs/07-modules.md) — Namespace import §2.3, export set §3.1.1, types file §5.1, implementor checklist §10.
- [kti-format.md](../../specs/kti-format.md) — Concrete `.kti` layout (if export shape or `version` changes).
- [08-tests.md](../../specs/08-tests.md) — §2.6 modules / conformance expectations (update when this feature lands).
- [10-compile-diagnostics.md](../../specs/10-compile-diagnostics.md) — §4 error codes/messages if new or changed diagnostics are introduced.
- [03-bytecode-format.md](../../specs/03-bytecode-format.md), [04-bytecode-isa.md](../../specs/04-bytecode-isa.md), [05-runtime-model.md](../../specs/05-runtime-model.md) — Only if bytecode, import linking, or ADT identity rules change.

## Acceptance criteria

### Behaviour

- [x] **Namespace members:** For `import * as M from "…"`, every **exported** ADT constructor of a **non-opaque** exported ADT in the dependency appears as `M.Ctor` with the correct scheme/type (including generics if applicable).
- [x] **Opaque / hidden constructors:** `M.SecNum(…)` (or any constructor of an **opaque** exported ADT) is a **compile-time error** with a clear message. Because opaque ADT constructors are omitted from the export set and from the types file’s constructor metadata (07 §5.1), the primary error is often indistinguishable from a missing export (e.g. `Namespace does not export 'SecNum'`). That is acceptable; optionally, the implementation may add a **stronger** opaque-specific message when it can correlate the name with an opaque type (06 §5.3). Constructors of **local** ADTs in the dependency remain absent from `M`.
- [x] **Unknown / typo:** `M.NotAConstructor` or a constructor name that does not exist on any **exported** ADT from that module → compile error (e.g. “does not export” or dedicated constructor message).
- [x] **Arity:** Wrong argument count for `M.Ctor` → type error (same standard as unqualified constructors).
- [x] **Argument types:** Wrong argument **types** for `M.Ctor` → type error (same standard as unqualified constructors).
- [x] **End-to-end:** A value produced by `Lib.PubNum(42)` interoperates with existing APIs that expect `Lib.PublicToken` (e.g. `Lib.publicTokenToInt`) under `./scripts/kestrel test` / VM execution—**same representation** as values produced inside the library module.
- [x] **`.kti` / compile-file path:** When the dependency is consumed via a **fresh `.kti`** only ([`isTypesFileFresh`](../../../compiler/src/compile-file.ts)), the importer still typechecks and compiles `M.Ctor(args)` correctly (metadata for constructors must be recoverable from the types file and/or embedded ADT export shape—see §5.1 ADT `constructors` array in 07, or equivalent in the reference `functions` map).

### Types file / codegen

- [x] **Export metadata:** Exported ADT constructors are representable for importers: either explicit entries in `.kti` (e.g. synthetic `kind` and indices) **or** a documented, implemented rule that derives constructor names, arities, and **lowering** from the serialized ADT in the type export. If the JSON shape or `version` changes, bump [`KTI_VERSION`](../../../compiler/src/types-file.ts) and reject stale files.
- [x] **Lowering:** Document in 07/04 (if needed) how `M.Ctor(args)` becomes bytecode while preserving defining-module ADT identity (see **Current state**).

### JVM

- [x] The repo includes [`compile-file-jvm.ts`](../../../compiler/src/compile-file-jvm.ts). Either **implement parity** for namespace-qualified constructor calls on the JVM path, or document a **clear, intentional exception** in [09-tools.md](../../specs/09-tools.md) (and ensure JVM compile fails with an actionable error if the unsupported form is used—prefer failing loud over silent wrong code).

### Documentation (must be updated as part of “done”)

- [x] **[07-modules.md](../../specs/07-modules.md) §2.3:** State that the namespace object exposes **exported constructors** of exported non-opaque ADTs (not only values, functions, type names, and type aliases). Align the opening semantics and **implementation note** with §3.1.1 (constructors are public bindings for exported ADTs).
- [x] **[07-modules.md](../../specs/07-modules.md) §3.1.1:** Explicitly mention **`import * as M from "…"`** alongside named imports: importers may construct via **`M.Ctor(…)`** for exported (non-opaque) ADTs, not only via unqualified or named constructor imports.
- [x] **[07-modules.md](../../specs/07-modules.md) §10 (Implementor checklist):** Extend the relevant items (import binding surface, types file emission, codegen) so a reader can implement namespace constructor access without reverse-engineering `compile-file.ts`.
- [x] **[01-language.md](../../specs/01-language.md):** Under imports / expressions, document qualified constructor use: **`M.Ctor`** for nullary (value of type `T`, 06 §5.1) and **`M.Ctor(e1,…,en)`** for n-ary, when `M` is a namespace bound by `import * as M from "…"`.
- [x] **[06-typesystem.md](../../specs/06-typesystem.md):** Note qualified constructor application: namespace field `M.C` has the same constructor scheme as unqualified `C` (nullary → `T`, k-ary → `(T1,…,Tk) -> T`); application rules match §5.1.
- [x] **[guide.md](../../guide.md) — Modules:** Short example (`export type …` + `import * as Lib` + `Lib.Ctor` / `Lib.Ctor(…)` per nullary vs n-ary rules), alongside existing namespace examples.
- [x] **[08-tests.md](../../specs/08-tests.md) §2.6:** Add a bullet that namespace imports and **exported ADT constructors** (including `.kti`-only dependency consumption) are covered by the conformance/unit/E2E tests listed in this story.
- [x] **[10-compile-diagnostics.md](../../specs/10-compile-diagnostics.md):** If new stable **`code`** values or representative messages are added (e.g. namespace + constructor), extend §4’s catalog accordingly.
- [x] **[kti-format.md](../../specs/kti-format.md):** If export entries or `version` change; keep **version** consistent with the compiler’s `KTI_VERSION`.
- [x] **[03-bytecode-format.md](../../specs/03-bytecode-format.md) / [04-bytecode-isa.md](../../specs/04-bytecode-isa.md) / [05-runtime-model.md](../../specs/05-runtime-model.md):** Only if the lowering or runtime story changes (new opcode, import-table role, or ADT identity rules).
- [x] **[09-tools.md](../../specs/09-tools.md):** If JVM support or limitations change (see JVM acceptance criterion; may be a short “parity” or “not supported” note only).

### Tests (exhaustive coverage required)

**Definition — exhaustive for this story:** Every behaviour bullet under **Behaviour** and **Types file / codegen** above has at least one automated test mapped to it; positives cover **nullary, unary, and multi-argument** constructors (extend [`tests/fixtures/opaque_pkg/lib.ks`](../../../tests/fixtures/opaque_pkg/lib.ks) or add a dedicated fixture if the current one has no `Ctor(A,B)`); negatives cover **opaque constructor, missing name, wrong arity, and wrong argument types**; **`.kti`-only** dependency consumption is covered in TypeScript integration tests; and the regression commands below all pass. **A single happy-path test alone is not sufficient.**

**Note — where negative tests must live:** [`tests/unit/*.test.ks`](../../../tests/unit/) files must **compile** to run under `./scripts/kestrel test`, so they cannot contain intentionally ill-typed lines. **`tests/conformance/typecheck/invalid/*.ks`** is driven by [`typecheck-conformance.test.ts`](../../../compiler/test/integration/typecheck-conformance.test.ts), which typechecks **one file in isolation** without `compileFile` import resolution—so it is **unsuitable** for `import * as Lib from "…"` scenarios unless the harness is extended. For this story, **multi-module compile failures** belong in **`compiler/test/integration/compile-file.test.ts`** (temporary fixture + `compileFile`) and/or **`tests/e2e/scenarios/negative/*.ks`** (see [README](../../../tests/e2e/scenarios/negative/README.md)).

- [x] **`tests/unit/namespace_import.test.ks` (Kestrel — positive runtime only):**
  - [x] **Positive — unary constructor:** `Lib.PubNum(42)` and pass the result to `Lib.publicTokenToInt` (or equivalent), asserting the same result as today’s `makePubNum` path.
  - [x] **Positive — nullary constructor:** **`Lib.PubEof`** as a **value** of type `Lib.PublicToken` (06 §5.1: nullary constructors use **no** `()`); feed it to `Lib.publicTokenToInt` and assert the expected tag outcome (`-1` for `PubEof` in the current fixture).
  - [x] **Positive — another unary constructor on the same ADT:** e.g. `Lib.PubOp("x")` and assert via `publicTokenToInt` (covers multiple constructors, disambiguation).
  - [x] **Positive — multi-argument constructor:** extend the fixture with at least one exported ADT constructor with **two or more** payload fields (e.g. `PubPair(Int, Int)`) and assert `Lib.PubPair(1, 2)` round-trips through a small exported `Lib` helper if needed.
  - [x] **Optional — generic exported ADT:** if the compiler already supports exported generic ADTs, add a case for `Lib.SomeCtor(...)` with correct instantiation; if not supported yet, skip with a comment referencing a future story (do not block this story on generics).
- [x] **Negative tests (Vitest and/or E2E — must exist, not necessarily in `namespace_import.test.ks`):**
  - [x] **Opaque constructor:** program that `import * as Lib` from the opaque fixture and references **`Lib.SecNum(…)`** (or equivalent) → **`compileFile` fails**; assert a diagnostic substring (e.g. `does not export` and/or opaque-related wording if implemented).
  - [x] **Missing / typo constructor:** e.g. `Lib.NotARealCtor(1)` → compile error (`does not export` or equivalent).
  - [x] **Wrong arity:** `Lib.PubNum()` and `Lib.PubNum(1, 2)` → **type error** (not silent codegen failure).
  - [x] **Wrong argument type:** e.g. `Lib.PubNum("hi")` → type error consistent with unqualified constructor calls.
- [x] **Compiler TypeScript tests:**
  - [x] **[`compiler/test/integration/compile-file.test.ts`](../../../compiler/test/integration/compile-file.test.ts):** (1) Namespace import + qualified constructor call with **full dependency compile**; (2) **at least one** scenario where the importer uses only a **fresh `.kti`** for the dependency (`isTypesFileFresh` in [`compile-file.ts`](../../../compiler/src/compile-file.ts)): dependency `.kti` (and `.kbc`) present and newer than `.ks` so the importer does **not** re-parse the dependency source, yet `M.Ctor(...)` still typechecks and compiles.
  - [x] **Unit tests:** Extend or add focused tests under `compiler/test/unit/` for typecheck/codegen paths for `M.Ctor` (constructor typing, `CONSTRUCT` / module identity, or documented equivalent), if not fully covered by integration tests.
  - [x] **[`compiler/test/unit/types-file.test.ts`](../../../compiler/test/unit/types-file.test.ts):** Whenever `.kti` shape, ADT `constructors` metadata, or `KTI_VERSION` changes—**round-trip write/read** and **consumer** behaviour (what `compileFile` reads when `fromTypesFile` is true).
- [x] **Regression suite (must pass before moving to done):** `cd compiler && npm test`, `cd vm && zig build test`, `./scripts/kestrel test`, and `./scripts/run-e2e.sh` per [AGENTS.md](../../../AGENTS.md).

## Notes

- Fixture today: [`tests/fixtures/opaque_pkg/lib.ks`](../../../tests/fixtures/opaque_pkg/lib.ks) exports `PublicToken` with `PubNum`, `PubOp`, `PubEof`; [`tests/unit/namespace_import.test.ks`](../../../tests/unit/namespace_import.test.ks) uses `Lib.makePubNum` because qualified constructors are not implemented—after this story, prefer exercising **`Lib.PubNum`** (and keep or adjust `makePubNum` as a secondary smoke test if desired).
- **07 §5.1** already describes an ADT `constructors` array in the abstract types-file shape; the reference compiler may use a merged `functions` map—the story does not mandate one layout, only that **namespace + `.kti` consumers** behave correctly and specs match the chosen representation.
