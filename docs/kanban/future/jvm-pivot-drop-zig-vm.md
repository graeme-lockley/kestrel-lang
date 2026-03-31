# Investigation: Drop Zig VM and Pivot to JVM-Only

**Status:** Investigation (future)  
**Date:** 2026-03-30  
**Author:** Research analysis

## Summary

Should Kestrel drop the custom Zig VM, rely solely on the JVM backend, and
potentially rewrite the TypeScript compiler in Java/Kotlin to fully embrace the
JVM ecosystem? This document captures the trade-offs.

---

## Current State

### What Exists Today

| Component | Technology | LOC | Maturity |
|-----------|-----------|-----|----------|
| Compiler | TypeScript (Node.js) | ~14,200 | Stable — lexer, parser, H-M type inference, dual codegen |
| VM backend | Zig bytecode interpreter | ~4,700 | Stable — 23 opcodes, mark-sweep GC, modules, closures, exceptions |
| JVM backend | TypeScript → .class files | ~3,170 | Stable — full codegen, StackMapTable, closures as inner classes |
| JVM runtime | Java (17 files) | ~1,000 | Stable — all primitives, ADTs, I/O, math |
| Stdlib | Kestrel (.ks) | ~28 modules | Runs on both backends |
| CLI | Bash (734 lines) | — | Supports `--target vm\|jvm`, `test-both` comparison |

### Feature Parity

| Feature | VM | JVM | Notes |
|---------|:--:|:---:|-------|
| Core language | ✅ | ✅ | Identical semantics |
| Pattern matching | ✅ | ✅ | |
| Closures | ✅ | ✅ | VM: bytecode; JVM: inner classes |
| Exception handling | ✅ | ✅ | |
| Mutual recursion | ✅ | ✅ | |
| Self-tail optimisation | ✅ | ✅ | VM: frame reuse; JVM: GOTO loop |
| Module system | ✅ | ✅ | |
| Async/await | ⚠️ stub | ⚠️ minimal | Neither has real suspension yet |
| Debug/stack traces | ✅ custom | ✅ JVM native | Different mechanisms |
| GC | ✅ mark-sweep | ✅ JVM GC | JVM GC far more mature |
| FFI | ❌ none | ⚠️ via Java interop | JVM opens Java ecosystem |

### Performance (from existing investigation)

The mandelbrot benchmark shows JVM completing in ~50% of VM time.
Root cause: HotSpot JIT compiles hot loops to native code; the Zig VM is a
simple interpreter loop with per-opcode dispatch overhead.

---

## Option A: Keep Both Backends (Status Quo)

### Advantages

1. **Standalone deployment** — The Zig VM produces a single native binary with
   no dependency on a JVM installation. Users can run Kestrel programs with only
   the ~2 MB VM binary.

2. **Educational and architectural value** — Building a custom VM deepens
   understanding of language implementation. The bytecode format, GC, and
   instruction set are all under full control.

3. **Startup time** — The Zig VM starts instantly (native process). JVM has
   class-loading overhead and JIT warmup latency (~100-500 ms for small
   programs). For short-lived scripts, the VM may actually be faster end-to-end.

4. **Full control over runtime model** — Custom GC tuning, value
   representation (61-bit tagged values), and instruction set evolution without
   JVM constraints.

5. **Zig-specific benefits** — Zig's safety guarantees, comptime, and
   zero-overhead abstractions make the VM implementation clean and low-risk for
   memory bugs.

### Disadvantages

1. **Double maintenance cost** — Every language feature must be implemented
   twice: VM codegen (2,831 LOC) + JVM codegen (2,380 LOC) + VM interpreter
   (2,023 LOC) + JVM runtime (1,000 LOC). The async/await story (seq 55) will
   need two implementations.

2. **Performance ceiling** — Without a JIT, the VM will always be slower than
   JVM on compute-heavy workloads. Building a JIT is a multi-person-year effort.

3. **Limited ecosystem access** — The Zig VM has no FFI; users cannot call
   into existing libraries. The 40 primitive functions are the entire API
   surface.

4. **Test burden** — Every feature needs testing on both backends. The
   `test-both` command exists but doubles CI time and debugging effort.

5. **Async divergence risk** — Implementing a proper event loop in both the Zig
   VM and as JVM bytecode is a major engineering challenge with high divergence
   risk.

---

## Option B: Drop Zig VM, JVM-Only (Keep TypeScript Compiler)

### Advantages

1. **Halve the codegen work** — Remove ~7,500 lines (VM codegen + Zig VM
   source). Every future feature only needs one backend implementation.

2. **Immediate performance win** — HotSpot JIT, G1/ZGC garbage collection,
   and decades of JVM optimisation for free.

3. **Java ecosystem access** — Path to Java interop opens access to thousands
   of libraries (HTTP servers, JSON, databases, async I/O via NIO/Netty).

4. **Async/await simplification** — JVM has `CompletableFuture`, virtual
   threads (Project Loom), and mature async primitives. Seq 55 becomes much
   simpler.

