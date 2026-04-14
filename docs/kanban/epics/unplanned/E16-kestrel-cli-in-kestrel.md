# Epic E16: Kestrel CLI in Kestrel

## Status

Unplanned

## Summary

Replace the bulk of `scripts/kestrel` — currently ~640 lines of Bash — with a Kestrel program
(`stdlib/kestrel/tools/cli.ks`) that implements every user-facing command (`run`, `dis`, `build`,
`status`, `test`, `fmt`, `doc`, `lock`) and the internal `__ts-compile` gate. A minimal Bash shim
(~40 lines) remains responsible for the three things that are genuinely circular or pre-runtime:
resolving `ROOT` from the script's own path, the `bootstrap` command (which must run before any
Kestrel code is available on a clean machine), and triggering `kestrel build` (no-arg) to compile
the TypeScript seed compiler and JVM runtime from source. Everything else delegates to the
self-hosted JVM CLI class via `exec java`. The epic also covers the end-to-end installation story —
both a fresh-machine bootstrap and the day-to-day developer workflow — so the runtime JAR, the CLI
class, and the bootstrap compiler JAR all land cleanly in `~/.kestrel/maven` with no project-tree
references at execution time.

## Stories

(None yet — use plan-epic to decompose, or story-create to add individual stories.)

## Dependencies

- **E14** (Self-Hosting Compiler) — done; provides `kestrel:tools/compiler/*` and the self-hosted
  CLI scaffolding.
- **E15** (Bootstrap JAR Self-Hosting Handoff) — done; establishes the `kestrel bootstrap`
  command, the Maven-cache layout (`~/.kestrel/maven/lang/kestrel/…`), and the `Cli_entry.class`
  gate that determines whether self-hosted mode is active. E16 builds directly on this contract.
- **E12** (Full Process Environment) — done; `getEnv`, `getCwd`, `runProcessStream`, and
  environment inheritance are all required for the CLI implementation.
- **E13** (Stdlib Compiler Readiness) — done; `Fs.stat` (mtime), `mkdirAll`, `collectFiles`, and
  `readText` are all required.

## Epic Completion Criteria

- `scripts/kestrel` is ≤ 50 lines of Bash; every user-visible command except `bootstrap` is
  handled by the Kestrel CLI class.
- `kestrel bootstrap` remains entirely in Bash and is responsible for: building the TypeScript
  seed compiler and JVM runtime (if needed), compiling `cli-entry.ks` and `cli.ks` into
  `~/.kestrel/maven/lang/kestrel/compile/…`, and installing the runtime JAR into
  `~/.kestrel/maven/lang/kestrel/runtime/…`.
- A clean-machine install walkthrough succeeds end-to-end:
  `./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap` leaves the machine in a state where
  all commands work without touching the project tree at execution time.
- `kestrel run`, `kestrel build <script>`, `kestrel test`, `kestrel fmt`, `kestrel doc`, and
  `kestrel dis` all pass their existing test suites.
- The Kestrel CLI performs incremental compile-staleness checks (mtime via `Fs.stat`) equivalent
  to the current `needs_compile_jvm` Bash logic.
- Maven classpath resolution (currently delegated to `resolve-maven-classpath.mjs` via Node) is
  handled by the Kestrel CLI.
- `kestrel status` reports compiler mode as before.
- The `KESTREL_ROOT` environment variable is set by the Bash shim and consumed by the Kestrel CLI
  so the CLI does not need to resolve its own source location.
- All existing E2E tests pass.
- specs in `docs/specs/11-bootstrap.md` and `docs/specs/09-tools.md` are updated to reflect the
  new bootstrap flow and CLI architecture.

## Implementation Approach

### Split of responsibilities

| Layer | What it does |
|---|---|
| `scripts/kestrel` (Bash shim, ≤ 50 lines) | Resolve `ROOT`, set `KESTREL_ROOT`, handle `bootstrap` and no-arg `build`, otherwise `exec java -cp $MAVEN_RUNTIME_JAR:$JVM_CACHE kestrel.tools.Cli "$@"` |
| `stdlib/kestrel/tools/cli.ks` (~350 lines) | All user commands: run, dis, build \<script\>, status, test, fmt, doc, lock, \_\_ts-compile |

### Bootstrap / clean-machine install flow

1. `./scripts/build-bootstrap-jar.sh` — builds TS compiler + JVM runtime, compiles `cli-entry.ks`
   **and** `cli.ks` into a bootstrap JAR, installs both JARs to `~/.kestrel/maven/…`.
2. `./kestrel bootstrap` — extracts the bootstrap JAR to `~/.kestrel/jvm/`, installing
   `Cli_entry.class`, `Cli_main.class`, and `kestrel/tools/Cli.class` (the new shim target).
3. From this point the Bash shim fully delegates to the Kestrel CLI class.

### Developer (re-compile) flow

- `./kestrel build` (no-arg, Bash-only path) — rebuilds TS compiler + JVM runtime, then copies
  the updated runtime JAR to the Maven cache path.
- `./kestrel build stdlib/kestrel/tools/cli.ks` — recompiles only the CLI program into
  `~/.kestrel/jvm/` so the shim picks up the updated class immediately.

### Two-JVM tradeoff

After this change, `kestrel run foo.ks` starts a JVM for the CLI which then spawns a second JVM
for the compiled script. The extra cold-start cost (~200 ms) is negligible for long-running
programs; a future GraalVM native-image build of the CLI can eliminate it.
