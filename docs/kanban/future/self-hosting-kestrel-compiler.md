# Self-Hosting Kestrel Compiler

## Kind

Investigation / engineering experiment — not on the numbered roadmap.

## Context

The current Kestrel compiler is written in TypeScript (~14,200 LOC) and targets
both a Zig bytecode VM and the JVM. The plan (see
`future/jvm-pivot-drop-zig-vm.md`) is to:

1. **Phase 1:** Move to JVM-only, deprecate the Zig VM.
2. **Phase 2:** Write the Kestrel compiler in Kestrel itself, using the
   TypeScript compiler only as a bootstrap.

This investigation captures the design, prerequisites, and open questions for
Phase 2: the **self-hosting Kestrel compiler**.

## What is self-hosting?

A self-hosting compiler is a compiler for language X that is itself written in
language X. The bootstrap process requires an existing compiler (here, the
TypeScript compiler) to compile the first version of the new compiler. After
that, the compiler can compile itself.

### Build chain

```
┌─────────────────────────────────────────────────────────────────┐
│  Bootstrap (one-time or from-scratch rebuild)                   │
│                                                                 │
│  TypeScript compiler ──compile──▶ Kestrel compiler (.class)     │
│  (frozen bootstrap)     (ksc.ks → JVM bytecode)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Self-hosting (normal development)                              │
│                                                                 │
│  Kestrel compiler (.class) ──compile──▶ Kestrel compiler (.class)│
│  (stage 1)                    (ksc.ks → JVM bytecode)           │
│                                                                 │
│  The stage-1 output can then compile itself again (stage 2).    │
│  Stage 1 output == Stage 2 output proves correctness.           │
└─────────────────────────────────────────────────────────────────┘
```

**Verification:** When the stage-1 compiled compiler produces identical output
to the stage-2 compiled compiler (compiling the same source), the self-hosting
chain is verified — the compiler faithfully reproduces itself.

## Language prerequisites

The Kestrel compiler needs these language features to write a compiler in
Kestrel:

| Feature | Current status | Notes |
|---------|---------------|-------|
| String manipulation | ✅ Basic ops | May need more: split, indexOf, substring, char-at |
| File I/O | ✅ `kestrel:fs` | Read source files, write `.class` output |
| Byte-level output | ❌ Not yet | `.class` file generation requires writing raw bytes (u8, u16, u32 big-endian); no byte/buffer type exists |
| Arrays / mutable collections | ❌ Not yet | Story 57 (array-builtin-type) is prerequisite |
| Maps / dictionaries | ❌ Not yet | Symbol tables, scope maps, type environments |
| Pattern matching | ✅ Full | Essential for AST traversal |
| ADTs (algebraic data types) | ✅ Full | AST node representation |
| Closures | ✅ Full | Parser combinators, visitors |
| Exception handling | ✅ Full | Error recovery |
| Module system | ✅ Full | Compiler module organisation |
| Generic types | ✅ Full | Type-safe collections |
| String interpolation | ✅ Yes | Diagnostic messages |

### Critical gaps

1. **Arrays (story 57):** The compiler needs mutable, indexed collections for
   bytecode emission buffers, constant pools, and operand stacks.
2. **Maps:** Symbol tables, type environments, and scope chains require
   key-value lookups. This may need a new story.
3. **Byte-level I/O:** Writing `.class` files requires emitting raw bytes
   (u8, u16, u32 in big-endian). Kestrel currently has no byte/buffer type.

## Compiler modules to port

| Module | TypeScript LOC | Complexity | Notes |
|--------|---------------|------------|-------|
| Lexer | ~336 | Low | Character-by-character scanning; straightforward |
| Parser | ~1,289 | Medium | Recursive descent; pattern matching maps well |
| Type checker | ~1,894 | High | H-M unification; union/intersection types |
| JVM codegen | ~2,380 | High | Emits JVM bytecode; needs byte-level I/O |
| Class file writer | ~594 | Medium | Binary format; constant pool, StackMapTable |
| Module resolution | ~500 | Medium | File system + import graph |
| Diagnostics | ~400 | Low | Error formatting with source locations |
| Bundler | ~300 | Low | Dependency ordering |
| **Total** | **~7,693** | | Core compiler without VM codegen |

*Note:* The VM codegen (~2,831 LOC) and related VM-specific code are dropped in
the JVM-only world, reducing total compiler scope significantly.

## Incremental strategy

Rather than a big-bang port, build the self-hosting compiler incrementally:

1. **Start with the lexer** — smallest module, minimal dependencies. Write
   `ksc/lexer.ks` that tokenizes Kestrel source. Test by comparing output to
   the TypeScript lexer.

2. **Add the parser** — depends only on the lexer and AST types. Write
   `ksc/parser.ks`. Test by comparing ASTs to TypeScript parser output.

3. **Add the type checker** — the most complex module. H-M unification with
   union/intersection types. Test by comparing type-annotated ASTs.

4. **Add JVM codegen** — requires byte-level output. This is where the
   bootstrap chain becomes useful: the TypeScript compiler compiles the Kestrel
   compiler, which then must produce working `.class` files.

5. **Add module resolution and bundler** — tie everything together into a
   working compiler.

6. **Bootstrap verification** — compile the Kestrel compiler with itself
   (stage 1), then use the output to compile itself again (stage 2). Verify
   stage 1 == stage 2.

## Questions or opportunities

1. **Which language features are blocking?** Arrays and maps are the biggest
   gaps. Should these be prioritised on the roadmap before self-hosting begins?

2. **Byte buffer type?** Should Kestrel have a first-class `Buffer` or
   `ByteArray` type for binary I/O, or can this be done through Java interop
   on the JVM?

3. **How to handle the TypeScript bootstrap freeze?** Once the self-hosting
   compiler exists, the TypeScript compiler should be frozen. But if Kestrel
   adds new syntax, the bootstrap compiler can't parse it. Options:
   - Keep the TypeScript compiler updated in lockstep (defeats the purpose)
   - Use a "last known good" `.class` snapshot for bootstrapping (simpler)
   - Two-stage bootstrap: old Kestrel compiler compiles new Kestrel compiler

4. **Testing strategy?** The existing conformance tests (80+ files) and e2e
   tests serve as a golden corpus. The Kestrel compiler must produce identical
   output for all of them.

5. **What about error messages?** The TypeScript compiler has rich diagnostics
   with source locations. The Kestrel compiler should match or exceed this
   quality.

6. **Build system complexity?** The build chain becomes:
   ```
   npm install → npm run build → node compile ksc.ks → java ksc ksc.ks → verify
   ```
   This is more complex than today but manageable with a Makefile or script.

## Relationship to other investigations

- **`jvm-pivot-drop-zig-vm.md`** — Phase 1 (JVM-only) is a prerequisite for
  this work. Self-hosting targets JVM exclusively.
- **Story 57 (array-builtin-type)** — Arrays are a prerequisite for the
  compiler.
- **Story 55 (async-await)** — Not needed for the compiler itself but
  validates the JVM-only direction.

## Promotion

When actionable: move to `unplanned/NN-self-hosting-kestrel-compiler.md` with
full unplanned sections. Prerequisites: Phase 1 of JVM pivot complete, arrays
and maps available in the language.
