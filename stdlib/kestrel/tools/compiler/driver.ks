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
import * as Fs from "kestrel:io/fs"
import * as Rep from "kestrel:dev/typecheck/reporter"

export type CompileOptions = {
  outDir: String,
  stdlibDir: String,
  cacheRoot: String,
  allowHttp: Bool,
  writeKti: Bool
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
async fun writeKtiIfNeeded(opts: CompileOptions, ktiPath: String, prog: Program, tcExports: TC.TypeEnv, source: String, entryPath: String): Task<CompileResult> =
  if (opts.writeKti) {
    val kti = Kti.buildKtiV4(prog, tcExports.items, source, Dict.emptyStringDict());
    match (await Kti.writeKtiFile(ktiPath, kti)) {
      Err(ktiErr) => failResult(entryPath, Diag.CODES.file.readError, "cannot write KTI: ${ktiErr}")
      Ok(()) => { ok = True, diagnostics = [] }
    }
  } else {
    { ok = True, diagnostics = [] }
  }

/// Codegen and write class files + KTI (extracted to reduce async locals).
async fun doCodegenAndWrite(moduleName: String, prog: Program, tcResult: TC.TypecheckResult, entryPath: String, opts: CompileOptions, ktiPath: String, source: String): Task<CompileResult> = {
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
          await writeKtiIfNeeded(opts, ktiPath, prog, tcResult.exports, source, entryPath)
      }
    }
  }
}

/// Typecheck, codegen, and write output for a parsed program (extracted to reduce async locals).
async fun doTypecheckAndEmit(prog: Program, entryPath: String, moduleName: String, source: String, opts: CompileOptions, ktiPath: String): Task<CompileResult> = {
  // 3. Resolve direct dependency paths
  val resolveOpts = { fromFile = entryPath, stdlibDir = opts.stdlibDir, cacheRoot = opts.cacheRoot, allowHttp = opts.allowHttp };
  match (Resolve.uniqueDependencyPaths(prog, entryPath, resolveOpts)) {
    Err(resolveErr) =>
      failWithDiags([diag(entryPath, Diag.CODES.resolve.moduleNotFound, resolveErr)])
    Ok(deps) => {
      // 4. Load dep KTIs for import bindings
      val depPairs = Lst.map(deps, (d: Resolve.ResolvedDep) => (d.spec, "${opts.outDir}/${classNameForPath(d.path)}.kti"));
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
            await doCodegenAndWrite(moduleName, prog, tc, entryPath, opts, ktiPath, source)
          }
        }
      }
    }
  }
}

export async fun compileFile(entryPath: String, opts: CompileOptions): Task<CompileResult> = {
  if (entryPath == "") {
    failResult(entryPath, Diag.CODES.file.readError, "entry path is empty")
  } else {
    // 1. Read source text
    match (await Fs.readText(entryPath)) {
      Err(_) =>
        failResult(entryPath, Diag.CODES.file.readError, "cannot read file: ${entryPath}")
      Ok(source) => {
        val moduleName = classNameForPath(entryPath);
        val srcHash = Kti.sourceHash(source);
        val ktiPath = "${opts.outDir}/${moduleName}.kti";
        val isAlreadyFresh: Bool = match (await Kti.readKtiFile(ktiPath)) {
          Err(_) => False
          Ok(existingKti) => isFresh(existingKti, srcHash, Dict.emptyStringDict())
        };
        if (isAlreadyFresh) {
          { ok = True, diagnostics = [] }
        } else {
          // 2. Lex + Parse
          val tokens = Lex.lex(source);
          match (parseOutcome(tokens)) {
            ParseFail(msg, off, ln, col) =>
              failWithDiags([mkParseErrDiag(entryPath, msg, off, ln, col)])
            ParseOk(prog) =>
              await doTypecheckAndEmit(prog, entryPath, moduleName, source, opts, ktiPath)
          }
        }
      }
    }
  }
}
