# HTTP Types and API Spec

## Sequence: S03-01
## Tier: 7 - Deferred (large / dependency-heavy)
## Former ID: (was part of old S03-01 monolith)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-05, S03-06, S03-02, S03-03, S03-04

## Summary

Design and document the complete `kestrel:http` public API in `docs/specs/02-stdlib.md` before any implementation begins. Define the opaque types `Server`, `Request`, and `Response` (backed by JDK classes — concrete JDK mapping chosen in this story and fixed for S03-05 and S03-06), document the concurrency model, TLS defaults, error semantics, and all function signatures. This story produces no runnable code — only spec, type shape decisions, and a stub `http.ks` that declares the type names. S03-05 (HTTP client) and S03-06 (HTTP server) both depend on this story's decisions.

## Current State

- `stdlib/kestrel/http.ks` exports only `nowMs()`.
- `docs/specs/02-stdlib.md` lists the `kestrel:http` surface at a high level but leaves type shapes implementation-defined.
- No JDK class mapping, concurrency model, or error-surfacing convention is documented for `kestrel:http`.

## Relationship to other stories

- **E01 — Async runtime foundation:** Done. `Task` semantics and error model are established; this story must align HTTP error surfacing with them.
- **E02 — JVM interop:** Done. `extern type` / `extern fun` are the binding mechanism. This story decides which JDK classes back each opaque type.
- **Blocks S03-05** (HTTP GET client) and **S03-06** (HTTP server) — both must wait for the type shapes and concurrency model agreed here.
- **S03-02 / S03-03 / S03-04:** Informed by the `Request` / `Response` contract fixed here.

## Goals

1. Produce a complete, normative `kestrel:http` section in `02-stdlib.md`: all function signatures, `Server` / `Request` / `Response` field contracts (as much as is implementation-stable), error semantics, concurrency model, and TLS defaults.
2. Choose the JDK backing class for each opaque type and record the choice as a fixed decision so S03-05 and S03-06 don't drift:
   - `Response` ← `java.net.http.HttpResponse<String>` (client response)
   - `Request` ← `com.sun.net.httpserver.HttpExchange` (server request/response handle)
   - `Server` ← `com.sun.net.httpserver.HttpServer`
3. Document the server concurrency model: one virtual thread per accepted request (Java 21 virtual-thread executor on `HttpServer`).
4. Document TLS defaults for `get`: system trust store, SNI enabled, TLS 1.2 minimum; server (`listen`) is HTTP-only.
5. Document `queryParam` duplicate-key rule: last occurrence wins.

## Acceptance Criteria

- [ ] `docs/specs/02-stdlib.md` §`kestrel:http` is fully written: all seven functions with signatures, `Server`/`Request`/`Response` shapes, concurrency model, TLS defaults, and queryParam duplicate-key rule.
- [ ] JDK class mapping for each opaque type is recorded in the spec (or in a build note) and matches what S03-05 and S03-06 will use.
- [ ] `stdlib/kestrel/http.ks` is updated to declare the opaque type stubs (`Server`, `Request`, `Response`) and export them alongside `nowMs()`, with `TODO` comments for the implementations landing in S03-05/S03-06.
- [ ] `docs/specs/05-runtime-model.md` has a short section (or cross-reference) for HTTP server concurrency model.
- [ ] No implementation tasks remain: this story is complete when specs are written and stubs are in place.

## Spec References

