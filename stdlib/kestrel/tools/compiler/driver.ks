//! Compiler driver — orchestrates lex→parse→typecheck→codegen→write pipeline.
//!
//! Defines compile options/result payloads, freshness checks, and the single-file
//! compilation pipeline. Multi-module and incremental support is added in S17-02+.

import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Chr from "kestrel:data/char"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as Lex from "kestrel:dev/parser/lexer"
import { Program, ImportDecl } from "kestrel:dev/parser/ast"
import { parseFromList, ParseError } from "kestrel:dev/parser/parser"
import { JByteArray } from "kestrel:data/bytearray"
import * as TC from "kestrel:dev/typecheck/typecheck"
import * as Codegen from "kestrel:tools/compiler/codegen"
import * as Kti from "kestrel:tools/compiler/kti"
import { DepLoadOk, DepLoadErr } from "kestrel:tools/compiler/kti"
import * as Resolve from "kestrel:tools/compiler/resolve"
import * as Crypto from "kestrel:io/crypto"
import * as Fs from "kestrel:io/fs"
import * as Rep from "kestrel:dev/typecheck/reporter"

export type CompileOptions = {
  outDir: String,
  stdlibDir: String,
  cacheRoot: String,
  allowHttp: Bool,
  writeKti: Bool,
  refresh: Bool
}

export type CompileResult = {
  ok: Bool,
  diagnostics: List<Diag.Diagnostic>
}

fun diag(file: String, code: String, message: String): Diag.Diagnostic = {
  severity = Diag.Error,
  code = code,
  message = message,
  location = Diag.locationFileOnly(file),
  sourceLine = None,
  related = [],
  suggestion = None,
  hint = None
}

export fun isFresh(kti: Kti.KtiV4, srcHash: String, depHashes: Dict<String, String>): Bool =
  kti.sourceHash == srcHash & kti.depHashes == depHashes

/// Internal result of a parse attempt — wraps either the program or the parse error fields
/// so that the async `compileFile` function can branch on it without allocating exception
/// pattern-binding locals inside the async state machine (which can cause JVM VerifyError).
type ParseOutcome =
    ParseOk(Program)
  | ParseFail(String, Int, Int, Int)

fun normalizeSegments(parts: List<String>, acc: List<String>): List<String> =
  match (parts) {
    [] => Lst.reverse(acc)
    part :: rest =>
      if (part == "." | Str.isEmpty(part)) normalizeSegments(rest, acc)
      else if (part == "..") {
        match (acc) {
          [] => normalizeSegments(rest, acc)
          _ :: accRest => normalizeSegments(rest, accRest)
        }
      } else normalizeSegments(rest, part :: acc)
  }

fun parseOutcome(tokens: List<Token.Token>): ParseOutcome =
  match (parseFromList(tokens)) {
    Ok(prog) => ParseOk(prog)
    Err(e) => match (e) {
      ParseError(msg, off, ln, col) => ParseFail(msg, off, ln, col)
    }
  }
/// Mirrors `classNameForPath` in `compiler/src/compile-file-jvm.ts`:
/// strip leading `/`, remove `.ks` extension, split on `/`, sanitize each segment
/// (replace non-alphanumeric chars with `_`), capitalize the last segment, re-join.
export fun classNameForPath(path: String): String = {
  val normalized = if (Str.startsWith("/", path)) Str.dropLeft(path, 1) else path
  val withoutExt = if (Str.endsWith(".ks", normalized)) Str.dropRight(normalized, 3) else normalized
  val parts = normalizeSegments(Str.split(withoutExt, "/"), [])
  val sanitize = (seg: String) =>
    Str.mapChars(seg, (c: Char) => if (Chr.isAlphaNum(c) | c == '_') c else '_')
  val sanitized = Lst.map(parts, sanitize)
  match (Lst.reverse(sanitized)) {
    [] => "Unknown"
    last :: rest => {
      val cap =
        if (Str.isEmpty(last)) last
        else "${Str.toUpper(Str.left(last, 1))}${Str.dropLeft(last, 1)}"
      Str.join("/", Lst.reverse(cap :: rest))
    }
  }
}

fun canonicalPath(path: String): String = {
  val abs = Str.startsWith("/", path)
  val parts = normalizeSegments(Str.split(path, "/"), [])
  if (abs) "/${Str.join("/", parts)}" else Str.join("/", parts)
}

fun failResult(file: String, code: String, message: String): CompileResult = {
  ok = False,
  diagnostics = [diag(file, code, message)]
}

