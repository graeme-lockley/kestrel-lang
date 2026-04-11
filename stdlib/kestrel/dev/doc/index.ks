//! In-memory search index and JSON API for the documentation browser.
//! Builds a flat list of all exported declarations from a `List<DocModule>`
//! and supports ranked text search across names, signatures, and doc bodies.

import * as List from "kestrel:data/list"
import * as Str  from "kestrel:data/string"
import { DocKind, DKFun, DKType, DKVal, DKVar, DKException, DKExternType, DKExternFun, DocEntry, DocModule } from "kestrel:dev/doc/extract"
import * as Sig  from "kestrel:dev/doc/sig"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type SearchResult = {
  moduleSpec: String,
  name:       String,
  kind:       DocKind,
  signature:  String,
  excerpt:    String
}

// An index record pairs a DocEntry with its containing module specifier.
type IndexEntry = {
  moduleSpec: String,
  entry:      DocEntry
}

// DocIndex wraps a flat list of all IndexEntry values across all modules.
export type DocIndex = {
  entries: List<IndexEntry>
}

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

fun moduleToEntries(mod: DocModule): List<IndexEntry> =
  List.map(mod.entries, (e: DocEntry) => { moduleSpec = mod.moduleSpec, entry = e })

/// Build a search index from a list of `DocModule` values.
export fun build(modules: List<DocModule>): DocIndex =
  { entries = List.concat(List.map(modules, (m: DocModule) => moduleToEntries(m))) }

// ---------------------------------------------------------------------------
// Querying
// ---------------------------------------------------------------------------

fun makeExcerpt(doc: String): String =
  if (Str.length(doc) > 120) "${Str.slice(doc, 0, 117)}..."
  else doc

fun toResult(ie: IndexEntry): SearchResult = {
  moduleSpec = ie.moduleSpec,
  name       = ie.entry.name,
  kind       = ie.entry.kind,
  signature  = Sig.format(ie.entry),
  excerpt    = makeExcerpt(ie.entry.doc)
}

// Simple insertion sort by (moduleSpec + "." + name)
fun insertAlpha(r: SearchResult, rs: List<SearchResult>): List<SearchResult> =
  match (rs) {
    [] => [r]
    h :: t => {
      val rKey = "${r.moduleSpec}.${r.name}";
      val hKey = "${h.moduleSpec}.${h.name}";
      if (rKey <= hKey) r :: rs else h :: insertAlpha(r, t)
    }
  }

fun sortAlpha(rs: List<SearchResult>): List<SearchResult> = match (rs) {
  [] => []
  h :: t => insertAlpha(h, sortAlpha(t))
}

fun rank1(es: List<IndexEntry>, ql: String): List<SearchResult> =
  sortAlpha(
    List.map(
      List.filter(es, (ie: IndexEntry) => Str.toLowerCase(ie.entry.name) == ql),
      (ie: IndexEntry) => toResult(ie)
    )
  )

fun rank2(es: List<IndexEntry>, ql: String): List<SearchResult> =
  sortAlpha(
    List.map(
      List.filter(es, (ie: IndexEntry) => {
        val n = Str.toLowerCase(ie.entry.name);
        Str.startsWith(ql, n) & (n != ql)
      }),
      (ie: IndexEntry) => toResult(ie)
    )
  )

fun rank3(es: List<IndexEntry>, ql: String): List<SearchResult> =
  sortAlpha(
    List.map(
      List.filter(es, (ie: IndexEntry) => {
        val n = Str.toLowerCase(ie.entry.name);
        val s = Str.toLowerCase(Sig.format(ie.entry));
        Str.contains(ql, s) & (n != ql) & !Str.startsWith(ql, n)
      }),
      (ie: IndexEntry) => toResult(ie)
    )
  )

