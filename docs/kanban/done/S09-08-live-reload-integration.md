# Live reload integration for `kestrel:tools/doc`

## Sequence: S09-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/done/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-06, S09-07

## Summary

Extends the running `kestrel:tools/doc` server (from S09-07) with live-reload behaviour:
when a watched `.ks` file is modified, the affected module's `DocModule` is re-extracted and
the search index is rebuilt within 2 seconds; the browser page reflects the change on its
next request. Optionally, a Server-Sent Events (SSE) endpoint notifies the browser to refresh
automatically.

This story depends on the file-watching primitive (S09-06) and the running server (S09-07).
It is the final story in epic E09.

## Current State

- `kestrel:io/fs` exports `Watcher`, `watchDir`, `watcherNext`, `watcherClose` since S09-06;
  `Watcher` type was made `export extern` as part of this story so it can be named in
  module-level function signatures.
- `kestrel:tools/doc` (S09-07) serves a static in-memory `DocState` built at startup.
- `kestrel:io/http` does not have an SSE primitive; a polling endpoint is used instead.
- There is no `/api/reload-token` endpoint in the server from S09-07.

## Relationship to other stories

- **Depends on:** S09-06 (file watching), S09-07 (doc server).
- **Blocks:** nothing — this is the last story in E09.
- This story completes the final epic completion criterion:
  "Modifying a `.ks` source file causes the affected module to be re-indexed within 2 seconds."

## Goals

1. Introduce `LiveState` (a record with `mut` fields) to hold the current `DocState` and
   a monotonically increasing `reloadGen` counter.
2. Update `dispatch` to read from `LiveState` and add `GET /api/reload-token` route.
3. Add a top-level `async fun watcherLoop` that:
   - Calls `Fs.watcherNext(watcher)` in a tail-recursive loop.
   - On each batch of changed `.ks` paths, re-extracts only the affected modules and rebuilds
     the index (updating `live.curState` and incrementing `live.reloadGen`).
4. Add `startWatcher` helper that sets up a watcher for a directory and fires the loop in
   background, logging a warning and continuing on failure.
5. Update `handler` to: create `LiveState`, start watchers after `Http.listen`, then park.
6. Update `render.staticJs()` to append a polling IIFE that calls `/api/reload-token` every
   second and calls `location.reload()` when the token changes.
7. Update `docs/specs/09-tools.md` `kestrel doc` section to document live reload.

## Acceptance Criteria

- Modifying any `.ks` file under the watched roots causes its `DocModule` to be re-extracted
  and the `DocIndex` to be rebuilt within 2 seconds on a developer laptop.
- `GET /api/reload-token` returns a different integer after a file change compared to before.
- The browser page automatically reloads within 2 seconds of a `.ks` file change when the
  doc browser tab is open.
- The server continues serving all routes normally while the watcher loop is running.
- If `watchDir` fails, the server logs a warning and continues serving the stale index.
- All Kestrel tests pass (`./kestrel test`).
- All compiler tests pass (`cd compiler && npm test`).

## Spec References

