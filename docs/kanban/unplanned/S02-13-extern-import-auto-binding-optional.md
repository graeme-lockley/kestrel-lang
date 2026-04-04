# `extern import` Auto-Binding from JVM Class Metadata (Optional)

## Sequence: S02-13
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-12

## Summary

Implement `extern import "java:pkg.Class" as Name { ... }` — a convenience form that reads a Java `.class` file's method table at compile time and auto-generates `extern fun` stubs for all methods. Individual methods can be overridden inline with precise Kestrel types. Generic Java types default to `Any` in the auto-generated stubs. This story is **Optional** — the rest of E02 delivers full value without it. It is a productivity feature for when users need to wrap many methods from a large Java API.

## Current State

- None. No `extern import` syntax exists.
- The compiler does not have a bytecode reader component. ASM or a custom reader would be needed to inspect `.class` files.
- The `java:` URI scheme for class metadata access is not implemented (the epic's `java:` scheme for module imports, as distinct from `jvm("...")` descriptors in extern bindings).

## Relationship to other stories

- **Depends on S02-01, S02-02, S02-03**: generated stub declarations are `extern type` and `extern fun` nodes. The compiler must already know how to handle them.
- **Depends on S02-12 (partially)**: if the class comes from a `maven:` dependency, the jar must already be resolved before `extern import` can read its class files.
- **Does not block any other story**: all other E02 stories are complete and deliver full value without this one.

## Goals

1. **`extern import` syntax**: parse `extern import "java:pkg.ClassName" as LocalName { override_section }` at the top level.
2. **Class metadata reader**: read the `.class` file for `pkg.ClassName` from the compiler's classpath and enumerate public methods (name, descriptor, static/instance/constructor).
3. **Stub generation**: for each public method, generate an `extern fun` stub with:
   - Kestrel parameter types: `Any` for all Java `Object`/generic types, primitives mapped to their Kestrel equivalents (`int` → `Int`, `long` → `Int`, `boolean` → `Bool`, `double` → `Float`).
   - Kestrel return type: `Unit` for `void`, `Any` for `Object`/generics, primitives mapped as above.
4. **Override inline**: method stubs listed in the `{ ... }` body override the auto-generated types with the precise types the author specifies:
   ```kestrel
   extern import "java:java.util.HashMap" as HashMap {
     fun get(m: HashMap, k: String): Option<String>
     fun size(m: HashMap): Int
   }
   ```
5. Register the resulting `extern type` and `extern fun` stubs in the typecheck environment exactly as hand-written declarations.
6. **Stub output file**: alongside the compiled `.class` output for the module containing the `extern import` declaration, emit `<ClassName>.extern.ks` — a generated Kestrel file that contains the full set of auto-generated stubs in valid Kestrel syntax (one file per `extern import` declaration). This file is for **inspection only**: it shows exactly what the auto-binder produced, in a form that can be copy-pasted into the override block to refine types. It is a generated artifact (never hand-edited, gitignore-able) and follows the `.kdeps` sidecar convention from S02-12.

## Acceptance Criteria

- [ ] `extern import "java:java.util.HashMap" as HashMap { }` generates stubs for all public methods of `java.util.HashMap` (with `Any` types).
- [ ] `extern import "java:java.util.HashMap" as HashMap { fun size(m: HashMap): Int }` generates all stubs but overrides `size` with the precise Kestrel type.
- [ ] Stubs for methods using erased generic return types use `Any`.
- [ ] The generated stubs are indistinguishable in the type environment from hand-written `extern fun` declarations.
- [ ] A test module using `extern import` from a JDK class compiles and runs correctly.
- [ ] `extern import "java:java.util.HashMap" as HashMap { }` emits `HashMap.extern.ks` alongside the compiled output; the file contains valid Kestrel `extern type` and `extern fun` stubs for all public methods.
- [ ] `cd compiler && npm test` passes.

## Spec References

- `docs/specs/01-language.md` — add `extern import` to the declarations section.

## Risks / Notes

- **Complexity**: reading `.class` files requires parsing the JVM class file format or depending on a library (ASM, etc.). Adding a library dependency to the TypeScript compiler is a significant architectural decision.
- **Generic erasure loss**: Java generics are erased in `.class` files. Auto-generated stubs cannot recover the original generic type parameters. Every erased return type becomes `Any` unless overridden. This limits the value of the auto-generation for heavily generic APIs (e.g. `Collections`, streams).
- **Stub output file location**: emitted alongside the `.class` output for the containing module (same directory, named `<ClassName>.extern.ks`). This parallels the `.kdeps` sidecar from S02-12. The file should be added to `.gitignore` (or the build system should treat the output directory as generated). If a module has multiple `extern import` declarations, each produces its own sidecar file.
- **Auto-generated overloads**: Java allows method overloading; Kestrel does not. If a Java class has multiple `put(K, V)` overloads, the auto-generator must either pick one, rename them, or emit `put_1`, `put_2`, etc. None of these options is clean. The override block allows the user to provide explicit bindings and rename as needed.
- **This feature is genuinely Optional — but has a concrete future trigger**: the only concrete value over hand-written `extern fun` declarations is reducing boilerplate when wrapping many methods. For the stdlib migrations (S02-04 through S02-10), hand-written declarations are used and are already minimal enough. **However**, an LLVM backend investigation is the anticipated trigger that makes this story non-optional. LLVM Java bindings (e.g. Bytedeco JavaCPP LLVM, LLVM4J) expose hundreds of functions; hand-writing `extern fun` stubs for exploratory API sketching would be prohibitively tedious. `extern import` would allow rapid stub generation during exploration, with precise type overrides added progressively as the needed API surface converges. Implement this story before or alongside any LLVM backend story — not after. **Note on JavaCPP-style bindings**: Bytedeco's LLVM bindings use a pointer-wrapper model (`LLVMContextRef`, `LLVMModuleRef`, etc.). Auto-generated stubs will treat these as `Any`; explicit `extern type` declarations and inline overrides will still be needed for each pointer type of interest, but this is far less work than starting from scratch.
