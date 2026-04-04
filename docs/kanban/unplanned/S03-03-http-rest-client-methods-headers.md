# HTTP client: methods, headers, bodies, and REST-oriented API

## Sequence: S03-03
## Tier: 8 - Networking expansion (post-HTTP baseline)
## Former ID: (none)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-01, S03-05, S03-06, S03-02, S03-04

## Summary

Extend the standard library **beyond** the current **`kestrel:http`** contract in **02**, which today centres on a server-oriented API and a **`get(url)`** client. Add a **REST-capable client surface**: arbitrary **methods** (GET, POST, PUT, PATCH, DELETE, ...), **request headers**, **request body**, **response status**, and **response headers/body**, all integrated with the **`Task`** model once **59** is in effect. Implementations use **native** HTTP client stacks on the **JVM** (`java.net.http.HttpClient` or equivalent) with **documented** behaviour goals.

## Current State

- `docs/specs/02-stdlib.md` §`kestrel:http` lists `get`, `createServer`, `listen`, `bodyText`, `queryParam`, `requestId`, `nowMs` but **no** general request builder, POST/PUT, or response metadata beyond what `Response` will carry after **60**.
- Sequence **60** delivers the **baseline** `kestrel:http` table; **69** **extends** that contract without removing **60**'s acceptance targets.
- No spec today describes **header maps**, **status codes**, or **content-type** conventions for client calls.

## Relationship to other stories

- **E01 — Async runtime foundation:** **Done.** Real `Task` completion on network I/O is available.
- **E02 — JVM interop (`extern` bindings):** **Done.** `extern type` / `extern fun` / `maven:` are the implementation mechanism. The REST client surface in S03-03 must be implemented via `extern fun` bindings to `java.net.http.HttpClient` (and builder/response types) — no `__http_*` builtins or `KRuntime.java` changes.
- **Depends on** S03-01 for **`Request` / `Response` / `Server`** types and the first working HTTP stack; S03-03 layers **client** ergonomics and **method/header/body** support on those types or on **new** client-specific types that **02** defines.
- **Optional coordination** with S03-02 if low-level TLS is exposed via `kestrel:socket`; HTTPS client may remain **implementation-internal** via native HTTP clients.
- **Distinct from** sequence **62** (compile-time URL imports).

## Goals

1. Callers can implement **REST** clients (JSON APIs, CRUD) **in Kestrel** without resorting to undefined behaviour or only GET.
2. **`kestrel:http`** (or a **clearly named** submodule pattern documented in **02**) stays a **single** import path so **07**'s stdlib list does not sprawl unnecessarily — prefer **extending** `kestrel:http` unless size forces a split (e.g. `kestrel:http-client`); the **planned** phase must choose and **update specs once**.
3. The **JVM** exposes the defined function signatures and observable **`Task`** behaviour for the documented API, entirely via `extern type` / `extern fun` bindings to `java.net.http.HttpClient` and builder types — no `maven:` dependencies, no new builtins.
4. Specs state how **errors** are surfaced (e.g. failed connect, non-2xx status, truncated body) so tests and users are not surprised.

## Acceptance Criteria

- [ ] **02** updated: new or extended functions for **client request** with **method**, **URL**, **headers**, optional **body**, returning **`Task<Response>`** (or equivalent documented type) with **status**, **response headers**, and **body** access.
- [ ] **`get`** remains valid per **60**/**02**; new API either wraps it or coexists without breaking the original signature table.
- [ ] At least **POST** with JSON body and **DELETE** documented and tested (REST-shaped E2E against a tiny local test server or harness).
- [ ] **HTTPS** to a known endpoint or local TLS test server (aligned with **60**/TLS capabilities); behaviour documented when TLS fails.
- [ ] The **JVM** backend implements the new surface; tests run on the JVM target.

## Spec References

Normative updates for consistency when this story closes:

- **`docs/specs/02-stdlib.md`** - §`kestrel:http` (and **Request/Response** shapes): add client request/response fields, method/header/body functions, and error/result semantics.
- **`docs/specs/05-runtime-model.md`** - If response bodies are streamed or size-limited, document **resource** lifetime and cancellation (if any).
- **`docs/specs/07-modules.md`** - Only if a **new** stdlib specifier is introduced instead of extending `kestrel:http`.
- **`docs/specs/08-tests.md`** - Extend stdlib/http test expectations if the harness must cover new entry points.

## Risks / Notes

- **API shape:** Avoid duplicating Python `requests` complexity in v1; a small **record** for options (method, headers, body) may suffice.
- **Large bodies:** Document max buffering or streaming stance.
- **Redirects, cookies, HTTP/2:** Mark **out of scope** in **02** unless explicitly implemented and tested in this story.
- **S03-05 vs S03-03:** S03-05 delivers `get` only; S03-03 extends that surface. Do not rewrite S03-05's tasks; add acceptance rows referencing both stories.

## Tests to add

### Kestrel unit tests (`stdlib/kestrel/http.test.ks`)

| Test name | What it does |
|-----------|---------------|
| `POST with JSON body to https://httpbin.org/post succeeds` | Calls `request(method: "POST", url: "https://httpbin.org/post", headers: [{"Content-Type", "application/json"}], body: "{\"x\":1}")`, asserts status is 200 and response body contains `"x"` |
| `DELETE to https://httpbin.org/delete succeeds` | Calls `request(method: "DELETE", url: "https://httpbin.org/delete")`, asserts status is 200 |
| `PUT to https://httpbin.org/put echoes body` | Sends a JSON body, asserts the echoed `data` field matches |
| `request headers are sent` | Calls `https://httpbin.org/headers` with a custom header `X-Kestrel-Test: hello`, asserts response body contains `"X-Kestrel-Test"` and `"hello"` |
| `response headers are readable` | Calls `https://httpbin.org/response-headers?Content-Type=text/plain`, asserts `Content-Type` header on response is `text/plain` |
| `non-2xx status is not a Task failure` | Calls `https://httpbin.org/status/422`, asserts status is 422 and task succeeds |

### E2E scenarios

| File | Endpoint | Assertion |
|------|----------|-----------|
| `tests/e2e/scenarios/positive/http-post.ks` | `https://httpbin.org/post` | POST with JSON body; output contains status `200` and the echoed JSON field |
| `tests/e2e/scenarios/positive/http-delete.ks` | `https://httpbin.org/delete` | DELETE; output contains status `200` |
| `tests/e2e/scenarios/positive/http-request-headers.ks` | `https://httpbin.org/headers` | Custom request header echoed in response body |

### Vitest (`compiler/test/`)

| File | Intent |
|------|--------|
| `compiler/test/unit/http-request.test.ts` | New `request` function (or equivalent) resolves and typechecks; request-options record type is correct |
| `compiler/test/integration/http-request.test.ts` | `extern fun` bindings for `HttpRequest.Builder` methods (`method`, `POST`, `PUT`, `DELETE`, `header`) compile and emit correct JVM instructions |

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: add `request` function (or equivalent name) with method, URL, headers, optional body, returning `Task<Response>`; document response header access; confirm `get` remains valid and coexists.
- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — Document `Response` header-access API and note that redirects, cookies, and HTTP/2 are out of scope.
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — Any resource-lifetime or cancellation notes for response bodies if not already covered by S03-05.
- [ ] [docs/specs/07-modules.md](../../specs/07-modules.md) — Only if a new stdlib specifier is introduced; otherwise confirm `kestrel:http` is the single import path.
