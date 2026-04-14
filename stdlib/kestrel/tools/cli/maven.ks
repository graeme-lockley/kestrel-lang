//! Maven classpath resolver for the Kestrel CLI.
//!
//! `resolveMavenClasspath` replicates the logic of `scripts/resolve-maven-classpath.mjs` in
//! Kestrel: it walks the transitive `.class.deps` dependency graph for a compiled `.ks` entry
//! point, reads `.kdeps` JSON sidecar files produced by the compiler, resolves Maven artefact
//! paths from the local cache, performs version-conflict detection, and returns the ordered
//! list of JAR paths to include in the JVM classpath.
//!
//! `mainClassFor` and `classFileForSource` are also exported here so that other CLI modules
//! (e.g. `kestrel:tools/cli`) can derive class names without duplicating the algorithm.

import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Res from "kestrel:data/result"
import * as Json from "kestrel:data/json"
import { StrVal, Object } from "kestrel:data/json"
import * as Path from "kestrel:sys/path"
import { readText, fileExists } from "kestrel:io/fs"

// ── Character predicates ──────────────────────────────────────────────────────

fun isIdentChar(c: Int): Bool =
  (c >= 65 & c <= 90)  |  // A–Z
  (c >= 97 & c <= 122) |  // a–z
  (c >= 48 & c <= 57)  |  // 0–9
  c == 95               // _

fun isIdentOrSlashChar(c: Int): Bool =
  isIdentChar(c) | c == 47  // '/'

// ── String helpers ────────────────────────────────────────────────────────────

fun sanitizeLoop(s: String, i: Int, n: Int, acc: String, pred: Int -> Bool): String =
  if (i >= n) acc
  else {
    val c = Str.codePointAt(s, i)
    val ch = if (pred(c)) Str.slice(s, i, i + 1) else "_"
    sanitizeLoop(s, i + 1, n, "${acc}${ch}", pred)
  }

// Replace chars not matching `pred` with `_`.
fun sanitize(s: String, pred: Int -> Bool): String =
  sanitizeLoop(s, 0, Str.length(s), "", pred)

// Uppercase the first code unit of `s` (ASCII-only; filename convention).
fun capitalizeFirst(s: String): String =
  if (Str.isEmpty(s)) s
  else "${Str.toUpperCase(Str.slice(s, 0, 1))}${Str.slice(s, 1, Str.length(s))}"

fun dropKsExt(base: String): String =
  if (Str.endsWith(".ks", base)) Str.dropRight(base, 3) else base

// ── Class-name derivation ─────────────────────────────────────────────────────

// Derive the slash-separated internal class name from an absolute .ks path.
// Matches the algorithm in `resolve-maven-classpath.mjs` and `main_class_for` in scripts/kestrel.
// Example: /Users/foo/hello.ks  →  Users/foo/Hello
// Example: /hello.ks            →  Hello
fun classInternalName(absPath: String): String = {
  val rel = if (Str.startsWith("/", absPath)) Str.dropLeft(absPath, 1) else absPath
  val dir = Path.dirname(rel)
  val base = capitalizeFirst(sanitize(dropKsExt(Path.basename(rel)), isIdentChar))
  if (dir == ".") base
  else "${sanitize(dir, isIdentOrSlashChar)}/${base}"
}

/// Derive the dot-separated Java main class name from an absolute .ks source path.
/// Example: /Users/foo/hello.ks  →  Users.foo.Hello
export fun mainClassFor(absSourcePath: String): String =
  Str.replace("/", ".", classInternalName(absSourcePath))

/// Absolute path of the compiled .class file for a .ks source in `classDir`.
export fun classFileForSource(classDir: String, absSourcePath: String): String =
  "${classDir}/${classInternalName(absSourcePath)}.class"

// ── Dependency helpers ────────────────────────────────────────────────────────

fun isKsFile(line: String): Bool = Str.endsWith(".ks", Str.trim(line))

fun ksDepsLines(content: String): List<String> =
  Lst.filter(Lst.map(Str.lines(content), Str.trim), (s: String) => Str.length(s) > 0 & isKsFile(s))

// ── JSON kdeps helpers ────────────────────────────────────────────────────────

