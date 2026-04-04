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

- [ ] `createServer(handler)` creates an `HttpServer` and registers a `HttpHandler` that calls the Kestrel handler on a virtual thread.
- [ ] `listen(server, { host, port })` binds the server and starts the accept loop as a `Task<Unit>`.
- [ ] A handler can read the request path, method, and body; build a `Response` (status, body); and the server sends it correctly.
- [ ] `queryParam(request, "key")` returns `Some(value)` for present keys (last-wins for duplicates) and `None` for absent keys.
- [ ] `requestId(request)` returns a different string for each accepted request.
- [ ] No `maven:` imports in `http.ks`.
- [ ] E2E test: start a server, perform a request (using S03-05's `get` or a fixture), assert status and body, shut down cleanly.
- [ ] `cd compiler && npm run build && npm test` passes; `./scripts/kestrel test` passes; `./scripts/run-e2e.sh` passes.

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

- [ ] **Gate:** Confirm S03-01 is done (type shapes fixed) before starting implementation.
- [ ] **JDK module check:** Verify `jdk.httpserver` is available on the JVM launch classpath; add `--add-modules jdk.httpserver` to `scripts/kestrel` if needed.
- [ ] **Extern bindings:** Add `extern type JHttpServer`, `extern type JHttpExchange`, and `extern fun` bindings for `create`, `bind`, `start`, `stop`, `createContext`, `getRequestURI`, `getRequestMethod`, `getRequestBody`, `getResponseHeaders`, `sendResponseHeaders`, `getResponseBody` to `stdlib/kestrel/http.ks`.
- [ ] **Handler bridge:** Implement the `HttpHandler` → Kestrel async handler bridge — either via `extern fun` calling a helper, or a minimal `KRuntime` shim. Document the approach.
- [ ] **`createServer`, `listen`, `queryParam`, `requestId`:** Implement as Kestrel functions over the extern bindings.
- [ ] **Query string parser:** Implement `queryParam` as pure Kestrel string parsing over `getRequestURI().getQuery()` (via `extern fun`); last-wins for duplicate keys.
- [ ] **Tests:** Add to `stdlib/kestrel/http.test.ks` covering `queryParam` edge cases (missing key, duplicate key, empty query string) and `requestId` uniqueness.
- [ ] **E2E:** Add positive scenario: server on `127.0.0.1`, client `get` request, assert body and status.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `./scripts/run-e2e.sh`.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| **Kestrel unit** | `stdlib/kestrel/http.test.ks` | `queryParam` last-wins; missing key → `None`; `requestId` uniqueness |
| **E2E** | `tests/e2e/scenarios/positive/` | Server start → request → response; clean shutdown |
| **Vitest** | `compiler/test/unit/` | `createServer`/`listen`/`queryParam`/`requestId` typecheck correctly |

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — Confirm `createServer`, `listen`, `queryParam`, `requestId` sections match implementation.
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — Server concurrency model (virtual thread per request); handler lifecycle and exchange close semantics.
- [ ] [docs/specs/09-tools.md](../../specs/09-tools.md) — Document `--add-modules jdk.httpserver` JVM flag if added to `scripts/kestrel`.
