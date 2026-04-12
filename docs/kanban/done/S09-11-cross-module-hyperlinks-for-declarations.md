# Documentation Browser: Cross-File Declaration Hyperlinks

## Sequence: S09-11
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-05, S09-07, S09-10

## Summary

Add hyperlinks from declaration signatures to declarations in dependent modules so developers can navigate through the codebase directly from docs pages. Referenced symbols in signatures should resolve to their target module/declaration docs route when available.

## Current State

Signatures and declaration sections are rendered as static text. Even when referenced declarations exist in the index, users cannot click through and must manually search module pages.

## Relationship to other stories

- Depends on S09-05 (search/index metadata) and S09-07 (route handling and docs serving).
- Complements S09-10 colorization but does not require it for correctness.
- Independent of S09-12 UI spacing and wrapping fixes.

## Goals

1. Resolve type/signature references to indexed declarations in dependent modules.
2. Render clickable links for resolved declarations in signature output.
3. Prefer stable doc routes (`/docs/{module}/{name}`) for cross-module navigation targets.
4. Keep unresolved or external references as plain text without breaking rendering.

## Acceptance Criteria

- When a declaration signature references another indexed declaration, the referenced name is rendered as a hyperlink.
- Clicking a hyperlink navigates to the referenced declaration docs page.
- Links work across module boundaries, including project modules and `kestrel:*` stdlib modules.
- Unresolvable names are rendered safely as non-links, without runtime exceptions.

## Spec References

- docs/specs/07-modules.md
- docs/specs/09-tools.md

## Risks / Notes

- Name resolution for links must account for aliases/import forms to avoid incorrect targets.
- Cyclic references between declarations should not cause recursive render loops.
- Planned-story phase should define deterministic link-priority rules when multiple declarations share the same name.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib doc render | Extend `stdlib/kestrel/dev/doc/render.ks` with link-aware signature rendering that resolves declaration-name tokens to docs routes (`/docs/{module}/{name}`) using indexed module metadata. |
| Stdlib doc markdown token rendering | Add optional token-link hook in `stdlib/kestrel/dev/doc/markdown.ks` so syntax tokenization and hyperlinking share one HTML emission path (no duplicate tokenization logic). |
| Doc server routing | Update `stdlib/kestrel/tools/doc.ks` request dispatch to support stable declaration pages at `/docs/{module}/{name}` and render module pages with global link context. |
| Link resolution determinism | Define deterministic target priority when names collide: prefer declarations in the current module, otherwise first module by sorted module specifier order. |
| Tests | Extend `stdlib/kestrel/dev/doc/render.test.ks` with cross-module link generation and unresolved-name fallback checks; verify `/docs/{module}/{name}` rendering path through route-level behavior in doc tool tests or render-level page tests. |
| Specs/docs | Update `docs/specs/07-modules.md` and `docs/specs/09-tools.md` to document declaration-link behavior, route shape, and unresolved-reference fallback. |

## Tasks

- [x] Add link-aware token rendering hook in `stdlib/kestrel/dev/doc/markdown.ks` so identifier/type tokens can optionally emit `<a href="...">` wrappers while preserving existing token class spans.
- [x] Implement deterministic declaration-link resolver in `stdlib/kestrel/dev/doc/render.ks` with priority: current module declaration name, then globally indexed declaration by sorted module spec.
- [x] Update signature rendering in `stdlib/kestrel/dev/doc/render.ks` to emit clickable links for resolvable references and plain tokenized text for unresolved names.
- [x] Add `renderModuleWithLinks` / declaration-page rendering support in `stdlib/kestrel/dev/doc/render.ks` for `/docs/{module}/{name}` outputs.
- [x] Update `stdlib/kestrel/tools/doc.ks` dispatch to serve `/docs/{module}` and `/docs/{module}/{name}` distinctly, including declaration-not-found behavior.
- [x] Ensure cross-module links work for both `kestrel:*` and `project:*` modules from the shared in-memory module index.
- [x] Add/extend tests in `stdlib/kestrel/dev/doc/render.test.ks` for cross-module signature links, deterministic collision behavior, and unresolved-name non-link fallback.
- [x] Add/extend doc-server behavior tests for `/docs/{module}/{name}` routing if route-level tests exist; otherwise add render-level declaration-page assertions and note route validation via integration run.
- [x] Update `docs/specs/07-modules.md` to note docs-browser declaration linking behavior relative to module-qualified names.
- [x] Update `docs/specs/09-tools.md` to document `/docs/{module}/{name}` behavior and cross-module signature hyperlink semantics.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Resolved reference in a signature links to `/docs/{module}/{name}` across modules (including `kestrel:*` and `project:*` style module specs). |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Name-collision priority is deterministic (current module first; otherwise sorted-module fallback). |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Unresolvable names remain plain non-link text; no exceptions or malformed HTML. |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Declaration-page rendering path for `/docs/{module}/{name}` returns a full page with linked signature output. |

## Documentation and specs to update

- [x] `docs/specs/07-modules.md` - describe how docs signature hyperlinks resolve declarations across module boundaries and how unresolved names are handled.
- [x] `docs/specs/09-tools.md` - document `/docs/{module}/{name}` route behavior and declaration-signature hyperlink semantics.

## Build notes

- 2026-04-12: Added `renderKestrelCodeWithLinks` in `kestrel:dev/doc/markdown` so hyperlinking and syntax-token classes share one rendering path.
- 2026-04-12: Implemented deterministic link target resolution in `kestrel:dev/doc/render`: current module wins for collisions, otherwise first match from module-spec-sorted global index.
- 2026-04-12: Extended doc server dispatch to resolve `/docs/{module}/{name}` by exact module hit first, then final-segment split fallback for declaration pages.
- 2026-04-12: One unresolved-link test initially over-asserted by forbidding any `/docs/` href; narrowed to assert that unresolved type names specifically are not linked.
