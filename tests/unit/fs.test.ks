import { readText } from "kestrel:fs"

// Smoke test: readText returns Task<String>; call it (file may not exist in all runs)
val _ = readText("tests/fixtures/hello.txt")
