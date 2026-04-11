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

fun dirPaths(entries: List<DirEntry>, acc: List<String>): List<String> =
  match (entries) {
    [] => acc
    hd :: tl => match (hd) {
      Dir(p) => dirPaths(tl, p :: acc)
      File(_) => dirPaths(tl, acc)
    }
  }

async fun listDirAllLoop(pending: List<String>, acc: List<DirEntry>): Task<Result<List<DirEntry>, FsError>> =
  match (pending) {
    [] => Ok(Lst.reverse(acc))
    d :: rest => {
      val step = await listDir(d)
      match (step) {
        Err(e) => Err(e)
        Ok(entries) => {
          val subDirs = dirPaths(entries, [])
          val next: Task<Result<List<DirEntry>, FsError>> = listDirAllLoop(Lst.append(subDirs, rest), Lst.append(entries, acc))
          await next
        }
      }
    }
  }

export async fun listDirAll(path: String): Task<Result<List<DirEntry>, FsError>> =
  await listDirAllLoop([path], [])

fun collectExt(entries: List<DirEntry>, ext: String, acc: List<String>): List<String> =
  match (entries) {
    [] => Lst.reverse(acc)
    hd :: tl => match (hd) {
      Dir(_) => collectExt(tl, ext, acc)
      File(p) => if (Str.endsWith(ext, p)) collectExt(tl, ext, p :: acc) else collectExt(tl, ext, acc)
    }
  }

export async fun collectFilesByExtension(path: String, ext: String): Task<Result<List<String>, FsError>> = {
  val allEntries = await listDirAll(path)
  Res.map(allEntries, (entries: List<DirEntry>) => collectExt(entries, ext, []))
}

export async fun writeText(path: String, content: String): Task<Result<Unit, FsError>> = {
	val result = await writeTextAsync(path, content)
	Res.mapError(result, mapFsError)
}

extern fun readAllStdinAsync(): Task<String> =
    jvm("kestrel.runtime.KRuntime#readAllStdin()")

export async fun readStdin(): Task<String> =
    await readAllStdinAsync()

extern fun fileExistsAsyncImpl(path: String): Task<Bool> =
	jvm("kestrel.runtime.KRuntime#fileExistsAsync(java.lang.Object)")

extern fun deleteFileAsyncImpl(path: String): Task<Result<Unit, String>> =
	jvm("kestrel.runtime.KRuntime#deleteFileAsync(java.lang.Object)")

extern fun renameFileAsyncImpl(src: String, dest: String): Task<Result<Unit, String>> =
	jvm("kestrel.runtime.KRuntime#renameFileAsync(java.lang.Object,java.lang.Object)")

export async fun fileExists(path: String): Task<Bool> =
	await fileExistsAsyncImpl(path)

export async fun deleteFile(path: String): Task<Result<Unit, FsError>> = {
	val result = await deleteFileAsyncImpl(path)
	Res.mapError(result, mapFsError)
}

export async fun renameFile(src: String, dest: String): Task<Result<Unit, FsError>> = {
	val result = await renameFileAsyncImpl(src, dest)
	Res.mapError(result, mapFsError)
}

// ─── Path utilities ──────────────────────────────────────────────────────────

export fun pathBaseName(path: String): String =
  Lst.foldl(Str.split(path, "/"), "", (acc: String, s: String) => if (Str.isEmpty(s)) acc else s)

// ─── ByteArray type and binary I/O ───────────────────────────────────────────

extern type JByteArray = jvm("java.lang.Object")

extern fun jbaNew(size: Int): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayNew(java.lang.Object)")
extern fun jbaLength(arr: JByteArray): Int =
  jvm("kestrel.runtime.KRuntime#byteArrayLength(java.lang.Object)")
extern fun jbaGet(arr: JByteArray, index: Int): Int =
  jvm("kestrel.runtime.KRuntime#byteArrayGet(java.lang.Object,java.lang.Object)")
extern fun jbaSet(arr: JByteArray, index: Int, value: Int): Unit =
  jvm("kestrel.runtime.KRuntime#byteArraySet(java.lang.Object,java.lang.Object,java.lang.Object)")
extern fun jbaFromList(xs: List<Int>): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayFromList(java.lang.Object)")
extern fun jbaToList(arr: JByteArray): List<Int> =
  jvm("kestrel.runtime.KRuntime#byteArrayToList(java.lang.Object)")
