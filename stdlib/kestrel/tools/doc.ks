// kestrel:tools/doc — Documentation browser HTTP server.
// Usage: kestrel doc [--port PORT] [--project-root PATH]
//
// Discovers all kestrel:* stdlib modules and project modules, extracts doc
// comments, builds a search index, and serves an HTML documentation browser
// on the given port (default 7070).

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import * as Res from "kestrel:data/result"
import * as Http from "kestrel:io/http"
import * as Web from "kestrel:io/web"
import * as Cli from "kestrel:dev/cli"
import { CliSpec, ParsedArgs, Flag, Value } from "kestrel:dev/cli"
import { collectFiles, readText, pathBaseName } from "kestrel:io/fs"
import { all } from "kestrel:sys/task"
import * as Extract from "kestrel:dev/doc/extract"
import { DocModule } from "kestrel:dev/doc/extract"
import * as Render from "kestrel:dev/doc/render"
import * as Idx from "kestrel:dev/doc/index"
import { DocIndex } from "kestrel:dev/doc/index"
import { getProcess, exit } from "kestrel:sys/process"

// ─── Path helpers ─────────────────────────────────────────────────────────────

fun isKsFile(path: String): Bool =
  Str.endsWith(".ks", path)

fun isTestFile(path: String): Bool =
  Str.endsWith(".test.ks", path)

fun isIgnoreDir(path: String): Bool = {
  val base = pathBaseName(path)
  Str.startsWith(".", base) | Str.equals(base, "node_modules")
}

fun isDocKsFile(path: String): Bool =
  isKsFile(path) & !isTestFile(path)

// Derive a kestrel: module specifier from an absolute stdlib path.
// e.g. "/…/stdlib/kestrel/data/list.ks" → "kestrel:data/list"
fun specFromStdlibPath(stdlibRoot: String, path: String): String = {
  val prefix = "${stdlibRoot}/kestrel/";
  val withoutPrefix =
    if (Str.startsWith(prefix, path)) Str.dropLeft(path, Str.length(prefix))
    else path;
  val withoutSuffix =
    if (Str.endsWith(".ks", withoutPrefix)) Str.dropRight(withoutPrefix, 3)
    else withoutPrefix;
  "kestrel:${withoutSuffix}"
}

// Derive a project: module specifier from an absolute project path.
fun specFromProjectPath(projectRoot: String, path: String): String = {
  val prefix = "${projectRoot}/";
  val withoutPrefix =
    if (Str.startsWith(prefix, path)) Str.dropLeft(path, Str.length(prefix))
    else path;
  val withoutSuffix =
    if (Str.endsWith(".ks", withoutPrefix)) Str.dropRight(withoutPrefix, 3)
    else withoutPrefix;
  "project:${withoutSuffix}"
}

// ─── Module discovery ─────────────────────────────────────────────────────────

// Discover all stdlib .ks files (excluding test files).
async fun discoverStdlib(stdlibRoot: String): Task<List<String>> =
  await collectFiles("${stdlibRoot}/kestrel", isDocKsFile, isIgnoreDir)

// Discover all project .ks files under the project root (excluding test files).
async fun discoverProject(projectRoot: String): Task<List<String>> =
  await collectFiles(projectRoot, isDocKsFile, isIgnoreDir)

// Extract a DocModule from a file, returning None on failure.
async fun tryExtract(path: String, spec: String): Task<Option<DocModule>> = {
  val result = await Extract.extractFile(path, spec)
  match (result) {
    Ok(m) => Some(m)
    Err(_) => None
  }
}

// Load and extract all modules from a list of (path, spec) pairs, dropping failures.
async fun loadModules(pairs: List<(String, String)>): Task<List<DocModule>> = {
  val opts = await all(Lst.map(pairs, (pair: (String, String)) => tryExtract(pair.0, pair.1)))
  Lst.filterMap(opts, (o: Option<DocModule>) => o)
}

// ─── CLI spec ─────────────────────────────────────────────────────────────────

val cliSpec = {
  name = "kestrel doc",
  version = "0.1.0",
  description = "Documentation browser for Kestrel modules",
  usage = "kestrel doc [--port PORT] [--project-root PATH]",
  options = [
    {
      short = Some("-p"),
      long = "--port",
      kind = Value("PORT"),
      description = "Port to listen on (default: 7070)"
    },
    {
      short = None,
      long = "--project-root",
      kind = Value("PATH"),
      description = "Root directory for project modules (default: current directory)"
    }
  ],
  args = []
}

// ─── Doc state ────────────────────────────────────────────────────────────────

// Holds all precomputed state for the doc server (modules, index, lookup dict).
type DocState = {
  allModules: List<DocModule>,
  idx: DocIndex,
  modDict: Dict<String, DocModule>
}

// ─── Content-type helpers ─────────────────────────────────────────────────────