// Extract (key, string-value) pairs from a JSON Object; skip non-string values.
fun stringPairsFrom(pairs: List<(String, Json.Value)>, acc: List<(String, String)>): List<(String, String)> =
  match (pairs) {
    [] => Lst.reverse(acc)
    h :: rest =>
      match (h.1) {
        StrVal(v) => stringPairsFrom(rest, (h.0, v) :: acc)
        _ => stringPairsFrom(rest, acc)
      }
  }

fun objectStringPairs(v: Json.Value): List<(String, String)> =
  match (v) {
    Object(pairs) => stringPairsFrom(pairs, [])
    _ => []
  }

// Look up a JSON field in an Object by key.
fun jsonLookup(pairs: List<(String, Json.Value)>, key: String): Option<Json.Value> =
  match (pairs) {
    [] => None
    h :: rest => if (h.0 == key) Some(h.1) else jsonLookup(rest, key)
  }

// ── Version-conflict helpers ──────────────────────────────────────────────────

fun lookupVersion(gaVersions: List<(String, String)>, ga: String): Option<String> =
  match (gaVersions) {
    [] => None
    h :: rest => if (h.0 == ga) Some(h.1) else lookupVersion(rest, ga)
  }

fun hasJar(jars: List<String>, jar: String): Bool =
  match (jars) {
    [] => False
    h :: t => if (h == jar) True else hasJar(t, jar)
  }

fun deriveJarPath(ga: String, version: String, mavenCache: String): String = {
  val colonIdx = Str.indexOf(ga, ":")
  if (colonIdx < 0) ""
  else {
    val groupId   = Str.slice(ga, 0, colonIdx)
    val artifactId = Str.dropLeft(ga, colonIdx + 1)
    val groupPath  = Str.replace(".", "/", groupId)
    Path.join([mavenCache, groupPath, artifactId, version, "${artifactId}-${version}.jar"])
  }
}

// ── Resolution loop ───────────────────────────────────────────────────────────

// Process a single Maven entry (ga → version) from a .kdeps file.
// Returns Ok with updated (gaVersions, gaSources, jarPaths) on success,
// Err with a conflict/missing message on failure.
fun processMavenEntry(
  ga: String,
  version: String,
  jarsOverride: Option<String>,
  source: String,
  mavenCache: String,
  gaVersions: List<(String, String)>,
  gaSources: List<(String, String)>,
  jarPaths: List<String>
): Result<(List<(String, String)>, List<(String, String)>, List<String>), String> = {
  val seenVersion = lookupVersion(gaVersions, ga)
  match (seenVersion) {
    Some(sv) =>
      if (sv == version) Ok((gaVersions, gaSources, jarPaths))
      else {
        val prevSrc = match (lookupVersion(gaSources, ga)) { Some(s) => s  None => "<unknown>" }
        Err("Dependency conflict:\n  ${prevSrc} requires ${ga}:${sv}\n  ${source} requires ${ga}:${version}\nFix: align both imports to the same version.")
      }
    None => {
      val newGaVersions = (ga, version) :: gaVersions
      val newGaSources  = (ga, source) :: gaSources
      val jar = match (jarsOverride) {
        Some(j) => j
        None    => deriveJarPath(ga, version, mavenCache)
      }
      if (Str.isEmpty(jar)) Ok((newGaVersions, newGaSources, jarPaths))
      else if (hasJar(jarPaths, jar)) Ok((newGaVersions, newGaSources, jarPaths))
      else Ok((newGaVersions, newGaSources, jar :: jarPaths))
    }
  }
}

// Process all Maven entries from a single .kdeps parse result.
fun processMavenList(
  mavenPairs: List<(String, String)>,
  jarsMap: List<(String, String)>,
  source: String,
  mavenCache: String,
  gaVersions: List<(String, String)>,
  gaSources: List<(String, String)>,
  jarPaths: List<String>
): Result<(List<(String, String)>, List<(String, String)>, List<String>), String> =
  match (mavenPairs) {
    [] => Ok((gaVersions, gaSources, jarPaths))
    h :: rest => {
      val ga = h.0
      val version = h.1
      val jarsOverride = lookupVersion(jarsMap, ga)
      val step = processMavenEntry(ga, version, jarsOverride, source, mavenCache, gaVersions, gaSources, jarPaths)
      match (step) {
        Err(msg) => Err(msg)
        Ok(newState) =>
          processMavenList(rest, jarsMap, source, mavenCache, newState.0, newState.1, newState.2)
      }
    }
  }

