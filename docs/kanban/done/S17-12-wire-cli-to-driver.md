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

- [x] `kestrel build hello.ks` compiles and writes `.class` files without invoking Node.
- [x] `kestrel run hello.ks` compiles and executes `hello.ks` without invoking Node.
- [x] No code path in `cli-main.ks` spawns `node` for normal compilation.
- [x] `cli-main.test.ks` is updated to reflect the new dispatch logic.
- [x] `cd compiler && npm run build && npm test` passes.
- [x] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/09-tools.md` — CLI architecture
- `docs/specs/11-bootstrap.md` — self-hosted compilation path

## Risks / Notes

- The `run` command also needs the compiled output to be executed in-process; verify that the
  existing `URLClassLoader` execution path in `Cli.ks` handles the output from the new driver.
- After this change, `kestrel build` still uses Node for compilation until the bootstrap
  JAR is regenerated; the `--self-hosted` flag or automatic mode detection handles this.

---

## Impact analysis

| File | Change |
|------|--------|
| `stdlib/kestrel/tools/cli.ks` | Add `Driver`/`Rep` imports; add `deleteFiles`, `deleteKtiFiles`, `compileWithDriver`; remove `compileScript` and `buildCompilerFlags`; remove `compilerCli` param from `cmdRun`, `cmdBuild`, `cmdDis`, `cmdTest`, `cmdFmt`, `cmdDoc`; inline node invocation in `cmdTsCompile`; remove `compilerCli` from `main` |
| `stdlib/kestrel/tools/compiler/cli-main.ks` | Fix `dispatch` to not forward to `./kestrel` after a successful `build` |
| `stdlib/kestrel/tools/compiler/cli-main.test.ks` | Update "build command forwards" test group to reflect that build no longer forwards |
| `docs/specs/09-tools.md` | Note compilation uses in-process Kestrel driver (not Node) |
| `docs/specs/11-bootstrap.md` | Update CLI compilation path description |

## Tasks

- [x] `cli.ks`: add imports for `Driver` (`kestrel:tools/compiler/driver`) and `Rep` (`kestrel:dev/typecheck/reporter`)
- [x] `cli.ks`: add `deleteFiles(files: List<String>): Task<Unit>` recursive helper
- [x] `cli.ks`: add `deleteKtiFiles(outDir: String): Task<Unit>` using `Fs.collectFilesByExtension`
- [x] `cli.ks`: add `compileWithDriver(entrySource, outDir, kestrelRoot, refresh, allowHttp, clean): Task<Int>`
- [x] `cli.ks`: remove `compileScript` function; inline node invocation in `cmdTsCompile`
- [x] `cli.ks`: remove `buildCompilerFlags` function
- [x] `cli.ks`: remove `compilerCli` param from `cmdRun`; replace `compileScript` call with `compileWithDriver`; remove `shouldCompile`/`needsCompile` check (driver handles freshness via KTI)
- [x] `cli.ks`: remove `compilerCli` param from `cmdDis`; replace `compileScript` call with `compileWithDriver`; remove `needsCompile` check
- [x] `cli.ks`: remove `compilerCli` param from `cmdBuild`; replace `compileScript` call with `compileWithDriver`
- [x] `cli.ks`: remove `compilerCli` param from `cmdTest`; replace `compileScript` call with `compileWithDriver`; remove `needsCompile` check
- [x] `cli.ks`: remove `compilerCli` param from `cmdFmt`; replace `compileScript` call with `compileWithDriver`; remove `needsCompile` check
- [x] `cli.ks`: remove `compilerCli` param from `cmdDoc`; replace `compileScript` call with `compileWithDriver`; remove `needsCompile` check
- [x] `cli.ks`: remove `compilerCli` local from `main`; update all call sites
- [x] `cli-main.ks`: fix `dispatch` — return `runBuildScaffold` result directly for `build`; forward other commands as before
- [x] `cli-main.test.ks`: rename "build command forwards" group to "forwardArgs for non-build commands"; test `run` command forwarding
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`
- [x] Update `docs/specs/09-tools.md`
- [x] Update `docs/specs/11-bootstrap.md`

## Tests to add

- Update `cli-main.test.ks`: rename group "build command forwards" to "forwardArgs for non-build commands" and test `run` command forwarding (the build-no-longer-forwards behavior is implicit in `dispatch`'s simplified structure)

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — add note that compilation uses the in-process Kestrel driver, not Node
- [x] `docs/specs/11-bootstrap.md` — update CLI compilation path section to reflect driver-based compilation

## Build notes

- 2026-04-27: Started implementation.
- 2026-04-27: `compileScript` (Node-based) replaced by `compileWithDriver` which calls `Driver.compileFile` in-process. `--clean` implemented by deleting `.kti` files before calling the driver (driver handles freshness via KTI, so deleting them forces a full recompile). `buildCompilerFlags` removed as it was only used to build the flags list for the node invocation. `cmdTsCompile` keeps an inline node invocation for the bootstrap `__ts-compile` internal command. `needsCompile`/`anyDepNewer` left as dead code — driver handles freshness internally via KTI. `cli-main.ks` `dispatch` simplified: `build` now returns `runBuildScaffold` directly without also forwarding to `./kestrel`.