5. **Debugging and profiling** — JVM has world-class tooling: JVisualVM,
   async-profiler, JFR, IDE debuggers. The custom VM has none of this.

6. **Mature GC** — G1, ZGC, Shenandoah. No need to maintain a custom
   mark-sweep collector.

### Disadvantages

1. **JVM dependency** — Users must have a JVM installed. Kestrel loses the
   "download one binary and run" story. This is significant for scripting use
   cases.

2. **Startup latency** — JVM startup is 100-500 ms. For short scripts and
   CLI tools, this is noticeable. GraalVM native-image could mitigate this
   but adds complexity.

3. **Loss of control** — Value representation is constrained by JVM's type
   system (everything is `Object`; no 61-bit tagged values). GC behaviour is
   opaque. Bytecode verification rules constrain codegen.

4. **Spec drift** — The bytecode format spec (03-bytecode-format.md) and
   runtime model spec (05-runtime-model.md) become irrelevant. Need new specs
   for JVM class generation conventions.

5. **Class file complexity** — The hand-rolled classfile.ts (594 LOC) is
   fragile. More complex features (generics reification, invokedynamic for
   closures) will push it toward needing a proper library like ASM.

---

## Option C: Full JVM Pivot (Rewrite Compiler in Java/Kotlin)

This is Option B plus rewriting the TypeScript compiler in Java or Kotlin.

### Additional Advantages Over Option B

1. **Single ecosystem** — One language (Java/Kotlin), one build tool
   (Gradle/Maven), one runtime (JVM) for everything. No Node.js dependency for
   the compiler.

2. **Compiler-runtime co-evolution** — The compiler and runtime share the same
   process. In-process compilation becomes trivial (useful for REPL, eval,
   hot-reload).

3. **ASM library** — Use the mature [ASM](https://asm.ow2.io/) bytecode
   library instead of hand-rolling classfile.ts. ASM handles StackMapTable,
   invokedynamic, and verification automatically.

4. **Kotlin advantages** — Kotlin's sealed classes model ADTs naturally;
   pattern matching is built-in; coroutines could simplify async implementation.
   The compiler's own type system (H-M unification) maps well to Kotlin idioms.

5. **GraalVM path** — A JVM-native compiler could eventually target GraalVM
   native-image for fast startup, or use Truffle for a high-performance
   interpreter with automatic JIT.

6. **Community appeal** — Java/Kotlin developers are more abundant than Zig
   developers. Contributions become more likely.

### Additional Disadvantages Over Option B

1. **Rewrite cost** — The TypeScript compiler is ~14,200 lines across lexer,
   parser, type checker, diagnostics, module resolution, and codegen. A faithful
   port is 3-6 months of effort depending on scope.

2. **Rewrite risk** — Rewrites frequently introduce subtle regressions. The
   existing 22 compiler test files, 80 conformance tests, and 32 unit tests
   would need porting. The risk is mitigated by having a golden corpus but not
   eliminated.

3. **Loss of existing investment** — The TypeScript compiler is stable and
   working. The 49 completed kanban stories represent significant validated
   work.

4. **TypeScript was a good choice** — TypeScript's type system is expressive,
   the tooling is excellent (Vitest, VS Code), and the language is well-suited
   to compiler implementation (union types, exhaustive matching via `never`).
   Kotlin is comparable but not dramatically better for this domain.

5. **Node.js is already a dependency** — The CLI (`scripts/kestrel`) already
   requires Node.js for compilation. Switching to JVM doesn't simplify the
   user-facing dependency story unless you also ship native binaries.

6. **Build tool overhead** — Gradle/Maven introduce their own complexity.
   The current `npm install && npm run build` is very fast (~3s). Gradle builds
   are heavier.

---

## Decision Matrix

| Criterion | Weight | A: Both | B: JVM + TS | C: Full JVM |
|-----------|--------|---------|-------------|-------------|
| Feature velocity | High | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ (after rewrite) |
| Performance | Medium | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Ecosystem access | High | ⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Deployment simplicity | Medium | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Maintenance burden | High | ⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Rewrite risk | High | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Startup time | Low | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Tooling (debug/profile) | Medium | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Async story (seq 55+) | High | ⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Community/contributions | Low | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |

⭐ = worse, ⭐⭐⭐⭐⭐ = best

---

## The Async Inflection Point

The upcoming async/await work (seq 55) is the most significant decision driver.
Implementing a proper event loop requires:

- **In the Zig VM:** A custom event loop, frame suspension/resumption,
  non-blocking I/O integration, and task scheduling. This is a substantial
  engineering effort (hundreds of lines of complex concurrent code) with
  limited precedent in the codebase.

- **On the JVM:** Virtual threads (Project Loom, Java 21+) or
  `CompletableFuture` provide production-grade async primitives. The JVM
  codegen could emit `CompletableFuture` chains or use virtual threads
  transparently. The async runtime is essentially free.

If async/await is a priority (it is — seq 55 is planned, seq 56 HTTP depends
on it), the JVM backend is dramatically easier to implement correctly.

---

## Recommended Approach: Phased Pivot (B → Self-Hosting)

Based on this analysis and subsequent discussion, the chosen direction is a
two-phase approach: JVM-only first, then a **self-hosting Kestrel compiler**
(rather than a Kotlin/Java rewrite).

### Phase 1: JVM-Primary, VM-Deprecated (Option B)

**Timeline:** Immediate  
**Effort:** Low  

1. Make JVM the default target (`--target jvm` becomes the default).
2. Implement async/await (seq 55) on JVM only.
3. Implement HTTP (seq 56) on JVM only.
4. Mark the Zig VM as "legacy/frozen" — no new features, keep existing tests
   passing for regression, but don't invest in parity.
5. Replace hand-rolled classfile.ts with a proper classfile builder if needed
   (or keep it — 594 LOC is manageable).
6. Update specs: deprecate 03-bytecode-format.md and 05-runtime-model.md;
   add JVM conventions spec.

This gets the biggest wins (halved feature work, better async, ecosystem
access) with minimal disruption.

### Phase 2: Self-Hosting Kestrel Compiler (Replaces Option C)

**Timeline:** After Phase 1 is stable  
**Effort:** High  
**See also:** `future/self-hosting-kestrel-compiler.md`

Instead of rewriting the compiler in Kotlin/Java, the plan is to write a
**Kestrel compiler in Kestrel itself**. The TypeScript compiler becomes the
bootstrap compiler only.

**Build chain:**

1. TypeScript compiler (bootstrap) compiles the Kestrel compiler source → JVM
   `.class` files.
2. The Kestrel compiler (running on JVM) compiles itself → JVM `.class` files.
3. The output from step 2 is the production compiler; the TypeScript compiler
   is only needed to rebuild from scratch.

**Benefits over Option C (Kotlin rewrite):**

- Kestrel is its own best test case ("eating your own dog food").
- Forces the language to be expressive enough for real-world tooling.
- Proves the JVM backend can handle a non-trivial program.
- No new language ecosystem to learn (no Kotlin/Gradle dependency).
- The TypeScript compiler remains as a frozen bootstrap — no rewrite risk.

**Risks:**

- Kestrel may need language features it doesn't yet have (file I/O, string
  manipulation, data structures) to write a compiler. These become
  prerequisites.