extern fun jbaConcat(a: JByteArray, b: JByteArray): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArrayConcat(java.lang.Object,java.lang.Object)")
extern fun jbaSlice(arr: JByteArray, start: Int, end: Int): JByteArray =
  jvm("kestrel.runtime.KRuntime#byteArraySlice(java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun readBytesAsyncImpl(path: String): Task<Result<JByteArray, String>> =
  jvm("kestrel.runtime.KRuntime#readBytesAsync(java.lang.Object)")
extern fun writeBytesAsyncImpl(path: String, bytes: JByteArray): Task<Result<Unit, String>> =
  jvm("kestrel.runtime.KRuntime#writeBytesAsync(java.lang.Object,java.lang.Object)")
extern fun appendBytesAsyncImpl(path: String, bytes: JByteArray): Task<Result<Unit, String>> =
  jvm("kestrel.runtime.KRuntime#appendBytesAsync(java.lang.Object,java.lang.Object)")

opaque type ByteArray = JByteArray

export fun byteArrayNew(size: Int): ByteArray = jbaNew(size)
export fun byteArrayLength(bytes: ByteArray): Int = jbaLength(bytes)
export fun byteArrayGet(bytes: ByteArray, index: Int): Int = jbaGet(bytes, index)
export fun byteArraySet(bytes: ByteArray, index: Int, value: Int): Unit = jbaSet(bytes, index, value)
export fun byteArrayFromList(xs: List<Int>): ByteArray = jbaFromList(xs)
export fun byteArrayToList(bytes: ByteArray): List<Int> = jbaToList(bytes)
export fun byteArrayConcat(a: ByteArray, b: ByteArray): ByteArray = jbaConcat(a, b)
export fun byteArraySlice(bytes: ByteArray, start: Int, end: Int): ByteArray = jbaSlice(bytes, start, end)

export async fun readBytes(path: String): Task<Result<ByteArray, FsError>> = {
  val result = await readBytesAsyncImpl(path)
  Res.mapError(result, mapFsError)
}

export async fun writeBytes(path: String, bytes: ByteArray): Task<Result<Unit, FsError>> = {
  val result = await writeBytesAsyncImpl(path, bytes)
  Res.mapError(result, mapFsError)
}

export async fun appendBytes(path: String, bytes: ByteArray): Task<Result<Unit, FsError>> = {
  val result = await appendBytesAsyncImpl(path, bytes)
  Res.mapError(result, mapFsError)
}

// ─── Directory creation and file metadata ────────────────────────────────────

export type FileStat = { mtimeMs: Int, size: Int, isDir: Bool, isFile: Bool }

extern fun mkdirAllAsyncImpl(path: String): Task<Result<Unit, String>> =
  jvm("kestrel.runtime.KRuntime#mkdirAllAsync(java.lang.Object)")
extern fun statAsyncImpl(path: String): Task<Result<FileStat, String>> =
  jvm("kestrel.runtime.KRuntime#statAsync(java.lang.Object)")
extern fun touchFileAsyncImpl(path: String): Task<Result<Unit, String>> =
  jvm("kestrel.runtime.KRuntime#touchFileAsync(java.lang.Object)")

export async fun mkdirAll(path: String): Task<Result<Unit, FsError>> = {
  val result = await mkdirAllAsyncImpl(path)
  Res.mapError(result, mapFsError)
}

export async fun stat(path: String): Task<Result<FileStat, FsError>> = {
  val result = await statAsyncImpl(path)
  Res.mapError(result, mapFsError)
}

export async fun touchFile(path: String): Task<Result<Unit, FsError>> = {
  val result = await touchFileAsyncImpl(path)
  Res.mapError(result, mapFsError)
}

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

// ── File watching ────────────────────────────────────────────────────────────

export extern type Watcher = jvm("kestrel.runtime.KWatcher")

extern fun watchDirAsyncImpl(path: String, debounceMs: Int): Task<Result<Watcher, String>> =
  jvm("kestrel.runtime.KRuntime#watchDirAsync(java.lang.Object,java.lang.Object)")

extern fun watcherNextAsyncImpl(w: Watcher): Task<List<String>> =
  jvm("kestrel.runtime.KRuntime#watcherNextAsync(java.lang.Object)")

extern fun watcherCloseAsyncImpl(w: Watcher): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#watcherCloseAsync(java.lang.Object)")

/// Start watching a directory tree for file-system changes.
/// Returns `Err(FsError)` if the directory does not exist.
/// `debounceMs` controls how long after the first event to wait for additional events
/// before delivering the batch to `watcherNext`.
export async fun watchDir(path: String, debounceMs: Int): Task<Result<Watcher, FsError>> = {
  val r = await watchDirAsyncImpl(path, debounceMs);
  Res.mapError(r, mapFsError)
}

/// Block until the next batch of file-system change events and return the list
/// of changed absolute paths. Returns an empty list if the watcher has been closed.
export async fun watcherNext(w: Watcher): Task<List<String>> =
  await watcherNextAsyncImpl(w)

/// Close the file watcher. Subsequent calls to `watcherNext` return an empty list.
export async fun watcherClose(w: Watcher): Task<Unit> =
  await watcherCloseAsyncImpl(w)

extern fun tempPathImpl(path: String): String =
  jvm("kestrel.runtime.KRuntime#tempPath(java.lang.Object)")

/// Returns a sibling temporary path for `path` suitable for atomic write patterns.
/// The path is in the same directory so a rename is on the same filesystem.
export fun tempPath(path: String): String = tempPathImpl(path)

/// Write `content` to `path` atomically: writes to a sibling temp file then renames.
/// If the write fails, `path` is not modified.
export async fun writeTextAtomic(path: String, content: String): Task<Result<Unit, FsError>> = {
  val tmp = tempPath(path);
  val wr = await writeText(tmp, content);
  match (wr) {
    Err(e) => Err(e)
    Ok(_) => await renameFile(tmp, path)
  }
}

/// Write `bytes` to `path` atomically: writes to a sibling temp file then renames.
/// If the write fails, `path` is not modified.
export async fun writeBytesAtomic(path: String, bytes: ByteArray): Task<Result<Unit, FsError>> = {
  val tmp = tempPath(path);
  val wr = await writeBytes(tmp, bytes);
  match (wr) {
    Err(e) => Err(e)
    Ok(_) => await renameFile(tmp, path)
  }
}
