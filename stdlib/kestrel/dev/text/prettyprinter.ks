// kestrel:dev/text/prettyprinter — Wadler–Lindig combinatorial pretty-printer.
// Based on "A prettier printer" (Wadler 1998) / Lindig (2000) bounded variant.
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Arr from "kestrel:data/array"

// Direct ArrayList join — avoids Arr.toList KList allocation.
extern fun joinArr(sep: String, parts: Array<String>): String =
  jvm("kestrel.runtime.KRuntime#stringJoinArr(java.lang.Object,java.lang.Object)")

// ─── Doc ADT ──────────────────────────────────────────────────────────────────

/** Document intermediate representation.
 *  Build with the combinators below; render with `pretty(width, doc)`. */
export type Doc =
    Empty
  | Text(String)
  | Concat(Doc, Doc)
  | Nest(Int, Doc)
  | Line
  | LineBreak
  | Group(Doc)
  | FlatAlt(Doc, Doc)

// ─── Internal helpers ─────────────────────────────────────────────────────────

// A repeated-space string.
fun spaces(n: Int): String =
  if (n <= 0) "" else Str.repeat(n, " ")

// Work-queue element: (indent, flat, doc).
// flat=True → flat mode (Line becomes " ", LineBreak becomes "").
// flat=False → broken mode (Line/LineBreak become newline + indent).

// fits(remaining_cols, queue): check whether the queue fits in remaining columns (flat mode).
// Returns True as soon as a Line/LineBreak is encountered (it terminates flat-fitting).
fun fitsQ(rem: Int, q: List<(Int, Bool, Doc)>): Bool =
  if (rem < 0) False
  else match (q) {
    [] => True
    item :: rest =>
      match (item.2) {
        Empty     => fitsQ(rem, rest)
        Text(s)   => fitsQ(rem - Str.length(s), rest)
        Concat(x, y) =>
          fitsQ(rem, (item.0, item.1, x) :: (item.0, item.1, y) :: rest)
        Nest(j, d) =>
          fitsQ(rem, (item.0 + j, item.1, d) :: rest)
        Line      =>
          if (item.1)
            fitsQ(rem - 1, rest)  // flat mode: Line → " ", costs 1 column
          else
            True                   // broken mode: Line → newline, ends this line
        LineBreak =>
          if (item.1)
            fitsQ(rem, rest)       // flat mode: LineBreak → "", no cost
          else
            True                   // broken mode: LineBreak → newline, ends this line
        Group(d)  =>
          fitsQ(rem, (item.0, True, d) :: rest)
        FlatAlt(_, fd) =>
          fitsQ(rem, (item.0, True, fd) :: rest)
      }
  }

// formatQArr(width, col, queue, out): push output strings into out in order.
// Uses Array<String> output instead of a reversed acc list — eliminates Lst.reverse
// and all intermediate KCons allocations from the output-assembly path.
fun formatQArr(w: Int, k: Int, q: List<(Int, Bool, Doc)>, out: Array<String>): Unit =
  match (q) {
    [] => ()
    item :: rest =>
      match (item.2) {
        Empty     => formatQArr(w, k, rest, out)
        Text(s)   => {
          Arr.push(out, s);
          formatQArr(w, k + Str.length(s), rest, out)
        }
        Concat(x, y) =>
          formatQArr(w, k, (item.0, item.1, x) :: (item.0, item.1, y) :: rest, out)
        Nest(j, d) =>
          formatQArr(w, k, (item.0 + j, item.1, d) :: rest, out)
        Line =>
          if (item.1) {
            Arr.push(out, " ");
            formatQArr(w, k + 1, rest, out)
          } else {
            val nl = "\n${spaces(item.0)}";
            Arr.push(out, nl);
            formatQArr(w, item.0, rest, out)
          }
        LineBreak =>
          if (item.1)
            formatQArr(w, k, rest, out)
          else {
            val nl = "\n${spaces(item.0)}";
            Arr.push(out, nl);
            formatQArr(w, item.0, rest, out)
          }
        Group(d) =>
          if (fitsQ(w - k, (item.0, True, d) :: rest))
            formatQArr(w, k, (item.0, True, d) :: rest, out)
          else
            formatQArr(w, k, (item.0, False, d) :: rest, out)
        FlatAlt(bd, fd) =>
          if (item.1)
            formatQArr(w, k, (item.0, True, fd) :: rest, out)
          else
            formatQArr(w, k, (item.0, False, bd) :: rest, out)
      }
  }

