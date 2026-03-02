# Lockfile (kestrel.lock)

## Description

Per spec 07 §7, a lockfile (`kestrel.lock` in the project root) records enough information to resolve URL (and optionally path) dependencies without network access or other non-determinism. When present, resolution uses the locked artifact for listed specifiers. The implementation does not yet support lockfile: no file format, no read/write, no “run kestrel lock” behaviour.

## Acceptance Criteria

- [ ] Define project root (e.g. directory containing kestrel.lock or current file’s ancestor; document in spec or README)
- [ ] Define lockfile format (e.g. TOML or JSON): map specifier → locked artifact (path, content hash, or pinned URL)
- [ ] When resolving: if lockfile is present and specifier is in lockfile, use locked artifact (fail if artifact missing)
- [ ] Add command or workflow to generate/update lockfile (e.g. `kestrel lock` or `kestrel install`) that resolves all dependencies and writes lockfile
- [ ] Document behaviour when lockfile is absent (07 §7)
- [ ] E2E or manual test: project with lockfile resolves without network; changing lockfile changes resolution
