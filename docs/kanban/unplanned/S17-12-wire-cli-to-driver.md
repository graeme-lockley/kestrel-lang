# Wire cli.ks compileScript to call the Kestrel driver in-process

## Sequence: S17-12
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-01, S17-02, S17-03, S17-04, S17-05, S17-06, S17-07, S17-08, S17-09, S17-10, S17-11, S17-13

## Summary

Replace the `runProcessStream("node", [compilerCli, ...])` call in `cli.ks` with a direct
in-process call to `Driver.compileFile`. Remove the `compilerCli` parameter from
`compileScript` and all call sites. The Node path must no longer be reachable for normal
compilation. `cli-main.ks` build scaffold is superseded by this wiring.

## Current State

`stdlib/kestrel/tools/compiler/cli-main.ks` calls `Driver.compileFile` for the `build` command
but then still forwards all commands (including `run`) through `runProcessStream("./kestrel", ...)`
which invokes the Node.js TypeScript compiler. The Node path is still the primary compilation
path in practice.

## Relationship to other stories

- **Depends on**: S17-11 (full driver pipeline with sidecars)
- **Blocks**: S17-13 (E2E validation that Node is not needed)

## Goals

1. In `cli-main.ks`, update `runBuildScaffold` to use the fully-implemented `Driver.compileFile`
   (not the stub).
2. For the `run` command: after compilation, run the output class in-process (as the current
   CLI already does via `URLClassLoader`).
3. Remove any code path that spawns `node compiler/dist/cli.js`.
4. Remove `compilerCli` parameter if present.
5. Ensure `kestrel build <file>` and `kestrel run <file>` work end-to-end without Node.

## Acceptance Criteria

- [ ] `kestrel build hello.ks` compiles and writes `.class` files without invoking Node.
- [ ] `kestrel run hello.ks` compiles and executes `hello.ks` without invoking Node.
- [ ] No code path in `cli-main.ks` spawns `node` for normal compilation.
- [ ] `cli-main.test.ks` is updated to reflect the new dispatch logic.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/09-tools.md` — CLI architecture
- `docs/specs/11-bootstrap.md` — self-hosted compilation path

## Risks / Notes

- The `run` command also needs the compiled output to be executed in-process; verify that the
  existing `URLClassLoader` execution path in `Cli.ks` handles the output from the new driver.
- After this change, `kestrel build` still uses Node for compilation until the bootstrap
  JAR is regenerated; the `--self-hosted` flag or automatic mode detection handles this.