fun htmlResp(status: Int, body: String): Http.Response =
  Http.makeResponseWithHeaders(status, body, [("Content-Type", "text/html; charset=utf-8")])

fun jsonResp(status: Int, body: String): Http.Response =
  Http.makeResponseWithHeaders(status, body, [("Content-Type", "application/json; charset=utf-8")])

fun cssResp(body: String): Http.Response =
  Http.makeResponseWithHeaders(200, body, [("Content-Type", "text/css; charset=utf-8")])

fun jsResp(body: String): Http.Response =
  Http.makeResponseWithHeaders(200, body, [("Content-Type", "application/javascript; charset=utf-8")])

fun redirectResp(location: String): Http.Response =
  Http.makeResponseWithHeaders(302, "", [("Location", location)])

// ─── Request dispatcher ───────────────────────────────────────────────────────

async fun dispatch(state: DocState, req: Http.Request, _params: Dict<String, String>): Task<Http.Response> = {
  val path = Http.requestPath(req);
  if (Str.equals(path, "/")) redirectResp("/docs/")
  else if (Str.equals(path, "/docs/")) htmlResp(200, Render.renderModuleList(state.allModules))
  else if (Str.equals(path, "/docs/static/style.css")) cssResp(Render.staticCss())
  else if (Str.equals(path, "/docs/static/search.js")) jsResp(Render.staticJs())
  else if (Str.equals(path, "/api/index")) jsonResp(200, Idx.toFullJson(state.idx))
  else if (Str.startsWith("/api/search", path)) {
    val q = match (Http.queryParam(req, "q")) {
      Some(s) => s
      None => ""
    };
    val results = Idx.query(state.idx, q);
    jsonResp(200, Idx.toSearchJson(results))
  } else if (Str.startsWith("/docs/", path)) {
    val rawSpec = Str.dropLeft(path, 6);
    match (Dict.get(state.modDict, rawSpec)) {
      Some(m) => htmlResp(200, Render.renderModule(m))
      None => htmlResp(404, "<html><body><h1>404 Not Found</h1><p>Module not found: ${rawSpec}</p></body></html>")
    }
  } else
    Http.makeResponse(404, "Not Found")
}

// ─── Handler ──────────────────────────────────────────────────────────────────

async fun handler(parsed: ParsedArgs): Task<Int> = {
  val portStr = match (Dict.get(parsed.options, "port")) {
    Some(s) => s
    None => "7070"
  }
  val port = match (Str.toInt(portStr)) {
    Some(n) => n
    None => {
      println("kestrel doc: invalid port: ${portStr}");
      1
    }
  }

  val proc = getProcess()
  val projectRoot = match (Dict.get(parsed.options, "project-root")) {
    Some(p) => p
    None => proc.cwd
  }

  // Derive stdlib root from cwd. By convention this tool is always run from
  // the Kestrel project root, so stdlib/ is a direct child.
  val stdlibRoot = "${proc.cwd}/stdlib"

  // Discover and load all stdlib modules.
  val stdlibFiles = await discoverStdlib(stdlibRoot)
  val stdlibPairs: List<(String, String)> = Lst.map(stdlibFiles, (p: String) => (p, specFromStdlibPath(stdlibRoot, p)))
  val stdlibModules = await loadModules(stdlibPairs)

  // Discover and load project modules (skip files already covered by stdlib).
  val projFiles = await discoverProject(projectRoot)
  val projFiltered = Lst.filter(projFiles, (p: String) => !Str.startsWith(stdlibRoot, p))
  val projPairs: List<(String, String)> = Lst.map(projFiltered, (p: String) => (p, specFromProjectPath(projectRoot, p)))
  val projModules = await loadModules(projPairs)

  val allModules: List<DocModule> = Lst.append(stdlibModules, projModules)
  val idx: DocIndex = Idx.build(allModules)
  val modDict: Dict<String, DocModule> = Lst.foldl(allModules, Dict.empty(), (acc: Dict<String, DocModule>, m: DocModule) => Dict.insert(acc, m.moduleSpec, m))
  val state: DocState = { allModules = allModules, idx = idx, modDict = modDict }

  // Single wildcard handler closes over state only (not nested async funs).
  val router =
    Web.newRouter()
    |> Web.get("/*", (req: Http.Request, params: Dict<String, String>) => dispatch(state, req, params))

  val server = await Http.createServer(Web.serve(router))
  await Http.listen(server, { host = "127.0.0.1", port = port })
  println("Docs available at http://localhost:${Str.fromInt(port)}/docs/")
  await Http.park()
  0
}

// ─── Entry point ──────────────────────────────────────────────────────────────

export async fun main(allArgs: List<String>): Task<Unit> = {
  val code = await Cli.run(cliSpec, handler, allArgs)
  exit(code)
}

main(getProcess().args)
