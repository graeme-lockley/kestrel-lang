# Stdlib kestrel:http Full Implementation

## Sequence: 56
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 23

## Summary

The `kestrel:http` module currently only exports `nowMs()`. [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) documents the full surface: `createServer`, `listen`, `get`, `bodyText`, `queryParam`, `requestId`, and `nowMs`, plus the standard types `Server`, `Request`, and `Response` (concrete shapes are implementation-defined as long as signatures hold). Everything except `nowMs` depends on async I/O and an event loop; sequence **55** is the hard prerequisite. **Product intent:** the **server** path is **plain HTTP** only; the **client** (`get`) must support **`https://`** as well as `http://`. **Zig VM and JVM** backends must gain the needed primitives/runtime **together**—no VM-only milestone that leaves JVM behind.

## Current State

- **Stdlib:** `stdlib/kestrel/http.ks` exports only `nowMs()` via `kestrel:basics` / `__now_ms()`.
- **VM:** `vm/` implements the `nowMs` primitive; there are no TCP/HTTP primitives, no request parsing, and no server or client runtime support.
- **JVM:** No HTTP/TLS primitives or parity path yet for `kestrel:http` beyond whatever the shared stdlib compiles to; planning must wire client TLS and server HTTP through the JVM runtime alongside the VM.
- **Compiler / types:** No special-case language support is required beyond existing `Task`, `async`/`await`, and stdlib module loading—once 55 lands, surface types can be ordinary records/ADTs in Kestrel or opaque handles backed by VM tags, as long as the spec signatures are met.
- **Tests:** No HTTP-focused E2E or conformance coverage; [docs/kanban/done/45-stdlib-json-fs-http.md](../done/45-stdlib-json-fs-http.md) delivered JSON/fs and explicitly treated HTTP as a minimal / deferred slice (`nowMs` only in practice).

## Relationship to other stories

- **55 — Async/Await / event loop:** Prerequisite for `listen`, `get`, and `bodyText` (`Task`-returning APIs). This story should not start implementation until 55’s model for scheduling blocking I/O is settled enough to hang TCP accept/read/write on.
- **65–67 (Tier 8 — networking expansion):** Roadmap items include `kestrel:socket`, richer TLS usage, “REST-capable HTTP **client** extensions,” and possible `kestrel:web` routing. **56** still targets a **minimal** HTTP/1.1 stack (no HTTP/2, no generic socket API, no connection pooling) but **does** include **HTTPS for `get`** on the client and **HTTP-only** for `listen`/`createServer`. Tier 8 can add sockets, pooling, broader TLS features, and routing without redefining the core `kestrel:http` entry points unless specs are updated.
- **45 (done):** Historical context for stub-only HTTP; links the original “full vs minimal” expectation.

## Goals

1. Bring the **reference** `kestrel:http` implementation up to the **02-stdlib** contract: all functions in the `kestrel:http` table and usable `Server` / `Request` / `Response` types for server and client use.
2. Implement **Zig VM and JVM** support **in the same delivery**: primitives and/or runtime services on both backends so the stdlib can accept connections, parse/serve **HTTP/1.1** on the server, and perform outbound **GET** with **`http://` and `https://`** on the client (TLS required for HTTPS—use host platform or embedded stack per planning).
3. Add **automated verification** (at least one E2E scenario) that exercises listen → handler → response and a client `get` (including **HTTPS**), with **both** backends covered or an explicitly equivalent split (e.g. same golden behaviour, dual harness)—decide in **planned**.
4. Keep **security and production** expectations explicit: default bind policy, server HTTP-only surface, TLS verification defaults for `get` (e.g. system trust store), and error behaviour documented; Tier 8 remains for sockets, pooling, and richer networking—not for “adding HTTPS to `get`.”

## Acceptance Criteria

