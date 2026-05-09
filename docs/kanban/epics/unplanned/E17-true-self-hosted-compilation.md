# Epic E17: True Self-Hosted Compilation

## Status

Unplanned

## Summary

Today `kestrel status` reports "self-hosted" and the CLI is written in Kestrel, yet every actual
compilation of a `.ks` file still shells out to `node compiler/dist/cli.js` (the TypeScript
bootstrap compiler). The Node runtime is therefore a hidden runtime dependency even after
bootstrap.

This epic wires all the already-implemented Kestrel compiler pieces into a real
`Driver.compileFile` implementation and then switches `cli.ks` to call that driver in-process
instead of spawning Node. When the epic is complete, every Kestrel program can be compiled and run
using only the JVM — Node is no longer a runtime dependency.

The individual pieces already exist in Kestrel:
- Front-end: `kestrel:dev/parser/lexer`, `kestrel:dev/parser/parser`
- Type checker: `kestrel:dev/typecheck/typecheck`
- Code generator: `kestrel:tools/compiler/codegen` (`jvmCodegen`)
- Class file serialiser: `kestrel:tools/compiler/classfile` (`cfToBytes`)
- KTI reader/writer: `kestrel:tools/compiler/kti`
- Module resolver: `kestrel:tools/compiler/resolve`

What is missing is the **driver** that orchestrates these pieces together into an incremental,
multi-module, caching compilation pipeline, and the **wiring** in `cli.ks` that calls it instead
of Node. The TypeScript reference implementation is `compiler/src/compile-file-jvm.ts`.

Stories must be **fine-grained** — each one adds exactly one pipeline capability and is
independently testable. No story should touch more than one concern at a time.

## Pivot — 2026-04-28

The original epic plan (S17-01..S17-42) wired all `./kestrel` commands through the self-hosted
`Driver.compileFile` as each story landed. In practice this caused the self-hosted compiler's
immaturity to degrade the TS compiler's test suite: ~20 E2E scenarios were suppressed with
`// E2E_SKIP_PENDING_CODEGEN` markers and two unit tests were TEMP-stubbed. This weakens the TS
compiler's ability to detect regressions.

**The new approach:**
- `~/.kestrel/jvm/` is split into `~/.kestrel/ts/` (TS compiler) and `~/.kestrel/self/`
  (self-hosted compiler). The shared Maven cache stays at `~/.kestrel/maven/`.
- `./kestrel` drives the TS compiler exclusively. The S17-12 in-process driver wiring is
  preserved in code but is only reachable via `./kestrel-self`.
- `./kestrel-self` (`scripts/kestrel-self`) is a new dedicated entry point for the self-hosted
  compiler, pinned to `~/.kestrel/self/`.
- Parallel test corpora (`tests/kunit/`, `tests/kfixtures/`, `tests/kconformance/`) are
  introduced as the exclusive target for self-hosted compiler testing. The TS corpora
  (`tests/unit/`, `tests/fixtures/`, `tests/conformance/`) are restored to their full strength.
- `./scripts/test-kestrel.sh` runs the self-hosted compiler against the `k*` corpora. It is
  NOT added to `scripts/test-all.sh` until a stable baseline is established.
- The flag-based CLI unification (`--compiler=ts|self`) is deferred to S17-45, a future story
  that must not be built until S17-44 (no-Node final validation) is complete.

Stories S17-43..S17-50 must land **before** any further gap-closure work (S17-39, S17-16..S17-42)
so that all subsequent stories are measured against the new `k*` corpora via `./kestrel-self`.

## Stories (ordered — implement sequentially)

1. [S17-01] Single-file happy-path compilation in driver
   — Read source, lex, parse, typecheck (no imports), `jvmCodegen`, write `.class` file(s) to
   `outDir`. No KTI, no incremental, no deps. `compileFile` returns `ok=True` for valid source.

2. [S17-02] Diagnostic propagation through `CompileResult`
   — Surface parse errors and typecheck `Diagnostic` list through `CompileResult.diagnostics`
   and render them to stderr in the same format as the TS compiler. `compileFile` returns
   `ok=False` with populated diagnostics for invalid source.

3. [S17-03] Source hashing and KTI write after successful compile
   — Compute SHA-256 source hash, call `Kti.buildKtiV4`, call `Kti.writeKtiFile` to persist
   the `.kti` cache file alongside `.class` output. No freshness check yet — always rewrite.

