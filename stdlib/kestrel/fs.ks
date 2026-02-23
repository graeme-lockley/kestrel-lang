// kestrel:fs — readText calling __read_file_async (Task<String>) per spec 02.
export fun readText(path: String): Task<String> = __read_file_async(path)
export fun listDir(path: String): List<String> = __list_dir(path)
export fun writeText(path: String, content: String): Unit = __write_text(path, content)
