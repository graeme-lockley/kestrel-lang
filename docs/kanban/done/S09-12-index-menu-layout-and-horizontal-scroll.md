# Documentation Browser: Index Menu Non-Wrapping Layout

## Sequence: S09-12
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-04, S09-07, S09-10, S09-11

## Summary

Polish the docs index menu layout so declaration rows do not wrap, support horizontal scrolling for long signatures/names, and tighten the spacing between declaration kind and declaration name for denser scanning.

## Current State

In the index menu, long declarations can wrap to additional lines. This reduces readability and causes misalignment in lists. The visual gap between declaration type and name is also wider than needed, making the index harder to scan quickly.

## Relationship to other stories

- Depends on S09-04 (HTML generation output structure).
- Can be implemented independently from S09-09 through S09-11.
- Improves the presentation of whichever signature content is available from S09-09 and S09-10.

## Goals

1. Keep declaration rows in the index menu on a single line.
2. Allow horizontal scrolling in the index container when content exceeds width.
3. Reduce excessive spacing between declaration kind token and declaration name.
4. Preserve responsive behavior for narrow screens without truncating essential identifier text by default.

## Acceptance Criteria

- Index menu declaration rows do not wrap under normal rendering.
- The index view provides horizontal scrolling for overflowed declaration text.
- Spacing between declaration kind and declaration name is visibly reduced and consistent.
- Desktop and mobile layouts remain usable; no overlapping text or hidden focus states.

## Spec References

- docs/specs/09-tools.md

## Risks / Notes

- CSS changes should avoid regressing module page declaration layouts outside the index menu.
- Horizontal scroll behavior must preserve keyboard accessibility and visible focus indicators.
- Planned-story phase should include viewport-specific checks for small-screen readability.

## Impact analysis

| Area | Change |
|------|--------|
| Docs CSS layout | Update `stdlib/kestrel/dev/doc/render.ks` `staticCss()` rules for `.decl-index`, `.decl-index a`, and `.idx-kind` to enforce non-wrapping index rows, horizontal overflow support, and tighter kind/name spacing. |
| Accessibility and responsiveness | Ensure horizontal overflow remains keyboard-usable (focus-visible outline, no clipped focus ring) and mobile breakpoints keep sidebar/index readable without overlap. |
| Render tests | Extend `stdlib/kestrel/dev/doc/render.test.ks` to assert emitted CSS includes non-wrapping index-row and horizontal-scroll declarations. |
| Specs/docs | Update `docs/specs/09-tools.md` docs-browser styling description for index behavior (single-line entries + horizontal scroll overflow handling). |

## Tasks

- [x] Update `.decl-index` CSS in `stdlib/kestrel/dev/doc/render.ks` to support horizontal scrolling for overflowed index content while retaining vertical scroll for long lists.
- [x] Update `.decl-index a` CSS to keep each index row on one line (`white-space` behavior) and avoid declaration-name wrapping.
- [x] Tighten `.idx-kind` spacing/width so kind labels and names are denser but still aligned.
- [x] Add explicit focus-visible styling for `.decl-index a` so keyboard navigation remains visible in overflow scenarios.
- [x] Validate media-query behavior in `staticCss()` for narrow screens to avoid overlap/truncation regressions.
- [x] Add/extend `stdlib/kestrel/dev/doc/render.test.ks` CSS assertions for index non-wrapping, horizontal overflow, and focus visibility rules.
- [x] Update `docs/specs/09-tools.md` to document non-wrapping index rows and horizontal-scroll overflow behavior.
- [x] Run `cd compiler && npm run build && npm test`.
- [x] Run `./scripts/kestrel test`.

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Assert generated CSS includes index-row non-wrap rule and horizontal overflow support for `.decl-index`. |
| Kestrel harness | `stdlib/kestrel/dev/doc/render.test.ks` | Assert generated CSS includes visible keyboard focus treatment for `.decl-index a`. |

## Documentation and specs to update

- [x] `docs/specs/09-tools.md` - describe docs index menu single-line row behavior, horizontal overflow scrolling, and keyboard-focus visibility expectations.

## Build notes

- 2026-04-12: Updated docs index CSS to combine vertical scrolling (`overflow-y`) with horizontal overflow (`overflow-x`) so long declaration rows stay single-line and remain reachable.
- 2026-04-12: Switched index links to a non-wrapping flex row with reduced kind-label width (`.idx-kind`) for denser scanning while keeping alignment.
- 2026-04-12: Added `.decl-index a:focus-visible` styles so keyboard focus remains visible even when users scroll horizontally through long index entries.
