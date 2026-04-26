# `runInProcess` — in-process class-loading runtime primitive

## Sequence: S16-01
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E16 Kestrel CLI in Kestrel](../epics/done/E16-kestrel-cli-in-kestrel.md)
- Companion stories: S16-02, S16-03, S16-04, S16-05

## Summary

Add a `KRuntime.runInProcess` static method to the JVM runtime (~30 lines Java) that loads a
compiled Kestrel program into the current JVM instance using a `URLClassLoader` constructed from a
supplied classpath, then dispatches the program's `$init` method on a new platform thread with an
8 MiB explicit stack (the same depth guarantee as `-Xss8m`). Expose this as an `extern fun` in
`kestrel:sys/process` (or a thin new module). The existing virtual-thread async executor and
`KRuntime.runMain` lifecycle are shared — no isolation boundary is needed because the user program
calls `System.exit()` directly, which terminates the CLI JVM with the correct exit code.

## Current State

The JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`) already contains:
- `runProcessStreamAsync` — spawns a child process (inherits stdin/stdout/stderr)
- `runMain(String[], KFunction)` — manages async quiescence and graceful shutdown
- `Class.forName` usage in `KWatcher` for cancel-class lookup

There is no in-process class-loading API. Currently `kestrel run` spawns a child `java` process
because the Bash launcher uses `exec java …`.

## Relationship to other stories

- **Prerequisite for S16-03** (`kestrel:tools/cli`): the Kestrel CLI uses `runInProcess` to
  execute user programs without spawning a child JVM.
- **Independent of S16-02** (Maven classpath resolver): can be built in any order.

## Goals

1. `KRuntime.runInProcess(Object classpath, Object mainClass, Object args)` is added to
   `KRuntime.java`. It:
   - Builds a `URLClassLoader` from the provided list of JAR/class-dir paths.
   - Loads the named main class via `classLoader.loadClass(mainClass)`.
   - Locates the `$init` method (the Kestrel entry-point convention).
   - Starts a new `Thread` with `stackSize = 8 * 1024 * 1024`, calls `$init` on it, and
     joins the thread.
   - Returns nothing (`KUnit`); the user program ends the process via `System.exit()`.
2. The Java method is exposed in the stdlib as:
   ```
   extern fun runInProcess(classpath: List<String>, mainClass: String, args: List<String>): Unit =
     jvm("kestrel.runtime.KRuntime#runInProcess(java.lang.Object,java.lang.Object,java.lang.Object)")
   ```
3. A minimal stdlib test (or conformance test) verifies that a trivial compiled program can be
   loaded and executed in-process.

## Acceptance Criteria

- `KRuntime.runInProcess` compiles and is callable from Kestrel via `extern fun`.
- Calling `runInProcess` with the classpath for a compiled `hello.ks` (or equivalent) prints the
  expected output — demonstrating that the loaded class's code runs in the caller's JVM.
- `System.exit(code)` called by the in-process program terminates the whole JVM (this is the
  desired behaviour; no security manager intercept is needed).
- Stack depth of 8 MiB is honoured (thread is created with explicit `stackSize` argument).
- Existing runtime tests pass.

## Spec References

- `docs/specs/09-tools.md` §2.1 (run — Execution section): currently describes spawning `java`;
  will be updated in S16-05 to reflect in-process execution.

## Risks / Notes

- **`System.exit` scope**: in-process execution means any `exit()` call in user code immediately
  terminates the CLI JVM. This is intentional and matches the current behaviour. If a future
  story needs to run programs without terminating the host (e.g. a REPL), a `SecurityManager`
  (deprecated in Java 17+) or a custom exit hook would be needed, but that is out of scope here.
- **Classloader isolation**: user program classes are loaded through a child `URLClassLoader`
  whose parent is the system classloader. Runtime classes (`kestrel.runtime.*`) are already on the
  system classpath and are shared — this is correct.
- **`mainClass` derivation**: the class-name derivation logic (`classNameForPath`) is currently
  duplicated in the Bash script and in `resolve-maven-classpath.mjs`. The Kestrel CLI (S16-03)
  will port it to Kestrel string functions; `runInProcess` itself just takes the pre-derived name.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `runtime/jvm/src/kestrel/runtime/KRuntime.java` — add `runInProcess(Object, Object, Object)` static method (~45 lines); add `java.net.URL`, `java.net.URLClassLoader`, `java.lang.reflect.Method` imports |
| Stdlib | `stdlib/kestrel/sys/process.ks` — add `extern fun runInProcess(...)` declaration |
| JVM build | Rebuild `kestrel-runtime.jar` via `cd runtime/jvm && bash build.sh` |

## Tasks

- [x] Add `java.net.URL`, `java.net.URLClassLoader`, and `java.lang.reflect.Method` imports to `KRuntime.java`
- [x] Add `KRuntime.runInProcess(Object classpath, Object mainClass, Object args)` to `KRuntime.java`:
  - Build `List<URL>` from the `KList<String>` classpath argument
  - Create `URLClassLoader(urls, Thread.currentThread().getContextClassLoader())` (fallback: `ClassLoader.getSystemClassLoader()`)
  - Load `mainClass` via `cl.loadClass(mainClass.replace('.', '/'))` — handle '.' vs '/' conversion for JVM internal names
  - Locate `main(String[])` via `cls.getDeclaredMethod("main", String[].class)` (or `$init` via `cls.getDeclaredMethod("$init")`)
  - Construct args `String[]` from `KList<String>` argsObj
  - Create `Thread(null, runnable, "kestrel-run", 8 * 1024 * 1024)` (platform thread with 8 MiB stack)
  - Start thread, join; on normal return (no System.exit): call `System.exit(0)`
  - Return `KUnit.INSTANCE`
- [x] Export `runInProcess` in `stdlib/kestrel/sys/process.ks` as `extern fun runInProcess(classpath: List<String>, mainClass: String, args: List<String>): Unit`
- [x] `cd runtime/jvm && bash build.sh`
- [x] `cd compiler && npm run build && npm test`
- [x] `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness (integration) | `tests/unit/process.test.ks` | Verify `runInProcess` can be called; since System.exit terminates the process, integration relies on S16-03 cmd_run tests |

*Note: a direct unit test for `runInProcess` is deferred to S16-03 integration (it would terminate the test process). The critical verification is that the symbol compiles and is reachable from Kestrel.*

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` §2.1 — completed in S16-05 (no spec change in this story)

## Build notes

- 2026-04-14: Implemented `KRuntime.runInProcess` using `URLClassLoader` with the current thread's
  context classloader as parent (falling back to `ClassLoader.getSystemClassLoader()`). Invokes
  `main(String[])` via reflection on a platform Thread with explicit 8 MiB stack. After the thread
  joins, calls `System.exit(0)` so the JVM always terminates — whether or not the user program
  called `exit()` explicitly. The `System.exit` path from `InvocationTargetException` is not
  reachable at runtime (the JVM terminates before unwinding), but the catch re-throws correctly
  for any non-exit error.
- 2026-04-14: mainClass input uses dots (Java convention); any '/' are normalised with `.replace('/', '.')`.
  The `$init` method is the internal Kestrel init method; `main(String[])` is what's actually
  invoked so KRuntime.runMain handles async quiescence correctly for the user program.
- 2026-04-14: Runtime build produced "unchecked or unsafe operations" warning — this is pre-existing
  in KRuntime.java (raw KList/KCons generics) and not introduced by this change.
- 2026-04-14: All 440 compiler tests and 1837 Kestrel tests pass.
