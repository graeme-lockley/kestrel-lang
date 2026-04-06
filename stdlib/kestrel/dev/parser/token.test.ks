import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"
import * as Lst from "kestrel:data/list"
import * as Token from "kestrel:dev/parser/token"
import { TPLiteral, TPInterp, TkTemplate } from "kestrel:dev/parser/token"

export async fun run(s: Suite): Task<Unit> =
  group(s, "token", (s1: Suite) => {

    group(s1, "spanZero", (sg: Suite) => {
      eq(sg, "start is 0", Token.spanZero().start, 0);
      eq(sg, "end is 0", Token.spanZero().end, 0);
      eq(sg, "line is 1", Token.spanZero().line, 1);
      eq(sg, "col is 1", Token.spanZero().col, 1)
    });

    group(s1, "isTrivia - trivia kinds", (sg: Suite) => {
      isTrue(sg, "TkWs is trivia",
        Token.isTrivia({ kind = Token.TkWs, text = " ", span = Token.spanZero() }));
      isTrue(sg, "TkLineComment is trivia",
        Token.isTrivia({ kind = Token.TkLineComment, text = "// x", span = Token.spanZero() }));
      isTrue(sg, "TkBlockComment is trivia",
        Token.isTrivia({ kind = Token.TkBlockComment, text = "/* */", span = Token.spanZero() }))
    });

    group(s1, "isTrivia - non-trivia kinds", (sg: Suite) => {
      isFalse(sg, "TkIdent is not trivia",
        Token.isTrivia({ kind = Token.TkIdent, text = "x", span = Token.spanZero() }));
      isFalse(sg, "TkKw is not trivia",
        Token.isTrivia({ kind = Token.TkKw, text = "fun", span = Token.spanZero() }));
      isFalse(sg, "TkEof is not trivia",
        Token.isTrivia({ kind = Token.TkEof, text = "", span = Token.spanZero() }))
    });

    group(s1, "TemplatePart construction", (sg: Suite) => {
      match (Token.TPLiteral("hello")) {
        TPLiteral(s) => eq(sg, "TPLiteral extracts string", s, "hello"),
        _ => isTrue(sg, "expected TPLiteral", False)
      };
      match (Token.TPInterp("x + 1")) {
        TPInterp(s) => eq(sg, "TPInterp extracts string", s, "x + 1"),
        _ => isTrue(sg, "expected TPInterp", False)
      };
      match (Token.TkTemplate([Token.TPLiteral("a"), Token.TPInterp("x")])) {
        TkTemplate(parts) => eq(sg, "TkTemplate parts length", Lst.length(parts), 2),
        _ => isTrue(sg, "expected TkTemplate", False)
      }
    })

  })
