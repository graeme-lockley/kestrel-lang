import * as Lst from "kestrel:data/list"
import * as Diag from "kestrel:compiler/diagnostics"

export type Reporter = { items: mut List<Diag.Diagnostic> }

export fun newReporter(): Reporter = { mut items = [] }

export fun report(r: Reporter, d: Diag.Diagnostic): Unit =
  {
    r.items := Lst.append(r.items, [d]);
    ()
  }

export fun diagnostics(r: Reporter): List<Diag.Diagnostic> = r.items

fun isError(s: Diag.Severity): Bool =
  s == Diag.Error

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
