# Stdlib Sub-Path Resolver

## Sequence: S04-02
## Tier: 4 — Near-term (small, unblocks E08)

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/done/E04-module-resolution-and-reproducibility.md)
- Companion stories: S04-01 (URL Import Resolution)

## Summary

`compiler/src/resolve.ts` resolves `kestrel:X` specifiers by checking against a hardcoded `STDLIB_NAMES` allowlist. This means adding any new stdlib module (e.g., the `kestrel:data/list`, `kestrel:io/fs` sub-namespaces planned for E08) requires a code change to the compiler. Replace the allowlist with a file-existence check: any `kestrel:X` or `kestrel:X/Y` specifier is resolved to `<stdlibDir>/kestrel/X.ks` or `<stdlibDir>/kestrel/X/Y.ks`; if the file does not exist the compiler reports an unknown-module error as before. The spec (07 §4.2) already allows this: "any other specifier that starts with `kestrel:` … may be reserved: the implementation may reject it or treat it as a future stdlib module."

## Current State

```typescript
// compiler/src/resolve.ts
const STDLIB_NAMES = [
  'kestrel:string', 'kestrel:char', 'kestrel:stack', 'kestrel:http', ...
] as const;

function stdlibSpecToPath(spec: string): string | null {
  if (!STDLIB_NAMES.includes(spec as ...)) return null;
  const [, mod] = spec.split(':');
  return `kestrel/${mod}.ks`;
}
```

Unknown `kestrel:X` specifiers fall through to the path resolver which also fails, yielding a confusing "Module not found: kestrel:X (resolved to ...)" message instead of "unknown stdlib module".

## Dependencies

- None. Fully independent; can land any time before E08.

## Risks / Notes

- **Diagnostic message quality:** The new behaviour must produce a clear error for truly unknown `kestrel:` specifiers, e.g. `unknown stdlib module 'kestrel:nonexistent'; expected a file at <stdlibDir>/kestrel/nonexistent.ks`. This is better than the current message which falls through to the path resolver error.
- **Sub-path separator:** `kestrel:data/list` maps to `kestrel/data/list.ks`. Slashes in the module name part must not be interpreted as path traversal (validate the module name part contains only `[a-zA-Z0-9_/-]` with no `..` segments).
- **Existing test coverage:** `compiler/test/unit/resolve.test.ts` has a test for `kestrel:nonexistent` that expects `ok: false`. This test must continue to pass; the error message content may change but `ok` must remain `false`.

## Acceptance Criteria

- [x] `stdlibSpecToPath` in `resolve.ts` is replaced: instead of checking `STDLIB_NAMES`, it maps any `kestrel:X` or `kestrel:X/Y/...` specifier to `kestrel/X.ks` or `kestrel/X/Y/....ks` and returns that path regardless of whether the file exists.
- [x] `resolveSpecifier` performs the `existsSync` check and returns `{ ok: false, error: "unknown stdlib module 'kestrel:X'; expected file at <path>" }` if the mapped file does not exist.
- [x] Module name segments are validated: each segment between `:` and `/` must match `[a-zA-Z0-9_-]+`; path traversal (`..`) is rejected as a compile error.
- [x] All existing `compiler/test/unit/resolve.test.ts` tests continue to pass.
- [x] The existing stdlib modules (kestrel:string, kestrel:list, etc.) continue to resolve correctly.
- [x] `kestrel:nonexistent` still produces `ok: false` (file does not exist).
- [x] A specifier `kestrel:data/list` resolves to `<stdlibDir>/kestrel/data/list.ks` (file existence check; no hardcoded list needed).
- [x] Spec section 07-modules §4.2 is updated to reflect the file-existence resolution rule for `kestrel:` sub-paths.

## Spec References

- 07-modules §4.2 (Stdlib specifier resolution — "reserved" sub-path note)

## Impact analysis

| Area | Change |
|------|--------|
| `compiler/src/resolve.ts` | Remove `STDLIB_NAMES` constant; replace `stdlibSpecToPath` with segment-validation + direct path mapping; update `resolveSpecifier` to use `existsSync` on the mapped path |
| `docs/specs/07-modules.md` | Update §4.2 stdlib specifier description to reflect file-existence rule and sub-path support |
| `compiler/test/unit/resolve.test.ts` | Existing tests sufficient; no new tests required |

**Note:** This work was absorbed into S04-01's `resolve.ts` rewrite. The `STDLIB_NAMES` allowlist was removed and the file-existence-based resolver implemented as part of that story. This story is being fast-tracked to done with only the spec update remaining.

## Tasks

- [x] Remove `STDLIB_NAMES` constant from `compiler/src/resolve.ts`
- [x] Replace `stdlibSpecToPath` with segment-validated file-existence mapping
- [x] Update `resolveSpecifier` to return `{ ok: false, error: "unknown stdlib module '...'; expected file at <path>" }` when mapped file does not exist
- [x] Update `docs/specs/07-modules.md` §4.2 stdlib specifier description

## Tests to add

- No new tests required: existing `resolve.test.ts` tests cover stdlib resolution (including `kestrel:nonexistent` → `ok: false`), and these all pass after the resolve.ts rewrite in S04-01.

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` §4.2 — stdlib specifier rule updated to file-existence approach

## Build notes

**2025-07-10** – Fast-tracked to done. Core implementation was completed as part of S04-01 since `resolve.ts` was being fully rewritten for URL import support. The `STDLIB_NAMES` allowlist was removed and the new file-existence-based `stdlibSpecToPath` implemented at that time. This story only required the spec update to `docs/specs/07-modules.md` §4.2, which was applied now.

- All `resolve.test.ts` tests continue to pass (including `kestrel:nonexistent` → `ok: false`).
- Sub-path specifiers like `kestrel:data/list` resolve to `<stdlibDir>/kestrel/data/list.ks` and produce a clear error if that file does not exist.
- 376 compiler tests pass, 1071 Kestrel tests pass.
