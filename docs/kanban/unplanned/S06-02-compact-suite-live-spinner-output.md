# Test output: suite-first live spinner and duration updates across all modes

## Sequence: S06-02
## Tier: Optional / verification — Test harness UX
## Former ID: (none)

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)
- Companion stories: 67, 72

## Summary

Improve test output readability across all three harness styles (compact, verbose, summary) by rendering each suite header before its child assertion lines, showing a visual spinner while the suite is running, and replacing that spinner in place with the suite duration when the suite completes.

## Current State

- The `kestrel test` runner wiring and mode selection live in `scripts/run_tests.ks`.
- Compact / verbose / summary rendering behavior is implemented in `stdlib/kestrel/test.ks`.
- Current compact mode prints passing suite summaries after child test lines, which can make duration context feel visually inverted.
- ANSI styling primitives already exist in `stdlib/kestrel/console.ks` and are used by test output.
- `stdlib/kestrel/process.ks` does not currently expose stdout TTY capability, so terminal-control behavior cannot be auto-gated from stdlib alone yet.

## Relationship to other stories

- Follow-up UX refinement on top of `docs/kanban/done/21-stdlib-kestrel-test-framework-completeness.md`.
- Independent of current networking roadmap stories (`68`–`70`) and async implementation story `59`.
- May require aligned wording updates with command-output docs in `docs/specs/09-tools.md` and test-library contract text in `docs/specs/02-stdlib.md`.

## Goals

1. In all three output styles (`outputCompact`, `outputVerbose`, `outputSummary`), suite context appears first and remains visually anchored while assertions print below.
2. A running suite shows a clear spinner marker to communicate active execution.
3. Suite completion replaces spinner state in place with final elapsed milliseconds for that suite.
4. Nested groups remain readable and preserve indentation without cursor corruption.
5. Existing pass/fail accounting semantics stay unchanged.

## Acceptance Criteria

- [ ] Compact mode prints suite headers before child assertion output for both passing and failing suites.
- [ ] Verbose mode prints suite headers before child assertion output and preserves existing per-assertion detail lines.
- [ ] Summary mode prints suite headers before child assertion output while preserving summary-oriented suppression of assertion chrome.
- [ ] Each running suite shows a spinner indicator (exact glyph set to be finalized in planned) and a live-running state.
- [ ] On suite completion, the same line is updated in place and spinner state is replaced by final duration text (no stale duplicate running line).
- [ ] Nested suite updates preserve indentation and do not overwrite unrelated lines.
- [ ] Failure output remains complete and understandable; failure expansion in compact mode still prints diagnostics reliably.
- [ ] Spinner-and-duration behavior is implemented in all three styles (`--verbose`, default compact, and `--summary`) with style-appropriate detail levels documented in specs.
- [ ] Non-interactive output path is explicitly handled (fallback rendering or opt-in gating) so redirected logs do not contain unreadable cursor-control artifacts.
- [ ] JVM test runs maintain equivalent logical harness behavior for the same test files, allowing timing differences.

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:test` output mode contract and `group` / `printSummary` behavior.
- `docs/specs/09-tools.md` — `kestrel test` output behavior and mode descriptions.
- `docs/specs/08-tests.md` — dual-runtime expectations and test harness coverage context.

## Risks / Notes

- Clarifying note: "applies to all three styles" means each suite still gets a visible lifecycle line (running spinner -> completed duration) in compact, verbose, and summary modes; assertion verbosity remains mode-specific.
- ANSI cursor control is terminal-dependent; redirected/CI logs must remain clean and readable.
- Without TTY detection from stdlib process APIs, planned phase must choose between explicit CLI opt-in, runtime capability extension, or conservative fallback behavior.
- Spinner update cadence should avoid noisy output or expensive redraw loops.
- Scope should remain test-output UX and avoid broad harness redesign unless separately tracked.
- Detailed Tasks, Tests to add, and Documentation/spec update checklists belong in `planned/` when this story is promoted.
