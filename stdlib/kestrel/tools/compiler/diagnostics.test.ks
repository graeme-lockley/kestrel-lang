import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Diag from "kestrel:tools/compiler/diagnostics"
import * as Rep from "kestrel:tools/compiler/reporter"

fun mkDiag(sev: Diag.Severity): Diag.Diagnostic = {
  severity = sev,
  code = Diag.CODES.type_.check,
  message = "example message",
  location = {
    file = "main.ks",
    line = 1,
    column = 1,
    endLine = None,
    endColumn = None,
    offset = None,
    endOffset = None
  },
  sourceLine = None,
  related = [],
  suggestion = None,
  hint = None
}

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/diagnostics", (s1: Suite) => {
    group(s1, "diagnostic construction", (sg: Suite) => {
      val dErr = mkDiag(Diag.Error)
      val dWarn = mkDiag(Diag.Warning)
      val dInfo = mkDiag(Diag.Info)
      val dHint = mkDiag(Diag.Hint)

      eq(sg, "error severity present", dErr.severity, Diag.Error)
      eq(sg, "warning severity present", dWarn.severity, Diag.Warning)
      eq(sg, "info severity present", dInfo.severity, Diag.Info)
      eq(sg, "hint severity present", dHint.severity, Diag.Hint)
    });

    group(s1, "locationFromSpan", (sg: Suite) => {
      val span: Diag.Span = {
        file = "main.ks",
        startOffset = 0,
        endOffset = 6,
        startLine = 1,
        startColumn = 1
      }
      val loc = Diag.locationFromSpan("main.ks", span, Some("hello\nworld"))
      eq(sg, "line", loc.line, 1)
      eq(sg, "column", loc.column, 1)
      eq(sg, "end line", loc.endLine, Some(2))
      eq(sg, "end column", loc.endColumn, Some(1))
    });

    group(s1, "reporter accumulation", (sg: Suite) => {
      val r = Rep.newReporter()
      Rep.report(r, mkDiag(Diag.Warning))
      isFalse(sg, "warning-only hasErrors false", Rep.hasErrors(r))

      Rep.report(r, mkDiag(Diag.Error))
      isTrue(sg, "contains error => hasErrors true", Rep.hasErrors(r))
      eq(sg, "diagnostic count", Diag.lineColumnFromOffset("ab\ncd", 3).0, 2)
      eq(sg, "stored diagnostics", Rep.diagnostics(r) != [], True)
    })
  })
