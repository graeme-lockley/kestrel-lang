//! Diagnostic accumulator for compiler passes.
//!
//! `Reporter` collects `Diagnostic` values emitted during a compilation pass
//! and can render them in a human-readable format for CLI output.
import * as Lst from "kestrel:data/list"
import * as Diag from "kestrel:tools/compiler/diagnostics"

/// Mutable accumulator that collects `Diagnostic` values during a compiler pass.
export type Reporter = { items: mut List<Diag.Diagnostic> }

/// Create a new empty `Reporter`.
export fun newReporter(): Reporter = { mut items = [] }

/// Append `d` to the reporter's diagnostic list.
export fun report(r: Reporter, d: Diag.Diagnostic): Unit =
  {
    r.items := Lst.append(r.items, [d]);
    ()
  }

/// Return all diagnostics collected by `r` in insertion order.
export fun diagnostics(r: Reporter): List<Diag.Diagnostic> = r.items

fun isError(s: Diag.Severity): Bool =
  s == Diag.Error

/// Return `True` if any collected diagnostic has severity `Error`.
export fun hasErrors(r: Reporter): Bool =
  Lst.any(r.items, (d: Diag.Diagnostic) => isError(d.severity))

fun rangeSuffix(loc: Diag.SourceLocation): String =
  match (loc.endLine) {
    Some(el) =>
      match (loc.endColumn) {
        Some(ec) => "-${el}:${ec}"
        None => ""
      }
    None => ""
  }

fun printOne(d: Diag.Diagnostic): Unit = {
  val loc = d.location
  val path = if (loc.file == "") "<source>" else loc.file
  println("  --> ${path}:${loc.line}:${loc.column}${rangeSuffix(loc)}")
  println("   |")
  println(" ${loc.line} | ")
  println("    ^ ${d.message}")
  match (d.hint) {
    Some(h) => println("   = hint: ${h}")
    None => ()
  };
  match (d.suggestion) {
    Some(n) => println("   = note: ${n}")
    None => ()
  };
  println("")
}

fun printLoop(ds: List<Diag.Diagnostic>): Unit =
  match (ds) {
    [] => ()
    d :: rest => {
      printOne(d);
      printLoop(rest)
    }
  }

/// Human-readable diagnostic output.
export fun printDiagnostics(ds: List<Diag.Diagnostic>, _source: Option<String>): Unit =
  printLoop(ds)
