# Lockfile: kestrel.lock

## Sequence: 26
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 140

## Summary

Spec 07 §7 defines `kestrel.lock` as a project-root file that records resolved dependency information for deterministic resolution without network access. This is primarily important for URL imports but also ensures reproducible builds for path dependencies.

## Current State

- No lockfile implementation exists.
- The compiler resolves imports on every compilation.
- URL imports are rejected (`resolve.ts` returns `null` for URLs).
- For local path imports, resolution is already deterministic (same project layout = same result).

## Dependencies

- Sequence **21** (URL imports) is the primary consumer. Lockfile for path-only projects is lower urgency.

## Acceptance Criteria

- [ ] Define lockfile format (JSON or TOML): for each specifier, store resolved path/hash/version.
- [ ] `kestrel lock` command: resolve all dependencies, write `kestrel.lock`.
- [ ] When lockfile is present, use locked artifacts for resolution.
- [ ] When a specifier is in the lockfile but the artifact is missing, report an error.
- [ ] When a specifier is NOT in the lockfile, either error or resolve-and-update (implementation choice).
- [ ] Integration test: create a lockfile, modify a dependency, verify the locked version is still used.

## Spec References

- 07-modules §7 (Lockfile: format, location, behaviour)
