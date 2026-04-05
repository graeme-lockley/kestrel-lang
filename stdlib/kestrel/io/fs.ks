import * as Res from "kestrel:data/result"
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"

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
