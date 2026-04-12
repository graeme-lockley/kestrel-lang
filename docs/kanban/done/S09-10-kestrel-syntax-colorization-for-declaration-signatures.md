# Documentation Browser: Kestrel Colorization for Declarations

## Sequence: S09-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/done/E09-documentation-browser.md)
- Companion stories: S09-03, S09-04, S09-07, S09-09

## Summary

Render declaration signatures in docs pages with the same token colorization style used for Kestrel code blocks. Declaration headers should visually match fenced kestrel snippets so keywords, type identifiers, punctuation, and literals are consistently readable.

## Current State

Declaration signatures are currently rendered as plain text or minimally styled inline code. This makes signature scanning harder and visually diverges from existing Kestrel code block styling already present in docs pages.

## Relationship to other stories

- Depends on S09-04 (HTML generation) and S09-07 (doc server output path).
- Benefits from S09-09 when inferred val/var type text is available.
- Can ship independently from S09-11 and S09-12.

## Goals

1. Apply Kestrel token-level color classes to declaration signatures in module and declaration views.
2. Reuse existing highlighting paths or tokenization logic to avoid a separate, inconsistent highlighter.
3. Keep rendered signatures accessible (sufficient contrast and readable when color is unavailable).
4. Ensure syntax colorization remains stable for common declaration forms (fun, val, var, type aliases, ADTs).

## Acceptance Criteria

- Declaration signatures are colorized in docs output with the same style family used by Kestrel code blocks.
- Colorization works for at least fun, val, var, and type declaration headers.
- HTML output remains valid and readable with CSS disabled (plain text fallback still understandable).
- Existing Markdown-rendered code blocks remain unchanged by this story.

## Spec References

- docs/specs/09-tools.md

## Risks / Notes

- Reusing existing syntax-highlighting CSS may require consolidating static asset loading for docs pages.
- Any server-side tokenization pass should be bounded to avoid regressions in page generation latency.
- Planned-story phase should define snapshot coverage for representative declaration signatures.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib doc markdown renderer | Export or factor shared Kestrel token-to-HTML rendering in `stdlib/kestrel/dev/doc/markdown.ks` so declaration signatures can reuse the exact token class mapping used by fenced `kestrel` code blocks. |
| Stdlib doc page renderer | Update `stdlib/kestrel/dev/doc/render.ks` signature rendering to emit tokenized HTML spans for declaration signatures (`fun`, `val`, `var`, `type`) while keeping readable plain text when CSS is disabled. |
| Static CSS | Reuse existing `.tok-*` styles in `staticCss()`; only adjust selector coverage if necessary so declaration signature blocks and markdown code fences share one visual style family. |
| Tests | Extend `stdlib/kestrel/dev/doc/render.test.ks` and (if shared helper changes) `stdlib/kestrel/dev/doc/markdown.test.ks` to assert declaration signature token spans and plain-text readability invariants. |
| Specs/docs | Update `docs/specs/09-tools.md` to describe syntax-colorized declaration signatures in docs HTML output and confirm markdown fenced block behavior is unchanged. |

## Tasks

- [x] Refactor `stdlib/kestrel/dev/doc/markdown.ks` to expose a reusable Kestrel code-token rendering helper used by both fenced markdown blocks and declaration signature rendering.
- [x] Update `stdlib/kestrel/dev/doc/render.ks` `renderEntry` signature output to use shared Kestrel tokenized HTML (not plain escaped text) for declaration signatures.
- [x] Ensure `renderModule` and `renderDeclaration` both render the same colorized signature output path for `fun`, `val`, `var`, and `type` entries.
- [x] Keep no-CSS readability by preserving literal source text in signature HTML output (only wrapped with semantic spans).
- [x] Confirm markdown-rendered fenced code blocks are unchanged in structure/class naming after shared-renderer refactor.
- [x] Add/extend declaration colorization tests in `stdlib/kestrel/dev/doc/render.test.ks` for `fun`, `val`, `var`, and `type` signature token spans.
- [x] Add/extend markdown renderer tests in `stdlib/kestrel/dev/doc/markdown.test.ks` if shared helper extraction changes fenced block rendering behavior.
- [x] Update `docs/specs/09-tools.md` to document syntax-colorized declaration signatures in docs pages.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Assert declaration signatures include expected token span classes (`tok-kw`, `tok-type`, `tok-op`, `tok-punct`, `tok-lit`) across representative `fun`/`val`/`var`/`type` declarations. |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Assert signature blocks still contain human-readable declaration text in source order (CSS-off readability). |
| Kestrel harness | `stdlib/kestrel/dev/doc/markdown.test.ks` | Regression-check fenced `kestrel` code block output remains unchanged after sharing token rendering helper. |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` - describe docs-page declaration signature syntax colorization and confirm fenced markdown code block behavior is unchanged.

## Build notes

- 2026-04-12: Reused the existing markdown lexer token renderer by exporting `renderKestrelCode` from `kestrel:dev/doc/markdown` and piping declaration signatures through it in `renderEntry`.
- 2026-04-12: Signature rendering now uses the exact `.tok-*` class family already used by fenced `kestrel` markdown blocks, so theme behavior stays consistent across docs surfaces.
- 2026-04-12: Updated render tests to assert tokenized HTML semantics instead of raw plain-string adjacency, since syntax spans intentionally split keyword/punctuation text nodes.
