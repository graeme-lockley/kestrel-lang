# Documentation Browser: Infer Exported val/var Types

## Sequence: S09-09
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-07

## Summary

Extend the documentation index pipeline so exported val and var declarations include inferred types in their doc signatures, even when no explicit type annotation is present in source. The docs browser should show the same inferred type shape developers see in compiler diagnostics and hover tooling.

## Current State

The current doc pipeline can format declaration signatures, but exported val/var declarations without explicit type annotations may display incomplete or generic signatures. This creates an information gap versus compiler output and makes docs less useful for API consumers.

## Relationship to other stories

- Depends on S09-03 (declaration signature pretty-printer) and S09-07 (doc server integration).
- Enables better usability for S09-10 (syntax-colorized declarations) by ensuring complete type text exists to highlight.
- Independent of S09-12 (index layout polish).

## Goals

1. Ensure exported val/var declarations always carry a resolved type string in the extracted doc model.
2. Use type inference when source declarations omit explicit annotation.
3. Keep formatting consistent with existing signature rendering output for functions and annotated bindings.
4. Expose inferred type details through both HTML views and JSON index output.

## Acceptance Criteria

- Exported val declarations without explicit type annotations show inferred types in module and declaration docs pages.
- Exported var declarations without explicit type annotations show inferred types in module and declaration docs pages.
- `/api/index` includes inferred type strings for affected declarations.
- If inference fails for an exported binding, the docs output is stable and includes a clear fallback marker instead of crashing.

## Spec References

- docs/specs/06-typesystem.md
- docs/specs/09-tools.md

## Risks / Notes

- Type inference work in docs must not duplicate compiler logic in a divergent way; prefer reusing canonical type rendering/typecheck output paths.
- Inference for mutually recursive exports may require explicit ordering or additional metadata from existing compiler phases.
- Any new fallback marker for unresolved types should be documented in planned-story docs updates.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib doc extract | Update `stdlib/kestrel/dev/doc/extract.ks` so exported `val`/`var` entries without explicit annotations get inferred type text in `DocEntry.signature`, using canonical parser/typecheck paths instead of ad-hoc inference. |
| Stdlib doc index | Keep `stdlib/kestrel/dev/doc/index.ks` JSON/search output stable while carrying inferred signature text through `Sig.format` and `toFullJson`; add deterministic fallback marker for unresolved inference. |
| Stdlib doc render | Verify `stdlib/kestrel/dev/doc/render.ks` module/declaration pages display inferred signatures for unannotated exports with no template changes required beyond compatibility checks. |
| Tests | Extend `stdlib/kestrel/dev/doc/extract.test.ks`, `stdlib/kestrel/dev/doc/index.test.ks`, and `stdlib/kestrel/dev/doc/render.test.ks` with inferred `val`/`var` coverage and unresolved-inference fallback assertions. |
| Specs/docs | Update `docs/specs/06-typesystem.md` and `docs/specs/09-tools.md` to document docs-browser inferred export signature behavior and unresolved-type fallback semantics in API/HTML outputs. |

## Tasks

- [ ] Update `stdlib/kestrel/dev/doc/extract.ks` to detect exported `val`/`var` declarations with missing type annotations and resolve an inferred type string via existing canonical typecheck/type-rendering utilities.
- [ ] Add a stable fallback marker for unresolved exported binding inference and ensure extractor output remains deterministic and non-crashing.
- [ ] Confirm `stdlib/kestrel/dev/doc/index.ks` preserves inferred/fallback signatures through `Sig.format`, `query`, and `toFullJson` payloads for `/api/index`.
- [ ] Verify `stdlib/kestrel/dev/doc/render.ks` module and declaration rendering paths surface inferred/fallback signatures for exported `val`/`var` entries.
- [ ] Add/extend doc extractor tests in `stdlib/kestrel/dev/doc/extract.test.ks` for inferred exported `val` and `var` signatures, plus unresolved-inference fallback behavior.
- [ ] Add/extend index JSON tests in `stdlib/kestrel/dev/doc/index.test.ks` to assert `/api/index`-equivalent payload includes inferred/fallback signatures.
- [ ] Add/extend render tests in `stdlib/kestrel/dev/doc/render.test.ks` to assert inferred signatures appear in HTML output for unannotated exported `val`/`var` declarations.
- [ ] Update `docs/specs/06-typesystem.md` with a note that docs tooling presents inferred types for unannotated exported bindings using compiler inference.
- [ ] Update `docs/specs/09-tools.md` (`kestrel doc` and `/api/index` sections) to document inferred binding signatures and unresolved fallback marker behavior.
- [ ] Run `cd compiler && npm run build && npm test`.
- [ ] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/extract.test.ks` | `export val` / `export var` without annotation produce inferred type text in `DocEntry.signature`; unresolved cases emit the documented fallback marker. |
| Kestrel harness | `stdlib/kestrel/dev/doc/index.test.ks` | `toFullJson(build(...))` includes inferred/fallback signature strings for unannotated exported bindings. |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | `renderModule`/`renderDeclaration` include inferred/fallback signature text for unannotated exported bindings in `<pre><code>`. |

## Documentation and specs to update

- [ ] `docs/specs/06-typesystem.md` - document that docs browser signatures for unannotated exported bindings are produced from compiler inference output (including limitations where inference cannot resolve).
- [ ] `docs/specs/09-tools.md` - update `kestrel doc` and `/api/index` behavior to specify inferred exported `val`/`var` signatures and the unresolved fallback marker.