- The bootstrap chain is more complex: changes to the language may require
  updating both the TypeScript bootstrap compiler and the Kestrel compiler.
- Debugging a self-hosting compiler is harder than debugging a Kotlin port.

Phase 2 is a significant engineering experiment but aligns with the project's
educational goals and validates Kestrel as a practical language.

---

## What Would Be Lost

To be honest about the costs:

- **The Zig VM is elegant** — 4,700 lines of clean, well-structured code with
  a custom GC, tagged value representation, and bytecode interpreter. It
  represents significant intellectual investment.

- **Zero-dependency deployment** — The Zig VM binary is self-contained. JVM
  requires a Java installation (though bundled JREs and GraalVM native-image
  mitigate this).

- **Fast startup** — The VM starts in <1ms. JVM startup is 100-500ms.
  For scripting use cases where you run many short programs, this matters.

- **Learning opportunity** — If Kestrel's purpose includes being educational
  (understanding language implementation at all levels), the custom VM is
  irreplaceable.

---

## What Would Be Gained

- **Async/await becomes tractable** — JVM virtual threads or CompletableFuture
  vs building a custom event loop from scratch in Zig.

- **2× performance for free** — HotSpot JIT on compute-heavy code, with no
  engineering investment.

- **Java library ecosystem** — HTTP servers (Jetty, Netty), JSON (Jackson,
  Gson), databases (JDBC), crypto (BouncyCastle), etc. FFI into Java
  opens enormous possibilities.

- **Feature velocity doubles** — One backend means one implementation per
  feature, one test suite, one debugging session.

- **Better tooling** — JVM profilers, debuggers, and monitoring are
  world-class. The Zig VM has none of this.

---

## Open Questions

1. ~~**Is Kestrel primarily educational or practical?**~~ **Resolved:** Both.
   The self-hosting approach serves both goals — it's practical (JVM
   performance, ecosystem) and educational (building a compiler in your own
   language).

2. ~~**How important is zero-dependency deployment?**~~ **Deferred:** JVM
   dependency is accepted for now. GraalVM native-image remains a future
   option for standalone binaries.

3. ~~**Is the compiler rewrite (Phase 2) worth it?**~~ **Resolved:** Yes, but
   as a self-hosting Kestrel compiler rather than a Kotlin port. See
   `future/self-hosting-kestrel-compiler.md`.

4. **GraalVM as a middle ground?** GraalVM native-image could compile the JVM
   output to native binaries, recovering zero-dependency deployment and fast
   startup. Worth investigating after Phase 1.

5. ~~**What is the team size?**~~ **Resolved:** Solo developer. Halving backend
   work (Phase 1) is high priority. Self-hosting (Phase 2) is a longer-term
   experiment.

6. **What language features does Kestrel need before self-hosting?** See the
   detailed prerequisite table in `future/self-hosting-kestrel-compiler.md`.
   Key gaps: arrays (story 57), maps, and byte-level I/O.
