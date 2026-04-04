# HTTP GET Client (`get`, `bodyText`)

## Sequence: S03-05
## Tier: 7 - Deferred (large / dependency-heavy)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-01, S03-06, S03-02, S03-03

## Summary

Implement `get(url)` and `bodyText(response)` in `stdlib/kestrel/http.ks` using `extern type` / `extern fun` bindings to `java.net.http.HttpClient` and related JDK 11+ classes. Both `http://` and `https://` are supported via the JDK's built-in TLS stack (system trust store). No `maven:` dependencies. Depends on S03-01 for the agreed `Response` type shape.

## Current State

- `stdlib/kestrel/http.ks` has a `Response` opaque type stub (from S03-01) but no implementation.
- `java.net.http.HttpClient` is available in Java 11+ (Java 21 is the target) and supports async `sendAsync` returning `CompletableFuture` — bridgeable to `Task` via E01's virtual-thread executor.

## Relationship to other stories

- **Depends on S03-01** (HTTP types and API spec): `Response` type shape must be decided before this story can bind to it.
- **E01 — Async runtime foundation:** Done. Virtual-thread executor bridges `CompletableFuture` → `Task`.
- **E02 — JVM interop:** Done. `extern type` / `extern fun` are the binding mechanism.
- **S03-06 (HTTP server)** can be implemented in parallel; both depend on S03-01.
- **S03-03 (REST client methods/headers):** Extends the client surface built here.

## Goals

1. `get(url): Task<Response>` — HTTP GET over `http://` and `https://` via `java.net.http.HttpClient.sendAsync`.
2. `bodyText(response: Response): Task<String>` — extract the body as UTF-8 text from the response.
3. TLS: system trust store, SNI enabled, TLS 1.2 minimum — no extra configuration needed from the caller.
4. Network errors and non-2xx responses both surfaced through `Task` failure semantics (as per E01 model); document the distinction (non-2xx is a successful `Task` with a status code, not a failure).
5. All bindings via `extern type` / `extern fun` only — no new builtins, no `codegen.ts` changes, no `KRuntime.java` additions.

## Acceptance Criteria