fun mkParseErrDiag(file: String, msg: String, offset: Int, ln: Int, col: Int): Diag.Diagnostic = {
  severity = Diag.Error,
  code = Diag.CODES.parse.unexpectedToken,
  message = msg,
  location = Diag.locationFromSpan(file, {
    file = file,
    startOffset = offset,
    endOffset = offset,
    startLine = ln,
    startColumn = col
  }, None),
  sourceLine = None,
  related = [],
  suggestion = None,
  hint = None
}

/// Ensure a URL dep's cache file exists, fetching if needed.
/// Returns None on success, Some(error) if fetch fails.
async fun ensureUrlDep(dep: Resolve.ResolvedDep, opts: CompileOptions): Task<Option<CompileResult>> =
  if (!Str.startsWith("https://", dep.spec) & !Str.startsWith("http://", dep.spec)) None
  else {
    val cacheFile = dep.path
    val cachedExists = await Fs.fileExists(cacheFile)
    val needFetch: Bool = opts.refresh | !cachedExists
    if (!needFetch) None
    else {
      match (await Resolve.fetchUrl(dep.spec, opts.cacheRoot, opts.allowHttp)) {
        Err(e) => Some(failResult(dep.spec, Diag.CODES.resolve.moduleNotFound, e))
        Ok(_) => None
      }
    }
  }

async fun ensureUrlDeps(deps: List<Resolve.ResolvedDep>, opts: CompileOptions): Task<Option<CompileResult>> =
  match (deps) {
    [] => None
    h :: rest => {
      match (await ensureUrlDep(h, opts)) {
        Some(err) => Some(err)
        None => {
          val next: Task<Option<CompileResult>> = ensureUrlDeps(rest, opts)
          await next
        }
      }
    }
  }

fun failWithDiags(ds: List<Diag.Diagnostic>): CompileResult = {
  Rep.printDiagnosticsErr(ds);
  { ok = False, diagnostics = ds }
}

fun classDirName(classPath: String): String = {
  val idx = Str.indexOf(classPath, "/")
  if (idx < 0) "." else Str.dropRight(classPath, Str.length(classPath) - Str.indexOf(classPath, "/"))
}

fun lastSlashIndex(s: String, i: Int, last: Int): Int =
  if (i >= Str.length(s)) last
  else if (Str.sliceRel(i, i + 1, s) == "/") lastSlashIndex(s, i + 1, i)
  else lastSlashIndex(s, i + 1, last)

fun classFileDir(outDir: String, className: String): String = {
  val last = lastSlashIndex(className, 0, -1)
  if (last < 0) outDir
  else "${outDir}/${Str.left(className, last)}"
}

async fun writeAllClasses(outDir: String, pairs: List<(String, JByteArray)>): Task<Result<Unit, String>> =
  match (pairs) {
    [] => Ok(())
    h :: rest => {
      val classPath = "${outDir}/${h.0}.class"
      val parentDir = classFileDir(outDir, h.0);
      match (await Fs.mkdirAll(parentDir)) {
        Err(_) => Err("failed to create directory: ${parentDir}")
        Ok(()) => {
          match (await Fs.writeBytes(classPath, h.1)) {
            Err(_) => Err("failed to write ${classPath}")
            Ok(()) => {
              val next: Task<Result<Unit, String>> = writeAllClasses(outDir, rest)
              await next
            }
          }
        }
      }
    }
  }

/// Write KTI file if writeKti option is set; otherwise return success.
async fun writeKtiIfNeeded(opts: CompileOptions, ktiPath: String, prog: Program, tcExports: TC.TypeEnv, source: String, depHashes: Dict<String, String>, entryPath: String): Task<CompileResult> =
  if (opts.writeKti) {
    val kti = Kti.buildKtiV4(prog, tcExports.items, source, depHashes);
    match (await Kti.writeKtiFile(ktiPath, kti)) {
      Err(ktiErr) => failResult(entryPath, Diag.CODES.file.readError, "cannot write KTI: ${ktiErr}")
      Ok(()) => { ok = True, diagnostics = [] }
    }
  } else {
    { ok = True, diagnostics = [] }
  }

