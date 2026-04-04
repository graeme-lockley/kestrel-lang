# Lightweight web routing framework (Sinatra-style)

## Sequence: S03-04
## Tier: 8 — Networking expansion (post–HTTP baseline)
## Former ID: (none)

## Epic

- Epic: [E03 HTTP and Networking Platform](../epics/unplanned/E03-http-and-networking-platform.md)
- Companion stories: S03-01, S03-05, S03-06, S03-03

## Summary

Add a **small, opinionated** standard library module (working name **`kestrel:web`**—final name set in **planned** and reflected in **02**/**07**) that sits **on top of** `kestrel:http` and provides **route matching** (method + path patterns), optional **filters** (before/after hooks), and **ergonomic handlers** for building **HTML** and **JSON/REST** servers without boilerplate. The implementation should be **mostly Kestrel source** (`.ks`) using **`kestrel:http`**’s `createServer` / `listen` and **`kestrel:json`** where appropriate; only add JVM primitives if the language cannot express the router.

## Current State

- No spec-defined routing or DSL above **`kestrel:http`**.
- **`kestrel:http`** (after **60**) provides low-level **request → Task response** handling; **69** improves **client** REST ergonomics—**70** focuses on **server** composition.
- Sinatra-like frameworks in other languages combine **routing + short handlers**; Kestrel needs a **documented** module so examples and tests stay portable across JVM deployments.

## Relationship to other stories

- **Depends on S03-06** (`kestrel:http` server path: `createServer`, `listen`, `Request`/`Response`).
- **Soft dependency on S03-03** if handlers need rich response helpers (status, JSON body) that align with client types.
- **Independent of S03-02** (`kestrel:socket`) unless WebSockets are added (out of scope).
- **S03-05** is indirectly useful for writing E2E tests (use `get` to hit the routing server).

## Goals

1. Users can write a **multi-route** HTTP server in **under a page** of Kestrel using the new module’s API.
2. **Path patterns** and **HTTP methods** are matched deterministically; **unmatched** routes produce a **documented** default (e.g. 404) in the reference implementations.
3. The module is **stdlib**-backed (bundled `.kbc` or equivalent) with **no** divergence in **routing logic** — only **http** primitives differ in the JVM runtime underneath.
4. Examples in **specs** or **`docs/`** (as listed in **planned**) stay in sync with the API so tutorials do not drift.

## Acceptance Criteria

- [x] New stdlib module documented in **`docs/specs/02-stdlib.md`** (section name and exports fixed in **planned**).
- [x] **`docs/specs/07-modules.md`** §4.2 lists the new **`kestrel:web`** specifier alongside other stdlib names.
- [x] At least: **register GET/POST (or any two methods)** routes, **path with one path parameter or wildcard** (exact pattern syntax specified in **02**), and a **JSON** or **plain text** response E2E test.
- [x] **Unit tests** in `stdlib/kestrel/web.test.ks` for route matching edge cases (method mismatch, 404, 405, path params) per **02** semantics.
- [x] **No** new runtime primitives for routing — pure Kestrel routing logic; only `requestMethod`/`requestPath` added to `kestrel:http`.
- [x] **JVM** runs the **`.ks`** implementation (pure Kestrel routing logic).

## Spec References

Normative and supporting docs for a consistent solution:

- **`docs/specs/02-stdlib.md`** — New § for **`kestrel:web`** (or chosen name): types (`Router`, `Route`, etc.), registration functions, default 404/error behaviour, interaction with **`kestrel:http`** `Request`/`Response`.
- **`docs/specs/07-modules.md`** — §4.2 stdlib name list and §2 cross-reference to **02**.
- **`docs/specs/08-tests.md`** — If stdlib coverage lists modules to hit in harness tests, include the new module.
- **`docs/specs/01-language.md`** — Only if the story introduces **new** surface syntax (unlikely); prefer pure library API.

## Risks / Notes

- **Scope creep:** Sinatra has many features (templates, sessions, middleware stacks). S03-04 must stay **lightweight**; defer templates/sessions to future stories and say so in **02**.
- **Type system:** Path params may require **string** extraction only in v1; typed path segments are a possible follow-up.
- **Performance:** Pure-Kestrel routing is fine for small services; document **O(n)** vs trie trade-offs if relevant.
- **Name collision:** If **`kestrel:web`** is reserved before implementation, document in **07** as **future stdlib** or implement immediately — avoid half-reserved names.

## Tests to add

### Kestrel unit tests (`tests/unit/web-routing.test.ks` or `stdlib/kestrel/web.test.ks`)

| Test name | What it does |
|-----------|---------------|
| `GET route matches exact path` | Registers `GET /hello`; fires a synthetic request; asserts handler called and response status 200 |
| `POST route matches exact path` | Registers `POST /submit`; fires POST; asserts correct handler called |
| `Method mismatch returns 405` | Registers only `GET /foo`; fires `POST /foo`; asserts status 405 (or documented default) |
| `Unmatched path returns 404` | No route for `/missing`; asserts status 404 |
| `Path parameter extracted correctly` | Registers `GET /user/:id`; fires `GET /user/42`; asserts handler receives `id = "42"` |
| `Trailing slash treated per spec` | Registers `/foo`; fires `/foo/`; asserts documented match or 404 behaviour |
| `Before-filter runs before handler` | Registers a before-filter that appends to a mutable list; asserts filter ran before handler |

### E2E scenarios

| File | What it tests | How |
|------|---------------|-----|
| `tests/e2e/scenarios/positive/web-router-basic.ks` | Multi-route server with GET and POST | Starts a router on `127.0.0.1:0`; uses `kestrel:http`'s `get` to hit `GET /hello` (asserts `"Hello"`) and a `POST /echo` route (asserts echoed body); shuts down cleanly |
| `tests/e2e/scenarios/positive/web-router-path-param.ks` | Path parameter extraction | Registers `GET /greet/:name`; calls `http://127.0.0.1:<port>/greet/World`; asserts response is `"Hello World"` |
| `tests/e2e/scenarios/positive/web-router-404.ks` | Default 404 behaviour | Calls an unregistered path; asserts status is 404 |

### Vitest (`compiler/test/`)

| File | Intent |
|------|--------|
| `compiler/test/unit/web-router.test.ts` | `kestrel:web` module resolves; `Router`, `Route` types and registration functions typecheck |
| `compiler/test/integration/web-router.test.ts` | Pure-Kestrel router implementation compiles with no new primitives; no `extern fun` additions expected |

## Documentation and specs to update

- [ ] [docs/specs/02-stdlib.md](../../specs/02-stdlib.md) — New §`kestrel:web` (or chosen name): types (`Router`, `Route`, etc.); registration functions (`get`, `post`, etc.); path parameter syntax; default 404/405 behaviour; interaction with `kestrel:http` `Request`/`Response`; scope limitations (no templates, sessions, WebSockets).
- [ ] [docs/specs/07-modules.md](../../specs/07-modules.md) — §4.2: add `kestrel:web` to the stdlib specifier list with cross-reference to **02**.
- [ ] [docs/specs/08-tests.md](../../specs/08-tests.md) — Extend stdlib coverage rules to include `kestrel:web` where harness tests are expected.

## Tasks

- [x] Create `stdlib/kestrel/web.ks` with `Router` type, `newRouter`, `route`, `get/post/put/delete/patch`, `serve`
- [x] Add `PathSegment` ADT (`Literal`, `Param`, `Wildcard`), `parsePattern`, `matchSegments`, `splitPath`
- [x] Implement `dispatchRequest` with 404/405 logic
- [x] Add `Http.requestMethod` and `Http.requestPath` to `kestrel:http` (requires `KRuntime.java` additions)
- [x] Register `kestrel:web` in `compiler/src/resolve.ts` `STDLIB_NAMES`
- [x] Create `stdlib/kestrel/web.test.ks` with 13 integration tests (GET/POST route, 404, 405, path params, multi-param, wildcard, root 404)
- [x] Create `.kestrel_web_only.ks` test runner
- [x] Create E2E scenario `web-router-basic.ks` (covers GET, POST, 404, 405)
- [x] Create E2E scenario `web-router-path-param.ks` (single + multi path params)
- [x] Update `docs/specs/02-stdlib.md` with `kestrel:web` section
- [x] Update `docs/specs/07-modules.md` §4.2 to include `kestrel:web`
- [x] Fix four JVM codegen bugs discovered during implementation

## Build Notes

**2025 — Implementation:**

**Module design:** `kestrel:web` is a pure Kestrel implementation (`stdlib/kestrel/web.ks`) with no new JVM primitives for routing itself. The only new JVM primitives added were `httpRequestMethod` and `httpRequestPath` in `KRuntime.java`, which are logically part of `kestrel:http` (S03-03) but needed here too.

**Dispatch model:** `serve(router)` returns a non-async lambda `(req) => dispatchRequest(router, req)`. The lambda must be non-async because `async (req) => asyncFun(req)` wraps the result in `Task<Task<Response>>` causing a type error. `dispatchRequest` is an `async fun` which returns `Task<Http.Response>` directly.

**Route matching:** First-match-wins O(n) linear scan. `findRoute` + `hasPathMatch` provide 405 vs 404 distinction. Wildcard `*` tail-matches (short-circuit on first `Wildcard` segment). `RouteMatch` ADT used internally to package matched route + params.

**Handler signature:** `(Http.Request, Dict<String, String>) -> Task<Http.Response>` where the second argument is extracted path parameters as a string dict.

**Four JVM codegen bugs fixed during this story:**
1. `collectLambdas`/`getFreeVars` didn't add pattern variables (from `match` arms, `try` catch patterns) to scope — fixed by adding `collectPatternVars` helper and using it in both passes.
2. `ConsPattern` head emitter only handled `VarPattern`, not `ConstructorPattern` — fixed with INSTANCEOF check + field binding.
3. Nested `ConstructorPattern` fields (e.g. `Some(Foo(s,n))`) not handled — added `emitSubPatternBindings` recursive helper.
4. Parameter name `request` in `http.ks` extern fun shadowed the exported `async fun request` — renamed extern params to `req`.

**Pre-existing typecheck bug (not fixed, workaround applied):** Sequential lambdas with the same parameter name in an outer lambda body cause "Unknown variable" error. Workaround in `web.test.ks`: use different names (`s1`, `sg`) for sibling lambdas.

**Tests:** 13 unit tests in `web.test.ks` via `.kestrel_web_only.ks`, 2 E2E scenarios (20 total E2E positive scenarios). All 339 compiler tests, 1040+ Kestrel unit tests, and 20 E2E scenarios pass.
