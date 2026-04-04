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

- [ ] New stdlib module documented in **`docs/specs/02-stdlib.md`** (section name and exports fixed in **planned**).
- [ ] **`docs/specs/07-modules.md`** §4.2 lists the new **`kestrel:…`** specifier alongside other stdlib names.
- [ ] At least: **register GET/POST (or any two methods)** routes, **path with one path parameter or wildcard** (exact pattern syntax specified in **02**), and a **JSON** or **plain text** response E2E test.
- [ ] **Unit tests** in `tests/unit/*.test.ks` for route matching edge cases (trailing slash, method mismatch) per **02** semantics.
- [ ] **No** new runtime primitives unless **planned** documents why Kestrel cannot implement the router (goal: **zero** new primitives preferred).
- [ ] **JVM** runs the **`.ks`** implementation (pure Kestrel routing logic with no backend divergence required).

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
