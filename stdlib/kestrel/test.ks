// Kestrel test framework — expectEqual, expectTrue, fail. On failure calls exit(1) for runner to detect.
export fun expectEqual(a: Int, b: Int): Unit = if (a == b) () else exit(1)
export fun expectTrue(b: Bool): Unit = if (b) () else exit(1)
export fun fail(msg: String): Unit = exit(1)