4. [S17-04] Single-file freshness check (skip recompile if fresh)
   — Before compiling a single file with no deps, attempt to read its `.kti` file; if
   `Driver.isFresh` returns `True` (source hash and dep hashes match), skip recompile entirely
   and return `ok=True`. Write unit tests verifying the skip path and the recompile path.

5. [S17-05] Direct dependency path resolution from a single source file
   — Call `Resolve.uniqueDependencyPaths` on the parsed program to obtain the flat list of
   `ResolvedDep` values for direct imports. No multi-module compile yet; just prove the paths
   are correctly resolved for stdlib and relative specifiers.

6. [S17-06] Cross-module KTI type loading for the typechecker ✅
   — Before typechecking a module, read the `.kti` files of each resolved direct dependency
   and reconstruct the `importBindings` snapshot that the typechecker needs. Handle the case
   where a dependency `.kti` is absent (dependency must be compiled first; return an error).

7. [S17-07] Topological dependency ordering and cycle detection ✅
   — Build a full import graph (recursively from the entry file), topologically sort it, detect
   circular imports, and compile each module in dependency order. Each module is compiled
   once per invocation (deduplicated by absolute path).

8. [S17-08] Multi-module incremental compilation (graph-wide freshness) ✅
   — Apply the single-file freshness check (S17-04) across the full dependency graph. Only
   recompile modules whose source has changed or whose dependencies have changed. Dep hashes
   are SHA-256 hashes of direct dependency `.kti` contents, matching the TS compiler's scheme.

9. ✅ [S17-09] URL dependency fetch integration
   — For `https://` (and optionally `http://` with `--allow-http`) specifiers, call
   `Resolve.fetchUrl` to populate the URL cache before attempting to resolve the path. Wire
   `--refresh` flag to force re-fetch. Verify cached-hit path skips the network.

10. ✅ [S17-10] `.class.deps` sidecar file writing
    — After compiling a module, write `<ClassName>.class.deps` listing the absolute paths of
    all direct and transitive source dependencies. This file is used by `cli.ks` for mtime-
    based staleness checks (legacy freshness path). Format: one absolute path per line.

11. [S17-11] Maven `.kdeps` sidecar handling
    — Detect `maven:` specifiers in source, write `<ClassName>.kdeps` sidecar alongside
    `.class` output (group:artifact:version, one per line). Driver does not download JARs;
    it records coordinates. `cli.ks` (and `kestrel:tools/cli/maven`) reads these sidecars
    to build the JVM classpath.

12. ✅ [S17-12] Wire `cli.ks` `compileScript` to call the Kestrel driver in-process
    — Replace the `runProcessStream("node", [compilerCli, ...])` call in `cli.ks` with a
    direct in-process call to `Driver.compileFile`. Remove the `compilerCli` parameter from
    `compileScript` and all call sites. The Node path must no longer be reachable for normal
    compilation. `cli-main.ks` build scaffold is superseded by this wiring.

13. ✅ [S17-13 — Fix JVM codegen variable binding for nested cons-chain patterns](../../done/S17-13-fix-nested-cons-pattern-codegen.md)
    — The TS JVM codegen mis-compiles `match` arms with 3+ variable bindings in a cons-chain
    (e.g. `g :: a :: v :: []`); middle bindings are lost, producing an "unknown variable"
    crash. Fix the binding-emission logic and add regression tests. Revert the S17-11
    workaround in `driver.ks` once fixed. (Renumbered from S17-14.)

14. [S17-14 — Refactor deep async-Result nesting in driver tests using combinators](../../unplanned/S17-14-refactor-test-async-result-nesting.md)
    — Add `andThenAsync` and `mapErrorAsync` to `kestrel:data/result`; refactor all 3+-level
    nested `match (await ...)` filesystem-setup blocks in `driver.test.ks` (and any other
    stdlib test files with the same pattern) to a flat `|>` pipeline with a single `match`,
    so each failing setup step surfaces a labelled error message. (Renumbered from S17-15.)

15. ✅ [S17-15 — Fix await direct-call type inference defect in recursive async functions](../../done/S17-15-await-direct-call-type-inference-defect.md)
    — Fix a type-inference/checking defect where `await f(...)` can fail with `await expects
    Task<T> but got α...` while `val x: Task<T> = f(...); await x` succeeds. Apply parity fixes
    in both the TypeScript and self-hosted Kestrel compilers, add regression tests, and remove
    unnecessary temporary `Task` bindings in affected call sites. (Renumbered from S17-16.)

