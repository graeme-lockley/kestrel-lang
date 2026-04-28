# `./kestrel-self` script and bootstrap into `~/.kestrel/self/`

## Sequence: S17-47
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-46, S17-48, S17-50, S17-49

## Summary

Add `scripts/kestrel-self` (and a root-level symlink `./kestrel-self`) as the dedicated entry
point for the self-hosted Kestrel compiler, pinned to `KESTREL_SELF_CACHE` (`~/.kestrel/self/`).
Move the `bootstrap` subcommand so that `./kestrel-self bootstrap` extracts to
`~/.kestrel/self/`; leave a one-release deprecation shim on `./kestrel bootstrap` that
redirects to the new location. Update `./kestrel status` to report both caches.

## Current State

- `scripts/kestrel` handles `bootstrap` by extracting the JAR to `$JVM_CACHE` (which after
  S17-45 is `~/.kestrel/ts/` — the TS cache). Bootstrap should target the self cache.
- There is no separate script for the self-hosted compiler path.
- `./kestrel status` reports only one compiler mode and one cache path.

## Relationship to other stories

- **Depends on**: S17-45 (dual cache), S17-46 (TS routing restored in `cli.ks`)
- **Blocks**: S17-48 (test runner needs `./kestrel-self` to drive tests)

## Goals

1. `scripts/kestrel-self` mirrors the shape of `scripts/kestrel` but:
   - Sets `JVM_CACHE` to `$KESTREL_SELF_CACHE` (default `~/.kestrel/self/`).
   - Sets `KESTREL_SELF=1` so `cli.ks` routes to `Driver.compileFile` in-process.
   - `bootstrap` extracts the JAR to `~/.kestrel/self/`.
2. Root-level `./kestrel-self` is a symlink to `scripts/kestrel-self`.
3. `./kestrel bootstrap` prints a one-line deprecation notice and delegates to
   `./kestrel-self bootstrap` (for one release).
4. `./kestrel status` (in `cli.ks`) is updated to show:
   - TS compiler cache: `~/.kestrel/ts/` — present/absent.
   - Self-hosted cache: `~/.kestrel/self/` — present/absent (bootstrapped/not bootstrapped).
5. `./kestrel-self bootstrap && ./kestrel-self run hello.ks` succeeds and produces output
   identical to `./kestrel run hello.ks`.

## Acceptance Criteria

- [ ] `scripts/kestrel-self` exists and is executable.
- [ ] `./kestrel-self` symlink exists at repository root.
- [ ] `./kestrel-self bootstrap` extracts to `~/.kestrel/self/`.
- [ ] `./kestrel bootstrap` prints a deprecation notice and forwards to `./kestrel-self bootstrap`.
- [ ] `./kestrel status` reports both caches with presence/absence.
- [ ] `./kestrel-self run hello.ks` produces the same stdout as `./kestrel run hello.ks`.
- [ ] `cd compiler && npm run build && npm test` passes.
- [ ] `./scripts/kestrel test` passes.

## Spec References

- `docs/specs/11-bootstrap.md` — bootstrap flow, cache paths, `./kestrel bootstrap` command
- `docs/specs/09-tools.md` — `kestrel` CLI commands and env vars

## Risks / Notes

- `./kestrel-self` must be in `.gitattributes` (or `chmod +x` via git) to preserve the
  executable bit in Git. Verify after adding the symlink.
- The `status` command currently lives inside the self-hosted `cli.ks`. Since `./kestrel
  status` will run through the TS path after S17-46, `cmdStatus` must read both cache
  directories from env vars rather than relying on self-hosted compiler state.
