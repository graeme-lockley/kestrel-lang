# kestrel:dev/text/prettyprinter — Wadler–Lindig Doc IR

## Sequence: S08-04
## Tier: 8 — Developer tooling / formatter epic
## Former ID: (none)

## Epic

- Epic: [E08 Source Formatter (`kestrel fmt`)](../epics/done/E08-source-formatter.md)
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
- Use `List<(Int, Bool, Doc)>` as the work queue (no separate WorkItem type needed; access via `.0`, `.1`, `.2`).
- `FlatAlt` and `Concat` are two-parameter constructors; both params are bound via positional patterns `Concat(x, y)`.

---

## Impact analysis

| Area | Change |
|------|--------|
| `stdlib/kestrel/dev/text/prettyprinter.ks` | New file: `Doc` ADT, `pretty`, and all combinators |
| `stdlib/kestrel/dev/text/prettyprinter.test.ks` | New file: unit tests |
| `docs/specs/02-stdlib.md` | Add `kestrel:dev/text/prettyprinter` section |

## Tasks

- [x] Create `stdlib/kestrel/dev/text/prettyprinter.ks` with `Doc` ADT and full implementation
- [x] Create `stdlib/kestrel/dev/text/prettyprinter.test.ks` with unit tests
- [x] Add `kestrel:dev/text/prettyprinter` section to `docs/specs/02-stdlib.md`
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Stdlib unit | `stdlib/kestrel/dev/text/prettyprinter.test.ks` | pretty, group, nest, line, combinators |

## Documentation and specs to update

- [x] `docs/specs/02-stdlib.md` — add `kestrel:dev/text/prettyprinter` section

## Build notes

2025-03-07: Implementation written using Wadler–Lindig work-queue algorithm (`fitsQ` + `formatQ`). Three bugs fixed during development:

1. **`h :: []` ConsPattern JVM codegen bug** (compiler): The JVM codegen for `ConsPattern` only checked `instanceof K_CONS` but never verified the tail was `K_NIL`. Any non-empty list matched `h :: []`. Fixed in `compiler/src/jvm-codegen/codegen.ts` by adding an `instanceof K_NIL` check on the tail when the tail pattern is an empty ListPattern. A stackmap frame bug was also fixed: the fall-through frame for the IFEQ must NOT use `addBranchTarget(ifeqTailNil + 3, matchBaseState)` — that stale frame (before `h` is bound) triggers a `VerifyError: Bad local variable type` at runtime. Conformance test added at `tests/conformance/runtime/valid/cons_pattern_singleton.ks`.

2. **`sep` parameter shadowing export** (stdlib): Naming the `punctuate` parameter `sep` shadowed the exported `PP.sep` function in the module namespace. Renamed to `separator`.

3. **`fitsQ` Line termination** (stdlib): `fitsQ` was returning `True` immediately upon encountering any `Line` or `LineBreak`, regardless of mode. This caused `Group` to always choose flat layout (since "fits" was always true). Fixed to respect the flat/broken mode flag: in flat mode, `Line` costs 1 column and `LineBreak` costs 0; in broken mode both terminate the fit check with `True` (newline ends the current line).

4. **`nest` test structure**: The test for nest used `concat(line, nest(2, text("42")))` but `nest(n, d)` only increases indent for content inside `d` — the `line` was outside the nest and saw indent 0. Correct form: `nest(2, concat(line, text("42")))` so the line is rendered with the new indent.