### Pivot: dual caches and dedicated Kestrel-compiler test corpora

These five stories implement the 2026-04-28 pivot (see § Pivot above). They must all land
**before** any further gap-closure work so the rest of E17 builds against the new `k*` corpora
via `./kestrel-self`. Acceptance for all subsequent stories is measured via
`./scripts/test-kestrel.sh` rather than `./kestrel test` / `tests/unit/`.

16. ✅ [S17-43 — Dual cache layout (`~/.kestrel/ts/` + `~/.kestrel/self/`)](../../done/S17-43-dual-cache-layout.md)
    — Split the single JVM class cache into two sub-directories under one root. `KESTREL_JVM_CACHE`
    is kept as a deprecated read-only alias for one release. Maven cache unchanged.

17. ✅ [S17-46 — Restore TS compiler as the default for `./kestrel`](../../done/S17-46-restore-ts-as-kestrel-default.md)
    — Revert the user-visible effect of S17-12: make `./kestrel` call the TS compiler subprocess.
    Restore weakened `tests/unit/` tests (union_intersection, functions). Remove all
    `// E2E_SKIP_PENDING_CODEGEN` markers and the corresponding skip logic from `run-e2e.sh`.

18. ✅ [S17-47 — `./kestrel-self` script and bootstrap into `~/.kestrel/self/`](../../done/S17-47-kestrel-self-script.md)
    — Add `scripts/kestrel-self` + root symlink as the dedicated self-hosted compiler entry point.
    Move `bootstrap` subcommand here. Update `./kestrel status` to report both caches.

19. ✅ [S17-48 — Kestrel-compiler test corpora scaffolding and `scripts/test-kestrel.sh`](../../done/S17-48-kestrel-test-corpora-and-runner.md)
    — Create `tests/kunit/`, `tests/kfixtures/`, `tests/kconformance/{parse,typecheck,runtime/valid}/`
    with READMEs and seed content. Add `scripts/test-kestrel.sh` runner (NOT added to test-all.sh).
    Runtime goldens use in-file `// =>` convention.

20. ✅ [S17-50 — Baseline-populate Kestrel-compiler test corpora](../../done/S17-50-baseline-populate-kestrel-corpora.md)
    — Sweep every existing TS-corpus file through `./kestrel-self`; copy all passing files into
    the matching `tests/k*/` location. Record baseline counts in each README and Build notes.
    `./scripts/test-kestrel.sh` must exit 0 over the baseline. Discovery script is temporary
    and removed after the baseline is committed.

21. [S17-45 — Future: flag-based CLI unification (`--compiler=ts|self`)](../../unplanned/S17-45-flag-based-cli-unification.md)
    — **Placeholder only.** Unify `./kestrel` and `./kestrel-self` into a single entry point with
    a `--compiler` flag once S17-44 (no-Node final validation) is complete. Not built now.

22. [S17-43 — Codegen: emit diagnostic for unresolved identifiers](../../unplanned/S17-43-codegen-unresolved-ident-diagnostic.md)
    — Replace the silent `pushNull` fallback at the end of the `EIdent` resolution chain with a
    proper `Diagnostic` record. Wire accumulated codegen diagnostics through `jvmCodegen`'s
    return value and `driver.ks` so the CLI reports the error. Completes the PARTIAL acceptance
    criterion left open in S17-25.

### KTI correctness (foundation for multi-module self-hosted compilation)

Three interconnected correctness bugs in the KTI subsystem must be fixed before the
self-hosted typechecker and codegen can produce correct multi-module output. These stories
precede the typechecker and codegen gap closures because several later stories depend on them:
S17-41 (codegenMeta) is a prerequisite for S17-22 (cross-module ADT environment) and S17-38
(JvmCodegenOptions), and S17-39 (serializeType) is a prerequisite for S17-41.

16. [S17-39 — Fix KTI `serializeType` to write JSON object format](../../unplanned/S17-39-kti-serialize-type-json-format.md)
    — The self-hosted `serializeType` currently writes types as human-readable strings via
    `typeToString`. The string-parsing fallback in `deserializeType` only recognises
    primitives and simple arrows; every other type form (schemes, ADT apps, records, tuples,
    unions, intersections) deserialises silently as `tUnit`. This breaks any downstream
    module that imports a polymorphic or complex type from a self-hosted-compiled dep.
    Fix: emit structured JSON objects matching the TS `{k:"scheme"|"arrow"|"app"|...}` format
    already handled by `deserializeTypeFromObj`.

