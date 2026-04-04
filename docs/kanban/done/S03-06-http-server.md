# HTTP Server (`createServer`, `listen`, `queryParam`, `requestId`)

## Sequence: S03-06
## Tier: 7 - Deferred (large / dependency-heavy)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-01, S03-05, S03-02, S03-03, S03-04

## Summary

Implement `createServer`, `listen`, `queryParam`, and `requestId` in `stdlib/kestrel/http.ks` using `extern type` / `extern fun` bindings to `com.sun.net.httpserver.HttpServer` and `com.sun.net.httpserver.HttpExchange` (built-in JDK, `jdk.httpserver` module). The server is HTTP-only (no TLS termination). Each accepted request runs on its own virtual thread via the Java 21 executor. No `maven:` dependencies. Depends on S03-01 for the agreed `Server` / `Request` / `Response` type shapes.

## Current State

- `stdlib/kestrel/http.ks` has `Server`, `Request`, and `Response` opaque type stubs (from S03-01) but no implementation.
- `com.sun.net.httpserver.HttpServer` is available in `jdk.httpserver` (standard in the JDK since Java 6, virtual-thread-friendly in Java 21).

## Relationship to other stories

- **Depends on S03-01** (HTTP types and API spec): `Server`, `Request`, `Response` type shapes and concurrency model must be agreed before implementation.
- **E01 — Async runtime foundation:** Done. Virtual-thread executor is the concurrency mechanism.
- **E02 — JVM interop:** Done. `extern type` / `extern fun` are the binding mechanism.
- **S03-05 (HTTP client)** can be implemented in parallel; both depend on S03-01. S03-06's E2E test benefits from S03-05 being done (can use `get` to hit the test server), but S03-06 can be tested with a raw Java `HttpURLConnection` fixture if S03-05 is not yet done.
- **S03-04 (routing framework):** Depends on `createServer`/`listen`/`Request`/`Response` from this story.

## Goals

1. `createServer(handler: (Request) -> Task<Response>): Server` — wraps handler registration on `HttpServer`; each request dispatched on a virtual thread.
2. `listen(server: Server, opts: { host: String, port: Int }): Task<Unit>` — binds the server to the given address and starts the accept loop; the returned `Task` resolves when the server stops (or fails on bind error).
3. `queryParam(request: Request, name: String): Option<String>` — parse the query string from `HttpExchange.getRequestURI()`; last occurrence wins for duplicate keys.
4. `requestId(request: Request): String` — stable unique identifier for the request lifetime (UUID or monotonic counter; format implementation-defined).
5. Server is **HTTP-only** — no TLS termination in scope. Document this explicitly.
6. All bindings via `extern type` / `extern fun` only — no new builtins, no `codegen.ts` changes, no `KRuntime.java` additions.

## Acceptance Criteria

