import * as Res from "kestrel:data/result"
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import { all } from "kestrel:sys/task"

export type FsError = NotFound | PermissionDenied | IoError(String)

export type DirEntry = File(String) | Dir(String)

extern fun readFileAsync(path: String): Task<Result<String, String>> =
	jvm("kestrel.runtime.KRuntime#readFileAsync(java.lang.Object)")
extern fun listDirAsync(path: String): Task<Result<List<String>, String>> =
	jvm("kestrel.runtime.KRuntime#listDirAsync(java.lang.Object)")
extern fun writeTextAsync(path: String, content: String): Task<Result<Unit, String>> =
	jvm("kestrel.runtime.KRuntime#writeTextAsync(java.lang.Object,java.lang.Object)")

fun mapFsError(code: String): FsError =
	if (Str.equals(code, "not_found")) NotFound
	else if (Str.equals(code, "permission_denied")) PermissionDenied
	else if (Str.startsWith("io_error:", code)) IoError(Str.dropLeft(code, 9))
	else IoError(code)

fun toDirEntry(raw: String): DirEntry = {
	val tabIdx = Str.indexOf(raw, "\t");
	if (tabIdx < 0) File(raw)
	else {
		val path = Str.slice(raw, 0, tabIdx);
		val kind = Str.slice(raw, tabIdx + 1, Str.length(raw));
		if (Str.equals(kind, "dir")) Dir(path) else File(path)
	}
}

export async fun readText(path: String): Task<Result<String, FsError>> = {
	val result = await readFileAsync(path)
	Res.mapError(result, mapFsError)
}

export async fun listDir(path: String): Task<Result<List<DirEntry>, FsError>> = {
	val result = await listDirAsync(path)
	Res.mapError(Res.map(result, (entries: List<String>) => Lst.map(entries, toDirEntry)), mapFsError)
}

export async fun writeText(path: String, content: String): Task<Result<Unit, FsError>> = {
	val result = await writeTextAsync(path, content)
	Res.mapError(result, mapFsError)
}

extern fun readAllStdinAsync(): Task<String> =
    jvm("kestrel.runtime.KRuntime#readAllStdin()")

export async fun readStdin(): Task<String> =
    await readAllStdinAsync()

// ─── Path utilities ──────────────────────────────────────────────────────────

export fun pathBaseName(path: String): String =
  Lst.foldl(Str.split(path, "/"), "", (acc: String, s: String) => if (Str.isEmpty(s)) acc else s)

// ─── Recursive file collection ───────────────────────────────────────────────

fun getFiles(entries: List<DirEntry>, include: String -> Bool, acc: List<String>): List<String> =
  match (entries) {
    [] => acc
    hd :: tl => match (hd) {
      Dir(_) => getFiles(tl, include, acc)
      File(p) => if (include(p)) getFiles(tl, include, p :: acc) else getFiles(tl, include, acc)
    }
  }

fun getSubDirs(entries: List<DirEntry>, excludeDir: String -> Bool, acc: List<String>): List<String> =
  match (entries) {
    [] => acc
    hd :: tl => match (hd) {
      Dir(p) => if (excludeDir(p)) getSubDirs(tl, excludeDir, acc) else getSubDirs(tl, excludeDir, p :: acc)
      File(_) => getSubDirs(tl, excludeDir, acc)
    }
  }

// Recursively collect files from a directory tree.
// include: predicate returning True for file paths to include.
// excludeDir: predicate returning True for directory paths to skip.
export async fun collectFiles(dir: String, include: String -> Bool, excludeDir: String -> Bool): Task<List<String>> =
  match (await listDir(dir)) {
    Err(_) => []
    Ok(entries) => {
      val files = getFiles(entries, include, [])
      val subDirs = getSubDirs(entries, excludeDir, [])
      val subLists = await all(Lst.map(subDirs, (d: String) => collectFiles(d, include, excludeDir)))
      Lst.append(files, Lst.concat(subLists))
    }
  }