- [ ] `createServer(handler)`: `((Request) -> Task<Response>) -> Server` per 02 — server value ready to bind; handler invoked per accepted connection/request per chosen concurrency model (documented).
- [ ] `listen(server, { host, port })`: `(Server, { host: String, port: Int }) -> Task<Unit>` — bind and accept loop integrated with the async runtime from 55.
- [ ] `get(url)`: `(String) -> Task<Response>` — HTTP GET for **`http://` and `https://`** URLs (TLS on HTTPS); other schemes rejected or documented. Server side remains **HTTP only** (no TLS terminator in scope for `listen` unless planning adds it).
- [ ] `bodyText(request)`: `(Request) -> Task<String>` — body as UTF-8 text; empty or missing body yields empty string or documented equivalent consistent with spec intent.
- [ ] `queryParam(request, name)`: `(Request, String) -> Option<String>` — duplicate query keys: **last occurrence wins** (notionally overwrites earlier values); add a one-line clarification to **02-stdlib** if not already stated; encoding rules documented if non-ASCII appears.
- [ ] `requestId(request)`: `(Request) -> String` — stable identifier for the lifetime of the request value (e.g. UUID string or monotonic id); format implementation-defined.
- [ ] `nowMs()`: unchanged, still matches 02 (already implemented).
- [ ] Exported **types** `Server`, `Request`, `Response` with enough structure to build responses in handlers (status, headers, body) and to read status/body on client `Response` — exact fields follow planning/spec updates if 02 is tightened.
- [ ] **VM:** Primitives or internal runtime support for TCP, HTTP parsing/serialization, and **client TLS** for `https` as needed; documented in spec or implementation notes if 09-tools or VM docs must list new opcodes/primitives.
- [ ] **JVM:** Matching capabilities for the same stdlib surface (HTTP server, HTTPS-capable `get`), implemented **in lockstep** with the VM—not a later follow-up story unless an explicit exception is recorded in **planned**.
- [ ] **E2E / verification:** Scenario(s) that start a server, perform at least one request, assert status/body (and tear down cleanly), and exercise **`get`** over **HTTPS** where CI allows (e.g. local TLS test server or documented skip). Both backends validated per AGENTS.md and story **Tests to add** in **planned**.

## Spec References