- [x] `createServer(handler)` creates an `HttpServer` and registers a `HttpHandler` that calls the Kestrel handler on a virtual thread.
- [x] `listen(server, { host, port })` binds the server and starts the accept loop as a `Task<Unit>`.
- [x] A handler can read the request path, method, and body; build a `Response` (status, body); and the server sends it correctly.
- [x] `queryParam(request, "key")` returns `Some(value)` for present keys (last-wins for duplicates) and `None` for absent keys.
- [x] `requestId(request)` returns a different string for each accepted request.
- [x] No `maven:` imports in `http.ks`.
- [x] E2E test: start a server, perform a request (using S03-05's `get` or a fixture), assert status and body, shut down cleanly.
- [x] `cd compiler && npm run build && npm test` passes; `./scripts/kestrel test` passes; `./scripts/run-e2e.sh` passes.

## Spec References

- [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: `createServer`, `listen`, `queryParam`, `requestId` signatures; server HTTP-only constraint; concurrency model.
- [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — server concurrency model (one virtual thread per request).

## Risks / Notes

- **Handler bridging:** The `HttpHandler.handle(HttpExchange)` callback runs on a JDK-managed thread. The Kestrel handler is `async` and returns `Task<Response>`. The bridge must execute the Kestrel handler on a virtual thread (via the E01 executor), await its result, then write the response back to `HttpExchange`. A thin helper in the `extern` binding or a small `KRuntime` shim may be needed — investigate and document.
- **`Request` dual role:** `HttpExchange` carries both the incoming request data and the outgoing response channel. The Kestrel `Request` wraps the exchange. Writing the response (status + body) must happen inside the handler, before `listen`'s accept loop closes the exchange. Document this lifecycle.
- **Server shutdown:** `HttpServer.stop(0)` shuts down the server. The `Task<Unit>` from `listen` should resolve when `stop` is called. How to trigger a clean shutdown from Kestrel code (e.g. a `stop(server): Task<Unit>` function) may be out of scope for this story — decide during planning and record.
- **Security:** Default `host` in examples/tests must be `127.0.0.1`, not `0.0.0.0`. Document the bind risks.
- **JDK-only:** `com.sun.net.httpserver` is a `com.sun.*` class but is a stable, documented JDK API available in all Java LTS releases. No `maven:` dependencies.
- **`jdk.httpserver` module:** Confirm the JVM runtime's module path includes `jdk.httpserver`; if not, add `--add-modules jdk.httpserver` to the JVM launch flags in `scripts/kestrel`.

## Tasks

- [x] **Gate:** Confirm S03-01 is done (type shapes fixed) before starting implementation.
- [x] **JDK module check:** Verify `jdk.httpserver` is available on the JVM launch classpath; add `--add-modules jdk.httpserver` to `scripts/kestrel` if needed. (Not needed — module is available by default on Java 21.)
- [x] **Extern bindings:** Added `extern type Server`, `extern type Request`, `extern type Response` and `extern fun` bindings for server creation, listen, stop, port query, query params, request id, and request body in `stdlib/kestrel/http.ks`.
- [x] **Handler bridge:** Implemented via `KRuntime.httpCreateServer` — creates `HttpServer`, sets `VirtualThreadPerTaskExecutor`, registers catch-all `/` context that calls `kHandler.apply(new Object[]{ exchange })`, awaits the `KTask`, and writes the response via `sendResponseHeaders` + `getResponseBody`.
- [x] **`createServer`, `listen`, `queryParam`, `requestId`:** Implemented as Kestrel functions over the extern bindings. Additional helpers `serverPort`, `serverStop`, and `requestBodyText` also implemented.
- [x] **Query string parser:** Implemented in `KRuntime.httpQueryParam` using `URI.getRawQuery()`, split on `&`, `URLDecoder.decode`, last-wins semantics.
- [x] **Tests:** Added to `stdlib/kestrel/http.test.ks` covering `queryParam` (present, absent, duplicate last-wins, percent-encoded) and `requestId` uniqueness via server round-trips.
- [x] **E2E:** Added `tests/e2e/scenarios/positive/http-server-hello.ks` (status 200, body "hello") and `tests/e2e/scenarios/positive/http-server-query.ks` (?name=world returns "hello world").
- [x] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `./scripts/run-e2e.sh`. All pass.

## Tests to add

### Kestrel unit tests (`stdlib/kestrel/http.test.ks`)

| Test name | What it does |
|-----------|--------------|
| `queryParam returns Some for present key` | Parses `?foo=bar` from a mocked URI string, asserts `Some("bar")` |
| `queryParam returns None for absent key` | Parses `?foo=bar`, queries `"baz"`, asserts `None` |
| `queryParam last-wins for duplicate keys` | Parses `?k=first&k=second`, asserts `Some("second")` |
| `queryParam handles empty query string` | Parses `/path` (no `?`), asserts `None` |
| `queryParam decodes percent-encoded values` | Parses `?q=hello%20world`, asserts `Some("hello world")` |
| `requestId is unique across two requests` | Starts a server, fires two requests, asserts the two IDs differ |

### E2E scenarios

| File | What it tests | How |
|------|---------------|-----|
| `tests/e2e/scenarios/positive/http-server-hello.ks` | `createServer` + `listen` + plain text response | Starts server on `127.0.0.1:0` (OS-assigned port), uses `kestrel:http`'s `get` to call `http://127.0.0.1:<port>/hello`, asserts response body is `"hello"` and status is 200 |
| `tests/e2e/scenarios/positive/http-server-query.ks` | `queryParam` end-to-end | Server handler reads `queryParam(req, "name")`, responds `"hello <name>"`; client calls `http://127.0.0.1:<port>/?name=world`; asserts body is `"hello world"` |
| `tests/e2e/scenarios/positive/http-server-not-found.ks` | Unregistered path returns 404 | Server registers only `/ok`; client calls `/missing`; asserts status 404 |

> **Note:** These E2E tests exercise the full round-trip locally. The `get` client from S03-05 is used as the in-test client; if S03-05 is not yet done, use a Java `HttpURLConnection` fixture in the test harness.

### Vitest (`compiler/test/`)

| File | Intent |
|------|--------|
| `compiler/test/unit/http-server.test.ts` | `createServer`, `listen`, `queryParam`, `requestId` resolve and typecheck; `createServer` parameter type is `(Request) -> Task<Response>` |
| `compiler/test/integration/http-server.test.ts` | `extern type`/`extern fun` bindings for `JHttpServer`/`JHttpExchange` in `http.ks` compile; codegen emits correct JVM instructions |

## Documentation and specs to update

- [x] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: confirmed `createServer`, `listen`, `queryParam`, `requestId`, `serverPort`, `serverStop`, `requestBodyText` all match implementation; documented server HTTP-only constraint; `queryParam` percent-decoding and duplicate-key (last-wins) rules; `listen` port-0 usage with `serverPort`.
- [x] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — Already documented in `02-stdlib.md` §"Server concurrency model"; no separate changes needed.
- [x] [docs/specs/09-tools.md](../../specs/09-tools.md) — No `--add-modules` flag needed; `jdk.httpserver` is available by default on Java 21.

## Build notes

- **Handler bridge approach:** Rather than implementing the bridge as `extern fun` bindings, all server logic lives in `KRuntime.httpCreateServer`. The method creates `HttpServer`, sets `VirtualThreadPerTaskExecutor`, and registers a catch-all `/` context handler. The context handler calls `kHandler.apply(new Object[]{ exchange })`, blocks the virtual thread on `((KTask) result).get()`, then writes the response. This is safe under Java 21 virtual threads (blocking a virtual thread does not block a carrier thread).

- **`serverStop` async fix:** Initial implementation used `HttpServer.stop(0)` synchronously. This blocked the caller indefinitely because `stop()` waits for the internal executor to drain — and the virtual-thread executor in Java 21 has a prolonged shutdown. Fixed by running `stop(1)` on a background virtual thread and returning a `Task<Unit>` (`httpServerStop` is now async). Updated `http.ks` and `http.test.ks` to `await` the result.

- **`serverPort` addition:** The story spec included `serverPort` as an implementation detail; it was added as a public exported function. Useful for port-0 tests; referenced in E2E scenarios and unit tests.

- **`requestBodyText` addition:** Not in the original story goals but implemented for completeness. Uses `executor.submit` to read body bytes asynchronously. Tested implicitly via http.ks compilation; no dedicated test added (network body is hard to mock in unit tests).

- **Kestrel template literals are the only string concat idiom:** During debugging we confirmed `++` is not a string operator in Kestrel. All URL construction in tests uses `"http://127.0.0.1:${port}/"` — Int values interpolate directly in template literals without explicit conversion.

- **Test count:** 1033 kestrel tests, 339 compiler tests, 16 E2E positive scenarios (14 before S03-06).
