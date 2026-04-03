# Epic E01: Async Runtime Foundation

## Status

Unplanned

## Summary

Foundation epic for real async behavior on the JVM backend: correct `await` suspension, event-loop execution model, and runtime confidence checks needed before higher-level networking work.

## Stories

- [S01-01-async-await-suspension-event-loop.md](../../unplanned/S01-01-async-await-suspension-event-loop.md)

## Dependencies

- Unblocks Epic E02 for robust async networking behavior.

## Epic Completion Criteria

- Story S01-01 is done with event-loop and suspension semantics verified.
- JVM compiler/runtime tests required by member stories pass.
