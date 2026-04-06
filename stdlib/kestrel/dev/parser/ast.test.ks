import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import {
  ATIdent, ATQualified, ATPrim, ATArrow, ATRecord, ATRowVar, ATApp, ATUnion, ATInter, ATTuple,
  PWild, PVar, PLit, PCon, PList, PCons, PTuple,
  ELit, EIdent, ECall, EField, EAwait, EUnary, EBinary, ECons, EPipe,
  EIf, EWhile, EMatch, ELambda, ETemplate, EList, ERecord, ETuple,
  EThrow, ETry, EBlock, EIs, ENever,
  SVal, SVar, SAssign, SExpr, SFun, SBreak, SContinue,
  TmplLit, TmplExpr, LElem, LSpread,
  IDNamed, IDNamespace, IDSideEffect,
  EIStar, EINamed, EIDecl,
  TDFun, TDExternFun, TDExternImport, TDExternType, TDType, TDException, TDExport,
  TDVal, TDVar, TDSVal, TDSVar, TDSAssign, TDSExpr,
  TBAdt, TBAlias
} from "kestrel:dev/parser/ast"

export async fun run(s: Suite): Task<Unit> =
  group(s, "ast", (s1: Suite) => {

    group(s1, "AstType construction", (sg: Suite) => {
      match (ATIdent("Foo")) {
        ATIdent(n) => eq(sg, "ATIdent name", n, "Foo"),
        _ => isTrue(sg, "expected ATIdent", False)
      };
      match (ATArrow([ATPrim("Int")], ATPrim("Bool"))) {
        ATArrow(ps, ret) => {
          eq(sg, "ATArrow params length", Lst.length(ps), 1);
          match (ret) { ATPrim(r) => eq(sg, "ATArrow return", r, "Bool"), _ => isTrue(sg, "expected ATPrim", False) }
        },
        _ => isTrue(sg, "expected ATArrow", False)
      };
      match (ATApp("List", [ATPrim("Int")])) {
        ATApp(n, args) => {
          eq(sg, "ATApp name", n, "List");
          eq(sg, "ATApp args length", Lst.length(args), 1)
        },
        _ => isTrue(sg, "expected ATApp", False)
      };
      match (ATRecord([{ name = "x", mut_ = False, type_ = ATPrim("Int") }])) {
        ATRecord(fields) => eq(sg, "ATRecord fields length", Lst.length(fields), 1),
        _ => isTrue(sg, "expected ATRecord", False)
      };
      match (ATTuple([ATPrim("Int"), ATPrim("Bool")])) {
        ATTuple(ts) => eq(sg, "ATTuple length", Lst.length(ts), 2),
        _ => isTrue(sg, "expected ATTuple", False)
      };
      match (ATUnion(ATIdent("A"), ATIdent("B"))) {
        ATUnion(l, r) => {
          match (l) { ATIdent(n) => eq(sg, "ATUnion left", n, "A"), _ => isTrue(sg, "expected ATIdent", False) };
          match (r) { ATIdent(n) => eq(sg, "ATUnion right", n, "B"), _ => isTrue(sg, "expected ATIdent", False) }
        },
        _ => isTrue(sg, "expected ATUnion", False)
      };
      match (ATQualified("Mod", "T")) {
        ATQualified(m, t) => { eq(sg, "ATQualified mod", m, "Mod"); eq(sg, "ATQualified type", t, "T") },
        _ => isTrue(sg, "expected ATQualified", False)
      }
    });

    group(s1, "Pattern construction", (sg: Suite) => {
      isTrue(sg, "PWild fires",
        match (PWild) { PWild => True, _ => False });
      match (PVar("x")) {
        PVar(n) => eq(sg, "PVar name", n, "x"),
        _ => isTrue(sg, "expected PVar", False)
      };
      match (PLit("int", "42")) {
        PLit(k, v) => { eq(sg, "PLit kind", k, "int"); eq(sg, "PLit value", v, "42") },
        _ => isTrue(sg, "expected PLit", False)
      };
      match (PCon("Some", [{ name = "__field_0", pattern = Some(PVar("x")) }])) {
        PCon(n, fields) => {
          eq(sg, "PCon name", n, "Some");
          eq(sg, "PCon fields length", Lst.length(fields), 1)
        },
        _ => isTrue(sg, "expected PCon", False)
      };
      match (PList([PWild], Some("rest"))) {
        PList(elems, rest) => {
          eq(sg, "PList elems length", Lst.length(elems), 1);
          match (rest) { Some(r) => eq(sg, "PList rest", r, "rest"), None => isTrue(sg, "expected Some", False) }
        },
        _ => isTrue(sg, "expected PList", False)
      };
      match (PCons(PVar("h"), PVar("t"))) {
        PCons(h, t) => {
          match (h) { PVar(n) => eq(sg, "PCons head", n, "h"), _ => isTrue(sg, "expected PVar", False) };
          match (t) { PVar(n) => eq(sg, "PCons tail", n, "t"), _ => isTrue(sg, "expected PVar", False) }
        },
        _ => isTrue(sg, "expected PCons", False)
      };
      match (PTuple([PVar("a"), PVar("b")])) {
        PTuple(elems) => eq(sg, "PTuple length", Lst.length(elems), 2),
        _ => isTrue(sg, "expected PTuple", False)
      }
    });

    group(s1, "Expr construction", (sg: Suite) => {
      match (ELit("int", "42")) {
        ELit(k, v) => { eq(sg, "ELit kind", k, "int"); eq(sg, "ELit value", v, "42") },
        _ => isTrue(sg, "expected ELit", False)
      };
      match (EIdent("x")) {
        EIdent(n) => eq(sg, "EIdent name", n, "x"),
        _ => isTrue(sg, "expected EIdent", False)
      };
      match (ECall(EIdent("f"), [ELit("int", "1")])) {
        ECall(callee, args) => {
          match (callee) { EIdent(n) => eq(sg, "ECall callee", n, "f"), _ => isTrue(sg, "expected EIdent", False) };
          eq(sg, "ECall args length", Lst.length(args), 1)
        },
        _ => isTrue(sg, "expected ECall", False)
      };
      match (EBinary("+", ELit("int","1"), ELit("int","2"))) {
        EBinary(op, _, _) => eq(sg, "EBinary op", op, "+"),
        _ => isTrue(sg, "expected EBinary", False)
      };
      match (EIf(EIdent("c"), EIdent("t"), Some(EIdent("e")))) {
        EIf(_, _, else_) => match (else_) { Some(_) => isTrue(sg, "EIf has else", True), None => isTrue(sg, "expected Some", False) },
        _ => isTrue(sg, "expected EIf", False)
      };
      match (EIf(EIdent("c"), EIdent("t"), None)) {
        EIf(_, _, else_) => match (else_) { None => isTrue(sg, "EIf no else", True), Some(_) => isTrue(sg, "expected None", False) },
        _ => isTrue(sg, "expected EIf", False)
      };
      match (ELambda(False, [], [{ name = "x", type_ = None }], EIdent("x"))) {
        ELambda(_, _, ps, _) => eq(sg, "ELambda params length", Lst.length(ps), 1),
        _ => isTrue(sg, "expected ELambda", False)
      };
      match (ETemplate([TmplLit("hello "), TmplExpr(EIdent("name"))])) {
        ETemplate(parts) => eq(sg, "ETemplate parts length", Lst.length(parts), 2),
        _ => isTrue(sg, "expected ETemplate", False)
      };
      match (ERecord(None, [{ name = "x", mut_ = False, value = ELit("int","1") }])) {
        ERecord(spread, fields) => {
          match (spread) { None => isTrue(sg, "ERecord spread is None", True), Some(_) => isTrue(sg, "expected None", False) };
          eq(sg, "ERecord fields length", Lst.length(fields), 1)
        },
        _ => isTrue(sg, "expected ERecord", False)
      };
      isTrue(sg, "ENever fires",
        match (ENever) { ENever => True, _ => False })
    });

    group(s1, "Stmt construction", (sg: Suite) => {
      match (SVal("x", None, ELit("int","1"))) {
        SVal(n, _, _) => eq(sg, "SVal name", n, "x"),
        _ => isTrue(sg, "expected SVal", False)
      };
      match (SAssign(EIdent("x"), ELit("int","2"))) {
        SAssign(_, _) => isTrue(sg, "SAssign fires", True),
        _ => isTrue(sg, "expected SAssign", False)
      };
      isTrue(sg, "SBreak fires",
        match (SBreak) { SBreak => True, _ => False });
      isTrue(sg, "SContinue fires",
        match (SContinue) { SContinue => True, _ => False });
      match (SFun(False, "f", [], [], ATPrim("Unit"), ELit("unit","()"))) {
        SFun(_, n, _, _, _, _) => eq(sg, "SFun name", n, "f"),
        _ => isTrue(sg, "expected SFun", False)
      }
    });

    group(s1, "ImportDecl construction", (sg: Suite) => {
      match (IDNamed("m", [{ external = "foo", local = "bar" }])) {
        IDNamed(spec, imports) => {
          eq(sg, "IDNamed spec", spec, "m");
          eq(sg, "IDNamed imports length", Lst.length(imports), 1)
        },
        _ => isTrue(sg, "expected IDNamed", False)
      };
      match (IDNamespace("m", "M")) {
        IDNamespace(spec, alias) => { eq(sg, "IDNamespace spec", spec, "m"); eq(sg, "IDNamespace alias", alias, "M") },
        _ => isTrue(sg, "expected IDNamespace", False)
      };
      match (IDSideEffect("m")) {
        IDSideEffect(spec) => eq(sg, "IDSideEffect spec", spec, "m"),
        _ => isTrue(sg, "expected IDSideEffect", False)
      }
    });

    group(s1, "TopDecl construction", (sg: Suite) => {
      match (TDSVal("x", ELit("int","1"))) {
        TDSVal(n, _) => eq(sg, "TDSVal name", n, "x"),
        _ => isTrue(sg, "expected TDSVal", False)
      };
      match (TDExport(EIStar("m"))) {
        TDExport(inner) => match (inner) {
          EIStar(spec) => eq(sg, "TDExport EIStar spec", spec, "m"),
          _ => isTrue(sg, "expected EIStar", False)
        },
        _ => isTrue(sg, "expected TDExport", False)
      };
      match (TDType({ visibility = "local", name = "T", typeParams = [], body = TBAlias(ATPrim("Int")) })) {
        TDType(d) => {
          eq(sg, "TDType visibility", d.visibility, "local");
          eq(sg, "TDType name", d.name, "T")
        },
        _ => isTrue(sg, "expected TDType", False)
      }
    });

    group(s1, "Program construction", (sg: Suite) => {
      val prog = { imports = [], body = [TDSExpr(ELit("unit","()"))] };
      eq(sg, "imports length 0", Lst.length(prog.imports), 0);
      eq(sg, "body length 1", Lst.length(prog.body), 1)
    })

  })