- [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — § **kestrel:http** (function table), § **Standard Types** (`Server`, `Request`, `Response`).
- [docs/specs/09-tools.md](../../specs/09-tools.md) — if new CLI/VM flags or primitive visibility need documenting.
- VM / bytecode docs under `docs/specs/` if this story adds or names public primitives (follow existing patterns from other stdlib-backed builtins).

## Risks / Notes

- **Ordering:** Starting before **55** will duplicate or throw away integration work; keep 56 unblocked-by-dependency in planning only after 55’s Task/event-loop design is agreed for I/O.
- **Scope vs Tier 8:** HTTP/2, generic **socket** API, connection pooling, and WebSocket remain **out of scope** for **56**; **client TLS for `https://`** is **in scope**. Tier 8 adds breadth (sockets, pooling, REST helpers, routing), not the basic HTTPS client requirement.
- **Dual backend cost:** VM (Zig) and JVM must both implement TLS-capable client I/O and HTTP server I/O; plan shared test strategy and avoid drift (e.g. same golden outputs, or paired smoke tests).
- **TLS specifics:** Certificate verification (system trust vs custom), SNI, TLS version floor, and error surfaces differ by platform—document defaults in **02** or **09** during **planned**; consider CI flakiness for HTTPS E2E (local test certs, skip flags).
- **Concurrency model:** Whether one handler runs at a time per process, per connection, or with limited parallelism affects both runtimes; decide in **planned** and document (including re-entrancy and `await` inside handlers).
- **Security:** Binding `0.0.0.0`, defaults for `host`, and error messages must not encourage unsafe dev practices without documentation; consider defaulting to `127.0.0.1` in examples/tests.
- **URL and parsing:** `get` URL parsing may overlap with **59 (URL stdlib)** if strict URL types are introduced later; for 56, a minimal string-based parser in VM or Kestrel is acceptable if documented.
- **Error handling:** Network failures, malformed requests, TLS failures, and partial reads: define whether tasks fail, throw, or complete with sentinel responses—align with 55’s error model for async I/O.

### Resolved decisions (for planning)

1. **Client vs server TLS:** **`get`** supports **`https://`**; **server** (`listen` / `createServer`) stays **HTTP only** for this story.
2. **Backends:** **VM and JVM implemented together**—no VM-first drop that defers JVM.
3. **`queryParam` duplicate keys:** **Last value wins**; update **02-stdlib** with a short normative line when implementing.

## Impact analysis

Incorporates **Risks / notes** above (55 ordering, dual backend, TLS, concurrency, security, URL parsing, errors). Roll forward in **lockstep VM + JVM**; avoid shipping primitives on only one backend.

| Area | Files / subsystems (indicative) | Change | Risk |
|------|----------------------------------|--------|------|
| **Prerequisite** | [55-async-await-suspension-event-loop.md](55-async-await-suspension-event-loop.md) | **56 starts only after 55** delivers real `Task` suspension, event loop, and non-blocking I/O hooks HTTP can register with | **Blocker** if ignored |
| **VM (Zig)** | `vm/src/primitives.zig`, `vm/src/exec.zig`, new or extended I/O modules (sockets, TLS client), `vm/src/gc.zig` if new object kinds | TCP listen/accept, HTTP/1.1 request/response parse + serialize (server, plain HTTP); outbound GET with optional TLS (`https`); integrate completions with **55** loop; optional new opcode(s) or reuse TASK + host callbacks | **High**: parsing edge cases, TLS on Zig, GC roots for live connections |
| **Bytecode / ISA** | `docs/specs/04-bytecode-isa.md` | Document any new calls or TASK-related behaviour for HTTP primitives | Low–medium |
| **Compiler (TS)** | `compiler/src/typecheck/check.ts` (new `__*` bindings, `Task<Result<…>>` if used), `compiler/src/codegen/codegen.ts`, `compiler/src/jvm-codegen/codegen.ts` | Wire builtins used from `stdlib/kestrel/http.ks`; align VM and JVM primitive indices / KRuntime entry points | Medium |
| **JVM runtime** | `runtime/jvm/src/kestrel/runtime/KRuntime.java` (and related classes) | **Mirror VM**: `HttpServer`/`HttpClient` (names TBD), non-blocking or loop-driven completion consistent with **55**, `HttpsURLConnection` or equivalent for `get` TLS | **High**: parity with VM, platform TLS |
| **Stdlib** | `stdlib/kestrel/http.ks`, optional `stdlib/kestrel/http.test.ks` | Implement full **02** surface: types + exports; thin wrappers over `__` primitives | Medium |
| **CLI / scripts** | `scripts/kestrel`, `scripts/build-cli.sh` if JVM classpath changes | Only if new native deps or flags; otherwise unchanged | Low |
| **Tests** | `tests/e2e/scenarios/positive/`, `tests/unit/*.test.ks`, `tests/conformance/` as needed, `compiler/test/`, `vm` tests | HTTPS may need local cert fixture or conditional skip; **`./scripts/kestrel test-both`** on shared `.ks` | Medium |
| **Docs** | `docs/specs/02-stdlib.md`, `05-runtime-model.md`, `09-tools.md`, `08-tests.md`, `AGENTS.md` if verification changes | `queryParam` duplicate-key rule; HTTP/TLS defaults; server HTTP-only; VM+JVM parity expectations | Low |

**Rollback:** Prefer feature branches; if TLS blocks release, document explicit deferral of `https` only with team agreement (contradicts current acceptance—avoid without amending story).

## Tasks

- [ ] **Gate:** Confirm **55** is **done** (or explicitly list remaining 55 items that block HTTP integration); re-read `05` / `04` for TASK + idle semantics.
- [ ] **Design note:** Record **concurrency model** for the server (e.g. single-threaded loop, one handler at a time vs per-connection serialization) in **02** or **05**; align VM and JVM.
- [ ] **Spec pass:** Update **02-stdlib** — `queryParam` **last duplicate wins**; clarify **server = HTTP only**, **`get`** supports **http + https**; document TLS verification (default: system trust), SNI, and error surfacing (`Task<Result<…>>` or exceptions per **55** contract).
- [ ] **VM:** Add TCP server path (bind, listen, accept) integrated with event loop; HTTP/1.1 request parsing and response writing for handler API; no TLS on listen.
- [ ] **VM:** Add outbound HTTP GET (`http://`) and **TLS** (`https://`) client; complete tasks on loop; failures map to agreed error model.
- [ ] **VM:** Expose minimal **opaque or record** representation for `Server`, `Request`, `Response` consistent with stdlib (handles, tags, or records per existing patterns).
- [ ] **Stdlib:** Implement `createServer`, `listen`, `get`, `bodyText`, `queryParam`, `requestId`, `nowMs` in `stdlib/kestrel/http.ks` using new primitives; define exported **Request** / **Response** / **Server** shapes.
- [ ] **Compiler:** Register primitive names, arities, and types in typecheck + **kbc** codegen + **JVM** codegen for every `__http_*` (or chosen split) builtin.
- [ ] **JVM:** Implement matching server and client behaviour in `KRuntime` (or decomposed classes), driven by same **55** event-loop semantics as VM.
- [ ] **Tests (Kestrel):** Add `stdlib/kestrel/http.test.ks` or `tests/unit/` cases for `queryParam`, `requestId`, handler response shaping (no ordering dependence unless documented).
- [ ] **E2E:** Add positive scenario: local HTTP server + client request + assertions; add **HTTPS** `get` path (e.g. `https://` to test endpoint with known cert, or documented `SKIP_HTTPS_E2E` with CI policy).
- [ ] **Dual backend:** Run shared programs with **`./scripts/kestrel test-both`** (or extend `scripts/jvm-smoke.mjs` if appropriate); fix drift until both pass.
- [ ] **Conformance / Vitest:** Add or extend conformance for `kestrel:http` types and imports if valuable; fix compiler tests for new builtins.
- [ ] **Zig:** VM unit/integration tests for parser edge cases or primitive wiring where feasible without full stdlib.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `cd vm && zig build test`; `./scripts/kestrel test`; `./scripts/kestrel test-both` on HTTP tests; `./scripts/run-e2e.sh` when E2E added.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| **Zig** | `vm` tests (e.g. `vm/src/main.zig` registered tests) | HTTP parse/format helpers; primitive smoke if isolable |
| **Vitest** | `compiler/test/unit/`, `compiler/test/integration/` | New primitive typing; `http.ks` module resolves; codegen symbol presence |
| **Kestrel unit** | `stdlib/kestrel/http.test.ks`, `tests/unit/*.test.ks` | `queryParam` last-wins; body/headers; handler builds `Response` |
| **Conformance** | `tests/conformance/runtime/` or `typecheck/` if shapes warrant | Optional: import `kestrel:http` and call `nowMs` + new APIs behind feature availability |
| **Dual backend** | `./scripts/kestrel test-both` | **Same** `.ks` sources on **VM and JVM** for HTTP scenarios |
| **E2E** | `tests/e2e/scenarios/positive/*.ks` + `.expected` | Server up → request → response; **`get`** over **HTTPS** per CI policy |
| **Smoke** | `scripts/jvm-smoke.mjs` | Extend if quick JVM sanity for HTTP path is useful |

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — **kestrel:http**: full function descriptions; **duplicate query keys: last wins**; **HTTP server only**; **`get`**: http + https; type contracts for `Request`/`Response`/`Server` as implemented.
- [ ] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — How HTTP I/O registers with the event loop (if not already implied by **55**); server concurrency model.
- [ ] [docs/specs/04-bytecode-isa.md](../../specs/04-bytecode-isa.md) — Any new or documented `CALL` targets / HTTP-related op behaviour.
- [ ] [docs/specs/09-tools.md](../../specs/09-tools.md) — CLI or flags only if this story adds them (e.g. trust store path—prefer avoid unless needed).
- [ ] [docs/specs/08-tests.md](../../specs/08-tests.md) — E2E / HTTPS testing notes, skips, or fixtures if non-obvious.
- [ ] [AGENTS.md](../../AGENTS.md) — Only if verification commands or required suites change.

## Notes

- **HTTPS in CI:** Prefer a fixed **localhost** TLS test server (self-signed cert committed under `tests/` or generated in script) and document **`curl -k` equivalent** behaviour (default **verify** on; test may use pinned cert or test-only trust). If full verification is too brittle initially, record a **time-boxed** follow-up—**do not** silently ship `https` without tests.
- **`bodyText` / `get` errors:** Follow **55**’s **`Task<Result<…>>`** (or documented equivalent) for network/TLS failures; avoid reintroducing empty-string sentinels for new surfaces.
- **Keep-alive / chunked encoding:** Out of scope unless required for minimal interop; document “first request/response per connection” if implementing the simplest server.
- **Relationship to 65–67:** No new public module names required for **56**; Tier 8 later adds `kestrel:socket`, pooling, etc., without renaming core `kestrel:http` entry points unless specs change.
