//! Declaration signature pretty-printer for Kestrel doc entries.
//! Takes a `DocEntry` (from `kestrel:dev/doc/extract`) and returns a
//! normalised, human-readable signature string suitable for display in the
//! documentation browser.
import * as Str from "kestrel:data/string"
import { DocEntry, DKType } from "kestrel:dev/doc/extract"

/// Format a `DocEntry` signature for display.
/// For `DKType` entries the full declaration is returned as-is (no truncation),
/// since the complete body is part of the type's public API.
/// For all other kinds the signature is trimmed and truncated with ` …` if it
/// exceeds 120 characters.
export fun format(entry: DocEntry): String = {
  val sig = Str.trim(entry.signature)
  if (entry.kind == DKType) sig
  else if (Str.length(sig) > 120) "${Str.slice(sig, 0, 117)} …"
  else sig
}
