# `kestrel:tools/doc` HTTP server, CLI, and tool spec

## Sequence: S09-07
## Tier: Optional
## Former ID: (none)

## Epic

- Epic: [E09 Documentation Browser](../epics/unplanned/E09-documentation-browser.md)
- Companion stories: S09-01, S09-02, S09-03, S09-04, S09-05, S09-06, S09-08

## Summary

Implements the `kestrel:tools/doc` main entry-point module — the HTTP server that serves the
documentation browser. It indexes all `kestrel:*` stdlib modules and the project modules
discovered from `--project-root` (default: `cwd`), starts an HTTP server on port 7070
(configurable via `--port`), and wires together the extractor (S09-01), renderer (S09-04), and
search index (S09-05) to handle all documented routes. The `kestrel doc` CLI alias is added to
`scripts/kestrel`. The `docs/specs/09-tools.md` `kestrel doc` section is written here.

## Current State

- `kestrel:io/http` (E03) provides `createServer`, `listen`, `makeResponse`, `queryParam`,
  `requestId`, `requestBodyText`.
- `kestrel:io/web` (E03) provides Sinatra-style routing via `newRouter`, `get`, and `serve`.
- `kestrel:io/fs` provides `collectFiles`, `readText`, `fileExists`.
- `kestrel:dev/cli` provides `CliSpec`, `ParsedArgs`, `run`.
- `kestrel:sys/process` provides `getProcess` for cwd and args.
- `kestrel:tools/format` (E08) is an example of the tool entry-point pattern.
- `kestrel:dev/doc/extract`, `kestrel:dev/doc/render`, `kestrel:dev/doc/index`
  (S09-01–S09-05 — not yet built when this story starts).
- No `kestrel doc` command exists in `scripts/kestrel` or `docs/specs/09-tools.md`.

## Relationship to other stories

- **Depends on:** S09-01 (extract), S09-02 (Markdown), S09-03 (sig), S09-04 (render),
  S09-05 (index) — all must be complete before this story starts.
- **Optionally uses:** S09-06 (file watching) — the server starts without live reload if
  S09-06 is not yet done; S09-08 adds live reload on top.
- **Blocks:** S09-08 (live reload is layered onto the server from this story).
- All prior E09 stories converge here.

## Goals

1. Implement `kestrel:tools/doc` (file `stdlib/kestrel/tools/doc.ks`) following the
   `kestrel:tools/format` pattern:
   - CLI spec with `--port PORT` (default 7070) and `--project-root PATH` (default cwd).
   - `main(args)` entry point called with `getProcess().args`.
2. Module discovery:
   - Stdlib modules: discover all `stdlib/kestrel/**/*.ks` files (excluding `*.test.ks`,
     `*.backup`), derive their specifiers from relative paths.
   - Project modules: collect all `.ks` files (excluding test files) under `--project-root`.
3. Indexing:
   - Call `extractFile(path, spec)` for each discovered file to produce `DocModule` values.
   - Build a `DocIndex` from all `DocModule` values via `index.build`.
4. Server routes (using `kestrel:io/web` router):
   - `GET /` → redirect 302 to `/docs/`.
   - `GET /docs/` → `render.renderModuleList(modules)` with `Content-Type: text/html`.
   - `GET /docs/{module}` → `render.renderModule(mod)` (404 if not found).
   - `GET /docs/{module}/{name}` → 301 redirect to `/docs/{module}#{name}`.
   - `GET /api/search?q=…` → `index.toSearchJson(index.query(idx, q))` with
     `Content-Type: application/json`.
   - `GET /api/index` → `index.toFullJson(idx)` with `Content-Type: application/json`.
   - `GET /static/doc.css` → `render.staticCss()` with `Content-Type: text/css`.
   - `GET /static/doc.js` → `render.staticJs()` with `Content-Type: application/javascript`.
5. Print startup message: `Docs available at http://localhost:{port}/docs/` on stdout.
6. Add `doc` subcommand alias to `scripts/kestrel` (delegates to
   `kestrel run kestrel:tools/doc -- "$@"`).
7. Write `docs/specs/09-tools.md` §2.X `kestrel doc` section documenting: flags, all routes,
   exit codes, and the module discovery rules.

## Acceptance Criteria

- `./kestrel doc` starts the server; `GET http://localhost:7070/docs/` returns HTML 200.
- `GET /docs/kestrel:data/list` returns an HTML page listing all exports from that module.
- `GET /api/search?q=map` returns a JSON array with at least one result.
- `GET /api/index` returns valid JSON.
- `GET /static/doc.css` returns CSS; `GET /static/doc.js` returns JavaScript.
- `GET /` redirects to `/docs/`.
- `GET /docs/nonexistent:module` returns HTTP 404.
- `./kestrel doc --port 9090` starts the server on port 9090.
- `docs/specs/09-tools.md` contains a `kestrel doc` section.
- All Kestrel tests pass (`./kestrel test`).
- All compiler tests pass (`cd compiler && npm test`).

## Spec References

- `docs/specs/09-tools.md` — §2.X `kestrel doc` (to be written here).
- `kestrel:io/http` — server primitives.
- `kestrel:io/web` — routing framework.
- `kestrel:dev/cli` — CLI argument parsing.
- `kestrel:dev/doc/extract`, `render`, `index` (S09-01–S09-05).

## Risks / Notes

- Module specifier derivation for stdlib files: strip `stdlib/` prefix and remove `.ks`
  suffix to get `kestrel:<path>`. For project files use relative path from `--project-root`
  with a `project:` prefix or the file's own import specifier if declared — V1 can use a
  simple fallback of `file:<relative-path>`.
- The routing for `/docs/{module}` must URL-decode the module segment — `kestrel:data/list`
  encodes the `:` as `%3A` in a URL path.
- Large stdlib: discovering and extracting ~40–60 stdlib files synchronously on startup may
  take 1–2 seconds. Using `all(Lst.map(files, extractFile))` runs extractions in parallel
  via virtual threads.
- No authentication or access control is needed; the server is local-only (`127.0.0.1`).
