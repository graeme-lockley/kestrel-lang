// Tests for kestrel:dev/doc/index
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import { build, query, toSearchJson, toFullJson, DocIndex, SearchResult } from "kestrel:dev/doc/index"
import { DocEntry, DocModule, DocKind, DKFun, DKType, DKVal, DKVar, extract } from "kestrel:dev/doc/extract"
import * as List from "kestrel:data/list"
import * as Str  from "kestrel:data/string"

// ── Helpers ──────────────────────────────────────────────────────────────────

fun mkEntry(k: DocKind, n: String, sig: String, doc: String): DocEntry =
  { name = n, kind = k, signature = sig, doc = doc }

fun mkMod(spec: String, entries: List<DocEntry>): DocModule =
  { moduleSpec = spec, moduleProse = "", entries = entries }

// ── Module fixture ────────────────────────────────────────────────────────────

val modA = mkMod("pkg:a", [
  mkEntry(DKFun,  "foo",    "fun foo(): Unit",       "Does foo."),
  mkEntry(DKFun,  "fooBar", "fun fooBar(): String",  "Does foo then bar."),
  mkEntry(DKType, "Widget", "type Widget",            "A widget type.")
])

val modB = mkMod("pkg:b", [
  mkEntry(DKVal,  "PI",     "val PI: Float",          "Pi constant."),
  mkEntry(DKFun,  "bar",    "fun bar(x: Widget): Int", "Accepts a Widget arg.")
])

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/doc/index", (sg: Suite) => {

    // ── build ─────────────────────────────────────────────────────────────────

    group(sg, "build: empty list gives empty index", (g: Suite) => {
      val idx = build([]);
      eq(g, "entries count", List.length(idx.entries), 0)
    });

    group(sg, "build: single module indexes all entries", (g: Suite) => {
      val idx = build([modA]);
      eq(g, "entries count", List.length(idx.entries), 3)
    });

    group(sg, "build: two modules indexes all entries", (g: Suite) => {
      val idx = build([modA, modB]);
      eq(g, "entries count", List.length(idx.entries), 5)
    });

    // ── query: empty / blank ──────────────────────────────────────────────────

    group(sg, "query: empty string returns empty", (g: Suite) => {
      val idx = build([modA, modB]);
      val results = query(idx, "");
      eq(g, "empty results", List.length(results), 0)
    });

    // ── query: rank 1 — exact name match ──────────────────────────────────────

    group(sg, "query: exact name match returns one result", (g: Suite) => {
      val idx = build([modA, modB]);
      val results = query(idx, "foo");
      // rank1: foo (exact); rank2: fooBar (prefix) — total 2
      isTrue(g, "at least 1 result", List.length(results) >= 1);
      val r = List.head(results);
      match (r) {
        None => isTrue(g, "should have result", False)
        Some(sr) => {
          eq(g, "name", sr.name, "foo");
          eq(g, "moduleSpec", sr.moduleSpec, "pkg:a")
        }
      }
    });

    group(sg, "query: exact name is case-insensitive", (g: Suite) => {
      val idx = build([modA]);
      val results = query(idx, "FOO");
      // rank1: foo exact; rank2: fooBar prefix — total 2
      isTrue(g, "at least 1", List.length(results) >= 1)
    });

    // ── query: rank 2 — name prefix match ─────────────────────────────────────

    group(sg, "query: prefix match finds fooBar but not foo when foo is exact", (g: Suite) => {
      val idx = build([modA, modB]);
      val results = query(idx, "foo");
      // rank1 = [foo], rank2 = [fooBar]
      eq(g, "total", List.length(results), 2);
      match (List.head(results)) {
        None => isTrue(g, "should have first result", False)
        Some(first) => eq(g, "first is foo (exact)", first.name, "foo")
      }
    });

    group(sg, "query: prefix match only", (g: Suite) => {
      val idx = build([modA]);
      val results = query(idx, "fooB");
      eq(g, "length", List.length(results), 1);
      match (List.head(results)) {
        None => isTrue(g, "should have result", False)
        Some(r) => eq(g, "name", r.name, "fooBar")
      }
    });

    // ── query: rank 3 — signature substring ───────────────────────────────────

    group(sg, "query: signature substring match", (g: Suite) => {
      val idx = build([modA, modB]);
      // "Widget" appears in modB.bar signature and modA.Widget type sig
      val results = query(idx, "Widget");
      // rank1: exact name "Widget" (from modA)
      // rank2: nothing starts with "Widget" except "Widget" itself (already rank1)
      // rank3: "Widget" in signature of modB.bar
      isTrue(g, "at least 1 result", List.length(results) >= 1)
    });

    // ── query: rank 4 — doc body substring ────────────────────────────────────

    group(sg, "query: doc body substring match", (g: Suite) => {
      val idx = build([modA, modB]);
      // "constant" only appears in modB.PI doc text
      val results = query(idx, "constant");
      eq(g, "length", List.length(results), 1);
      match (List.head(results)) {
        None => isTrue(g, "should have result", False)
        Some(r) => eq(g, "name is PI", r.name, "PI")
      }
    });

    // ── query: rank ordering ──────────────────────────────────────────────────

    group(sg, "query: exact before prefix before sig before doc", (g: Suite) => {
      val idx = build([modA, modB]);
      val results = query(idx, "foo");
      // foo (exact rank1) should come before fooBar (prefix rank2)
      val names = List.map(results, (r: SearchResult) => r.name);
      match (names) {
        first :: _ => eq(g, "first is foo", first, "foo")
        [] => isTrue(g, "expected results", False)
      }
    });

    // ── query: alphabetical within rank ───────────────────────────────────────

    group(sg, "query: alphabetical sort within rank", (g: Suite) => {
      val modC = mkMod("pkg:c", [
        mkEntry(DKFun, "mapZ",  "fun mapZ(): Unit",  ""),
        mkEntry(DKFun, "mapA",  "fun mapA(): Unit",  ""),
        mkEntry(DKFun, "mapB",  "fun mapB(): Unit",  "")
      ]);
      val idx = build([modC]);
      // Query "map" — all three are prefix matches; no exact match
      val results = query(idx, "map");
      // rank2: mapA, mapB, mapZ sorted alphabetically
      val names = List.map(results, (r: SearchResult) => r.name);
      eq(g, "count", List.length(names), 3);
      match (List.head(names)) {
        None => isTrue(g, "should have first", False)
        Some(a) => eq(g, "first", a, "mapA")
      };
      match (List.head(List.drop(names, 1))) {
        None => isTrue(g, "should have second", False)
        Some(b) => eq(g, "second", b, "mapB")
      };
      match (List.head(List.drop(names, 2))) {
        None => isTrue(g, "should have third", False)
        Some(c) => eq(g, "third", c, "mapZ")
      }
    });

    // ── query: max 50 results ─────────────────────────────────────────────────

    group(sg, "query: returns at most 50 results", (g: Suite) => {
      val manyEntries = List.map(List.range(0, 60), (i: Int) =>
        mkEntry(DKFun, "fn${Str.fromInt(i)}", "fun fn${Str.fromInt(i)}(): Unit", "fn body")
      );
      val bigMod = mkMod("pkg:big", manyEntries);
      val idx = build([bigMod]);
      val results = query(idx, "fn");
      isTrue(g, "at most 50", List.length(results) <= 50)
    });

    // ── SearchResult fields ───────────────────────────────────────────────────

    group(sg, "result: excerpt truncated at 120 chars", (g: Suite) => {
      val longDoc = Str.repeat(200, "a");
      val mod = mkMod("pkg:x", [mkEntry(DKFun, "x", "fun x(): Unit", longDoc)]);
      val idx = build([mod]);
      val results = query(idx, "x");
      match (List.head(results)) {
        None => isTrue(g, "should have result", False)
        Some(r) => isTrue(g, "excerpt <= 120", Str.length(r.excerpt) <= 120)
      }
    });

    group(sg, "result: empty doc gives empty excerpt", (g: Suite) => {
      val mod = mkMod("pkg:nodoc", [mkEntry(DKFun, "nodocFn", "fun nodocFn(): Unit", "")]);
      val idx = build([mod]);
      val results = query(idx, "nodocFn");
      match (List.head(results)) {
        None => isTrue(g, "should have result", False)
        Some(r) => eq(g, "excerpt", r.excerpt, "")
      }
    });

    // ── toSearchJson ──────────────────────────────────────────────────────────

    group(sg, "toSearchJson: empty list is []", (g: Suite) =>
      eq(g, "json", toSearchJson([]), "[]")
    );

    group(sg, "toSearchJson: one result produces valid JSON", (g: Suite) => {
      val idx = build([modA]);
      val results = query(idx, "foo");
      val json = toSearchJson(results);
      isTrue(g, "starts with [", Str.startsWith("[", json));
      isTrue(g, "ends with ]", Str.endsWith("]", json));
      isTrue(g, "contains moduleSpec", Str.contains("moduleSpec", json));
      isTrue(g, "contains pkg:a", Str.contains("pkg:a", json))
    });

    group(sg, "toSearchJson: special chars are escaped", (g: Suite) => {
      val mod = mkMod("pkg:q", [mkEntry(DKFun, "q\"r", "fun q(): Unit", "")]);
      val idx = build([mod]);
      val results = query(idx, "q\"r");
      val json = toSearchJson(results);
      isTrue(g, "quote escaped", Str.contains("\\\"", json))
    });

    // ── toFullJson ────────────────────────────────────────────────────────────

    group(sg, "toFullJson: empty index is {}", (g: Suite) => {
      val idx = build([]);
      eq(g, "json", toFullJson(idx), "{}")
    });

    group(sg, "toFullJson: contains module specifiers", (g: Suite) => {
      val idx = build([modA, modB]);
      val json = toFullJson(idx);
      isTrue(g, "starts with {", Str.startsWith("{", json));
      isTrue(g, "ends with }", Str.endsWith("}", json));
      isTrue(g, "contains pkg:a", Str.contains("pkg:a", json));
      isTrue(g, "contains pkg:b", Str.contains("pkg:b", json))
    });

    group(sg, "toFullJson: single module has entries array", (g: Suite) => {
      val idx = build([modA]);
      val json = toFullJson(idx);
      isTrue(g, "has entries", Str.contains("entries", json));
      isTrue(g, "has foo entry", Str.contains("foo", json))
    });

    group(sg, "toFullJson: includes inferred val/var signature text", (g: Suite) => {
      val mod = extract("export val answer = 42\nexport var counter = 0\n", "pkg:infer");
      val idx = build([mod]);
      val json = toFullJson(idx);
      isTrue(g, "has inferred val signature", Str.contains("val answer: Int", json));
      isTrue(g, "has inferred var signature", Str.contains("var counter: Int", json))
    });

    group(sg, "toFullJson: includes fallback marker when inference fails", (g: Suite) => {
      val mod = extract("export val broken = (\n", "pkg:fallback");
      val idx = build([mod]);
      val json = toFullJson(idx);
      isTrue(g, "has fallback signature marker", Str.contains("<inference-unavailable>", json))
    })

  })
