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
