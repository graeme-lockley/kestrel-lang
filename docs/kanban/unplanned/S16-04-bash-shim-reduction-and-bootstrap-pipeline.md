# Bash shim reduction and bootstrap pipeline integration

## Sequence: S16-04
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E16 Kestrel CLI in Kestrel](../epics/unplanned/E16-kestrel-cli-in-kestrel.md)
- Companion stories: S16-01, S16-02, S16-03, S16-05

## Summary

Trim `scripts/kestrel` from ~640 lines to ≤ 50 lines and update `scripts/build-bootstrap-jar.sh`
so that the bootstrap JAR includes the compiled `cli.ks` classes alongside the compiler classes.
After this story, `kestrel bootstrap` installs `kestrel/tools/Cli.class` into `~/.kestrel/jvm/`
and the shrunk Bash shim delegates every user command to the Kestrel CLI class via a single
`exec java` invocation.

These two changes are bundled in one story because they form two sides of the same transition:
the shim reduction is only safe once the bootstrap pipeline guarantees the CLI class is present
after `kestrel bootstrap`.

## Current State

`scripts/kestrel` contains ~640 lines of Bash. The bootstrap JAR packaging script
(`scripts/build-bootstrap-jar.sh`) compiles only `cli-entry.ks`, packaging the compiler classes
but not a general CLI dispatcher class.

After S16-03, `stdlib/kestrel/tools/cli.ks` exists and is compilable. After S16-05 (bootstrap
pipeline) the class will be in the JAR; this story makes both halves happen together.

## Relationship to other stories

- **Depends on S16-03** (`kestrel:tools/cli`): the Kestrel CLI must be implemented before the
  shim can delegate to it.
- **Prerequisite for S16-05** (spec updates): specs describe the new shim contract.

## Goals

### Bash shim (`scripts/kestrel`)

The new shim performs exactly these steps:
1. Resolve `ROOT` via `BASH_SOURCE` + `readlink` (symlink-safe, unchanged).
2. Set and export `KESTREL_ROOT="$ROOT"`.
3. Set `JVM_CACHE`, `MAVEN_RUNTIME_JAR`, `MAVEN_BOOTSTRAP_JAR` as before.
4. If command is `bootstrap` — run the existing `cmd_bootstrap` logic (JAR extraction to
   `~/.kestrel/jvm/`). This is unchanged and stays in Bash.
5. If command is `build` with no script argument — call `npm run build` + `runtime/jvm/build.sh`
   + copy runtime JAR to Maven cache. This is unchanged and stays in Bash.
6. If command is `--allow-ts-compiler __ts-compile` — delegate directly to
   `node "$COMPILER_CLI" …` (unchanged; needed during bootstrap JAR construction).
7. Otherwise: `exec java -Xss8m -cp "$MAVEN_RUNTIME_JAR:$JVM_CACHE" kestrel.tools.Cli "$@"`.

The shim does **not** check for the runtime JAR or the `Cli_entry.class` gate — those are the
responsibility of the Kestrel CLI class (which will report an appropriate error if the gate files
are absent).

### Bootstrap JAR (`scripts/build-bootstrap-jar.sh`)

After compiling `cli-entry.ks` into `$CLASSES_DIR`, also compile `cli.ks`:
```bash
"$ROOT/kestrel" --allow-ts-compiler __ts-compile \
    "$ROOT/stdlib/kestrel/tools/cli.ks" "$CLASSES_DIR"
```
The JAR packaging step (`jar --create`) then includes the `kestrel/tools/Cli.class` together with
the compiler classes.

Add a verification step: `jar tf "$JAR_PATH" | grep -q 'tools/Cli.class'`.

The `kestrel bootstrap` command (still in Bash) extracts the JAR to `~/.kestrel/jvm/`. Because
`kestrel/tools/Cli.class` is now in the JAR, extraction automatically installs it. No change to
the `kestrel bootstrap` Bash implementation is needed.

## Acceptance Criteria

- `scripts/kestrel` is ≤ 50 lines of Bash.
- `build-bootstrap-jar.sh` produces a JAR that contains `kestrel/tools/Cli.class`.
- After `./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap`, all commands work without
  the project tree at execution time:
  `kestrel run`, `kestrel build <script>`, `kestrel test --summary`, `kestrel fmt`, `kestrel doc`,
  `kestrel dis`, `kestrel status` all succeed.
- `kestrel bootstrap` itself continues to work on a clean machine (no regression).
- The `--allow-ts-compiler __ts-compile` path continues to work during
  `build-bootstrap-jar.sh` execution.
- All E2E tests pass.

## Spec References

- `docs/specs/11-bootstrap.md` §1.1 Architecture Stages — stage 2 ("kestrel bootstrap") and
  stage 3 ("Normal commands") are updated in S16-05 to reflect the new Cli class.
- `docs/specs/09-tools.md` §1 Entry Point.

## Risks / Notes

- **`Cli_entry.class` gate**: currently the Bash script checks for `Cli_entry.class` in
  `~/.kestrel/jvm/` before allowing normal commands. After this story the Kestrel CLI performs
  this check. Ensure the error message and instructions are preserved.
- **Clean-machine test**: the most important acceptance test is `rm -rf ~/.kestrel && \
  ./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap && ./kestrel test --summary`.
  Run this manually before marking done.
- **`maybe_exec_selfhost_cli`**: the current Bash script contains a stub
  `maybe_exec_selfhost_cli() { return 0; }` that was pre-wired for this moment. The new shim
  replaces this with the unconditional `exec java` delegation.
