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
import * as Par from "kestrel:dev/parser/parser"
import * as TC from "kestrel:dev/typecheck/typecheck"
import * as Codegen from "kestrel:tools/compiler/codegen"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Fs from "kestrel:io/fs"

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

/// Derives the JVM class name from an absolute source path.
/// Mirrors `classNameForPath` in `compiler/src/compile-file-jvm.ts`:
/// strip leading `/`, remove `.ks` extension, split on `/`, sanitize each segment
/// (replace non-alphanumeric chars with `_`), capitalize the last segment, re-join.
export fun classNameForPath(path: String): String = {
  val normalized = if (Str.startsWith("/", path)) Str.dropLeft(path, 1) else path
  val withoutExt = if (Str.endsWith(".ks", normalized)) Str.dropRight(normalized, 3) else normalized
  val parts = Lst.filter(Str.split(withoutExt, "/"), (p: String) => !Str.isEmpty(p))
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

async fun writeAllClasses(outDir: String, pairs: List<(String, ByteArray)>): Task<Result<Unit, String>> =
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

export async fun compileFile(entryPath: String, opts: CompileOptions): Task<CompileResult> = {
  if (entryPath == "") {
    failResult(entryPath, Diag.CODES.file.readError, "entry path is empty")
  } else {
    // 1. Read source text
    match (await Fs.readText(entryPath)) {
      Err(_) =>
        failResult(entryPath, Diag.CODES.file.readError, "cannot read file: ${entryPath}")
      Ok(source) => {
        // 2. Lex
        val tokens = Lex.lex(source);
        // 3. Parse
        match (Par.parseFromList(tokens)) {
          Err(_parseErr) => { ok = False, diagnostics = [] }
          Ok(prog) => {
            // 4. Typecheck (no imports in this story)
            val tcOpts = {
              importBindings = None,
              typeAliasBindings = None,
              importOpaqueTypes = None,
              sourceFile = entryPath
            };
            val tc = TC.typecheck(prog, tcOpts);
            if (!tc.ok) {
              { ok = False, diagnostics = [] }
            } else {
              // 5. Code generate
              val moduleName = classNameForPath(entryPath);
              val codegenResult = Codegen.jvmCodegen(moduleName, prog);
              // 6. Write class files
              match (await Fs.mkdirAll(opts.outDir)) {
                Err(_) =>
                  failResult(entryPath, Diag.CODES.file.readError,
                    "cannot create output directory: ${opts.outDir}")
                Ok(()) => {
                  val pairs = Dict.toList(codegenResult.classes);
                  match (await writeAllClasses(opts.outDir, pairs)) {
                    Err(msg) => failResult(entryPath, Diag.CODES.file.readError, msg)
                    Ok(()) => { ok = True, diagnostics = [] }
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

