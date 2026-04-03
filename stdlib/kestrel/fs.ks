import * as Res from "kestrel:result"
import * as Str from "kestrel:string"

export type FsError = NotFound | PermissionDenied | IoError(String)

fun mapFsError(code: String): FsError =
	if (Str.equals(code, "not_found")) NotFound
	else if (Str.equals(code, "permission_denied")) PermissionDenied
	else if (Str.startsWith("io_error:", code)) IoError(Str.dropLeft(code, 9))
	else IoError(code)

export async fun readText(path: String): Task<Result<String, FsError>> = {
	val result = await __read_file_async(path)
	Res.mapError(result, mapFsError)
}

export async fun listDir(path: String): Task<Result<List<String>, FsError>> = {
	val result = await __list_dir(path)
	Res.mapError(result, mapFsError)
}

export async fun writeText(path: String, content: String): Task<Result<Unit, FsError>> = {
	val result = await __write_text(path, content)
	Res.mapError(result, mapFsError)
}