fun rank4(es: List<IndexEntry>, ql: String): List<SearchResult> =
  sortAlpha(
    List.map(
      List.filter(es, (ie: IndexEntry) => {
        val n = Str.toLowerCase(ie.entry.name);
        val s = Str.toLowerCase(Sig.format(ie.entry));
        val d = Str.toLowerCase(ie.entry.doc);
        Str.contains(ql, d) & (n != ql) & !Str.startsWith(ql, n) & !Str.contains(ql, s)
      }),
      (ie: IndexEntry) => toResult(ie)
    )
  )

/// Query the index and return ranked results (max 50).
/// Rank order: exact name match > name prefix > signature substring > doc body substring.
/// Results within a rank are sorted alphabetically by `moduleSpec.name`.
export fun query(idx: DocIndex, q: String): List<SearchResult> = {
  val ql = Str.toLowerCase(q);
  if (Str.isEmpty(ql)) []
  else {
    val es = idx.entries;
    val r1 = rank1(es, ql);
    val r2 = rank2(es, ql);
    val r3 = rank3(es, ql);
    val r4 = rank4(es, ql);
    List.take(List.concat([r1, r2, r3, r4]), 50)
  }
}

// ---------------------------------------------------------------------------
// JSON serialisation
// ---------------------------------------------------------------------------

fun jsonEscape(s: String): String = {
  val s1 = Str.replace("\\", "\\\\", s);
  val s2 = Str.replace("\"", "\\\"", s1);
  val s3 = Str.replace("\n", "\\n", s2);
  val s4 = Str.replace("\r", "\\r", s3);
  s4
}

fun kindToString(k: DocKind): String = match (k) {
  DKFun        => "fun"
  DKType       => "type"
  DKVal        => "val"
  DKVar        => "var"
  DKException  => "exception"
  DKExternType => "externType"
  DKExternFun  => "externFun"
}

fun resultToJson(r: SearchResult): String =
  "{\"moduleSpec\":\"${jsonEscape(r.moduleSpec)}\",\"name\":\"${jsonEscape(r.name)}\",\"kind\":\"${kindToString(r.kind)}\",\"signature\":\"${jsonEscape(r.signature)}\",\"excerpt\":\"${jsonEscape(r.excerpt)}\"}"

/// Serialise a list of `SearchResult` values to a JSON array string.
export fun toSearchJson(results: List<SearchResult>): String =
  if (List.isEmpty(results)) "[]"
  else "[${Str.join(",", List.map(results, (r: SearchResult) => resultToJson(r)))}]"

fun entryToJson(ie: IndexEntry): String = {
  val sig = Sig.format(ie.entry);
  "{\"name\":\"${jsonEscape(ie.entry.name)}\",\"kind\":\"${kindToString(ie.entry.kind)}\",\"signature\":\"${jsonEscape(sig)}\",\"doc\":\"${jsonEscape(ie.entry.doc)}\"}"
}

fun moduleEntriesToJson(spec: String, es: List<IndexEntry>): String = {
  val items = List.map(es, (ie: IndexEntry) => entryToJson(ie));
  "\"${jsonEscape(spec)}\":{\"entries\":[${Str.join(",", items)}]}"
}

// Collect all unique module specifiers in order of first appearance
fun uniqueSpecs(entries: List<IndexEntry>, seen: List<String>): List<String> =
  match (entries) {
    [] => List.reverse(seen)
    h :: t =>
      if (List.member(seen, h.moduleSpec)) uniqueSpecs(t, seen)
      else uniqueSpecs(t, h.moduleSpec :: seen)
  }

/// Serialise the full index to a JSON object mapping module specifiers to their entries.
/// Intended for `GET /api/index` (editor/tooling integration).
export fun toFullJson(idx: DocIndex): String = {
  val specs = uniqueSpecs(idx.entries, []);
  val parts = List.map(specs, (spec: String) => {
    val es = List.filter(idx.entries, (ie: IndexEntry) => ie.moduleSpec == spec);
    moduleEntriesToJson(spec, es)
  });
  "{${Str.join(",", parts)}}"
}
