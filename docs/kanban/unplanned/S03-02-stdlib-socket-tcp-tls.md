# Stdlib: TCP/TLS sockets (`kestrel:socket`)

## Sequence: S03-02
## Tier: 8 — Networking expansion (post–HTTP baseline)
## Former ID: (none)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: 60, 69, 70

## Summary

Introduce a **user-facing** standard library module for **TCP** sockets (connect, listen, accept, read, write, close) and **TLS** over TCP for client and server roles where the host platform allows it. Implementations use **native** facilities in the **JVM backend** (no bundled third-party protocol stacks required beyond what the host provides). This complements sequence **60** (`kestrel:http`), which may use sockets internally without exposing them; this story **documents and stabilises** the socket surface for protocols and tooling that need raw streams.

## Current State

- `docs/specs/02-stdlib.md` defines `kestrel:http` but **no** first-class socket module.
- `docs/specs/07-modules.md` lists core stdlib specifiers; `kestrel:socket` is not a reserved name.
- Sequence **60** acceptance criteria mention VM primitives for TCP/HTTP; any **public** socket API is out of scope for **60** unless explicitly merged—this story assumes **60** may deliver internal transport first, then **68** adds the **stdlib contract** and the JVM implementation for programs that need streams.

## Relationship to other stories

- **Depends on** sequence **59** (async/event loop) for non-blocking read/write and accept patterns consistent with `Task` and `await`, unless the first slice is **strictly blocking** with documented limitations (prefer aligning with **59** before closing **68**).
- **Builds on / coordinates with** sequence **60** (`kestrel:http` full implementation): shared low-level code or primitives should be **factored** so HTTP and sockets do not fork incompatible TLS or TCP behaviour.
- **Related (not duplicate):** sequence **62** (URL import resolution) is **compile-time** fetch; **68** is **runtime** I/O.
- **Optional later:** WebSockets or other framed protocols may be separate stories on top of **68**.

## Goals

1. Kestrel programs can open **TCP** connections and accept **TCP** connections with predictable error and closure semantics on the **JVM**.
2. **TLS** (HTTPS-style handshakes on streams) is available where the reference implementation can rely on **Java** platform TLS without mandating a specific certificate verification policy beyond what is documented and tested.
3. The **specs** name the module, types, and functions so compiler resolution, typechecking, and conformance tests can treat `kestrel:socket` like other stdlib modules.
4. Security-sensitive defaults (e.g. verification mode, allowed ciphers) are **specified or explicitly implementation-defined** so the two runtimes do not silently diverge in ways that confuse users.

## Acceptance Criteria

- [ ] `kestrel:socket` resolves from source like other stdlib modules (`docs/specs/07-modules.md` updated accordingly).
- [ ] Documented API in `docs/specs/02-stdlib.md` covers at least: client connect (host, port), server listen/bind, accept, close, and byte-oriented send/receive returning **`Task`-shaped** results where **59** requires async I/O (or a documented blocking subset if **59** is not yet done—planning must pick one and stick to it).
- [ ] TLS: documented API for upgrading or creating a **TLS client** stream and **TLS server** context (exact shape left to planned phase but must appear in **02** before **done**).
- [ ] **JVM:** JVM runtime primitives or host calls implementing the module behaviour with the Kestrel-visible signatures.
- [ ] Unit/E2E tests under `tests/unit/*.test.ks` (and any JVM harness tests) exercise connect + short request/response over **plain TCP**; at least one **TLS** smoke test if CI can run it deterministically (or documented skip with local-only command).

## Spec References

Normative updates required for a consistent end state (this story is not complete until these reflect the shipped API):

- **`docs/specs/02-stdlib.md`** — New section **`kestrel:socket`**: types, functions, `Task` vs sync, error/closure semantics, TLS defaults and implementation-defined corners.
- **`docs/specs/07-modules.md`** — §4.2: add `kestrel:socket` to the stdlib specifier list and cross-reference **02**.
- **`docs/specs/05-runtime-model.md`** — I/O, blocking vs event-driven completion, interaction with **TASK** and host resources (sockets as owned handles), if not already sufficient.
- **`docs/specs/04-bytecode-isa.md`** — §7: any **new** `CALL` primitive ids for sockets/TLS must be documented with arity and JVM mapping notes (match existing primitive table style).
- **`docs/specs/08-tests.md`** — If stdlib coverage rules mention only certain modules, extend so **socket** test coverage is required where feasible.

## Risks / Notes

- **Ordering:** Implementing **68** before **59** risks duplicating TLS/TCP work; prefer **shared internal layer** or implement **68** after the first **60** vertical slice that already owns sockets.
- **TLS in tests:** Certificate fixtures, trust stores, and CI headless environments differ between macOS/Linux and JVM; plan deterministic local certs or mock server in **planned** phase.
- **Semantics:** JVM implementation edge cases (half-close, timeout granularity, DNS); **02** should mark behaviour **implementation-defined** where needed.
- **Security:** Raw sockets increase attack surface for user code; document that servers must not run with elevated trust without host hardening.
- Detailed **Tasks**, **Tests to add**, and **Documentation and specs to update** checklists belong in **`planned/`** when this story is promoted.
