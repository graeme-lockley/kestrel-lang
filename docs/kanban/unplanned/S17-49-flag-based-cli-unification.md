# Future: flag-based CLI unification (`--compiler=ts|self`)

## Sequence: S17-49
## Tier: 9
## Former ID: (none)

## Epic

- Epic: [E17 True Self-Hosted Compilation](../epics/unplanned/E17-true-self-hosted-compilation.md)
- Companion stories: S17-45, S17-46, S17-47, S17-48, S17-50

## Summary

Once the self-hosted Kestrel compiler reaches feature parity (all E17 gap-closure stories
complete), unify `./kestrel` and `./kestrel-self` into a single entry point with a
`--compiler=ts|self` flag (default `self` once self-hosted is stable). Remove the separate
`scripts/kestrel-self` script. Remove the `KESTREL_SELF_CACHE` / `KESTREL_TS_CACHE` split and
return to a unified `KESTREL_JVM_CACHE` pointing at the active compiler's cache.

## Current State

Not started. `./kestrel` and `./kestrel-self` are deliberately separate scripts until the
self-hosted compiler reaches parity (by design from the S17-45..S17-50 pivot). This story is a
placeholder capturing the intended end state; it must not be built until S17-42 (final
no-Node validation) is complete.

## Relationship to other stories

- **Depends on**: S17-42 (no-Node validation), all E17 gap-closure stories
- **Blocks**: nothing (last story in E17)

## Goals

1. `./kestrel [--compiler=ts|self] <command>` selects which compiler path to use.
2. Default compiler after transition is `self` (or determined by `kestrel status`).
3. `scripts/kestrel-self` is removed; root `./kestrel-self` symlink is removed.
4. `KESTREL_JVM_CACHE` is restored as the single cache env var (pointing at the appropriate
   sub-directory based on `--compiler` flag, or a single unified cache once both compilers
   produce identical output).
5. `docs/specs/09-tools.md` and `docs/specs/11-bootstrap.md` updated to reflect unified CLI.

## Acceptance Criteria

- [ ] `./kestrel run hello.ks` uses the self-hosted compiler by default.
- [ ] `./kestrel --compiler=ts run hello.ks` uses the TS compiler.
- [ ] `scripts/kestrel-self` and `./kestrel-self` are removed.
- [ ] All existing tests pass under the unified entry point.
- [ ] Specs updated.

## Spec References

- `docs/specs/09-tools.md` — CLI commands and env vars
- `docs/specs/11-bootstrap.md` — compiler mode and provenance

## Risks / Notes

- This story is intentionally a **placeholder**. Do not build it until the self-hosted
  compiler is stable enough to be the default.
- The transition point is S17-42 (end-to-end validation without Node). Once S17-42 is green,
  this story can be planned and built.
- KESTREL_JVM_CACHE deprecation (from S17-45) expires with this story — the warning should
  be removed here.
