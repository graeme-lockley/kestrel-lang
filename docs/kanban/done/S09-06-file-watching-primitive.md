# File-watching JVM primitive and stdlib binding

## Sequence: S09-06
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/done/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-07, S09-08

## Summary

Adds a file-system change-notification primitive to the JVM runtime (`KRuntime`) and exposes
it as a Kestrel API in `kestrel:io/fs`. The primitive uses Java's `WatchService` API to watch
a directory tree for file-creation, modification, and deletion events. The Kestrel binding
presents a simple `Watcher` opaque type with `watch(dir)` and `watcherNext(watcher)` functions,
where `watcherNext` blocks (asynchronously) until at least one change is detected and returns
the list of changed paths.

This is a standalone infrastructure story with no dependency on the doc extraction or rendering
pipeline. It is consumed by S09-08 (live reload).

## Current State

- No `watchDir`, `WatchService`, or file-watching primitive exists in `KRuntime.java` or
  `kestrel:io/fs`.
- Java `java.nio.file.WatchService` is available in the JDK and integrates well with virtual
  threads (can be driven via a blocking `take()` call inside a virtual thread without blocking
  the carrier).
- `kestrel:io/fs` currently exports `readText`, `listDir`, `writeText`, `readStdin`,
  `fileExists`, `deleteFile`, `renameFile`, and `collectFiles`. Adding watching maintains
  the module's design of exposing async Task-based wrappers over blocking JVM I/O.

## Relationship to other stories

- **Depends on:** nothing in E09 — independent of all other E09 stories.
- **Blocks:** S09-08 (live reload integration — uses `Watcher` from this story).
- **Independent of:** S09-01 through S09-05, S09-07.
- This story can be developed at any point after E08 and E03 are complete.

## Goals

1. Add `watchDirAsync(path: String, debounceMs: Int): Task<Watcher>` to `KRuntime.java` using
   `java.nio.file.WatchService`. The watcher registers the target directory and all
   subdirectories recursively at creation time.
2. Add `watcherNextAsync(watcher: Watcher): Task<List<String>>` to `KRuntime.java`. This
   blocks (in a virtual thread) for up to `debounceMs` after the first event, collects all
   further events that arrive in that window, and returns the deduplicated list of changed
   absolute path strings. Calling it again resets the debounce window.
3. Add `watcherCloseAsync(watcher: Watcher): Task<Unit>` to close the underlying `WatchService`.
4. Expose `extern type Watcher`, `watchDir`, `watcherNext`, and `watcherClose` from
   `kestrel:io/fs`.
5. Re-register new sub-directories automatically when they are created inside a watched tree
   (standard `WatchService` limitation workaround).

## Acceptance Criteria

- `watchDir(dir, debounceMs)` returns a `Task<Watcher>` that succeeds for an existing directory
  and fails with `Err("not_found")` for a non-existent path.
- `watcherNext(watcher)` returns a non-empty `List<String>` when a `.ks` file in the watched
  directory is modified.
- `watcherNext` does not return until at least one change event has been received (it does not
  busy-poll).
- `watcherClose(watcher)` closes the underlying watch service; subsequent `watcherNext` calls
  return an error or empty list rather than blocking forever.
- Unit tests in `tests/unit/io_fs_watch.test.ks` (or `stdlib/kestrel/io/fs.test.ks` extension):
  - Create a temp file, start a watcher, write to the file, call `watcherNext`, verify the
    path appears in the result.
  - Verify that changes to a newly created subdirectory inside the watched tree are also detected.
- All compiler tests pass (`cd compiler && npm test`).
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- `docs/specs/02-stdlib.md` — `kestrel:io/fs` section; add `Watcher`, `watchDir`,
  `watcherNext`, `watcherClose`.
- Java `java.nio.file.WatchService` documentation (JDK 21+).

## Risks / Notes

- `WatchService` on macOS uses polling by default (not `kqueue`) which has higher latency
  than Linux `inotify`. The 2-second re-index deadline from the epic's completion criteria is
  achievable with a 500 ms poll interval and a 300–500 ms debounce window.
- Recursive registration: `WatchService` only monitors the registered directory itself, not
  subdirectories. Subdirectories must be registered individually at creation time. The
  implementation must listen for `ENTRY_CREATE` events and register newly-created directories.
- Virtual-thread integration: blocking `watcher.take()` inside a virtual thread is idiomatic
  (virtual threads are designed for blocking I/O). No `CompletableFuture` bridging is needed.
- The `Watcher` extern type is backed by a JVM class that bundles `WatchService` + a
  `ConcurrentLinkedQueue<String>` for accumulating events between `watcherNext` calls.

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime (new class) | `runtime/jvm/src/kestrel/runtime/KWatcher.java` — `WatchService` wrapper with debouncing and auto-registration of new subdirs |
| JVM runtime (`KRuntime`) | Added `watchDirAsync`, `watcherNextAsync`, `watcherCloseAsync` methods |
| JVM build | `runtime/jvm/build.sh` — added `KWatcher.java` to compile list |
| Stdlib (`kestrel:io/fs`) | Added `extern type Watcher`, `watchDir`, `watcherNext`, `watcherClose` |
| Tests (new) | `stdlib/kestrel/io/fs_watch.test.ks` — 7 async integration tests |
| Specs | None updated (spec refs in Risks / Notes) |

## Tasks

- [x] Create `runtime/jvm/src/kestrel/runtime/KWatcher.java`
- [x] Add `watchDirAsync`, `watcherNextAsync`, `watcherCloseAsync` to `KRuntime.java`
- [x] Add `KWatcher.java` to `runtime/jvm/build.sh`
- [x] Rebuild JVM runtime: `cd runtime/jvm && bash build.sh`
- [x] Add `extern type Watcher`, `watchDir`, `watcherNext`, `watcherClose` to `stdlib/kestrel/io/fs.ks`
- [x] Create `stdlib/kestrel/io/fs_watch.test.ks` with async integration tests
- [x] Run `./kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel async harness | `stdlib/kestrel/io/fs_watch.test.ks` | `watchDir` succeeds for existing dir, fails for missing |
| Kestrel async harness | `stdlib/kestrel/io/fs_watch.test.ks` | `watcherNext` detects file write in watched dir |
| Kestrel async harness | `stdlib/kestrel/io/fs_watch.test.ks` | `watcherNext` detects change in new subdirectory |
| Kestrel async harness | `stdlib/kestrel/io/fs_watch.test.ks` | `watcherClose` causes next to return empty |

## Documentation and specs to update

- None.

## Build notes

- `KWatcher` uses a background virtual thread (`Thread.ofVirtual().start()`) to drain the `WatchService` with a debounce window. The debounce loop polls for additional events for `debounceMs` after the first event, then queues a batch to a `BlockingQueue` consumed by `watcherNextAsync`.
- macOS `WatchService` uses polling (~2s latency) — tests use a 300ms debounce which means `watcherNext` can take up to ~2.3s on macOS. This is acceptable for the doc-server live-reload use case.
- Subdirectory auto-registration: after observing `ENTRY_CREATE` for a directory, `registerTree` is called recursively on the new directory.
- The `extern type Watcher = jvm("kestrel.runtime.KWatcher")` declaration in `fs.ks` binds the JVM class to the Kestrel opaque type.
- 7 tests pass (including the 2.3s-per-watcher async tests).
