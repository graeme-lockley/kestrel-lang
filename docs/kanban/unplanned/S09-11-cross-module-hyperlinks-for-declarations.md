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
