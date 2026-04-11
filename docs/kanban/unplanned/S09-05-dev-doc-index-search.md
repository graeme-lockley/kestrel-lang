# `kestrel:dev/doc/index` — search index and JSON API

## Sequence: S09-05
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-06, S09-07, S09-08

## Summary

Implements `kestrel:dev/doc/index` — the in-memory search index and query layer for the
documentation browser. The index is built from a list of `DocModule` values and supports
ranked text search across declaration names, signatures, and doc-comment bodies. Query results
are returned as a list of `SearchResult` records and also serialised to JSON for the
`GET /api/search?q=…` and `GET /api/index` HTTP endpoints.

## Current State

- No search index or JSON serialisation module exists in `kestrel:dev/doc/`.
- `kestrel:data/dict` provides a hash map that can hold the in-memory index.
- `kestrel:data/list`, `kestrel:data/string` provide the filtering and sorting primitives
  needed for ranking.
- `kestrel:dev/doc/extract` (S09-01) will provide `DocModule` and `DocEntry` with `name`,
  `signature`, and `doc` fields.
- `kestrel:dev/doc/sig` (S09-03) will provide normalised signature strings for indexing.

## Relationship to other stories

- **Depends on:** S09-01 (`DocModule`, `DocEntry`), S09-03 (normalised signatures for
  signature-substring matching).
- **Blocks:** S09-07 (the server calls `index.query` and `index.toJson` to serve the search
  and index API endpoints).
- **Independent of:** S09-02, S09-04, S09-06.
- Can be developed in parallel with S09-04 after S09-01 and S09-03 are done.

## Goals

1. Export `DocIndex` opaque type from `kestrel:dev/doc/index`.
2. Export `build(modules: List<DocModule>): DocIndex`.
3. Export `query(idx: DocIndex, q: String): List<SearchResult>` with ranked results:
   - Rank 1 (highest): exact name match (`entry.name == q`).
   - Rank 2: name prefix match (`entry.name` starts with `q`).
   - Rank 3: signature substring match (normalised `sig.format(entry)` contains `q`).
   - Rank 4: doc body substring match (`entry.doc` contains `q`).
   - Results within a rank are ordered alphabetically by `moduleSpec + "." + name`.
   - Maximum 50 results total.
4. Export `SearchResult` record: `{ moduleSpec: String, name: String, kind: DocKind,
   signature: String, excerpt: String }` where `excerpt` is the first 120 characters of
   `doc` (or empty if no doc-comment).
5. Export `toSearchJson(results: List<SearchResult>): String` — JSON array of result objects.
6. Export `toFullJson(idx: DocIndex): String` — JSON object mapping module specifiers to their
   `DocModule` data; intended for `GET /api/index` (for editor/tooling integration).

## Acceptance Criteria

- `build([])` returns a valid empty index (no crash).
- `query` returns results in rank order (exact > prefix > signature > doc body).
- `query` returns at most 50 results for any input.
- `toSearchJson` and `toFullJson` produce valid JSON (parseable by a standard JSON parser).
- `toSearchJson([])` returns `"[]"`.
- Unit tests in `stdlib/kestrel/dev/doc/index.test.ks` cover:
  - Building an index from two modules, querying by exact name, by prefix, by signature
    substring, and by doc body substring.
  - Multiple results per rank sorted alphabetically.
  - JSON serialisation output for at least one non-empty result.
- All Kestrel tests pass (`./kestrel test`).

## Spec References

- `kestrel:dev/doc/extract` — `DocModule`, `DocEntry`, `DocKind` (S09-01).
- `kestrel:dev/doc/sig` — `format(entry: DocEntry): String` (S09-03).

## Risks / Notes

- A full inverted index (trigram, BM25) is not needed for V1 — the expected index size of
  a few hundred to a few thousand entries makes a linear scan with ranked short-circuits
  fast enough (< 10 ms for 5 000 entries).
- JSON serialisation is hand-written using `kestrel:data/string` helpers. A generic JSON
  encoder would be nice but is out of scope; targeted serialisation of the two result types
  is acceptable.
- `toFullJson` is intended to allow VS Code extensions or other tooling to consume the full
  index without running a search — keep the format simple and documented in the spec.
