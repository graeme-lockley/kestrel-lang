# Documentation Browser: Kestrel Colorization for Declarations

## Sequence: S09-10
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser (kestrel doc)](../epics/unplanned/E09-documentation-browser.md)
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
