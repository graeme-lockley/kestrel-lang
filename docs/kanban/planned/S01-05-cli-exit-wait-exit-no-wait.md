# CLI --exit-wait and --exit-no-wait Flags

## Sequence: S01-05
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: (none — split from original S01-01)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)
- Companion stories: S01-01, S01-02, S01-03, S01-04, S01-06, S01-07, S01-08, S01-09

## Summary

Add process lifetime flags to `kestrel run`. By default (`--exit-wait`), the JVM process stays alive until the virtual thread executor is quiescent — all spawned virtual threads have completed. `--exit-no-wait` overrides this: exit immediately after `main` returns, abandoning any pending async work. Wire the flags through `scripts/kestrel` into the JVM launch path and document in `09-tools`.

## Current State

Current repo state:
- `runtime/jvm/src/kestrel/runtime/KRuntime.java` already owns the virtual-thread executor, tracks in-flight async tasks, and `runMain` currently always calls `awaitAsyncQuiescence()` before `shutdownAsyncRuntime()`.
- `scripts/kestrel` already parses `--exit-wait` and `--exit-no-wait` for `kestrel run`, rejects the mutually-exclusive combination, and passes `-Dkestrel.exitWait=false` for `--exit-no-wait`.
- The runtime does not yet read `kestrel.exitWait`, so both CLI modes still behave as wait-on-exit today.
- The CLI exposes only top-level usage text; there is no dedicated `kestrel run --help` output documenting the new flags.
- Existing async runtime coverage exercises task overlap and `await` exception flow, but there is no targeted integration or E2E coverage for wait-vs-no-wait process lifetime.

## Relationship to other stories

- **Depends on S01-02**: The virtual thread executor must exist for shutdown behavior to matter.
- **Independent of S01-03, S01-04**: Error handling and I/O changes are orthogonal.
- **Verified by S01-06**: E2E tests exercise both modes.

## Goals

1. **--exit-wait (default)**: After `main` returns, the JVM waits for the virtual thread executor to become idle (all submitted tasks completed) before exiting.
2. **--exit-no-wait**: After `main` returns, shut down the executor immediately and exit — pending async work is abandoned.
3. **Flag parsing**: `scripts/kestrel` parses `--exit-wait` and `--exit-no-wait` for the `run` subcommand. Supplying both is an error with a clear message.
4. **JVM wiring**: The chosen mode is passed to the JVM runtime (e.g. as a system property or command-line argument to the Java process).
5. **Documentation**: `docs/specs/09-tools.md` updated with flag descriptions and behavior.
6. **CLI help**: `kestrel run --help` shows the new flags.

## Acceptance Criteria

- [ ] `kestrel run script.ks` (no flags) waits for async work to complete before exiting.
- [ ] `kestrel run --exit-wait script.ks` behaves identically to the default.
- [ ] `kestrel run --exit-no-wait script.ks` exits after `main` returns, even if async tasks are pending.
- [ ] `kestrel run --exit-wait --exit-no-wait script.ks` prints an error and exits non-zero.
- [ ] The exit mode is passed to the JVM and respected by `KRuntime` executor shutdown logic.
- [ ] `docs/specs/09-tools.md` documents both flags under `kestrel run`.
- [ ] `kestrel run --help` includes `--exit-wait` and `--exit-no-wait` descriptions.
- [ ] Existing tests pass: `cd compiler && npm run build && npm test`, `./scripts/kestrel test`.

## Spec References

- `docs/specs/09-tools.md` (CLI: `kestrel run`, flags, help output)
- `docs/specs/01-language.md` §5 (Task model and process lifetime at program exit)

## Risks / Notes

- **Executor shutdown semantics**: `executor.shutdown()` + `awaitTermination()` for `--exit-wait`; `executor.shutdownNow()` for `--exit-no-wait`. Virtual threads that are mid-I/O will be interrupted on `shutdownNow()`.
- **Default behavior change**: If today's behavior is "exit immediately after main," then `--exit-wait` as default changes behavior for programs with pending async work. Since async work does not overlap today (pre-S01-02), this is safe — no existing program has pending work at exit.
- **Test programs**: Need a test program that spawns async work and relies on the exit mode to verify both paths. S01-06 covers the E2E test.

## Impact analysis

