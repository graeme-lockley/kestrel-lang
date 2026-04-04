# Epic E03: HTTP and Networking Platform

## Status

Unplanned

## Summary

Delivers the HTTP baseline and higher-level networking capabilities (socket, REST client ergonomics, and lightweight routing) for the JVM backend.

## Design Constraint: JDK-Only

All E03 implementations **must** use built-in JDK classes only — no `maven:` external dependencies. The HTTP client uses `java.net.http.HttpClient` (JDK 11+); the HTTP server uses `com.sun.net.httpserver.HttpServer` (available via `jdk.httpserver`); sockets use `java.net.Socket` / `javax.net.ssl.SSLSocket`.

Every Kestrel binding uses `extern type` / `extern fun` from E02 (no `__*` builtins; no `codegen.ts` changes). However, following the established pattern for dict, fs, process, and task modules, **KRuntime.java static helpers are added** for:
- Async operations (HTTP GET, server accept) — must return `KTask` and integrate with the virtual-thread executor.
- Primitive-returning JDK methods (e.g., `statusCode()` returns `int`) — must be boxed to `Long` for Kestrel's `Int`.
- Callback-bridging (HTTP server handler must wrap a `KFunction` into a Java `HttpHandler` interface).

Simple Object-returning JDK methods may be called directly via `extern fun` instance dispatch without KRuntime wrappers.

## Stories

- [S03-01-http-types-and-api-spec.md](../../unplanned/S03-01-http-types-and-api-spec.md)
- [S03-05-http-get-client.md](../../unplanned/S03-05-http-get-client.md)
- [S03-06-http-server.md](../../unplanned/S03-06-http-server.md)
- [S03-02-stdlib-socket-tcp-tls.md](../../unplanned/S03-02-stdlib-socket-tcp-tls.md)
- [S03-03-http-rest-client-methods-headers.md](../../unplanned/S03-03-http-rest-client-methods-headers.md)
- [S03-04-lightweight-web-routing-framework.md](../../unplanned/S03-04-lightweight-web-routing-framework.md)

**Story ordering:** S03-01 → (S03-05, S03-06 in parallel) → S03-03 → S03-04. S03-02 depends on S03-01 and can proceed after S03-05/S03-06.

## Dependencies

- Depends on Epic E01 for reliable async runtime behaviour (`Task`, virtual-thread executor, non-blocking I/O).
- Depends on Epic E02 for `extern type` / `extern fun` — the mechanism all E03 stdlib implementations use to bind JDK classes without adding `__*` compiler builtins.

## Epic Completion Criteria

- S03-01 is done: `Server`, `Request`, `Response` types specified; `02-stdlib.md` fully updated; concurrency model documented.
- S03-05 and S03-06 are done: `get`/`bodyText` and `createServer`/`listen`/`queryParam`/`requestId` delivered on JVM via JDK-only `extern` bindings; E2E tests pass.
- S03-02, S03-03, and S03-04 are done with specs and tests updated.
- No `maven:` dependencies introduced anywhere in E03.
- No unresolved networking API conflicts remain between stories.
