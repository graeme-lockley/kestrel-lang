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

After S01-02:
- A virtual thread executor exists and manages async work.
- When `main` returns, the process exits — there is no mechanism to wait for pending virtual threads.
- `scripts/kestrel` parses subcommands (`run`, `build`, `test`, `dis`) but has no `--exit-wait` / `--exit-no-wait` flags.

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

- `docs/specs/09-tools.md` (CLI: `kestrel run`, flags)
- `docs/specs/01-language.md` §5 (process lifetime and async model)

## Risks / Notes

- **Executor shutdown semantics**: `executor.shutdown()` + `awaitTermination()` for `--exit-wait`; `executor.shutdownNow()` for `--exit-no-wait`. Virtual threads that are mid-I/O will be interrupted on `shutdownNow()`.
- **Default behavior change**: If today's behavior is "exit immediately after main," then `--exit-wait` as default changes behavior for programs with pending async work. Since async work does not overlap today (pre-S01-02), this is safe — no existing program has pending work at exit.
- **Test programs**: Need a test program that spawns async work and relies on the exit mode to verify both paths. S01-06 covers the E2E test.
