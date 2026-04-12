import * as Dict from "kestrel:data/dict"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as Kti from "kestrel:tools/compiler/kti"

export type CompileOptions = {
  outDir: String,
  stdlibDir: String,
  cacheRoot: String,
  allowHttp: Bool,
  writeKti: Bool
}

export type CompileResult = {
  ok: Bool,
  diagnostics: List<Diag.Diagnostic>
}

fun diag(file: String, code: String, message: String): Diag.Diagnostic = {
  severity = Diag.Error,
  code = code,
  message = message,
  location = Diag.locationFileOnly(file),
  sourceLine = None,
  related = [],
  suggestion = None,
  hint = None
}

export fun isFresh(kti: Kti.KtiV4, srcHash: String, depHashes: Dict<String, String>): Bool =
  kti.sourceHash == srcHash & kti.depHashes == depHashes

export async fun compileFile(entryPath: String, _opts: CompileOptions): Task<CompileResult> = {
  if (entryPath == "") {
    {
      ok = False,
      diagnostics = [diag(entryPath, Diag.CODES.file.readError, "entry path is empty")]
    }
  } else {
    {
      ok = True,
      diagnostics = []
    }
  }
}