- `kestrel:io/fs` — `Watcher`, `watchDir`, `watcherNext` (S09-06).
- `kestrel:tools/doc` — the server module extended by this story (S09-07).
- `docs/specs/09-tools.md` — update the `kestrel doc` section to document live-reload.

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/tools/doc.ks` | Add `LiveState`, update `dispatch`, add `watcherLoop`/`reloadChanged`/`startWatcher`, update `handler` |
| `stdlib/kestrel/dev/doc/render.ks` | Append live-reload polling snippet to `staticJs()` |
| `stdlib/kestrel/io/fs.ks` | Export `Watcher` type (needed for function parameter annotations) |
| `docs/specs/09-tools.md` | Document `/api/reload-token` and live-reload behaviour |

## Tasks

- [x] Export `Watcher` type in `stdlib/kestrel/io/fs.ks`
- [x] Add live-reload polling snippet to `render.staticJs()` in `stdlib/kestrel/dev/doc/render.ks`
- [x] Update `stdlib/kestrel/tools/doc.ks`:
  - [x] Add `LiveState` record type with `curState: mut DocState` and `reloadGen: mut Int`
  - [x] Import `Watcher` from `kestrel:io/fs`
  - [x] Update `dispatch` from `DocState` to `LiveState`; add `/api/reload-token` route
  - [x] Add `reloadChanged` top-level async fun
  - [x] Add `watcherLoop` top-level async fun (tail-recursive)
  - [x] Add `startWatcher` helper async fun (fire-and-forget)
  - [x] Update `handler` to create `LiveState`, build router with `live`, start watchers
- [x] Update `docs/specs/09-tools.md` with live-reload section
- [x] Run `./kestrel test`
- [x] Run `cd compiler && npm test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Manual / smoke | `./kestrel doc --port 7070` + modify a file | Reload token changes; browser reloads |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` — add `/api/reload-token` route and live-reload description

## Build notes

**2026-03-08**

- `Watcher` was declared as `extern type` (non-exported) in `fs.ks`. Module-level function signatures require named types, so changed to `export extern type Watcher`. This is a clean addition — callers already used the type through inference.

- `mut` field syntax in `type` declarations uses `fieldName: mut Type` (not `mut fieldName: Type`). The corresponding record literal creation uses `{ mut fieldName = value }`. Used this pattern for `LiveState.curState` and `LiveState.reloadGen`.

- Recursive `async fun watcherLoop` required the intermediate type annotation trick (also used in `fs.ks listDirAllLoop`): `val next: Task<Unit> = watcherLoop(...); await next`. Direct `await watcherLoop(...)` caused the type checker to produce an unresolved type variable `α174`.

- Fire-and-forget for `startWatcher` and the inner watcher loop uses `val _name = asyncFun(...)` (no `await`). The task starts running immediately in the JVM executor while the parent task continues.

- Smoke test confirmed: touching `stdlib/kestrel/data/list.ks` while server is running causes `/api/reload-token` to change from `0` to `1` within seconds. All 1633 Kestrel tests and 433 compiler tests pass.

## Sequence: S09-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/done/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-06, S09-07

## Summary

Extends the running `kestrel:tools/doc` server (from S09-07) with live-reload behaviour:
when a watched `.ks` file is modified, the affected module's `DocModule` is re-extracted and
the search index is rebuilt within 2 seconds; the browser page reflects the change on its
next request. Optionally, a Server-Sent Events (SSE) endpoint notifies the browser to refresh
automatically.

This story depends on the file-watching primitive (S09-06) and the running server (S09-07).
It is the final story in epic E09.

## Current State

- `kestrel:io/fs` will export `Watcher`, `watchDir`, `watcherNext`, `watcherClose` after S09-06.
- `kestrel:tools/doc` (S09-07) will expose a static in-memory `DocIndex` built at startup.
  The index is not currently updated on file change.
- `kestrel:io/http` does not have an SSE primitive, but a polling endpoint can be added
  with standard HTTP primitives.
- There is no `GET /api/reload` or SSE endpoint in the server from S09-07.

## Relationship to other stories

- **Depends on:** S09-06 (file watching), S09-07 (doc server).
- **Blocks:** nothing — this is the last story in E09.
- This story completes the final epic completion criterion:
  "Modifying a `.ks` source file causes the affected module to be re-indexed within 2 seconds."

## Goals

1. Start a background watcher loop inside `kestrel:tools/doc` that:
   - Calls `watchDir` on each watched root (stdlib root + project root) with a 500 ms debounce.
   - On receiving a list of changed paths, re-extracts only the affected `DocModule` values.
   - Atomically replaces the relevant entries in the in-memory module list and rebuilds the
     `DocIndex`.
2. Add a `GET /api/reload-token` endpoint that returns a monotonically increasing integer
   (the current reload generation counter) as plain text. The browser JavaScript polls this
   endpoint every second; when the counter changes, it calls `window.location.reload()`.
3. Update `render.staticJs()` (from S09-04) to include the polling snippet (or add the
   snippet via a template parameter in `renderModule` / `renderModuleList`).
4. Verify the round-trip: modify a stdlib `.ks` file while the server is running; within 2
   seconds, a new request to the same module page reflects the change.

## Acceptance Criteria

- Modifying any `.ks` file under the watched roots causes its `DocModule` to be re-extracted
  and the `DocIndex` to be rebuilt within 2 seconds on a developer laptop.
- `GET /api/reload-token` returns a different integer after a file change compared to before.
- The browser page automatically reloads within 2 seconds of a `.ks` file change when the
  doc browser tab is open.
- The server continues serving all routes normally while the watcher loop is running
  (no deadlocks, no dropped requests during re-indexing).
- If `watchDir` fails (e.g. the directory disappears), the server logs a warning and continues
  serving the stale index rather than crashing.
- All Kestrel tests pass (`./kestrel test`).
- All compiler tests pass (`cd compiler && npm test`).
- All E09 epic completion criteria are satisfied.

## Spec References

- `kestrel:io/fs` — `Watcher`, `watchDir`, `watcherNext` (S09-06).
- `kestrel:tools/doc` — the server module extended by this story (S09-07).
- `docs/specs/09-tools.md` — update the `kestrel doc` section to document live-reload
  behaviour and the `/api/reload-token` endpoint.

## Risks / Notes

- Concurrency: the watcher loop runs as a background async task; the HTTP handler tasks
  read the shared module list and index. Use an `mut` top-level variable holding the
  current `DocIndex`, updated atomically (assignment via `:=`) so readers always see a
  complete and consistent index. Kestrel's async model ensures that virtual-thread
  scheduling constraints are respected.
- Rebuilding the full index (calling `index.build`) after every file change is safe for
  V1 because the index build is fast (linear scan). Incremental updates (removing old entries
  and inserting new ones) would require a more complex index API and are deferred to V2.
- macOS `WatchService` polling interval (~1 s) + 500 ms debounce + re-extraction time leaves
  ~0.5 s margin for the 2-second requirement. Testing on macOS should verify this.
- SSE (Server-Sent Events) would give sub-second push notification without polling but requires
  a long-lived HTTP connection and more complex KRuntime support. Polling at 1 Hz is simpler
  and meets the 2-second requirement.
