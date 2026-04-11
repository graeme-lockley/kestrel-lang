# Live reload integration for `kestrel:tools/doc`

## Sequence: S09-08
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
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
