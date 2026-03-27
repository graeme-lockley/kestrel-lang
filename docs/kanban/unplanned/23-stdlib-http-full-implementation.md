# Stdlib kestrel:http Full Implementation

## Sequence: 23
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 155

## Summary

The `kestrel:http` module currently only exports `nowMs()`. The spec (02) requires `createServer`, `listen`, `get`, `bodyText`, `queryParam`, `requestId`, and `nowMs`. Most of these require async I/O and the event loop (sequence **18**).

## Current State

- `stdlib/kestrel/http.ks`: exports only `nowMs()` wrapping `__now_ms()`.
- VM `primitives.zig`: implements `nowMs` as a simple timestamp.
- No HTTP server, client, or request/response types implemented.
- Prior work in `docs/kanban/done/stdlib-json-fs-http.md` may note partial HTTP deferral.

## Dependencies

- Sequence **18** (Async/Await event loop) is effectively a prerequisite for `listen`, `get`, `bodyText`.

## Acceptance Criteria

- [ ] `createServer(handler)`: Create an HTTP server that calls `handler(request)` for each request.
- [ ] `listen(server, { host, port })`: Bind the server and start listening (async).
- [ ] `get(url)`: HTTP GET request returning `Task<Response>`.
- [ ] `bodyText(request)`: Extract request body as string.
- [ ] `queryParam(request, name)`: Get a query parameter by name.
- [ ] `requestId(request)`: Get request ID.
- [ ] Define `Request`, `Response`, `Server` types.
- [ ] VM primitives for TCP/HTTP operations.
- [ ] E2E test: start server, make a request, verify response.

## Spec References

- 02-stdlib (kestrel:http: full function table)
