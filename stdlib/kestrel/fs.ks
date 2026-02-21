// kestrel:fs — readText calling __read_file_async (Task<String>) per spec 02.
export fun readText(path: String): Task<String> = __read_file_async(path)