/// Codegen and write class files + KTI (extracted to reduce async locals).
async fun doCodegenAndWrite(moduleName: String, prog: Program, tcResult: TC.TypecheckResult, entryPath: String, opts: CompileOptions, ktiPath: String, source: String, depHashes: Dict<String, String>): Task<CompileResult> = {
  val codegenResult = Codegen.jvmCodegen(moduleName, prog);
  match (await Fs.mkdirAll(opts.outDir)) {
    Err(_) =>
      failResult(entryPath, Diag.CODES.file.readError,
        "cannot create output directory: ${opts.outDir}")
    Ok(()) => {
      val pairs = Dict.toList(codegenResult.classes);
      match (await writeAllClasses(opts.outDir, pairs)) {
        Err(writeErr) => failResult(entryPath, Diag.CODES.file.readError, writeErr)
        Ok(()) =>
          await writeKtiIfNeeded(opts, ktiPath, prog, tcResult.exports, source, depHashes, entryPath)
      }
    }
  }
}

/// Typecheck, codegen, and write output for a parsed program (extracted to reduce async locals).
async fun doTypecheckAndEmit(prog: Program, entryPath: String, moduleName: String, source: String, opts: CompileOptions, ktiPath: String, deps: List<Resolve.ResolvedDep>, depHashes: Dict<String, String>): Task<CompileResult> = {
  // 4. Load dep KTIs for import bindings
  val depPairs = Lst.map(deps, (d: Resolve.ResolvedDep) => (d.spec, "${opts.outDir}/${classNameForPath(canonicalPath(d.path))}.kti"));
  match (await Kti.loadDepBindings(depPairs, prog.imports)) {
    DepLoadErr(depErr) =>
      failWithDiags([diag(entryPath, Diag.CODES.resolve.moduleNotFound, depErr)])
    DepLoadOk(importBindings) => {
      val importEnv = if (Dict.isEmpty(importBindings)) None else Some({ items = importBindings });
      val tcOpts = {
        importBindings = importEnv,
        typeAliasBindings = None,
        importOpaqueTypes = None,
        sourceFile = entryPath
      };
      val tc = TC.typecheck(prog, tcOpts);
      if (!tc.ok) {
        failWithDiags(tc.diagnostics)
      } else {
        await doCodegenAndWrite(moduleName, prog, tc, entryPath, opts, ktiPath, source, depHashes)
      }
    }
  }
}

type GraphState = {
  compiled: Dict<String, Bool>,
  ktiTexts: Dict<String, String>
}

fun ktiPathForModule(path: String, opts: CompileOptions): String =
  "${opts.outDir}/${classNameForPath(path)}.kti"

async fun loadKtiText(path: String, opts: CompileOptions, state: GraphState): Task<Result<String, String>> =
  match (Dict.get(state.ktiTexts, path)) {
    Some(content) => Ok(content)
    None => {
      val ktiPath = ktiPathForModule(path, opts)
      match (await Fs.readText(ktiPath)) {
        Err(_) => Err("dependency not compiled yet: ${path} (missing ${ktiPath})")
        Ok(content) => Ok(content)
      }
    }
  }

async fun depHashesForDeps(deps: List<Resolve.ResolvedDep>, opts: CompileOptions, state: GraphState): Task<Result<Dict<String, String>, String>> =
  match (deps) {
    [] => Ok(Dict.emptyStringDict())
    h :: rest => {
      val depPath = canonicalPath(h.path)
      match (await loadKtiText(depPath, opts, state)) {
        Err(_) => Err("dependency not compiled yet: ${h.spec} (missing ${ktiPathForModule(depPath, opts)})")
        Ok(content) => {
          val next: Task<Result<Dict<String, String>, String>> = depHashesForDeps(rest, opts, state)
          match (await next) {
            Err(e) => Err(e)
            Ok(hashes) => Ok(Dict.insert(hashes, depPath, Crypto.sha256(content)))
          }
        }
      }
    }
  }

type GraphCompileResult =
    GraphCompileOk(GraphState)
  | GraphCompileErr(CompileResult)

type ModuleCompileResult =
    ModuleCompileOk(String)
  | ModuleCompileErr(CompileResult)

fun cycleMessage(path: String, visiting: List<String>): String = {
  val nodes = Lst.append(Lst.reverse(path :: visiting), [path])
  "circular import: ${Str.join(" -> ", nodes)}"
}

