# Declaration signature pretty-printer (`kestrel:dev/doc/sig`)

## Sequence: S09-03
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/done/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-04, S09-05, S09-06, S09-07, S09-08

## Summary

Implements `kestrel:dev/doc/sig` — a pure-Kestrel module that takes a `DocEntry` (from
`kestrel:dev/doc/extract`) and produces a formatted, human-readable declaration signature
string. The signature is used both in the rendered HTML (as a syntax-highlighted code block
header) and in the search index (for substring matching against the full signature text).

Examples of target output:
```
fun map<A, B>(list: List<A>, f: A -> B): List<B>
type Option<A> = None | Some(A)
val pi: Float
exception ParseError(String)
```

## Current State

- `kestrel:dev/doc/extract` (S09-01) stores a raw `signature: String` captured from the token
  stream (the declaration head up to `=` or `{`). This raw string may contain excess whitespace
  or comment tokens.
- `kestrel:dev/parser/ast` exports typed AST nodes (`FunDecl`, `TypeDecl`, `ExternFunDecl`,
  `ExternTypeDecl`, `ExceptionDecl`) that could be used as an alternative structured source
  for signature generation.
- No signature pretty-printer exists yet.

## Relationship to other stories

- **Depends on:** S09-01 (provides `DocEntry` with `signature` and declaration kind).
- **Blocks:** S09-04 (HTML renderer calls `sig.format` to display declaration headers).
  S09-05 (search index stores `sig.format` output for signature substring matching).
- **Independent of:** S09-02, S09-06.
- Can be developed in parallel with S09-02 after S09-01 is done.

## Goals

1. Export `format(entry: DocEntry): String` from `kestrel:dev/doc/sig`.
2. Produce readable, normalised signature strings for each `DocKind`:
   - `DKFun` / `DKExternFun`: `fun [async] name<T...>(param: Type, ...): RetType`
   - `DKType`: `type name<T...> = <body summary>` (ADT lists first constructor; alias shows
     full alias type).
   - `DKVal`: `val name: Type`
   - `DKVar`: `var name: Type`
   - `DKException`: `exception name` or `exception name(Type, ...)`
   - `DKExternType`: `extern type name<T...>`
3. Normalise whitespace: collapse internal runs of whitespace to a single space; strip leading
   and trailing whitespace.
4. Truncate very long ADT bodies (> 120 chars) with ` | …` to avoid overflow in page headers.

## Acceptance Criteria

- `format` is exported from `kestrel:dev/doc/sig`.
- For each `DocKind`, the output matches the format described in Goals.
- Truncation rule is applied for ADT type bodies exceeding 120 characters.
- Whitespace in the output is normalised (no double spaces, no leading/trailing).
- Unit tests in `stdlib/kestrel/dev/doc/sig.test.ks` cover each `DocKind` with at least two
  examples: one minimal, one with type parameters.
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- `kestrel:dev/doc/extract` — `DocEntry`, `DocKind` (defined in S09-01).
- `kestrel:dev/parser/ast` — `FunDecl`, `TypeDecl`, `ExternFunDecl`, `ExternTypeDecl`,
  `ExceptionDecl` for structural reference.

## Risks / Notes

- The `signature: String` in `DocEntry` is a raw token-stream excerpt (set in S09-01).
  This story may instead re-parse the header using the AST types if structured access is
  needed for fine-grained formatting. If S09-01's raw capture is good enough, this story
  simply normalises whitespace on that string rather than re-parsing.
- `extern type` declarations with `jvmClass` are not useful to document in full; showing
  just the `extern type name` is sufficient.
- V1 does not need to produce syntax-coloured output — colour is handled by the HTML renderer
  in S09-04 by wrapping the signature in a `<pre><code class="kestrel">` block with CSS styling.

## Impact analysis

| Area | Change |
|------|--------|
| Stdlib (new module) | `stdlib/kestrel/dev/doc/sig.ks` — `format(entry: DocEntry): String` |
| Tests (new) | `stdlib/kestrel/dev/doc/sig.test.ks` — unit tests |
| Specs | None required |

## Tasks

- [x] Create `stdlib/kestrel/dev/doc/sig.ks` with `format(entry: DocEntry): String`
- [x] Normalise whitespace and apply 120-char truncation
- [x] Create `stdlib/kestrel/dev/doc/sig.test.ks` with unit tests for each `DocKind`
- [x] Run `./kestrel test`

## Tests to add

| Layer | Path | Intent |
|-------|------|--------|
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKFun` minimal signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKFun` with type parameters |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKType` minimal |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKVal` signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKVar` signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKException` signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKExternFun` signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | `DKExternType` signature |
| Kestrel harness | `stdlib/kestrel/dev/doc/sig.test.ks` | Long signature is truncated at 120 chars |

## Documentation and specs to update

- None.

## Build notes

- 2025-03-07: `entry.signature` from S09-01 is already whitespace-normalised by
  `normalizeWs` in `extract.ks`. The `format` function simply trims and applies the
  120-char truncation rule. No re-parsing is needed.
- 14 unit tests pass; 1548 Kestrel tests pass.