// ─── Public API ───────────────────────────────────────────────────────────────

/** Render a document to a string at the given column width. */
export fun pretty(width: Int, doc: Doc): String = {
  val out: Array<String> = Arr.new()
  formatQArr(width, 0, [(0, False, doc)], out);
  joinArr("", out)
}

// ─── Primitive combinators ────────────────────────────────────────────────────

/** The empty document. */
export val empty: Doc = Empty

/** A literal string (must not contain newlines). */
export fun text(s: String): Doc = Text(s)

/** Concatenate two documents. */
export fun concat(x: Doc, y: Doc): Doc = Concat(x, y)

/** Append a document to another (alias for concat). */
export fun append(x: Doc, y: Doc): Doc = Concat(x, y)

/** Increase indentation by `n` for document `d`. */
export fun nest(n: Int, d: Doc): Doc = Nest(n, d)

/** A newline in broken mode; a single space in flat mode. */
export val line: Doc = Line

/** A newline in broken mode; nothing in flat mode. */
export val lineBreak: Doc = LineBreak

/** A space in flat mode; nothing in broken mode (soft break). */
export val softBreak: Doc = FlatAlt(Empty, Text(" "))

/** Try to render `d` on one line; break at `line`/`lineBreak` if it does not fit. */
export fun group(d: Doc): Doc = Group(d)

/** `flatAlt(broken, flat)`: use `broken` in broken mode, `flat` in flat mode. */
export fun flatAlt(broken: Doc, flat: Doc): Doc = FlatAlt(broken, flat)

// ─── Derived combinators ──────────────────────────────────────────────────────

/** Separate two documents with a single space. */
export fun beside(x: Doc, y: Doc): Doc = Concat(x, Concat(Text(" "), y))

/** Separate two documents with `line` (space or newline). */
export fun softLine(x: Doc, y: Doc): Doc = Concat(x, Concat(Line, y))

/** Concatenate a list of documents with no separator. */
export fun hcat(docs: List<Doc>): Doc =
  Lst.foldl(docs, Empty, (acc: Doc, d: Doc) => Concat(acc, d))

/** Concatenate a list of documents separated by spaces. */
export fun hsep(docs: List<Doc>): Doc = match (docs) {
  [] => Empty
  h :: t => Lst.foldl(t, h, (acc: Doc, d: Doc) => Concat(acc, Concat(Text(" "), d)))
}

/** Concatenate a list of documents separated by `line`. */
export fun vsep(docs: List<Doc>): Doc = match (docs) {
  [] => Empty
  h :: t => Lst.foldl(t, h, (acc: Doc, d: Doc) => Concat(acc, Concat(Line, d)))
}

/** Concatenate a list of documents separated by `lineBreak`. */
export fun vcat(docs: List<Doc>): Doc = match (docs) {
  [] => Empty
  h :: t => Lst.foldl(t, h, (acc: Doc, d: Doc) => Concat(acc, Concat(LineBreak, d)))
}

/** Try `hsep`; fall back to `vsep` if it does not fit (uses `group`). */
export fun sep(docs: List<Doc>): Doc = group(vsep(docs))

/** Indent document by `n` spaces from the current position. */
export fun indent(n: Int, d: Doc): Doc = Concat(Text(spaces(n)), nest(n, d))

/** Hanging indent: first item at current indent; rest indented by `n`. */
export fun hang(n: Int, d: Doc): Doc = align(nest(n, d))

/** Align `d` so continuation matches the current column (no-op in this implementation). */
export fun align(d: Doc): Doc = d

/** Intersperse a separator before all but the first element. */
export fun punctuate(separator: Doc, docs: List<Doc>): List<Doc> = match (docs) {
  [] => []
  h :: [] => [h]
  h :: t => Concat(h, separator) :: punctuate(separator, t)
}

/** Surround a document with opening and closing delimiters. */
export fun enclose(open: Doc, close: Doc, d: Doc): Doc =
  Concat(open, Concat(d, close))

/** A single space document. */
export val space: Doc = Text(" ")

/** A comma document. */
export val comma: Doc = Text(",")

/** Wrap a list of documents in delimiters with separator `sep` between items. */
export fun encloseSep(open: Doc, close: Doc, separator: Doc, docs: List<Doc>): Doc =
  enclose(open, close, hcat(punctuate(separator, docs)))
