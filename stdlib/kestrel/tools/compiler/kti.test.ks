import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Res from "kestrel:data/result"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Kti from "kestrel:tools/compiler/kti"
import { KtiFunction, KtiVal, KtiVar, KtiConstructor } from "kestrel:tools/compiler/kti"
import * as Ty from "kestrel:dev/typecheck/types"

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => prog
    Err(e) => throw e
  }

fun baseExports(): Dict<String, Ty.InternalType> =
  Dict.insert(
    Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)),
    "x",
    Ty.tInt
  )

export async fun run(s: Suite): Task<Unit> =
  {
    val rtProg = program("export fun id(x: Int): Int = x")
    val rtKti = Kti.buildKtiV4(
      rtProg,
      Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)),
      Dict.emptyStringDict(),
      Dict.emptyStringDict(),
      Dict.emptyStringDict(),
      "src",
      Dict.emptyStringDict()
    )
    val rtPath = "/tmp/kestrel-kti-roundtrip.kti"
    val rtWrite = await Kti.writeKtiFile(rtPath, rtKti)
    val rtRead = await Kti.readKtiFile(rtPath)

    val metaRtSrc = "export fun add(a: Int, b: Int): Int = a\nexport type Color = Red | Green\nexport exception Boom { code: Int }"
    val metaRtProg = program(metaRtSrc)
    val metaRtColorType = Ty.TApp("Color", [])
    val metaRtBoomType = Ty.TApp("Boom", [])
    val metaRtExports = Dict.insert(
      Dict.insert(Dict.emptyStringDict(), "add", Ty.TArrow([Ty.tInt, Ty.tInt], Ty.tInt)),
      "Boom",
      metaRtBoomType
    )
    val metaRtCtorExports = Dict.insert(
      Dict.insert(Dict.emptyStringDict(), "Red", metaRtColorType),
      "Green",
      metaRtColorType
    )
    val metaRtTypeAliases = Dict.insert(Dict.emptyStringDict(), "Color", metaRtColorType)
    val metaRtTypeVis = Dict.insert(Dict.emptyStringDict(), "Color", "export")
    val metaRtKti = Kti.buildKtiV4(metaRtProg, metaRtExports, metaRtTypeAliases, metaRtCtorExports, metaRtTypeVis, "src", Dict.emptyStringDict())
    val metaRtPath = "/tmp/kestrel-kti-codegenmeta-roundtrip.kti"
    val metaRtWrite = await Kti.writeKtiFile(metaRtPath, metaRtKti)
    val metaRtRead = await Kti.readKtiFile(metaRtPath)

    group(s, "kestrel:tools/compiler/kti", (s1: Suite) => {
    group(s1, "build v4 shape", (sg: Suite) => {
      val prog = program("export fun id(x: Int): Int = x\nexport val x: Int = 1")
      val kti = Kti.buildKtiV4(
        prog,
        baseExports(),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        "module source",
        Dict.emptyStringDict()
      )
      eq(sg, "version", kti.version, 4)
      isTrue(sg, "functions include id", Dict.member(kti.functions, "id"))
      isTrue(sg, "sourceHash present", kti.sourceHash != "")
    })

    group(s1, "write/read round trip", (sg: Suite) => {
      eq(sg, "write ok", Res.isOk(rtWrite), True)
      eq(sg, "read ok", Res.isOk(rtRead), True)
      match (rtRead) {
        Ok(k2) => {
          eq(sg, "round-trip version", k2.version, 4)
          isTrue(sg, "round-trip function kept", Dict.member(k2.functions, "id"))
        }
        Err(_) => isTrue(sg, "unexpected read error", False)
      }
    })

    group(s1, "deserialize exports", (sg: Suite) => {
      val prog = program("export fun id(x: Int): Int = x")
      val kti = Kti.buildKtiV4(
        prog,
        Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        "src",
        Dict.emptyStringDict()
      )
      val ex = Kti.deserializeExports(kti)
      match (Dict.get(ex, "id")) {
        Some(t) => eq(sg, "id type restored", Ty.typeToString(t), "(Int) -> Int")
        None => isTrue(sg, "missing id export", False)
      }
    })

    group(s1, "extract codegen meta", (sg: Suite) => {
      val src = "export fun f(x: Int): Int = x\nexport var c: Int = 0\nexport val k: Int = 1\nexport extern fun fetch(): Task<Int> = jvm(\"example.Runtime#fetch()I\")\nexport type Color = Red | Green\nexport exception Boom { code: Int }"
      val prog = program(src)
      val colorType = Ty.TApp("Color", [])
      val boomType = Ty.TApp("Boom", [])
      val exports = Dict.insert(
        Dict.insert(
          Dict.insert(
            Dict.insert(
              Dict.insert(Dict.emptyStringDict(), "f", Ty.TArrow([Ty.tInt], Ty.tInt)),
              "c",
              Ty.tInt
            ),
            "k",
            Ty.tInt
          ),
          "fetch",
          Ty.TArrow([], Ty.TApp("Task", [Ty.tInt]))
        ),
        "Boom",
        boomType
      )
      val typeAliases = Dict.insert(Dict.emptyStringDict(), "Color", colorType)
      val typeVis = Dict.insert(Dict.emptyStringDict(), "Color", "export")
      val meta = Kti.extractCodegenMeta(prog, exports, typeAliases, typeVis)
      match (Dict.get(meta.funArities, "f")) {
        Some(n) => eq(sg, "arity tracked", n, 1)
        None => isTrue(sg, "missing arity", False)
      }
      match (Dict.get(meta.funArities, "fetch")) {
        Some(n) => eq(sg, "extern arity tracked", n, 0)
        None => isTrue(sg, "missing extern arity", False)
      }
      isTrue(sg, "extern Task return marked async", Lst.member(meta.asyncFunNames, "fetch"))
      isTrue(sg, "var tracked", Lst.member(meta.varNames, "c"))
      isTrue(sg, "val tracked", Lst.member(meta.valOrVarNames, "k"))
      val colorGroups = Lst.filter(meta.adtConstructors, (g: Kti.KtiAdtConstructorGroup) => g.typeName == "Color")
      isTrue(sg, "missing adtConstructors group", !Lst.isEmpty(colorGroups))
      match (colorGroups) {
        [] => isTrue(sg, "unexpected empty color groups", False)
        adtGroup :: _ => {
          isTrue(sg, "Red constructor tracked", Lst.any(adtGroup.constructors, (c: (String, Int)) => c.0 == "Red" & c.1 == 0));
          isTrue(sg, "Green constructor tracked", Lst.any(adtGroup.constructors, (c: (String, Int)) => c.0 == "Green" & c.1 == 0))
        }
      }
      val boomDecls = Lst.filter(meta.exceptionDecls, (e: Kti.KtiExceptionEntry) => e.name == "Boom")
      isTrue(sg, "missing exceptionDecls entry", !Lst.isEmpty(boomDecls))
      match (boomDecls) {
        [] => isTrue(sg, "unexpected empty exception decls", False)
        exn :: _ => eq(sg, "exception arity tracked", exn.arity, 1)
      }
    })

    group(s1, "buildKtiV4 export entry kinds", (sg: Suite) => {
      val src = "export fun add(a: Int, b: Int): Int = a\nexport val fixed: Int = 1\nexport var counter: Int = 0\nexport type Color = Red | Green\nexport exception Boom { code: Int }"
      val prog = program(src)
      val colorType = Ty.TApp("Color", [])
      val boomType = Ty.TApp("Boom", [])
      val exports = Dict.insert(
        Dict.insert(
          Dict.insert(
            Dict.insert(Dict.emptyStringDict(), "add", Ty.TArrow([Ty.tInt, Ty.tInt], Ty.tInt)),
            "fixed",
            Ty.tInt
          ),
          "counter",
          Ty.tInt
        ),
        "Boom",
        boomType
      )
      val ctorExports = Dict.insert(
        Dict.insert(Dict.emptyStringDict(), "Red", colorType),
        "Green",
        colorType
      )
      val typeAliases = Dict.insert(Dict.emptyStringDict(), "Color", colorType)
      val typeVis = Dict.insert(Dict.emptyStringDict(), "Color", "export")
      val kti = Kti.buildKtiV4(prog, exports, typeAliases, ctorExports, typeVis, "src", Dict.emptyStringDict())

      match (Dict.get(kti.functions, "add")) {
        Some(KtiFunction(f)) => eq(sg, "add arity", f.arity, 2)
        _ => isTrue(sg, "add is function entry", False)
      }

      match (Dict.get(kti.functions, "fixed")) {
        Some(KtiVal(_)) => isTrue(sg, "fixed is val entry", True)
        _ => isTrue(sg, "fixed is val entry", False)
      }

      match (Dict.get(kti.functions, "counter")) {
        Some(KtiVar(_)) => isTrue(sg, "counter is var entry", True)
        _ => isTrue(sg, "counter is var entry", False)
      }

      match (Dict.get(kti.functions, "Red")) {
        Some(KtiConstructor(c)) => {
          eq(sg, "Red ctor index", c.ctor_index, 0);
          eq(sg, "Red ctor arity", c.arity, 0)
        }
        _ => isTrue(sg, "Red is constructor entry", False)
      }

      match (Dict.get(kti.functions, "Green")) {
        Some(KtiConstructor(c)) => eq(sg, "Green ctor index", c.ctor_index, 1)
        _ => isTrue(sg, "Green is constructor entry", False)
      }

      match (Dict.get(kti.functions, "Boom")) {
        Some(KtiConstructor(c)) => eq(sg, "Boom exception arity", c.arity, 1)
        _ => isTrue(sg, "Boom is constructor entry", False)
      }

      match (Dict.get(kti.types, "Color")) {
        Some(entry) => {
          eq(sg, "Color kind is adt", entry.kind, "adt");
          match (entry.constructors) {
            Some(ctors) => eq(sg, "Color constructor count", Lst.length(ctors), 2)
            None => isTrue(sg, "Color constructors present", False)
          }
        }
        None => isTrue(sg, "Color type entry present", False)
      }
    })

    group(s1, "codegenMeta round-trip preserves adt and exception metadata", (sg: Suite) => {
      eq(sg, "write ok", Res.isOk(metaRtWrite), True)
      eq(sg, "read ok", Res.isOk(metaRtRead), True)
      match (metaRtRead) {
        Ok(readKti) => {
          isTrue(sg, "adtConstructors preserved", Lst.any(readKti.codegenMeta.adtConstructors, (g: Kti.KtiAdtConstructorGroup) => g.typeName == "Color"));
          isTrue(sg, "exceptionDecls preserved", Lst.any(readKti.codegenMeta.exceptionDecls, (e: Kti.KtiExceptionEntry) => e.name == "Boom" & e.arity == 1))
        }
        Err(_) => isTrue(sg, "unexpected read error", False)
      }
    })

    group(s1, "buildKtiV4 ADT constructor groups", (sg: Suite) => {
      val src = "export type Color = Red | Green | Blue\nexport val x: Int = 1"
      val prog = program(src)
      val colorType = Ty.TApp("Color", [])
      val ctorExports = Dict.insert(
        Dict.insert(
          Dict.insert(Dict.emptyStringDict(), "Red", colorType),
          "Green", colorType),
        "Blue", colorType)
      val typeAliases = Dict.insert(Dict.emptyStringDict(), "Color", colorType)
      val typeVis = Dict.insert(Dict.emptyStringDict(), "Color", "export")
      val kti = Kti.buildKtiV4(
        prog,
        Dict.insert(Dict.emptyStringDict(), "x", Ty.tInt),
        typeAliases,
        ctorExports,
        typeVis,
        "src",
        Dict.emptyStringDict()
      )
      val colorEntry = Dict.get(kti.types, "Color")
      match (colorEntry) {
        None => isTrue(sg, "Color type entry present", False)
        Some(entry) => {
          match (entry.constructors) {
            None => isTrue(sg, "constructors present", False)
            Some(ctors) => {
              eq(sg, "ctor count", Lst.length(ctors), 3);
              isTrue(sg, "Red in ctors", Lst.any(ctors, (c: (String, Int)) => c.0 == "Red"));
              isTrue(sg, "Green in ctors", Lst.any(ctors, (c: (String, Int)) => c.0 == "Green"));
              isTrue(sg, "Blue in ctors", Lst.any(ctors, (c: (String, Int)) => c.0 == "Blue"))
            }
          }
        }
      }
    });

    group(s1, "deserializeCtorMaps round-trip", (sg: Suite) => {
      val src = "export type Color = Red | Green\nexport val x: Int = 1"
      val prog = program(src)
      val colorType = Ty.TApp("Color", [])
      val ctorExports = Dict.insert(
        Dict.insert(Dict.emptyStringDict(), "Red", colorType),
        "Green", colorType)
      val typeAliases = Dict.insert(Dict.emptyStringDict(), "Color", colorType)
      val typeVis = Dict.insert(Dict.emptyStringDict(), "Color", "export")
      val kti = Kti.buildKtiV4(
        prog,
        Dict.insert(Dict.emptyStringDict(), "x", Ty.tInt),
        typeAliases,
        ctorExports,
        typeVis,
        "src",
        Dict.emptyStringDict()
      )
      val maps = Kti.deserializeCtorMaps(kti)
      val ctorEnv = maps.0
      val adtCtors = maps.1
      val ctorOwners = maps.2

      // adtConstructors
      match (Dict.get(adtCtors, "Color")) {
        None => isTrue(sg, "Color in adtConstructors", False)
        Some(ctorList) => {
          eq(sg, "ctor list length", Lst.length(ctorList), 2);
          isTrue(sg, "Red in list", Lst.member(ctorList, "Red"));
          isTrue(sg, "Green in list", Lst.member(ctorList, "Green"))
        }
      };

      // ctorOwners
      eq(sg, "Red owner", Dict.get(ctorOwners, "Red"), Some("Color"));
      eq(sg, "Green owner", Dict.get(ctorOwners, "Green"), Some("Color"));

      // ctorEnv types
      isTrue(sg, "Red in ctorEnv", Dict.member(ctorEnv, "Red"));
      isTrue(sg, "Green in ctorEnv", Dict.member(ctorEnv, "Green"))
    });

    group(s1, "opaque ADT excluded from ctor maps", (sg: Suite) => {
      val src = "export type Secret = SecretCtor"
      val prog = program(src)
      val secretType = Ty.TApp("Secret", [])
      val ctorExports = Dict.emptyStringDict()
      val typeAliases = Dict.insert(Dict.emptyStringDict(), "Secret", secretType)
      val typeVis = Dict.insert(Dict.emptyStringDict(), "Secret", "opaque")
      val kti = Kti.buildKtiV4(
        prog,
        Dict.emptyStringDict(),
        typeAliases,
        ctorExports,
        typeVis,
        "src",
        Dict.emptyStringDict()
      )
      val maps = Kti.deserializeCtorMaps(kti)
      val adtCtors = maps.1
      isTrue(sg, "opaque type excluded from adtConstructors", !Dict.member(adtCtors, "Secret"))
    })
    })
  }
