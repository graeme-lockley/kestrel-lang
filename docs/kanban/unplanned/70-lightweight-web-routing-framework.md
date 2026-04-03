# Lightweight web routing framework (Sinatra-style)

## Sequence: 70
## Tier: 8 — Networking expansion (post–HTTP baseline)
## Former ID: (none)

## Summary

Add a **small, opinionated** standard library module (working name **`kestrel:web`**—final name set in **planned** and reflected in **02**/**07**) that sits **on top of** `kestrel:http` and provides **route matching** (method + path patterns), optional **filters** (before/after hooks), and **ergonomic handlers** for building **HTML** and **JSON/REST** servers without boilerplate. The implementation should be **mostly Kestrel source** (`.ks`) using **`kestrel:http`**’s `createServer` / `listen` and **`kestrel:json`** where appropriate; only add VM/JVM primitives if the language cannot express the router.

## Current State

- No spec-defined routing or DSL above **`kestrel:http`**.
- **`kestrel:http`** (after **60**) provides low-level **request → Task response** handling; **69** improves **client** REST ergonomics—**70** focuses on **server** composition.
- Sinatra-like frameworks in other languages combine **routing + short handlers**; Kestrel needs a **documented** module so examples and tests stay portable across VM and JVM.

## Relationship to other stories

- **Depends on** sequence **60** (`kestrel:http` server path: `createServer`, `listen`, `Request`/`Response`).
- **Soft dependency** on sequence **69** if handlers need rich **response** helpers (status, JSON body) that align with client types—**planned** should order **70** after **60** minimum, and after **69** if shared **Response** builders are required.
- **Depends on** sequence **59** indirectly through **60** (async server).
- **Independent of** sequence **68** (`kestrel:socket`) unless the framework later supports **WebSockets** (out of scope unless added as a follow-up).

## Goals

1. Users can write a **multi-route** HTTP server in **under a page** of Kestrel using the new module’s API.
2. **Path patterns** and **HTTP methods** are matched deterministically; **unmatched** routes produce a **documented** default (e.g. 404) in the reference implementations.
3. The module is **stdlib**-backed (bundled `.kbc` or equivalent) with **no** VM/JVM divergence in **routing logic**—only **http** primitives differ underneath.
4. Examples in **specs** or **`docs/`** (as listed in **planned**) stay in sync with the API so tutorials do not drift.

## Acceptance Criteria

- [ ] New stdlib module documented in **`docs/specs/02-stdlib.md`** (section name and exports fixed in **planned**).
- [ ] **`docs/specs/07-modules.md`** §4.2 lists the new **`kestrel:…`** specifier alongside other stdlib names.
- [ ] At least: **register GET/POST (or any two methods)** routes, **path with one path parameter or wildcard** (exact pattern syntax specified in **02**), and a **JSON** or **plain text** response E2E test.
- [ ] **Unit tests** in `tests/unit/*.test.ks` for route matching edge cases (trailing slash, method mismatch) per **02** semantics.
- [ ] **No** new VM primitives unless **planned** documents why Kestrel cannot implement the router (goal: **zero** new primitives preferred).
- [ ] **JVM and VM** both run the same **`.ks`** implementation (or document any unavoidable divergence—default is **none**).

## Spec References

Normative and supporting docs for a consistent solution:

- **`docs/specs/02-stdlib.md`** — New § for **`kestrel:web`** (or chosen name): types (`Router`, `Route`, etc.), registration functions, default 404/error behaviour, interaction with **`kestrel:http`** `Request`/`Response`.
- **`docs/specs/07-modules.md`** — §4.2 stdlib name list and §2 cross-reference to **02**.
- **`docs/specs/08-tests.md`** — If stdlib coverage lists modules to hit in harness tests, include the new module.
- **`docs/specs/01-language.md`** — Only if the story introduces **new** surface syntax (unlikely); prefer pure library API.

## Risks / Notes

- **Scope creep:** Sinatra has many features (templates, sessions, middleware stacks). **70** should stay **lightweight**; defer templates/sessions to future stories and say so in **02**.
- **Type system:** Path params may require **string** extraction only in v1; typed path segments are a possible follow-up.
- **Performance:** Pure-Kestrel routing is fine for small services; document **O(n)** vs trie trade-offs if relevant.
- **Name collision:** If **`kestrel:web`** is reserved before implementation, document in **07** as **future stdlib** or implement immediately—avoid half-reserved names.
- Detailed **Tasks**, **Tests to add**, and **Documentation and specs to update** belong in **`planned/`** when promoted.
