# Stdlib Sub-Path Resolver

## Sequence: S04-02
## Tier: 4 — Near-term (small, unblocks E08)

## Epic

- Epic: [E04 Module Resolution and Reproducibility](../epics/unplanned/E04-module-resolution-and-reproducibility.md)
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

- [ ] `stdlibSpecToPath` in `resolve.ts` is replaced: instead of checking `STDLIB_NAMES`, it maps any `kestrel:X` or `kestrel:X/Y/...` specifier to `kestrel/X.ks` or `kestrel/X/Y/....ks` and returns that path regardless of whether the file exists.
- [ ] `resolveSpecifier` performs the `existsSync` check and returns `{ ok: false, error: "unknown stdlib module 'kestrel:X'; expected file at <path>" }` if the mapped file does not exist.
- [ ] Module name segments are validated: each segment between `:` and `/` must match `[a-zA-Z0-9_-]+`; path traversal (`..`) is rejected as a compile error.
- [ ] All existing `compiler/test/unit/resolve.test.ts` tests continue to pass.
- [ ] The existing stdlib modules (kestrel:string, kestrel:list, etc.) continue to resolve correctly.
- [ ] `kestrel:nonexistent` still produces `ok: false` (file does not exist).
- [ ] A specifier `kestrel:data/list` resolves to `<stdlibDir>/kestrel/data/list.ks` (file existence check; no hardcoded list needed).
- [ ] Spec section 07-modules §4.2 is updated to reflect the file-existence resolution rule for `kestrel:` sub-paths.

## Spec References

- 07-modules §4.2 (Stdlib specifier resolution — "reserved" sub-path note)