async fun compileOneModule(entryPath: String, source: String, prog: Program, deps: List<Resolve.ResolvedDep>, opts: CompileOptions, state: GraphState): Task<ModuleCompileResult> = {
  val moduleName = classNameForPath(entryPath)
  val srcHash = Kti.sourceHash(source)
  val ktiPath = "${opts.outDir}/${moduleName}.kti"
  match (await depHashesForDeps(deps, opts, state)) {
    Err(depErr) =>
      ModuleCompileErr(failWithDiags([diag(entryPath, Diag.CODES.resolve.moduleNotFound, depErr)]))
    Ok(depHashes) => {
      val isAlreadyFresh: Bool = match (await Kti.readKtiFile(ktiPath)) {
        Err(_) => False
        Ok(existingKti) => isFresh(existingKti, srcHash, depHashes)
      }
      if (isAlreadyFresh) {
        match (await loadKtiText(entryPath, opts, state)) {
          Err(depErr2) => ModuleCompileErr(failWithDiags([diag(entryPath, Diag.CODES.resolve.moduleNotFound, depErr2)]))
          Ok(content) => ModuleCompileOk(content)
        }
      } else {
        val emitted = await doTypecheckAndEmit(prog, entryPath, moduleName, source, opts, ktiPath, deps, depHashes)
        if (!emitted.ok) ModuleCompileErr(emitted)
        else if (!opts.writeKti) ModuleCompileOk("")
        else {
          match (await Fs.readText(ktiPath)) {
            Err(_) => ModuleCompileErr(failResult(entryPath, Diag.CODES.file.readError, "cannot read file: ${ktiPath}"))
            Ok(content) => ModuleCompileOk(content)
          }
        }
      }
    }
  }
}

async fun compileGraph(path: String, opts: CompileOptions, visiting: List<String>, state: GraphState): Task<GraphCompileResult> = {
  val p = canonicalPath(path)
  if (Dict.member(state.compiled, p)) {
    GraphCompileOk(state)
  } else if (Lst.member(visiting, p)) {
    GraphCompileErr(failWithDiags([diag(p, Diag.CODES.resolve.moduleNotFound, cycleMessage(p, visiting))]))
  } else {
    match (await Fs.readText(p)) {
      Err(_) =>
        GraphCompileErr(failResult(p, Diag.CODES.file.readError, "cannot read file: ${p}"))
      Ok(source) => {
        val tokens = Lex.lex(source)
        match (parseOutcome(tokens)) {
          ParseFail(msg, off, ln, col) =>
            GraphCompileErr(failWithDiags([mkParseErrDiag(p, msg, off, ln, col)]))
          ParseOk(prog) => {
            val resolveOpts = { fromFile = p, stdlibDir = opts.stdlibDir, cacheRoot = opts.cacheRoot, allowHttp = opts.allowHttp }
            match (Resolve.uniqueDependencyPaths(prog, p, resolveOpts)) {
              Err(resolveErr) =>
                GraphCompileErr(failWithDiags([diag(p, Diag.CODES.resolve.moduleNotFound, resolveErr)]))
              Ok(deps) => {
                match (await ensureUrlDeps(deps, opts)) {
                  Some(fetchErr) => GraphCompileErr(fetchErr)
                  None => {
                    val next: Task<GraphCompileResult> = compileDepsInOrder(deps, opts, p :: visiting, state)
                    match (await next) {
                      GraphCompileErr(e) => GraphCompileErr(e)
                      GraphCompileOk(stateAfterDeps) => {
                        match (await compileOneModule(p, source, prog, deps, opts, stateAfterDeps)) {
                          ModuleCompileErr(e) => GraphCompileErr(e)
                          ModuleCompileOk(ktiText) => {
                            val ktiTexts = if (Str.isEmpty(ktiText)) stateAfterDeps.ktiTexts else Dict.insert(stateAfterDeps.ktiTexts, p, ktiText)
                            GraphCompileOk({
                              compiled = Dict.insert(stateAfterDeps.compiled, p, True),
                              ktiTexts = ktiTexts
                            })
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

async fun compileDepsInOrder(deps: List<Resolve.ResolvedDep>, opts: CompileOptions, visiting: List<String>, state: GraphState): Task<GraphCompileResult> =
  match (deps) {
    [] => GraphCompileOk(state)
    h :: rest => {
      match (await compileGraph(h.path, opts, visiting, state)) {
        GraphCompileErr(e) => GraphCompileErr(e)
        GraphCompileOk(stateNext) => {
          val more: Task<GraphCompileResult> = compileDepsInOrder(rest, opts, visiting, stateNext)
          await more
        }
      }
    }
  }

export async fun compileFile(entryPath: String, opts: CompileOptions): Task<CompileResult> = {
  if (entryPath == "") {
    failResult(entryPath, Diag.CODES.file.readError, "entry path is empty")
  } else {
    match (await compileGraph(entryPath, opts, [], {
      compiled = Dict.emptyStringDict(),
      ktiTexts = Dict.emptyStringDict()
    })) {
      GraphCompileErr(e) => e
      GraphCompileOk(_) => { ok = True, diagnostics = [] }
    }
  }
}