// Check all resolved jar paths exist on disk; return Err for the first missing one.
async fun checkAllJarsExist(jars: List<String>): Task<Result<Unit, String>> =
  match (jars) {
    [] => Ok(())
    jar :: rest => {
      val exists = await fileExists(jar)
      if (exists) {
        val next: Task<Result<Unit, String>> = checkAllJarsExist(rest)
        await next
      }
      else Err("kestrel: maven artifact missing: ${jar}")
    }
  }

// BFS loop: process the queue of source files one by one, accumulating state.
async fun resolveLoop(
  queue: List<String>,
  seen: List<String>,
  classDir: String,
  mavenCache: String,
  gaVersions: List<(String, String)>,
  gaSources: List<(String, String)>,
  jarPaths: List<String>
): Task<Result<List<String>, String>> =
  match (queue) {
    [] => {
      val checkResult = await checkAllJarsExist(Lst.reverse(jarPaths))
      match (checkResult) {
        Err(msg) => Err(msg)
        Ok(_) => Ok(Lst.reverse(jarPaths))
      }
    }
    source :: rest => {
      if (Lst.member(seen, source)) {
        val next: Task<Result<List<String>, String>> = resolveLoop(rest, seen, classDir, mavenCache, gaVersions, gaSources, jarPaths)
        await next
      }
      else {
        val newSeen = source :: seen
        val classFile = classFileForSource(classDir, source)
        val depsFile = "${classFile}.deps"

        // Read .class.deps to find transitive .ks source dependencies.
        val depsResult = await readText(depsFile)
        val moreSources: List<String> = match (depsResult) {
          Err(_) => []
          Ok(content) => ksDepsLines(content)
        }
        val newQueue = Lst.append(moreSources, rest)

        // Read .kdeps JSON sidecar to find Maven coordinates.
        val kdepsPath = Str.replace(".class", ".kdeps", classFile)
        val kdepsExists = await fileExists(kdepsPath)
        if (!kdepsExists) {
          val next: Task<Result<List<String>, String>> = resolveLoop(newQueue, newSeen, classDir, mavenCache, gaVersions, gaSources, jarPaths)
          await next
        }
        else {
          val kdepsResult = await readText(kdepsPath)
          match (kdepsResult) {
            Err(e) => Err("kestrel: could not read kdeps file: ${kdepsPath}")
            Ok(content) => {
              val parsed = Json.parse(content)
              match (parsed) {
                Err(e) => Err("kestrel: invalid kdeps file: ${kdepsPath}: ${Json.errorAsString(e)}")
                Ok(root) => {
                  val mavenObj: Option<Json.Value> = match (root) {
                    Object(pairs) => jsonLookup(pairs, "maven")
                    _ => None
                  }
                  val jarsObj: Option<Json.Value> = match (root) {
                    Object(pairs) => jsonLookup(pairs, "jars")
                    _ => None
                  }
                  val mavenPairs: List<(String, String)> = match (mavenObj) {
                    None => []
                    Some(v) => objectStringPairs(v)
                  }
                  val jarsMap: List<(String, String)> = match (jarsObj) {
                    None => []
                    Some(v) => objectStringPairs(v)
                  }
                  val result = processMavenList(mavenPairs, jarsMap, source, mavenCache, gaVersions, gaSources, jarPaths)
                  match (result) {
                    Err(msg) => Err(msg)
                    Ok(newState) => {
                      val next: Task<Result<List<String>, String>> = resolveLoop(newQueue, newSeen, classDir, mavenCache, newState.0, newState.1, newState.2)
                      await next
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

/// Resolve the transitive Maven classpath for a compiled Kestrel entry point.
///
/// - `entrySource` — absolute path to the entry `.ks` source file.
/// - `classDir`    — root directory containing compiled `.class` files.
/// - `mavenCache`  — root of the local Maven cache (e.g. `~/.kestrel/maven`).
///
/// Returns `Ok(jars)` — an ordered list of absolute JAR paths — or `Err(message)` on
/// version conflict, missing artefact, or parse error.
export async fun resolveMavenClasspath(
  entrySource: String,
  classDir: String,
  mavenCache: String
): Task<Result<List<String>, String>> =
  await resolveLoop([entrySource], [], classDir, mavenCache, [], [], [])