17. [S17-40 — Add `freshenImportedTypeVars` to KTI `loadDepBindings`](../../unplanned/S17-40-kti-freshen-imported-type-vars.md)
    — Deserialized `TVar` nodes carry their raw integer IDs from the KTI file. Since the
    self-hosted typechecker's fresh-var counter is always positive (starting at 0), imported
    type vars from different modules can share the same ID, causing the unifier to
    incorrectly merge them. Fix: remap all imported type vars to negative IDs (mirroring the
    TS compiler's `freshenImportedTypeVars` with `importedTypeVarIdRef = { value: -1 }`).

18. [S17-41 — Fix KTI `codegenMeta` extraction and serialisation](../../unplanned/S17-41-kti-codegenmeta-correctness.md)
    — The self-hosted `extractCodegenMeta` is a stub: all arities are 0, and `asyncFunNames`,
    `varNames`, `adtConstructors`, and `exceptionDecls` are empty. `buildEntries` always writes
    `kind="function"` with `arity=0`. `buildTypeEntries` always writes `kind="alias"`, never
    `kind="adt"` with a `constructors` list. `parseCodegenMeta` hardcodes `adtConstructors=[]`
    and `exceptionDecls=[]`, silently dropping this data even when reading bootstrap KTIs.
    Fix: port `extractCodegenMeta`, `buildEntries`, `buildTypeEntries`, and `parseCodegenMeta`
    to match the TS reference (`compiler/src/kti.ts` lines 202–445). Depends on S17-39.

### Self-hosted typechecker gap closure

The self-hosted typechecker MVP raises "Unsupported top-level declaration in self-hosted
checker MVP" for several declaration forms used across the stdlib. These must be implemented
before the self-hosted compiler can typecheck its own stdlib modules.

19. ✅ [S17-16 — Self-hosted typecheck for `extern fun` declarations](../../done/S17-16-self-hosted-typecheck-extern-fun.md)
    — Add `TDExternFun` arms to `prebindFunDecls` and `checkDecls`. Required for every
    stdlib primitive module (`data/string`, `data/list`, `io/fs`, `io/process`, etc.).

20. [S17-17 — Self-hosted typecheck and codegen for `extern type` declarations](../../done/S17-17-self-hosted-typecheck-codegen-extern-type.md) ✅
    — Add `TDExternType` arms to `prebindTypeDecls`, `checkDecls`, and `emitDecl`. Required
    for opaque types (`ByteArray`, `FileHandle`, ...).

21. ✅ [S17-18 — Self-hosted typecheck and codegen for `extern import` declarations](../../done/S17-18-self-hosted-typecheck-codegen-extern-import.md)
    — Add `TDExternImport` arms to typecheck and codegen so JVM-bridge primitives are
    accepted by the self-hosted compiler.

22. ✅ [S17-19 — Self-hosted typecheck for `exception` declarations](../../done/S17-19-self-hosted-typecheck-exception-decls.md)
    — Add `TDException` arms to typecheck (codegen already handles them). Required for any
    module declaring its own exception types.

23. ✅ [S17-20 — Self-hosted typecheck and codegen for `export * from` / `export { x } from` re-exports](../../done/S17-20-self-hosted-typecheck-codegen-reexports.md)
    — Add the `EIStar` and `EINamed` arms to `TDExport` handling in both typecheck and
    codegen so aggregator modules typecheck and emit correct KTI.

24. ✅ [S17-21 — Self-hosted typecheck for top-level assignments (`TDSAssign`)](../../done/S17-21-self-hosted-typecheck-top-level-assignment.md)
    — Add a `TDSAssign` arm to `checkDecls` reusing the existing `SAssign` rule.

25. [S17-22 — Cross-module ADT constructor environment for the self-hosted typechecker](../../done/S17-22-self-hosted-cross-module-ctor-exhaustiveness.md) ✅
    — Plumb `adtConstructors` / `ctorOwners` / `ctorEnv` from imported KTIs through
    `DepBindingBundle` and `TypecheckOptions` so imported constructors are recognised in
    pattern matching and exhaustiveness checking. Depends on S17-41.

### Self-hosted codegen gap closure

The self-hosted `emitExpr` pushes `null` for every expression except `ELit(int/bool)` and
`EIdent(local)`. The JVM cache masking effect (bootstrap-compiled classes reused via freshness
checks) hides this until the cache is empty. Each story below implements one group of
expression forms, includes unit tests that verify real bytecode emission, and must not regress
any existing tests. The KTI correctness block (stories 16–18) must be complete first because
S17-25 (EIdent) and S17-38 (JvmCodegenOptions) consume `codegenMeta` data from KTI.

This block now has an explicit phased rollout:

- **Execution tranche first**: S17-25 and S17-37 land together to replace the temporary
    self-hosted `main(String[])` shim with real identifier/global-init/startup behavior.
- **Core runtime semantics second**: S17-26 through S17-34 restore real calls, operators,
    records, control flow, exceptions, and async so runtime-negative E2Es and then positive E2Es
    can be re-enabled in slices.
- **Higher-order and parity stories last**: S17-35, S17-36, and the remaining S17-38 work bring
    the self-hosted codegen up to full parity after the pipeline is already exercising real code.

During this transition the pipeline may stay green via temporary `E2E_SKIP_PENDING_CODEGEN`
markers, but those are considered tranche-local scaffolding, not the final state of the epic.

26. [S17-24 — Codegen: complete `ELit` emission (string, char, float, unit)](../../unplanned/S17-24-codegen-literal-emission.md)
    — Add `"string"` (`LDC_W`), `"char"` (code-point boxing), `"float"` (`LDC2_W` double),
    and `"unit"` (`GETSTATIC KUnit.INSTANCE`) arms. Int and bool already work.

27. ~~[S17-25 — Codegen: `EIdent` — global vals/vars, imported names, function references](../../done/S17-25-codegen-ident-resolution.md)~~
    **DONE.** Full identifier resolution implemented: local slots, global `val`/`var`
    (`GETSTATIC`), nullary ADT constructors (`GETSTATIC INSTANCE`), imported val/var/fun,
    and module-level function references. All tests passing.

28. [S17-26 — Codegen: `EBinary` and `EUnary` operator emission](../../unplanned/S17-26-codegen-binary-unary-operators.md)
    — Emit real arithmetic (`+`, `-`, `*`, `/`, `%`), comparison (`<`, `>`, `<=`, `>=`),
    equality (`==`, `!=`), boolean short-circuit (`&`, `|`), string append (`++`), unary
    negate, and boolean not.

29. [S17-27 — Codegen: `ECall` — local, imported, and namespace function calls](../../unplanned/S17-27-codegen-call-emission.md)
    — Emit `INVOKESTATIC` for direct local and imported calls; `INVOKEVIRTUAL KFunc.invoke`
    for indirect calls; ADT constructor calls (`NEW; INVOKESPECIAL`); extern JVM calls.
    **This is the first major runtime-semantics story after the S17-25 + S17-37 tranche and is a
    gate for re-enabling meaningful runtime-negative execution.**

30. [S17-28 — Codegen: `EField`, `ERecord`, spread, and mutable-field assignment](../../unplanned/S17-28-codegen-field-record-emission.md)
    — Emit `KRecord.get` for field reads, `KRecord.put` for field writes, `new KRecord`
    construction with and without spread, and `var` boxing (KRecord wrapper).

31. [S17-29 — Codegen: `EList`, `ECons`, `ETuple`, `ETemplate`, and `EPipe`](../../unplanned/S17-29-codegen-list-tuple-template-pipe.md)
    — Emit `KList.cons` / `KNil` chains, `KTuple.of`, `KString.append` template parts, and
    pipe-operator rewriting to `ECall`.

32. [S17-30 — Codegen: `EIf` — conditional branching with JVM backpatching](../../unplanned/S17-30-codegen-if-branching.md)
    — Emit `CHECKCAST Boolean; booleanValue; IFEQ; GOTO; ASTORE/ALOAD` with correct JVM
    stackmap frames at branch targets.

33. ✅ [S17-31 — Codegen: `EWhile` — loops with real `break` / `continue`](../../done/S17-31-codegen-while-loops.md)
    — Emit loop-head label, `IFEQ` exit test, back-edge `GOTO`, `SBreak` / `SContinue` GOTO
    patching, and wide stackmap frame for the JVM verifier.

34. [S17-32 — Codegen: `EMatch` — pattern matching with real JVM branching](../../unplanned/S17-32-codegen-pattern-matching.md)
    — Emit per-arm `INSTANCEOF`/`CHECKCAST` type checks, field destructuring, and `GOTO`
    skip patches. Covers all pattern kinds: `PWild`, `PVar`, `PLit`, `PCon`, `PList`,
    `PCons`, `PTuple`.

35. [S17-33 — Codegen: `ETry` / `EThrow` — real JVM exception handling](../../done/S17-33-codegen-try-throw.md)
    — Emit `ATHROW` for throw, JVM exception-table entries for `try/catch` arms, and catch
    dispatch with `CHECKCAST` per exception type. **Completing this with S17-30/S17-32 is the
    direct gate for restoring the runtime-negative throw/catch E2Es.** ✓ DONE

36. [S17-34 — Codegen: `EAwait` and async function scaffolding](../../done/S17-34-codegen-await-async.md)
    — Emit `INVOKEVIRTUAL KTask.await` for await; emit async payload methods for `async fun`;
    wrap results in `KTask`. **This is the main gate for re-enabling the first positive E2E slice
    (core async/task/fs/process scenarios).** ✓ DONE

37. [S17-35 — Codegen: `ELambda` — closure class generation and free variable capture](../../unplanned/S17-35-codegen-lambda-closures.md)
    — Collect all lambdas and local funs, compute free variables, emit `OuterClass$lambda_N`
    JVM classes with `invoke(Object[])Object` methods and env capture. **Treat as later parity work
    after the first execution and runtime-negative/positive E2E tranche is already honest.**

38. [S17-36 — Codegen: tail-call optimisation (loop-back GOTO)](../../unplanned/S17-36-codegen-tail-call-optimisation.md)
    — Detect self-tail calls in tail position; emit `ASTORE` of each argument + `GOTO loopHead`
    instead of `INVOKESTATIC` + `ARETURN`. **Recommended after the initial runtime-restoration
    tranche unless a restored scenario proves it is still blocking.**

39. [S17-37 — Codegen: global `val`/`var` lazy initialisation (`$init` pattern)](../../unplanned/S17-37-codegen-global-lazy-init.md)
    — Emit `static $initialized` lock field and `static $init()V` method; emit
    `INVOKESTATIC $init` before every imported global access. **Deliver together with S17-25 and
    use the same tranche to remove the temporary startup shim and the temporary runtime-negative
    E2E skips.**

40. [S17-38 — Codegen: `EIs` type narrowing, `ENever`, and `JvmCodegenOptions`](../../unplanned/S17-38-codegen-is-never-options.md)
    — Emit real `INSTANCEOF` for `EIs`; extend `jvmCodegen` with an options parameter carrying
    cross-module import maps (class names, arities, var sets) built from KTI `codegenMeta`.
    Depends on S17-41 for correct `codegenMeta` data. **The `JvmCodegenOptions` plumbing is needed
    early alongside S17-25/S17-27 even if the narrower `EIs` semantics finish later.**

### Final validation

41. [S17-42 — Self-hosted typecheck: `is` narrowing for union-typed identifiers](../../unplanned/S17-42-self-hosted-typecheck-is-narrowing-union.md)
    — Implement branch-local narrowing for `if (x is T)` in the self-hosted typechecker,
    re-enable `tests/unit/union_intersection.test.ks`, and keep the scenario green under
    `./kestrel test` before final no-Node validation.

42. [S17-44 — End-to-end validation without Node; CI gate and spec update](../../unplanned/S17-44-e2e-validation-no-node.md)
    — Rename `compiler/` to verify the full test suite passes with Node unreachable. Add a
    CI step that runs `mv compiler compiler_DISABLED && ./kestrel test` and must exit 0.
    Restore `compiler/`. Update `docs/specs/11-bootstrap.md` and
    `docs/specs/12-agent-enablement-and-knowledge.md` to reflect the JVM-only runtime path.
    **This now explicitly comes after re-enabling runtime-negative E2Es, re-enabling positive E2Es
    in slices, and restoring strict `scripts/test-all.sh` gating.**

43. [S17-51 — Self-hosted corpus expansion after codegen/KTI closure](../../unplanned/S17-51-self-hosted-corpus-expansion-post-codegen-kti.md)
    — Roadmap story to capture phased corpus growth (runtime, parse/typecheck, kunit,
    kfixtures) once S17-36..S17-41 are complete, so expansion validates the real self-hosted
    execution path instead of the temporary TS runtime fallback.

## Dependencies

- **E14** (Self-Hosting Compiler, done) — provides all individual compiler pieces:
  parser, typechecker, codegen, classfile writer, KTI, resolver.
- **E15** (Bootstrap JAR Self-Hosting Handoff, done) — establishes the bootstrap flow and
  `~/.kestrel/jvm` cache layout that `compileFile` must write into.
- **E16** (Kestrel CLI in Kestrel, in epics/unplanned with all stories ticked) — provides
  `stdlib/kestrel/tools/cli.ks`; S17-12 modifies `compileScript` directly in that file.
- **E12** (Full Process Environment, done) — `getEnv`, `mkdirAll`, `readText`, `writeBytes`
  are all required by the driver.
- **Spec 12** (Agent Enablement, docs/specs/12-agent-enablement-and-knowledge.md) — Phase 3
  (minimal dependency installer) is blocked on this epic; completing E17 unblocks it.

## Implementation Approach

The implementation follows the TypeScript reference in `compiler/src/compile-file-jvm.ts`
exactly, but expressed in Kestrel and using the already-ported Kestrel stdlib modules. No new
language features or stdlib primitives are required.

Each story corresponds to one vertical slice of `compile-file-jvm.ts`:
- S17-01–S17-04 cover the single-file path (lines ~40–120 of the TS reference).
- S17-05–S17-08 cover the multi-module graph path (the outer loop in `compileJvmMultiModule`).
- S17-09 covers URL fetch (the `fetchUrlDeps` helper).
- S17-10–S17-11 cover sidecar emission.
- S17-12 covers the CLI wiring (the call site in `cli.ks`).
- S17-13–S17-15 are bugfix / test-refactor stories scheduled before the gap-closure block.
- S17-39, S17-40, S17-41 fix KTI correctness gaps (type serialisation format, imported type var
  freshening, codegenMeta extraction/serialisation). Scheduled before the typechecker and
  codegen gap closures because S17-41 is a prerequisite for S17-22 and S17-38, and S17-39 is
  a prerequisite for S17-41.
- S17-16–S17-22 close the self-hosted typechecker MVP gaps.
- S17-24–S17-38 close the self-hosted codegen gaps — the much larger body of work: the
    self-hosted `emitExpr` is currently a stub that pushes `null` for every expression except
    `ELit(int/bool)` and `EIdent(local)`. Delivery is phased: first the S17-25 + S17-37 execution
    tranche, then the runtime/control-flow/async tranche (S17-26 through S17-34), then the later
    parity tranche (S17-35, S17-36, remaining S17-38 work). Each story must still pass focused
    unit tests that verify real bytecode is emitted and executes correctly.
- S17-44 is the final validation gate only after temporary startup/E2E workarounds are gone and
    strict pipeline gating has been restored.

**Key implementation invariants to preserve (match TS compiler exactly):**
- Source hash: SHA-256 of raw source bytes, hex-encoded.
- Dep hashes: SHA-256 of each direct dependency's `.kti` file bytes.
- `isFresh` check: `kti.sourceHash == srcHash && kti.depHashes == depHashes`.
- Output path derivation: same scheme as `cli.ks` `classOutputPath` (strip leading `/`,
  replace `.ks` with `.class`, mirror under `jvmCache`).
- `.class.deps` format: one absolute source path per line, no trailing newline.

## Epic Completion Criteria

- `Driver.compileFile` correctly compiles any Kestrel source file (with transitive imports,
  URL deps, Maven deps, and incremental freshness checks) to `.class` output in the JVM cache.
- `cli.ks` `compileScript` calls `Driver.compileFile` in-process; no `node` subprocess is
  spawned during compilation.
- All existing Kestrel tests pass without `compiler/dist/cli.js` present:
  `mv compiler compiler_DISABLED && ./kestrel test` exits 0.
- Node is documented as a maintainer-only build dependency; the README "What you need" section
  lists only Java for normal use.
- `docs/specs/11-bootstrap.md` is updated to reflect that runtime compilation uses the
  self-hosted Kestrel driver.
- `docs/specs/12-agent-enablement-and-knowledge.md` Phase 3 prerequisite is unblocked.
- CI includes a no-Node compilation gate that fails if Node is implicitly required at runtime.
