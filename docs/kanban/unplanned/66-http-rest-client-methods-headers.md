# HTTP client: methods, headers, bodies, and REST-oriented API

## Sequence: 66
## Tier: 8 — Networking expansion (post–HTTP baseline)
## Former ID: (none)

## Summary

Extend the standard library **beyond** the current **`kestrel:http`** contract in **02**, which today centres on a server-oriented API and a **`get(url)`** client. Add a **REST-capable client surface**: arbitrary **methods** (GET, POST, PUT, PATCH, DELETE, ...), **request headers**, **request body**, **response status**, and **response headers/body**, all integrated with the **`Task`** model once sequence **56** is in effect. Implementations use **native** HTTP client stacks on the Zig VM and JVM (`std.http` / platform TLS on Zig; `java.net.http.HttpClient` or equivalent on the JVM) with **documented** parity goals.

## Current State

- `docs/specs/02-stdlib.md` §`kestrel:http` lists `get`, `createServer`, `listen`, `bodyText`, `queryParam`, `requestId`, `nowMs` but **no** general request builder, POST/PUT, or response metadata beyond what `Response` will carry after **56**.
- Sequence **56** delivers the **baseline** `kestrel:http` table; **66** **extends** that contract without removing **56**’s acceptance targets.
- No spec today describes **header maps**, **status codes**, or **content-type** conventions for client calls.

## Relationship to other stories

- **Depends on** sequence **56** for real **`Task` completion** on network I/O (same dependency as **57**).
- **Depends on** sequence **56** for **`Request` / `Response` / `Server`** types and the first working HTTP stack; **66** layers **client** ergonomics and **method/header/body** support on those types or on **new** client-specific types that **02** defines.
- **Optional coordination** with sequence **65** if low-level TLS is exposed via `kestrel:socket`; HTTPS client may remain **implementation-internal** via native HTTP clients.
- **Distinct from** sequence **58** (compile-time URL imports).

## Goals

1. Callers can implement **REST** clients (JSON APIs, CRUD) **in Kestrel** without resorting to undefined behaviour or only GET.
2. **`kestrel:http`** (or a **clearly named** submodule pattern documented in **02**) stays a **single** import path so **07**’s stdlib list does not sprawl unnecessarily—prefer **extending** `kestrel:http` unless size forces a split (e.g. `kestrel:http-client`); the **planned** phase must choose and **update specs once**.
3. **Zig VM and JVM** expose the **same** function signatures and observable **`Task`** behaviour for the documented API.
4. Specs state how **errors** are surfaced (e.g. failed connect, non-2xx status, truncated body) so tests and users are not surprised by VM/JVM differences.

## Acceptance Criteria

- [ ] **02** updated: new or extended functions for **client request** with **method**, **URL**, **headers**, optional **body**, returning **`Task<Response>`** (or equivalent documented type) with **status**, **response headers**, and **body** access.
- [ ] **`get`** remains valid per **56**/**02**; new API either wraps it or coexists without breaking the original signature table.
- [ ] At least **POST** with JSON body and **DELETE** documented and tested (REST-shaped E2E against a tiny local test server or harness).
- [ ] **HTTPS** to a known endpoint or local TLS test server (aligned with **56**/TLS capabilities); behaviour documented when TLS fails.
- [ ] JVM and Zig backends both implement the new surface; parity tests or shared `.ks` tests run on both where the repo’s harness allows.
- [ ] **`docs/specs/04-bytecode-isa.md`** updated if new **primitive** `CALL` ids are introduced.

## Spec References

Normative updates for consistency when this story closes:

- **`docs/specs/02-stdlib.md`** — §`kestrel:http` (and **Request/Response** shapes): add client request/response fields, method/header/body functions, and error/result semantics.
- **`docs/specs/05-runtime-model.md`** — If response bodies are streamed or size-limited, document **resource** lifetime and cancellation (if any).
- **`docs/specs/04-bytecode-isa.md`** — §7 primitive table for any new **`__http_*`** (or similar) ids and JVM mapping.
- **`docs/specs/07-modules.md`** — Only if a **new** stdlib specifier is introduced instead of extending `kestrel:http`.
- **`docs/specs/08-tests.md`** — Extend stdlib/http test expectations if the harness must cover new entry points.

## Risks / Notes

- **API shape:** Avoid duplicating Python `requests` complexity in v1; a small **record** for options (method, headers, body) may suffice.
- **Large bodies:** Document max buffering or streaming stance; mismatch between Zig and JVM could otherwise break parity.
- **Redirects, cookies, HTTP/2:** Mark **out of scope** in **02** unless explicitly implemented and tested in this story.
- **56 vs 66:** If **56** lands with only GET, **66** should not rewrite **56**’s tasks; add acceptance rows that reference **both** sequences during transition.
- Detailed **Tasks**, **Tests to add**, and **Documentation and specs to update** belong in **`planned/`** when promoted.
