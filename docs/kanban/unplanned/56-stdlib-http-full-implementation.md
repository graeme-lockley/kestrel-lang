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
