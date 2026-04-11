// kestrel:tools/test/discovery — file-discovery helpers for `kestrel test`.
// Finds *.test.ks files under tests/unit/ and stdlib/kestrel/ (up to 3 levels deep).

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import { listDir, NotFound, PermissionDenied, IoError, DirEntry, File, Dir } from "kestrel:io/fs"
import { all } from "kestrel:sys/task"

// ─── Path utilities ───────────────────────────────────────────────────────────

export fun hasSuffix(s: String, suffix: String): Bool = Str.endsWith(suffix, s)

export fun isAbsolute(path: String): Bool =
  if (Str.length(path) > 0) Str.equals(Str.slice(path, 0, 1), "/") else False

export fun resolvePath(base: String, path: String): String =
  if (isAbsolute(path)) path else "${base}/${path}"

export fun resolvePaths(base: String, paths: List<String>): List<String> =
  Lst.map(paths, (p: String) => resolvePath(base, p))

export fun filterToTestFiles(paths: List<String>): List<String> =
  Lst.filter(paths, (p: String) => hasSuffix(p, ".test.ks"))

// ─── Directory listing ────────────────────────────────────────────────────────

export async fun listDirOrExit(path: String): Task<List<DirEntry>> =
  match (await listDir(path)) {
    Ok(entries) => entries,
    Err(err) => {
      val message =
        match (err) {
          NotFound => "not found"
          PermissionDenied => "permission denied"
          IoError(_) => "io error"
        };
      println("kestrel test: listDir failed for ${path}: ${message}");
      exit(1);
      []
    }
  }

export fun getTestFilePaths(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => match (hd) {
      Dir(_) => getTestFilePaths(tl, acc),
      File(p) => if (hasSuffix(p, ".test.ks")) getTestFilePaths(tl, p :: acc)
                 else getTestFilePaths(tl, acc)
    }
  }

export fun getDirPaths(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc,
    hd :: tl => match (hd) {
      Dir(path) => getDirPaths(tl, path :: acc),
      File(_) => getDirPaths(tl, acc)
    }
  }

// ─── High-level discovery ─────────────────────────────────────────────────────

/** Discover all *.test.ks files under unitDir and stdlibDir (3 levels deep). */
export async fun discoverTests(unitDir: String, stdlibDir: String): Task<List<String>> = {
  val unitEntries = await listDirOrExit(unitDir)
  val unitTests = getTestFilePaths(unitEntries, [])
  val stdlibEntries = await listDirOrExit(stdlibDir)
  val stdlibTopFiles = getTestFilePaths(stdlibEntries, [])
  val level1Dirs = getDirPaths(stdlibEntries, [])
  val level1EntryLists = await all(Lst.map(level1Dirs, (d: String) => listDirOrExit(d)))
  val level1Entries = Lst.concat(level1EntryLists)
  val level1Files = getTestFilePaths(level1Entries, [])
  val level2Dirs = getDirPaths(level1Entries, [])
  val level2EntryLists = await all(Lst.map(level2Dirs, (d: String) => listDirOrExit(d)))
  val level2Entries = Lst.concat(level2EntryLists)
  val level2Files = getTestFilePaths(level2Entries, [])
  val stdlibTests = Lst.append(stdlibTopFiles, Lst.append(level1Files, level2Files))
  Lst.append(unitTests, stdlibTests)
}