- [ ] `get(url: String): Task<Response>` calls `HttpClient.newHttpClient().sendAsync(...)` via `extern fun` and returns a `Task<Response>` consistent with the spec.
- [ ] Both `http://` and `https://` URLs work; other schemes produce a documented error.
- [ ] `bodyText(response: Response): Task<String>` returns the response body as UTF-8 text.
- [ ] Non-2xx responses are accessible (status code readable from `Response`) — they are not `Task` failures.
- [ ] Network/TLS errors surface as `Task` failures using E01's error model.
- [ ] No `maven:` imports in `http.ks`.
- [ ] E2E test: `get("http://...")` against a locally started server (can use S03-06's server once landed; alternatively a minimal Java `HttpServer` fixture in the test harness).
- [ ] HTTPS test: `get("https://...")` against a localhost TLS fixture or documented `SKIP_HTTPS_E2E` skip with CI policy.
- [ ] `cd compiler && npm run build && npm test` passes; `./scripts/kestrel test` passes; `./scripts/run-e2e.sh` passes.

## Spec References

- [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: `get`, `bodyText` signatures; TLS defaults; error semantics.

## Risks / Notes

- **`CompletableFuture` bridging:** `HttpClient.sendAsync` returns `CompletableFuture<HttpResponse<T>>`. The bridge to `Task` must use the E01 virtual-thread executor, not a new thread pool — investigate whether `extern fun` can call `sendAsync(...).get()` on a virtual thread and have E01's scheduler handle it correctly, or whether a thin `KRuntime` helper is needed. Document the outcome.
- **Body buffering:** `HttpClient` with `BodyHandlers.ofString()` buffers the entire response body in memory — acceptable for v1; document as a limitation.
- **JDK-only:** No `maven:` dependencies. `java.net.http` is available in Java 11+; no additional JDK modules required beyond the standard module path.
- **HTTPS in CI:** Prefer a fixed localhost TLS test server with a self-signed cert committed under `tests/`. If too brittle initially, record a time-boxed follow-up — do not ship `https` without tests.

## Tasks

- [ ] **Gate:** Confirm S03-01 is done (type shapes fixed) before starting implementation.
- [ ] **Extern bindings:** Add `extern type JHttpClient`, `extern type JHttpRequest`, `extern type JHttpResponse`, and `extern fun` bindings for `newHttpClient`, `newRequestBuilder`, `uri`, `build`, `sendAsync`, `statusCode`, `body` to `stdlib/kestrel/http.ks`.
- [ ] **Bridge:** Implement the `CompletableFuture` → `Task` bridge — investigate using a virtual-thread blocking call (`cf.get()` from a virtual thread) vs a callback-based approach. Document the chosen approach.
- [ ] **`get` and `bodyText`:** Implement as Kestrel functions over the extern bindings.
- [ ] **Error handling:** Map `IOException` / `HttpConnectTimeoutException` to `Task` failure; document that non-2xx is a successful task.
- [ ] **Tests:** Add `stdlib/kestrel/http.test.ks` covering status code access and body extraction.
- [ ] **E2E:** Add positive scenario(s) for HTTP and HTTPS `get`.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `./scripts/run-e2e.sh`.

## Tests to add

### Kestrel unit tests (`stdlib/kestrel/http.test.ks`)

| Test name | What it does |
|-----------|--------------|
| `get returns 200 status for http://httpbin.org/status/200` | Calls `get("http://httpbin.org/status/200")`, asserts status code is 200 |
| `get returns 404 status for http://httpbin.org/status/404` | Calls `get("http://httpbin.org/status/404")`, asserts status code is 404 — non-2xx is **not** a Task failure |
| `bodyText returns JSON body from http://httpbin.org/json` | Calls `get("http://httpbin.org/json")` then `bodyText`, asserts body contains `"slideshow"` |
| `get returns 200 for https://httpbin.org/get` | Same over HTTPS — verifies TLS stack (system trust store, SNI) |
| `get over HTTPS returns response headers` | Calls `get("https://httpbin.org/get")`, reads status code, asserts ≥ 0 |
| `get fails for unsupported scheme` | Calls `get("ftp://example.com")`, asserts Task failure |

### E2E scenarios

| File | Endpoint | Assertion |
|------|----------|-----------|
| `tests/e2e/scenarios/positive/http-get-plain.ks` | `http://httpbin.org/status/200` | Output contains status code `200` |
| `tests/e2e/scenarios/positive/http-get-body.ks` | `http://httpbin.org/json` | Output contains `"slideshow"` (substring match) |
| `tests/e2e/scenarios/positive/https-get.ks` | `https://httpbin.org/get` | Output contains `"url"` (httpbin echoes the URL in JSON) |

### Vitest (`compiler/test/`)

| File | Intent |
|------|--------|
| `compiler/test/unit/http-get.test.ts` | `get` and `bodyText` resolve and typecheck; return type is `Task<Response>` / `Task<String>` |
| `compiler/test/integration/http-get.test.ts` | `extern type`/`extern fun` bindings in `http.ks` for `JHttpClient`/`JHttpResponse` compile and codegen emits `INVOKEVIRTUAL`/`INVOKESTATIC` (no `__` dispatch) |

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: confirm `get(url: String): Task<Response>` and `bodyText(response: Response): Task<String>` match implementation; document: http + https supported; other schemes produce `Task` failure; non-2xx is a successful `Task`; TLS defaults (system trust store, SNI on, TLS 1.2 min); body buffered in memory (size limit implementation-defined).
- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — Document `Response` fields accessible after `get`: status code accessor; body via `bodyText`.
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — Note that `get` bridges `CompletableFuture` → `Task` via the virtual-thread executor; document the chosen approach (blocking `cf.get()` on a virtual thread vs callback).
