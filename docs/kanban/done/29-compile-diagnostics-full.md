# Complete Compile Diagnostics per Spec 10


## Sequence: 29
## Former ID: 50
## Priority: 50 (High)

## Summary

Spec 10 defines a comprehensive diagnostic system with structured diagnostics, error codes, source snippets with carets, and machine-readable JSON output. The current implementation is partial -- the `diagnostics/` module exists with the right types, but coverage is incomplete and not all compiler phases emit structured diagnostics consistently.

## Current State

- `diagnostics/types.ts`: Defines `Diagnostic`, `SourceLocation`, `Severity`, and error code constants. Good foundation.
- `diagnostics/reporter.ts`: Implements human-readable (Rust-style with carets) and JSON formatting. Works for the cases it handles.
- **Parser**: Throws `ParseError` which is caught and converted to one `Diagnostic` in `compile()`. Location comes from the parser's token span. Works but only produces one error (stops at first).
- **Type checker**: Collects multiple `TypeCheckError` items, converted to `Diagnostic` in `compile()`. Has `code`, `message`, and location (`line`, `column`). Reasonably complete.
- **Resolver**: Returns success/failure; caller (`compile-file.ts`) builds Diagnostics with file and import span. Working.
- **CLI**: Supports `--format=json` flag. Outputs diagnostics to stderr. Exits non-zero on error.

### Gaps

- Parser does not recover and collect multiple errors (stops at first).
- Not all error codes from spec 10 &sect;4 are used consistently.
- `endLine`/`endColumn` often missing (only `line`/`column` set).
- `sourceLine` field not populated by all phases.
- `related` locations (secondary spans) not used.
- `hint` and `suggestion` fields rarely populated.
- No `--format=json` documentation.

## Acceptance Criteria

- [ ] Parser error recovery: continue parsing after an error to report multiple diagnostics per compilation (at least for common cases like missing semicolons, unmatched braces).
- [ ] All compiler phases use the error code taxonomy from spec 10 &sect;4 (`parse:*`, `resolve:*`, `type:*`, `export:*`, `file:*`).
- [ ] Diagnostics include `endLine`/`endColumn` where the AST span provides them.
- [ ] At least one diagnostic uses `related` (secondary location) -- e.g., type mismatch showing where the expected type was inferred.
- [ ] At least one diagnostic uses `hint` or `suggestion` -- e.g., "Did you mean `println`?" for unknown identifiers.
- [ ] Human output format matches spec 10 &sect;6 (file:line:column, source line, caret).
- [ ] JSON output format matches spec 10 &sect;7 (one JSON object per line on stderr).
- [ ] **Integration test**: verify diagnostic output format for a known parse error and a known type error.
- [ ] **Documentation**: Update all relevent specification documents allowing the decisions and formats and rationale to be well communicated and understood.

## Spec References

- 10-compile-diagnostics (entire spec)
