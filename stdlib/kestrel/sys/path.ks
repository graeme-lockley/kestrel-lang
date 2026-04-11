extern fun pathJoinImpl(parts: List<String>): String =
  jvm("kestrel.runtime.KRuntime#pathJoin(java.lang.Object)")

extern fun pathDirnameImpl(path: String): String =
  jvm("kestrel.runtime.KRuntime#pathDirname(java.lang.Object)")

extern fun pathBasenameImpl(path: String): String =
  jvm("kestrel.runtime.KRuntime#pathBasename(java.lang.Object)")

extern fun pathResolveImpl(base: String, rel: String): String =
  jvm("kestrel.runtime.KRuntime#pathResolve(java.lang.Object,java.lang.Object)")

extern fun pathIsAbsoluteImpl(path: String): Bool =
  jvm("kestrel.runtime.KRuntime#pathIsAbsolute(java.lang.Object)")

extern fun pathExtensionImpl(path: String): Option<String> =
  jvm("kestrel.runtime.KRuntime#pathExtension(java.lang.Object)")

extern fun pathWithoutExtensionImpl(path: String): String =
  jvm("kestrel.runtime.KRuntime#pathWithoutExtension(java.lang.Object)")

extern fun pathSplitImpl(path: String): (String, String) =
  jvm("kestrel.runtime.KRuntime#pathSplit(java.lang.Object)")

extern fun pathNormalizeImpl(path: String): String =
  jvm("kestrel.runtime.KRuntime#pathNormalize(java.lang.Object)")

export fun join(parts: List<String>): String = pathJoinImpl(parts)
export fun dirname(path: String): String = pathDirnameImpl(path)
export fun basename(path: String): String = pathBasenameImpl(path)
export fun resolve(base: String, rel: String): String = pathResolveImpl(base, rel)
export fun isAbsolute(path: String): Bool = pathIsAbsoluteImpl(path)
export fun extension(path: String): Option<String> = pathExtensionImpl(path)
export fun withoutExtension(path: String): String = pathWithoutExtensionImpl(path)
export fun splitPath(path: String): (String, String) = pathSplitImpl(path)
export fun normalize(path: String): String = pathNormalizeImpl(path)
