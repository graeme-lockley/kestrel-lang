# Stdlib Tests for json, fs, and stack Modules

## Sequence: 16
## Tier: 4 — Stdlib and test harness
## Former ID: 111

## Summary

Three stdlib modules — `kestrel:json`, `kestrel:fs`, and `kestrel:stack` — have implementations but zero test coverage. Adding tests ensures these modules work correctly and prevents regressions.

## Current State

- `stdlib/kestrel/json.ks`: `parse` and `stringify` exported; no `json.test.ks`.
- `stdlib/kestrel/fs.ks`: `readText`, `writeText`, `listDir` exported; no `fs.test.ks`.
- `stdlib/kestrel/stack.ks`: `format` and `print` exported (`trace` is deferred to sequence **13**); no `stack.test.ks`.

## Acceptance Criteria

### kestrel:json
- [ ] `json.test.ks` exists.
- [ ] Test `parse` with valid JSON (object, array, string, number, bool, null).
- [ ] Test `stringify` round-trips with `parse`.
- [ ] Test `parse` with invalid JSON returns an error (Result Err).

### kestrel:fs
- [ ] `fs.test.ks` exists.
- [ ] Test `readText` reads an existing file and returns its contents.
- [ ] Test `readText` on a missing file returns an error.
- [ ] Test `writeText` writes a file, then `readText` reads it back.
- [ ] Test `listDir` returns entries for a directory.

### kestrel:stack
- [ ] `stack.test.ks` exists.
- [ ] Test `format` returns a non-empty string.
- [ ] Test `print` does not crash (output verification is optional).

## Spec References

- 02-stdlib (kestrel:json, kestrel:fs, kestrel:stack)
- 08-tests (stdlib coverage)