| Area | Change |
|------|--------|
| Compiler / JVM codegen (`compiler/src/jvm-codegen/codegen.ts`) | No intentional compiler surface change if exit mode remains a JVM system property: generated mains already enter through `KRuntime.runMain`. Verify the existing `runMain` call remains compatible; only change compiler wiring if property-based runtime selection proves insufficient. Rollback risk is low because the call boundary can stay stable. |
| JVM runtime (`runtime/jvm/src/kestrel/runtime/KRuntime.java`) | Add explicit exit-mode selection at process shutdown so `runMain` can choose wait-for-quiescence vs immediate executor shutdown. This is the core behavioral change and carries the main compatibility risk called out above: defaulting to wait changes program lifetime for scripts that launch background async work. |
| CLI script (`scripts/kestrel`) | Finish the CLI surface by documenting `--exit-wait` / `--exit-no-wait` in help text, preserving mutual-exclusion validation, and keeping JVM property wiring stable. Risk: help parsing must not regress script-argument forwarding for `kestrel run <script> [args...]`. |
| Stdlib / user-visible runtime behavior | No API signature changes, but observable process-lifetime behavior changes for async programs. Incorporate the executor interruption risk from Risks / Notes into the implementation and docs so abandoned work under `--exit-no-wait` is intentional and documented. |
| Tests (`compiler/test/integration/`, `tests/e2e/scenarios/`, `scripts/run-e2e.sh`) | Add direct coverage for default wait behavior, explicit no-wait behavior, mutually-exclusive flag errors, and help output. Regression risk is moderate because timing-sensitive tests can be flaky unless the scenario prints unambiguous markers. |
| Specs (`docs/specs/09-tools.md`, `docs/specs/01-language.md`) | Update CLI and async-runtime documentation to describe the default wait semantics, the opt-out flag, and the fact that `--exit-no-wait` may abandon pending async work by interrupting virtual threads. |

## Tasks

- [ ] Update `runtime/jvm/src/kestrel/runtime/KRuntime.java` `runMain` / shutdown helpers to read the configured exit mode and branch between wait-for-quiescence + orderly shutdown and immediate `shutdownNow()` semantics.
- [ ] Update `scripts/kestrel` `usage()` and `cmd_run()` help handling so `kestrel run --help` documents `--exit-wait` and `--exit-no-wait` without regressing existing run-argument parsing or mutual-exclusion errors.
- [ ] Verify `compiler/src/jvm-codegen/codegen.ts` main entrypoint remains compatible with property-driven runtime selection; keep the existing `KRuntime.runMain` call unchanged unless runtime wiring requires a signature change.
- [ ] Add JVM/runtime integration coverage in `compiler/test/integration/jvm-async-runtime.test.ts` for wait-vs-no-wait shutdown behavior, ideally via a small Java harness that sets `kestrel.exitWait` and observes whether pending async work prints before process exit.
- [ ] Add CLI-facing end-to-end coverage under `tests/e2e/scenarios/positive/` and/or `tests/e2e/scenarios/negative/` plus any needed `scripts/run-e2e.sh` support so default run, explicit `--exit-wait`, explicit `--exit-no-wait`, and conflicting flags are exercised through `./scripts/kestrel`.
- [ ] Update `docs/specs/09-tools.md` `kestrel run` usage/help text to document both flags, the default wait behavior, and the conflicting-flags error.
- [ ] Update `docs/specs/01-language.md` §5 to document process lifetime at program exit for async tasks, including the `--exit-no-wait` abandonment/interruption behavior.
- [ ] Run `cd compiler && npm run build && npm test`
- [ ] Run `cd runtime/jvm && bash build.sh`
- [ ] Run `./scripts/kestrel test`
- [ ] Run `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Vitest integration | `compiler/test/integration/jvm-async-runtime.test.ts` | Add a harness that launches async work after `main` returns and asserts default / explicit wait allows the work to finish while `kestrel.exitWait=false` exits before the trailing marker is printed. |
| Vitest integration | `compiler/test/integration/jvm-async-runtime.test.ts` | Add a direct runtime-level regression for `shutdownNow()` semantics so interrupted virtual-thread work does not hang the process on `--exit-no-wait`. |
| E2E positive | `tests/e2e/scenarios/positive/async-exit-wait-default.ks` | Exercise `kestrel run` with default behavior and assert stdout includes the async completion marker that would be lost under immediate exit. |
| E2E positive | `tests/e2e/scenarios/positive/async-exit-wait-explicit.ks` | Exercise `kestrel run --exit-wait` and assert it matches the default wait-on-exit behavior. |
| E2E negative | `tests/e2e/scenarios/negative/run-conflicting-exit-flags.ks` or scripted `run-e2e.sh` case | Assert `kestrel run --exit-wait --exit-no-wait ...` fails fast with the documented mutual-exclusion error and non-zero exit. |
| CLI smoke / script test | `scripts/run-e2e.sh` or a focused shell test helper | Add a check that `kestrel run --help` prints both exit flags so the documented CLI surface is enforced. |

## Documentation and specs to update

- [ ] `docs/specs/09-tools.md` — update `kestrel run` usage, option descriptions, help behavior, and conflicting-flag error handling for `--exit-wait` / `--exit-no-wait`.
- [ ] `docs/specs/01-language.md` — extend §5 async runtime behavior with process-lifetime semantics at `main` exit and the interruption/abandonment behavior of `--exit-no-wait`.
