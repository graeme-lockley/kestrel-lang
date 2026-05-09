import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Json from "kestrel:data/json"
import * as Str from "kestrel:data/string"
import * as Ast from "kestrel:dev/parser/ast"
import { IDNamed } from "kestrel:dev/parser/ast"
import * as Fs from "kestrel:io/fs"
import * as Kti from "kestrel:tools/compiler/kti"
import { KtiFunction, DepLoadOk, DepLoadErr } from "kestrel:tools/compiler/kti"
import * as Ty from "kestrel:dev/typecheck/types"
import { TVar, TArrow, TScheme } from "kestrel:dev/typecheck/types"

fun assertRoundTrip(s: Suite, name: String, ty: Ty.InternalType): Unit =
  eq(s, name, Kti.deserializeType(Kti.serializeType(ty)), ty)

fun hasNegativeVarId(t: Ty.InternalType): Bool =
  Str.indexOf(Json.stringify(Kti.serializeType(t)), "\"id\":-") >= 0

export async fun run(s: Suite): Task<Unit> = {
  val idTy = Ty.TScheme([0], Ty.TArrow([Ty.TVar(0)], Ty.TVar(0)))
  val ktiPath = "/tmp/kestrel_kti_serialize_acceptance.kti"
  val depAPath = "/tmp/kestrel_kti_serialize_dep_a.kti"
  val depBPath = "/tmp/kestrel_kti_serialize_dep_b.kti"
  val _cleanupBefore = await Fs.deleteFile(ktiPath)
  val _cleanupDepABefore = await Fs.deleteFile(depAPath)
  val _cleanupDepBBefore = await Fs.deleteFile(depBPath)
  val kti: Kti.KtiV4 = {
    version = 4,
    functions = Dict.singletonStringDict(
      "id",
      KtiFunction({ kind = "function", function_index = 0, arity = 1, type_ = Kti.serializeType(idTy) })
    ),
    types = Dict.emptyStringDict(),
    sourceHash = "test-source-hash",
    depHashes = Dict.emptyStringDict(),
    codegenMeta = {
      funArities = Dict.emptyStringDict(),
      asyncFunNames = [],
      varNames = [],
      valOrVarNames = [],
      adtConstructors = [],
      exceptionDecls = []
    }
  }
  val writeOk = match (await Kti.writeKtiFile(ktiPath, kti)) {
    Ok(_) => True
    Err(_) => False
  }
  val ktiText = match (await Fs.readText(ktiPath)) {
    Ok(text) => text
    Err(_) => ""
  }
  val loadedIdType = match (await Kti.loadDepBindings(
    [("dep", ktiPath, "Dep")],
    [IDNamed("dep", [{ external = "id", local = "id" }])]
  )) {
    DepLoadOk(bundle) => Dict.get(bundle.importBindings, "id")
    DepLoadErr(_) => None
  }
  val depWriteAOk = match (await Kti.writeKtiFile(depAPath, kti)) {
    Ok(_) => True
    Err(_) => False
  }
  val depWriteBOk = match (await Kti.writeKtiFile(depBPath, kti)) {
    Ok(_) => True
    Err(_) => False
  }
  val loadedPair = match (await Kti.loadDepBindings(
    [("depA", depAPath, "DepA"), ("depB", depBPath, "DepB")],
    [
      IDNamed("depA", [{ external = "id", local = "idA" }]),
      IDNamed("depB", [{ external = "id", local = "idB" }])
    ]
  )) {
    DepLoadOk(bundle) => {
      val a = Dict.get(bundle.importBindings, "idA")
      val b = Dict.get(bundle.importBindings, "idB")
      match (a) {
        None => None
        Some(ta) =>
          match (b) {
            None => None
            Some(tb) => Some((ta, tb))
          }
      }
    }
    DepLoadErr(_) => None
  }

  Ty.resetVarId()
  val freshVarIsPositive = match (Ty.freshVar()) {
    TVar(v) => v >= 0
    _ => False
  }

  val _cleanupAfter = await Fs.deleteFile(ktiPath)
  val _cleanupDepAAfter = await Fs.deleteFile(depAPath)
  val _cleanupDepBAfter = await Fs.deleteFile(depBPath)

  group(s, "kestrel:tools/compiler/kti", (s1: Suite) => {
    group(s1, "round-trip", (sg: Suite) => {
      assertRoundTrip(sg, "primitive Int", Ty.TPrim("Int"))
      assertRoundTrip(sg, "primitive Bool", Ty.TPrim("Bool"))
      assertRoundTrip(sg, "primitive String", Ty.TPrim("String"))
      assertRoundTrip(sg, "primitive Unit", Ty.TPrim("Unit"))
      assertRoundTrip(sg, "type var 0", Ty.TVar(0))
      assertRoundTrip(sg, "type var 42", Ty.TVar(42))
      assertRoundTrip(sg, "arrow nullary", Ty.TArrow([], Ty.TPrim("Unit")))
      assertRoundTrip(
        sg,
        "arrow multi param",
        Ty.TArrow([Ty.TPrim("Int"), Ty.TPrim("Bool")], Ty.TPrim("String"))
      )
      assertRoundTrip(sg, "type application", Ty.TApp("List", [Ty.TPrim("Int")]))
      assertRoundTrip(sg, "tuple", Ty.TTuple([Ty.TPrim("Int"), Ty.TPrim("Bool")]))
      assertRoundTrip(sg, "union", Ty.TUnion(Ty.TPrim("Int"), Ty.TPrim("Bool")))
      assertRoundTrip(sg, "intersection", Ty.TInter(Ty.TPrim("Int"), Ty.TPrim("Bool")))
      assertRoundTrip(
        sg,
        "scheme identity",
        Ty.TScheme([0], Ty.TArrow([Ty.TVar(0)], Ty.TVar(0)))
      )
      assertRoundTrip(
        sg,
        "record closed",
        Ty.TRecord([{ name = "x", mut_ = False, type_ = Ty.TPrim("Int") }], None)
      )
      assertRoundTrip(
        sg,
        "record open row var",
        Ty.TRecord([{ name = "x", mut_ = False, type_ = Ty.TPrim("Int") }], Some(Ty.TVar(1)))
      )
      assertRoundTrip(
        sg,
        "nested scheme list map",
        Ty.TScheme(
          [0],
          Ty.TArrow(
            [Ty.TApp("List", [Ty.TVar(0)])],
            Ty.TApp("List", [Ty.TVar(0)])
          )
        )
      )
    })

    group(s1, "acceptance regression", (sg: Suite) => {
      isTrue(sg, "writeKtiFile succeeds", writeOk)
      isTrue(sg, "scheme stored as object kind", Str.indexOf(ktiText, "\"k\":\"scheme\"") >= 0)
      isTrue(sg, "legacy forall string not written", Str.indexOf(ktiText, "forall") < 0)
      isTrue(sg, "single dep write A succeeds", depWriteAOk)
      isTrue(sg, "single dep write B succeeds", depWriteBOk)
      eq(sg, "loadDepBindings preserves scheme shape", loadedIdType == None, False)

      val singleIdIsNegative = match (loadedIdType) {
        None => False
        Some(t) => hasNegativeVarId(t)
      }
      isTrue(sg, "single import freshens scheme var to negative id", singleIdIsNegative)

      val pairFreshenedAndDistinct = match (loadedPair) {
        None => False
        Some(pair) => {
          val aJson = Json.stringify(Kti.serializeType(pair.0))
          val bJson = Json.stringify(Kti.serializeType(pair.1))
          hasNegativeVarId(pair.0) & hasNegativeVarId(pair.1) & aJson != bJson
        }
      }
      isTrue(sg, "two imported schemes use distinct negative ids", pairFreshenedAndDistinct)
      isTrue(sg, "freshVar remains non-negative", freshVarIsPositive)
    })

    group(s1, "namespace fallback", (sg: Suite) => {
      val namespaceJson = Json.stringify(Kti.serializeType(Ty.TNamespace(Dict.emptyStringDict())))
      eq(sg, "namespace placeholder shape", namespaceJson, "{\"k\":\"app\",\"n\":\"__namespace__\",\"as\":[]}")
      isTrue(sg, "namespace serializes as object", namespaceJson != "\"__namespace__\"")
    })
  })
}