- [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http` (primary target of this story).
- [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — concurrency model for HTTP server.
- [docs/specs/07-modules.md](../../specs/07-modules.md) — confirm `kestrel:http` is listed in the stdlib specifier table.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| **Vitest** | `compiler/test/unit/http-types.test.ts` | `Server`, `Request`, `Response` opaque type stubs in `http.ks` resolve and typecheck; `nowMs` signature unchanged |
| **Vitest** | `compiler/test/integration/http-module.test.ts` | `import * as Http from "kestrel:http"` resolves without error; all exported names are present |
| **Conformance typecheck** | `tests/conformance/typecheck/http-types.ks` | `createServer`, `listen`, `get`, `bodyText`, `queryParam`, `requestId`, `nowMs` all typecheck against the declared signatures |

No runtime or E2E tests are added in this story — only spec and stub work.

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — §`kestrel:http`: write full normative text for all seven functions (`createServer`, `listen`, `get`, `bodyText`, `queryParam`, `requestId`, `nowMs`); document `Server`, `Request`, `Response` type shapes; queryParam duplicate-key rule (last wins); server HTTP-only; `get` http+https; TLS defaults (system trust store, SNI on, TLS 1.2 minimum); error semantics (network failure = `Task` failure; non-2xx = successful `Task`).
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — Add §`HTTP server concurrency model`: one virtual thread per accepted request via Java 21 executor; handler lifecycle (exchange open for handler duration); no re-entrancy guarantee.
- [ ] [docs/specs/07-modules.md](../../specs/07-modules.md) — Confirm `kestrel:http` is present in the stdlib specifier table; add a note that `Server`, `Request`, `Response` are opaque types backed by JDK classes.

## Impact analysis

| Area | Change |
|------|--------|
| `docs/specs/02-stdlib.md` | Replace minimal §`kestrel:http` table with full normative section: type shapes, all seven function signatures, error semantics, TLS defaults, concurrency model, queryParam rule |
| `docs/specs/05-runtime-model.md` | New file: create with §`HTTP server concurrency model` (one virtual thread per request, handler lifecycle, no re-entrancy guarantee) |
| `docs/specs/07-modules.md` | Add note to `kestrel:http` entry that `Server`, `Request`, `Response` are opaque types backed by JDK classes |
| `stdlib/kestrel/http.ks` | Add `extern type` stubs for `Server`, `Request`, `Response`; declare `export` stubs with `TODO` for functions landing in S03-05/S03-06; keep `nowMs` |
| `tests/conformance/typecheck/http-types.ks` | New file: typecheck-conformance test verifying all seven function signatures and three opaque types typecheck |
| `compiler/test/unit/http-types.test.ts` | New Vitest unit test: opaque type stubs resolve; `nowMs` signature unchanged |
| `compiler/test/integration/http-module.test.ts` | New Vitest integration test: `import * as Http from "kestrel:http"` resolves; all exported names present |

## Tasks

- [x] Update `docs/specs/02-stdlib.md` §`kestrel:http`: full normative section with all seven functions, `Server`/`Request`/`Response` type shapes, error semantics, TLS defaults, concurrency model, queryParam duplicate-key rule (last wins)
- [x] Create `docs/specs/05-runtime-model.md` with §`HTTP server concurrency model`
- [x] Update `docs/specs/07-modules.md`: add opaque type note for `kestrel:http` entry
- [x] Update `stdlib/kestrel/http.ks`: add `extern type` stubs for `Server`, `Request`, `Response`; add stub function export declarations with `TODO` comments
- [x] Add `tests/conformance/typecheck/http-types.ks` conformance typecheck test
- [x] Add `compiler/test/unit/http-types.test.ts` Vitest unit test
- [x] Add `compiler/test/integration/http-module.test.ts` Vitest integration test
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Risks / Notes

- **Spec decisions are load-bearing:** S03-05 and S03-06 will implement against whatever this story decides without renegotiation. Make conservative, JDK-stable choices. Avoid exotic JDK preview APIs.
- **`Request` dual role:** `com.sun.net.httpserver.HttpExchange` provides both the incoming request (method, path, headers, body) and the outgoing response channel (status, response headers, body output stream). The Kestrel `Request` type wraps the exchange as a whole; the handler writes back by calling `bodyText`, setting status, etc. Document this clearly.
- **`Response` for client vs server:** The client `get` call returns a `Response` wrapping `HttpResponse<String>`. The server handler must also return a `Response`. These may be the same opaque type (with a factory function for server handlers to build one) or two separate types — decide and document. Prefer a single `Response` type with a `makeResponse(status, body)` constructor for server use.
- **JDK-only constraint:** No `maven:` dependencies anywhere in E03. All JDK classes used here are available in Java 21 without additional modules beyond `jdk.httpserver` (already on the JVM classpath for the runtime).

## Build notes

- 2025-03-07: Decided on single `Response` type with `makeResponse(status, body)` for server use and `get(url)` for client use. `Request` wraps `HttpExchange` (server side only); `bodyText` on `Response` reads the client response body, `requestBodyText` on `Request` reads the server request body. Concurrency model: one virtual thread per accepted request via Java 21 virtual-thread executor on `HttpServer`.
- 2025-03-07: JDK class mapping fixed: `Server` ← `com.sun.net.httpserver.HttpServer`, `Request` ← `com.sun.net.httpserver.HttpExchange`, `Response` ← `java.lang.Object` (unified opaque for both client `HttpResponse<String>` and server-side constructed response via `makeResponse`). Using `java.lang.Object` for `Response` defers the concrete wrapper to S03-05/S03-06 implementation.
- 2025-03-07: Discovered that top-level `val` without `export` goes to `parseTopLevelStmt()` which does NOT support type annotations (only `parseTopLevelDecl` does, for exported val). Unit tests adjusted to remove type annotations from bare `val` bindings.
- 2025-03-07: Conformance test (`tests/conformance/typecheck/valid/http-types.ks`) must use inline `extern type` declarations (not `import * as Http from "kestrel:http"`) because typecheck conformance tests do not resolve stdlib imports. Must also use `export exception` (not bare `exception`) since bare `exception` at top level is not recognized by the parser.
- 2025-03-07: All tests passing: 339 compiler (vitest), 1020 Kestrel (kestrel test), 64 typecheck conformance including new http-types case.
