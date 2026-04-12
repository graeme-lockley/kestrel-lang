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
