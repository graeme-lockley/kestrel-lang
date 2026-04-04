# Stdlib: TCP/TLS sockets (`kestrel:socket`)

## Sequence: S03-02
## Tier: 8 — Networking expansion (post–HTTP baseline)
## Former ID: (none)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-01, S03-05, S03-06, S03-03

## Summary

Introduce a **user-facing** standard library module for **TCP** sockets (connect, listen, accept, read, write, close) and **TLS** over TCP for client and server roles where the host platform allows it. Implementations use **native** facilities in the **JVM backend** (no bundled third-party protocol stacks required beyond what the host provides). This complements sequence **60** (`kestrel:http`), which may use sockets internally without exposing them; this story **documents and stabilises** the socket surface for protocols and tooling that need raw streams.

## Current State

- `docs/specs/02-stdlib.md` defines `kestrel:http` but **no** first-class socket module.
- `docs/specs/07-modules.md` lists core stdlib specifiers; `kestrel:socket` is not a reserved name.
- Sequence **60** acceptance criteria mention VM primitives for TCP/HTTP; any **public** socket API is out of scope for **60** unless explicitly merged—this story assumes **60** may deliver internal transport first, then **68** adds the **stdlib contract** and the JVM implementation for programs that need streams.

## Relationship to other stories

- **E01 — Async runtime foundation:** **Done.** Virtual-thread executor and `Task`-based I/O are in place. The async prerequisite for non-blocking socket read/write/accept is cleared.
- **E02 — JVM interop (`extern` bindings):** **Done.** `extern type` / `extern fun` / `maven:` are the required implementation mechanism for S03-02. Socket types (`java.net.Socket`, `java.net.ServerSocket`, `javax.net.ssl.SSLSocket`, etc.) and their methods must be bound via `extern type`/`extern fun`. No new `__socket_*` builtins or `KRuntime.java` additions are wanted.
- **Depends on** sequence **60** (S03-01, `kestrel:http` full implementation): shared low-level code or primitives should be **factored** so HTTP and sockets do not fork incompatible TLS or TCP behaviour.
- **Related (not duplicate):** sequence **62** (URL import resolution) is **compile-time** fetch; **68** is **runtime** I/O.
- **Optional later:** WebSockets or other framed protocols may be separate stories on top of **68**.

## Goals

1. Kestrel programs can open **TCP** connections and accept **TCP** connections with predictable error and closure semantics on the **JVM**, using `java.net.Socket` / `java.net.ServerSocket` via `extern type` / `extern fun`.
2. **TLS** (HTTPS-style handshakes on streams) is available via `javax.net.ssl.SSLSocket` / `javax.net.ssl.SSLServerSocket` — no third-party TLS library; JDK-only.
3. The **specs** name the module, types, and functions so compiler resolution, typechecking, and conformance tests can treat `kestrel:socket` like other stdlib modules.
4. Security-sensitive defaults (e.g. verification mode, allowed ciphers) are **specified or explicitly implementation-defined** so implementations do not silently diverge in ways that confuse users.
5. **JDK-only:** No `maven:` dependencies. All socket and TLS classes are in the JDK standard library.

## Acceptance Criteria

- [x] `kestrel:socket` resolves from source like other stdlib modules (`docs/specs/07-modules.md` updated accordingly).
- [x] Documented API in `docs/specs/02-stdlib.md` covers: client connect (host, port, `tcpConnect`/`tlsConnect`), server listen/bind/accept/close, `sendText`, `readAll`, `readLine`, `close`, `serverPort`.
- [x] TLS: `tlsConnect` for TLS client streams using JDK default `SSLContext` (system trust store, hostname verification).
- [x] **JVM:** `KRuntime.java` methods implementing all socket operations with `Task`-shaped results via virtual threads.
- [x] Unit tests in `stdlib/kestrel/socket.test.ks` exercise TCP connect, TLS connect, and loopback round-trip.
- [x] E2E scenarios: `socket-tcp-connect.ks`, `socket-tls-connect.ks`, `socket-server-roundtrip.ks`.

## Spec References

Normative updates required for a consistent end state (this story is not complete until these reflect the shipped API):

- **`docs/specs/02-stdlib.md`** — New section **`kestrel:socket`**: types, functions, `Task` vs sync, error/closure semantics, TLS defaults and implementation-defined corners.
- **`docs/specs/07-modules.md`** — §4.2: add `kestrel:socket` to the stdlib specifier list and cross-reference **02**.
- **`docs/specs/05-runtime-model.md`** — I/O, blocking vs event-driven completion, interaction with **TASK** and host resources (sockets as owned handles), if not already sufficient.
- **`docs/specs/04-bytecode-isa.md`** — §7: any **new** `CALL` primitive ids for sockets/TLS must be documented with arity and JVM mapping notes (match existing primitive table style).
- **`docs/specs/08-tests.md`** — If stdlib coverage rules mention only certain modules, extend so **socket** test coverage is required where feasible.

## Risks / Notes

- **Ordering:** S03-02 depends on S03-01 (type shapes and concurrency model established); implementation can proceed in parallel with S03-05/S03-06 but shares no internal code with them.
- **TLS in tests:** Integration tests connect to real public endpoints (`example.com:443`) to exercise the JDK TLS stack; do not rely solely on self-signed certs for the HTTPS path.
- **Semantics:** JVM implementation edge cases (half-close, timeout granularity, DNS); **02** should mark behaviour **implementation-defined** where needed.
- **Security:** Raw sockets increase attack surface for user code; document that servers must not run with elevated trust without host hardening.

