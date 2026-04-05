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

## Impact Analysis

- `runtime/jvm/src/kestrel/runtime/KRuntime.java` — add `isTtyStdout()`.
- `stdlib/kestrel/basics.ks` — add `isTtyStdout()` extern.
- `stdlib/kestrel/console.ks` — add `SPINNER` and `CLEAR_LINE` constants.
- `stdlib/kestrel/test.ks` — add `isTty: Bool` to `Suite` type; add `spinnerActive: mut Bool` to `counts`; remove `compactStackBox: mut CompactStackBox`; rewrite `group()` for suite-first output; simplify `onAssertionFailure()`.
- `scripts/run_tests.ks` — update generated test-runner template to include `isTty` field.
- `docs/specs/02-stdlib.md` — update kestrel:test section.
- `docs/specs/09-tools.md` — update test output description.

## Tasks

- [x] Add `isTtyStdout()` to `KRuntime.java`
- [x] Add `isTtyStdout` extern to `basics.ks`
- [x] Add `SPINNER` and `CLEAR_LINE` to `console.ks`
- [x] Rewrite `test.ks`: remove `compactStackBox`, add `isTty`/`spinnerActive`, new `group()` behaviour
- [x] Update `run_tests.ks` generated template for new Suite shape
- [x] Update `docs/specs/02-stdlib.md`
- [x] Update `docs/specs/09-tools.md`
- [x] Verify all tests pass

## Build notes

2026-03-07: All Kestrel tests pass (exit code 0).

- Removed `compactStackBox` and its supporting functions (`printBatchesOuterFirst`, `compactPrependToTop`, `compactPop`, `flushFrameIfNonempty`, `emptyFrames`, `flushCompactForFailure`). The new "suite-first" approach does not need back-buffering since group headers are printed eagerly.
- `isTtyStdout` uses `System.console() != null` — returns `false` in piped/redirected contexts (CI). In non-TTY mode the output is verbose-style: group title at start + summary line at end, which is clean in log files.
- Kestrel does not support `&&`/`||` — uses `&`/`|` for boolean operators. Assignments (`:=`) must be statements (semicolon-terminated); using `:=` as the final expression in a block requires an explicit `; ()` to follow.
- Spinner behavior: leaf groups (no nested group calls) get the in-place update. Parent groups that spawn child groups have their spinner committed when the first child calls `commitSpinner(s)` at group start; the parent's completion line is then printed on a new line below children. The stale `⠋ name` line on screen for non-leaf groups in TTY mode is functionally acceptable.
- `compactExpanded` is now reset to `False` at each group start and restored after the body completes, ensuring sibling groups each start in unexpanded state.

## Tests to add

No new test files needed — existing tests exercise the group/assertion logic.

## Docs to update

- `docs/specs/02-stdlib.md` — kestrel:test section
- `docs/specs/09-tools.md` — test output behavior

## Risks / Notes

- Removing `compactStackBox` is a breaking change to the `Suite` public type; the only consumer outside stdlib is the generated runner in `run_tests.ks` which is also updated.
- In-place spinner update uses `\r\033[2K` — only applied when `isTty` is true and no child output was printed during the body.
- Nested groups with child output: parent spinner is committed (newline printed) when the first child group runs; parent completion line is printed on a new line after children complete.
- TTY detection relies on `System.console() != null` (standard Java approach).
