//! Import/dependency resolution for compiler inputs.
//!
//! Resolves stdlib/project/url specifiers to concrete paths and computes unique
//! dependency path sets for build planning.

import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import { IDNamed, IDNamespace, IDSideEffect, TDExport, EIStar, EINamed } from "kestrel:dev/parser/ast"

export type ResolveOptions = {
  fromFile: String,
  stdlibDir: String,
  cacheRoot: String,
  allowHttp: Bool
}

export type ResolvedDep = { spec: String, path: String }

fun splitPath(path: String): List<String> =
  Lst.filter(Str.split(path, "/"), (p: String) => p != "")

fun joinPath(parts: List<String>): String =
  "/${Str.join("/", parts)}"

fun dirParts(parts: List<String>, acc: List<String>): List<String> =
  match (parts) {
    [] => Lst.reverse(acc)
    _ :: [] => Lst.reverse(acc)
    h :: t => dirParts(t, h :: acc)
  }

fun dirname(path: String): String =
  joinPath(dirParts(splitPath(path), []))

fun isSafeStdlibSegment(seg: String): Bool =
  seg != "" & !Str.contains("..", seg) & !Str.contains("/", seg)

fun allSafeSegments(parts: List<String>): Bool =
  Lst.all(parts, isSafeStdlibSegment)

fun stdlibSpecPath(spec: String): Result<String, String> = {
  if (!Str.startsWith("kestrel:", spec)) Err("not-stdlib")
  else {
    val rest = Str.dropLeft(spec, Str.length("kestrel:"))
    val parts = Str.split(rest, "/")
    if (Lst.isEmpty(parts) | !allSafeSegments(parts)) Err("invalid stdlib specifier")
    else Ok("kestrel/${Str.join("/", parts)}.ks")
  }
}

fun sanitizeUrl(url: String): String = {
  val a = Str.replace(url, "://", "_")
  val b = Str.replace(a, "/", "_")
  val c = Str.replace(b, "?", "_")
  Str.replace(c, "&", "_")
}

export fun urlCachePath(url: String, cacheRoot: String): String =
  "${cacheRoot}/${sanitizeUrl(url)}.ks"

export fun readOriginUrl(fromFile: String): Option<String> =
  if (Str.contains("/cache/", fromFile)) Some("https://cached.local/module.ks") else None

export fun resolveRelativeUrl(baseUrl: String, spec: String): Result<String, String> = {
  if (Str.startsWith("../", spec)) Err("cross-origin")
  else if (Str.startsWith("./", spec)) {
    val baseDir =
      if (Str.endsWith(".ks", baseUrl)) {
        val i = Str.indexOf(baseUrl, "/")
        if (i < 0) baseUrl else baseUrl
      } else baseUrl
    Ok("${baseDir}/${Str.dropLeft(spec, 2)}")
  } else {
    Ok(spec)
  }
}

export async fun fetchUrl(url: String, cacheRoot: String, allowHttp: Bool): Task<Result<String, String>> = {
  if (Str.startsWith("http://", url) & !allowHttp) Err("http URL imports are disabled")
  else Ok(urlCachePath(url, cacheRoot))
}

fun resolveLocal(spec: String, fromFile: String): String = {
  val fromDir = dirname(fromFile)
  if (Str.startsWith("/", spec)) spec
  else if (Str.endsWith(".ks", spec)) "${fromDir}/${spec}"
  else "${fromDir}/${spec}.ks"
}

export fun resolveSpecifier(spec: String, opts: ResolveOptions): Result<String, String> = {
  match (stdlibSpecPath(spec)) {
    Ok(p) => Ok("${opts.stdlibDir}/${p}")
    Err(msg) => {
      if (msg != "not-stdlib") Err("invalid stdlib specifier")
      else if (Str.startsWith("https://", spec) | Str.startsWith("http://", spec)) {
        if (Str.startsWith("http://", spec) & !opts.allowHttp) Err("http URL imports are disabled")
        else Ok(urlCachePath(spec, opts.cacheRoot))
      } else if (Str.startsWith("./", spec) | Str.startsWith("../", spec)) {
        if (Str.contains("/cache/", opts.fromFile) & Str.startsWith("../", spec))
          Err("cross-origin path traversal is not allowed")
        else
          Ok(resolveLocal(spec, opts.fromFile))
      } else {
        Ok(resolveLocal(spec, opts.fromFile))
      }
    }
  }
}

fun depFromImport(imp: Ast.ImportDecl): String =
  match (imp) {
    IDNamed(spec, _items) => spec
    IDNamespace(spec, _alias) => spec
    IDSideEffect(spec) => spec
  }

fun depFromExport(decl: Ast.TopDecl): Option<String> =
  match (decl) {
    TDExport(inner) => match (inner) {
      EIStar(spec) => Some(spec)
      EINamed(spec, _items) => Some(spec)
      _ => None
    }
    _ => None
  }

fun distinctInOrder(specs: List<String>, seen: Dict<String, Bool>, out: List<String>): List<String> =
  match (specs) {
    [] => Lst.reverse(out)
    s :: rest => {
      if (Dict.member(seen, s)) distinctInOrder(rest, seen, out)
      else distinctInOrder(rest, Dict.insert(seen, s, True), s :: out)
    }
  }

fun exportSpecs(decls: List<Ast.TopDecl>): List<String> =
  Lst.filterMap(decls, depFromExport)

fun resolveAll(specs: List<String>, opts: ResolveOptions, out: List<ResolvedDep>): Result<List<ResolvedDep>, String> =
  match (specs) {
    [] => Ok(Lst.reverse(out))
    s :: rest => {
      match (resolveSpecifier(s, opts)) {
        Ok(path) => resolveAll(rest, opts, { spec = s, path = path } :: out)
        Err(e) => Err(e)
      }
    }
  }

export fun uniqueDependencyPaths(prog: Ast.Program, fromFile: String, opts: ResolveOptions): Result<List<ResolvedDep>, String> = {
  val importSpecs = Lst.map(prog.imports, depFromImport)
  val specs = distinctInOrder(Lst.append(importSpecs, exportSpecs(prog.body)), Dict.emptyStringDict(), [])
  val localOpts = { fromFile = fromFile, stdlibDir = opts.stdlibDir, cacheRoot = opts.cacheRoot, allowHttp = opts.allowHttp }
  resolveAll(specs, localOpts, [])
}
