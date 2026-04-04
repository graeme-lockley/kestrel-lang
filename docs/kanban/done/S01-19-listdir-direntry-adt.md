# `listDir` Typed `DirEntry` ADT

## Sequence: S01-19
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E01 Async Runtime Foundation](../epics/unplanned/E01-async-runtime-foundation.md)

## Summary

`listDir` returns `List<String>` where each element is a raw `"<fullPath>\t<dir|file>"` string. This is a leaky abstraction: callers must split on a tab character and pattern-match the kind string manually. A typed `DirEntry` ADT (`File(String)` and `Dir(String)`) would be idiomatic Kestrel and eliminate the need for manual string parsing.

## Current State

```java
// KRuntime.java — listDirAsync
entries.add(entry.toString() + "\t" + (Files.isDirectory(entry) ? "dir" : "file"));
```

```kestrel
// fs.ks
export async fun listDir(path: String): Task<Result<List<String>, FsError>>
```

Callers receive strings like `"/tmp/foo\tfile"` and must parse them.

## Relationship to other stories

- Depends on S01-07 (async listDir cascade).
- Breaking API change: all callers of `listDir` must be updated.
- S01-18 (runProcess stdout capture) is a similarly-scoped breaking API change and can be done in the same release window.

## Goals

1. Define a `DirEntry` ADT in `stdlib/kestrel/fs.ks`:
   ```kestrel
   export type DirEntry = File(String) | Dir(String)
   ```
2. `KRuntime.listDirAsync` returns a `KList` of `KConstructor("File", path)` / `KConstructor("Dir", path)` values.
3. `listDir` in `fs.ks` updated to return `Task<Result<List<DirEntry>, FsError>>`.
4. All callers updated.
5. Conformance or unit test pattern-matches on `DirEntry`.

## Acceptance Criteria

- `match entry { File(p) => ..., Dir(p) => ... }` compiles and runs correctly on each `DirEntry`.
- No caller receives raw tab-embedded strings.
- Existing fs tests continue to pass with updated match expressions.
- `cd compiler && npm test` and `./scripts/kestrel test` pass.

## Spec References

- `docs/specs/02-stdlib.md` — update `listDir` return type; document `DirEntry`.

## Risks / Notes

- Callers that previously called `String.split` on tab-embedded strings will break; a mechanical find-and-replace should be sufficient since usage in the repo is small.
- Symlinks: `Files.isDirectory` follows symlinks; decide whether to add a `Symlink(String)` variant or follow the link (document the decision).
- Decision: symlinks are treated as `File(path)` (follows link, if it resolves to a dir it becomes `Dir`, otherwise `File`). No `Symlink` variant needed.
- Implementation approach: use a pure-Kestrel wrapper in `fs.ks` that converts raw tab-separated strings to `DirEntry` ADT values. No JVM or codegen changes needed.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/fs.ks` | Add `DirEntry` ADT type, `toDirEntry` helper, update `listDir` return type to `Task<Result<List<DirEntry>, FsError>>` |
| `stdlib/kestrel/fs.test.ks` | Update listDir test cases to use `File(p)` / `Dir(p)` patterns |
| `scripts/run_tests.ks` | Update `collectTests` to pattern-match `DirEntry` instead of splitting tab strings |
| `compiler/test/integration/runtime-stdlib.test.ts` | Update listDir test to use `DirEntry` patterns |
| `docs/specs/02-stdlib.md` | Add `DirEntry` type, update `listDir` signature |
| New conformance test | `tests/conformance/runtime/valid/listdir_direntry.ks` |

## Tasks

- [ ] `stdlib/kestrel/fs.ks`: add `import * as Lst from "kestrel:list"`, add `export type DirEntry = File(String) | Dir(String)`, add `fun toDirEntry(raw: String): DirEntry`, update `listDir` return type to `Task<Result<List<DirEntry>, FsError>>` using `Res.map(..., (entries) => Lst.map(entries, toDirEntry))`
- [ ] `stdlib/kestrel/fs.test.ks`: update listDir tests to use `DirEntry` — update `entryContains` to take `List<DirEntry>`, pattern-match `File(p)` / `Dir(p)` instead of string contains
- [ ] `scripts/run_tests.ks`: update `collectTests` signature to `List<DirEntry>`, update import from `kestrel:fs` to include `DirEntry, File, Dir`, replace tab-splitting logic with `File(p) => ...` / `Dir(p) => ...` match arms; update `listDirOrExit` return type to `Task<List<DirEntry>>`
- [ ] `compiler/test/integration/runtime-stdlib.test.ts`: update listDir integration test to use `File(p)` / `Dir(p)` patterns
- [ ] Add conformance test `tests/conformance/runtime/valid/listdir_direntry.ks`
- [ ] `docs/specs/02-stdlib.md`: add `DirEntry` type, update `listDir` signature
- [ ] `cd compiler && npm run build && npm test`
- [ ] `./scripts/kestrel test`
- [ ] `./scripts/run-e2e.sh`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Conformance runtime | `tests/conformance/runtime/valid/listdir_direntry.ks` | pattern-match `File(p)` / `Dir(p)` on entries |

## Documentation and specs to update

- [ ] `docs/specs/02-stdlib.md` — add `DirEntry` ADT, update `listDir` signature