## Tests to add

### Kestrel unit tests (`stdlib/kestrel/socket.test.ks`)

| Test name | What it does |
|-----------|---------------|
| `TCP connect to example.com:80 succeeds` | Opens a plain TCP socket to `example.com:80`, sends a minimal HTTP/1.0 GET, reads at least one byte, closes — asserts no Task failure |
| `TCP connect to closed port fails` | Connects to `127.0.0.1:1` (expected closed), asserts Task failure with connection-refused error |
| `TLS connect to example.com:443 succeeds` | Opens a TLS socket to `example.com:443`, sends a minimal request, reads a response, closes — asserts no Task failure and that the TLS handshake succeeded (no exception) |
| `socket write and read round-trip` | Starts a local `ServerSocket` listener, connects from a client socket, writes bytes, reads them back, asserts round-trip equality |
| `socket close releases resource` | Connects, closes, confirms further reads return a documented error / empty |

### E2E scenarios

| File | Endpoint | Assertion |
|------|----------|-----------|
| `tests/e2e/scenarios/positive/socket-tcp-connect.ks` | `example.com:80` | Plain TCP connect, send HTTP/1.0 GET /, receive status line starting with `HTTP/` |
| `tests/e2e/scenarios/positive/socket-tls-connect.ks` | `example.com:443` | TLS connect, send HTTP/1.1 GET /, receive response containing `200` or `301` |

### Vitest (`compiler/test/`)

| File | Intent |
|------|--------|
| `compiler/test/unit/socket.test.ts` | `kestrel:socket` module resolves; public types and functions typecheck |
| `compiler/test/integration/socket.test.ts` | `extern type`/`extern fun` bindings for `java.net.Socket`/`ServerSocket`/`SSLSocket` compile; no `__socket_*` dispatch |

## Documentation and specs to update

- [x] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — New §`kestrel:socket`: types (`Socket`, `ServerSocket`, `TlsSocket`), functions (connect, listen/bind, accept, send, receive, close), `Task` semantics, error/closure behaviour, TLS defaults (system trust store, no hostname override without explicit opt-in), implementation-defined corners.
- [x] [docs/specs/07-modules.md](../../specs/07-modules.md) — §4.2: add `kestrel:socket` to the stdlib specifier list with cross-reference to §`kestrel:socket` in **02**.
- [x] [docs/specs/05-runtime-model.md](../../specs/05-runtime-model.md) — §Socket I/O: owned handles, virtual-thread blocking semantics, resource lifetime and close semantics.
- [x] [docs/specs/08-tests.md](../../specs/08-tests.md) — Extend stdlib coverage rules to include `kestrel:socket`.

## Tasks

- [x] Add TCP/TLS socket methods to `runtime/jvm/src/kestrel/runtime/KRuntime.java`: `tcpConnect`, `tlsConnect`, `socketSendText`, `socketReadAll`, `socketReadLine`, `socketClose`, `tcpListen`, `serverSocketAccept`, `serverSocketPort`, `serverSocketClose`
- [x] Build JVM runtime (`cd runtime/jvm && bash build.sh`)
- [x] Create `stdlib/kestrel/socket.ks` with `Socket`/`ServerSocket` extern types and all exported functions
- [x] Register `kestrel:socket` in `compiler/src/resolve.ts` `STDLIB_NAMES`
- [x] Build compiler (`cd compiler && npm run build`)
- [x] Create `stdlib/kestrel/socket.test.ks` with 3 integration tests (TCP, TLS, loopback round-trip)
- [x] Create `.kestrel_socket_only.ks` test runner
- [x] Create E2E scenario `socket-tcp-connect.ks` + `.expected`
- [x] Create E2E scenario `socket-tls-connect.ks` + `.expected`
- [x] Create E2E scenario `socket-server-roundtrip.ks` + `.expected`
- [x] Update `docs/specs/02-stdlib.md` with `kestrel:socket` section
- [x] Update `docs/specs/07-modules.md` §4.2 to include `kestrel:socket`

## Build Notes

**2025 — Implementation:**

**Implementation model:** All socket primitives are implemented as `KRuntime.java` static methods using the existing virtual-thread executor (`asyncExecutor`). No new JVM dependencies — all socket classes are in JDK 21 standard library (`java.net.Socket`, `java.net.ServerSocket`, `javax.net.ssl.SSLSocket`).

**TLS:** `tlsConnect` uses `SSLSocketFactory.getDefault()` which uses the JDK default `SSLContext` (system trust store, hostname verification enabled). There is intentionally no override API — security defaults should not be soft-pedalled.

**`readAll` vs `readLine`:** `readAll` calls `InputStream.readAllBytes()` which blocks until EOF (remote close). This is correct for HTTP/1.0 and similar protocols. For protocols that keep the connection open, `readLine` reads one line at a time. Tests use `readAll` with HTTP/1.0 requests to avoid keep-alive complexity.

**Server pattern:** The idiomatic pattern is: `listen` (bind) → start async `acceptOnce` task → client `tcpConnect` → client `sendText` → client `close` (half-close triggers EOF on server) → `await serverTask` → `serverClose`. This avoid races: the server task starts before the client connects.

**No TLS server:** TLS server support (SSLServerSocket) was not added in this story — the scope was TCP client + TLS client + TCP server. TLS server socket (with cert/key management) is a follow-up.

**Tests:** 3 unit tests in `socket.test.ks`, 3 E2E scenarios (23 total E2E positive scenarios after this story). All tests pass.
