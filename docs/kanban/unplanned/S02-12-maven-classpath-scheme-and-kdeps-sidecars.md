# `maven:` Classpath Scheme and `.kdeps` Conflict Detection

## Sequence: S02-12
## Tier: 7
## Former ID: (none)

## Epic

- Epic: [E02 JVM Interop — extern Bindings and Intrinsic Migration](../epics/unplanned/E02-jvm-reflection-interop-and-intrinsic-migration.md)
- Companion stories: S02-01, S02-02, S02-03, S02-04, S02-05, S02-06, S02-07, S02-08, S02-09, S02-10, S02-11, S02-13

## Summary

Implement the `maven:` import scheme: `import "maven:groupId:artifactId:version"` declares a Maven jar dependency inline in the source file. The compiler resolves and downloads the jar, caches it locally, and makes it available for `extern fun` descriptor resolution in the current file. On emit, the compiler writes a `.kdeps` sidecar file alongside the generated `.class` file recording the Maven coordinates. The CLI (`kestrel run`, `kestrel build`) reads `.kdeps` files transitively and reports version conflicts at link time.

## Current State

- `import` declarations support string specs (`"kestrel:string"`, relative paths, etc.) via `SideEffectImport` AST node in `compiler/src/ast/nodes.ts`. No `maven:` scheme is recognised — a `maven:` string would be treated as an unknown module specifier.
- `compiler/src/module-specifiers.ts` and `compiler/src/resolve.ts` define the current import resolution logic. Neither handles `maven:` coordinates.
- `compiler/src/compile-file-jvm.ts` orchestrates compilation of a single file. It does not generate sidecar files.
- `scripts/kestrel` (the CLI) does not aggregate `.kdeps` files or perform dependency conflict checking.
- There is no local Maven cache mechanism in the compiler.

## Relationship to other stories

- **Depends on S02-01, S02-02**: `maven:` is only useful in combination with `extern type` and `extern fun`. Without them, a jar on the classpath cannot be bound to Kestrel types.
- **Independent of S02-04 through S02-11** (migration stories): no migration story uses `maven:` — they all bind to the JVM runtime jar which is always on the classpath.
- **Independent of S02-13** (`extern import`): both can be built in parallel. `maven:` provides the artifact; `extern import` reads the class metadata. They compose but neither depends on the other.

## Goals

1. **Parser/resolver**: recognise `import "maven:groupId:artifactId:version"` as a new import kind. Define `MavenImport` AST node (or extend `SideEffectImport` with a `maven` subtype). No names are brought into scope — the import is purely a classpath declaration.
2. **Artifact resolution**: at compile time, resolve the Maven coordinates:
   - Check a local cache directory at `~/.kestrel/maven/<groupId>/<artifactId>/<version>/<artifactId>-<version>.jar`.
   - On cache miss: download from Maven Central (`https://repo1.maven.org/maven2/...`) or a configurable repository.
   - **Download progress**: while downloading, render an inline progress bar to stderr. Format: `  Downloading org.apache.commons:commons-lang3:3.20.0 [=====>     ] 47%`. Update in-place using ANSI cursor-up/carriage-return so multiple concurrent downloads compose cleanly. On completion replace the bar with a single-line summary: `  Downloaded org.apache.commons:commons-lang3:3.20.0 (542 KB)`. Suppress progress when stderr is not a TTY (pipes, CI with no TTY) — emit a plain single-line `Downloading ...` instead.
   - Add the resolved jar to the compiler's classpath for JVM descriptor resolution in the current file.
3. **`.kdeps` sidecar emission**: after compiling a file that contains `maven:` imports, write a `<outputFile>.kdeps` JSON file:
   ```json
   {
     "maven": {
       "org.apache.commons:commons-lang3": "3.20.0"
     }
   }
   ```
4. **CLI conflict detection**: when running or building a multi-module program, collect `.kdeps` files from all compiled modules transitively. Detect any artifact with two different version requirements. Report the conflict clearly:
   ```
   Dependency conflict:
     myapp.ks requires org.apache.commons:commons-lang3:3.20.0
     util/text.ks requires org.apache.commons:commons-lang3:3.18.0
   Fix: align both imports to the same version.
   ```
5. **Classpath propagation**: when `kestrel run myapp.ks` runs, include all resolved jars from `.kdeps` files on the JVM classpath passed to the JVM process.

## Acceptance Criteria

- [ ] `import "maven:org.apache.commons:commons-lang3:3.20.0"` parses without error.
- [ ] The compiler downloads and caches the jar to `~/.kestrel/maven/` on first use.
- [ ] A download in progress renders an inline progress bar to stderr (percentage + bar); on completion it collapses to a single summary line.
- [ ] When stderr is not a TTY, a plain `Downloading ...` line is emitted instead.
- [ ] An `extern fun` descriptor in the same file can reference classes from the downloaded jar.
- [ ] Compiling a file with `maven:` imports produces a `.kdeps` sidecar alongside the `.class` output.
- [ ] `kestrel run` with a two-module program whose `.kdeps` files conflict reports the conflict clearly and exits with a non-zero code before running the program.
- [ ] `kestrel run` with a two-module program with the same maven version in both `.kdeps` files succeeds.
- [ ] A new E2E test (`tests/e2e/scenarios/positive/maven_import.ks` or similar) uses `maven:` and an `extern fun` to call a function from a downloaded jar.
- [ ] `cd compiler && npm test` passes.

## Spec References

- `docs/specs/09-tools.md` — document the `maven:` import scheme, local cache location, and conflict detection behaviour.
- `docs/specs/01-language.md` — note `maven:` as a module specifier form that is a classpath declaration, not a namespace import.

## Risks / Notes

- **Security**: downloading arbitrary jars from the internet is a significant security concern. The compiler must:
  - Only download from HTTPS endpoints.
  - Verify the SHA-1/SHA-256 checksum from Maven Central before using the jar.
  - Store the checksum in the `.kdeps` file so multi-machine builds can verify cache integrity.
  - Never execute downloaded jars during compilation (classpath access only).
- **Maven Central availability**: if Maven Central is unreachable, the build must fail with a clear error, not a cryptic connection timeout. Provide a `--offline` flag to skip download and fail fast on cache miss.
- **Version resolution is NOT performed**: this story implements *conflict detection* (two modules disagreeing on the version of the same artifact), not *version resolution* (picking the higher version automatically). Automatic resolution is out of scope — the fix is always "edit the source file."
- **Transitive Maven dependencies**: the `maven:` import specifies a single artifact. That artifact may itself have Maven transitive dependencies. Resolving transitive deps requires a POM parser and conflict graph, which is far more complex. For the initial implementation: resolve only the directly-specified artifact and its direct compile-scope deps listed in its POM, or simply require the user to list all required jars explicitly if transitive deps are needed.
- **Cache location**: `~/.kestrel/maven/<groupId>/<artifactId>/<version>/` mirrors the standard Maven local repository layout, making it familiar and easy to inspect manually. Configurable via `KESTREL_MAVEN_CACHE` environment variable for CI and hermetic build environments. The full path matches `~/.kestrel/maven/org/apache/commons/commons-lang3/3.20.0/commons-lang3-3.20.0.jar`.
- **`.kdeps` is generated, not committed**: add `*.kdeps` to `.gitignore` recommendations. These files are build artifacts.
