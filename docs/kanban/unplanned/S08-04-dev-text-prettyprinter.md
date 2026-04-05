# kestrel:dev/text/prettyprinter — Wadler–Lindig Doc IR

## Sequence: S08-04
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/unplanned/E08-source-formatter.md)
- Companion stories: S08-01, S08-02, S08-03, S08-05, S08-06, S08-07

## Summary

Create `stdlib/kestrel/dev/text/prettyprinter.ks` — a Wadler–Lindig combinatorial pretty-printer. It provides a `Doc` ADT and a `pretty : Int -> Doc -> String` rendering function that lays out documents at a given column width. The formatter (S08-07) uses this to convert the Kestrel AST into canonical source text at 120 columns.

This is a pure Kestrel library; no TypeScript, Java, or compiler changes are required.

## Current State

No pretty-printing library exists in the stdlib. All formatted output is currently produced by manual string concatenation.

## Relationship to other stories

- **Depends on** S08-01 (namespace restructure) because `prettyprinter.ks` imports from `kestrel:data/string`, `kestrel:data/list`.
- **Required by** S08-07 (kestrel:tools/format).
- **Independent of** S08-03 (dev/cli) and S08-05 (dev/parser).

## Goals

1. Implement the `Doc` ADT:
   ```
   type Doc = Empty | Text(String) | Concat(Doc, Doc) | Nest(Int, Doc)
            | Line | LineBreak | Group(Doc) | FlatAlt(Doc, Doc)
   ```
2. Implement `pretty : Int -> Doc -> String` using the Wadler–Lindig algorithm.
3. Provide combinators: `empty`, `text`, `concat`, `nest`, `line`, `lineBreak`, `group`, `flatAlt`, `<+>` (space-separated), `</>` (line-separated), `vsep`, `hsep`, `sep`, `hcat`, `vcat`, `indent`, `hang`, `align`, `punctuate`.
4. `Group(d)` tries to render `d` flat (replacing `Line` with a space); falls back to broken layout if it does not fit within the column width.

## Acceptance Criteria

- `pretty 80 (group (text "hello" <> line <> text "world"))` produces `"hello world"` when it fits; `"hello\nworld"` when it does not.
- `pretty 120 (nest 2 (text "fun f =" <> line <> text "42"))` produces the indented layout.
- Idempotent: `pretty w (parse (pretty w doc)) == pretty w doc` (given the formatter story).
- Unit tests in `stdlib/kestrel/dev/text/prettyprinter.test.ks` pass.

## Spec References

- `docs/specs/02-stdlib.md` — stdlib public API

## Risks / Notes

- The Wadler–Lindig algorithm is described in "A prettier printer" (Wadler 1998) and "Linear, bounded, functional pretty-printing" (Lindig 2000). Implement the simpler Lindig variant (scan-then-print with a deque or continuation approach).
- `Line` renders as a newline in broken mode and as a space in flat mode. `LineBreak` renders as a newline in broken mode and as `""` (empty) in flat mode. `FlatAlt(broken, flat)` allows specifying a different flat rendering.
- The `Doc` ADT may need to be represented as a recursive type; Kestrel supports recursive types natively.
- The `pretty` function processes a sequence of `(indent, flat, doc)` triples; the algorithm is O(n) in output size.
- Implement using a tail-recursive helper or continuation-passing to avoid stack overflow on deeply nested documents.
