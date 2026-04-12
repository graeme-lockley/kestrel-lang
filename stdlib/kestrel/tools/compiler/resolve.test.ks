import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Lst from "kestrel:data/list"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Resolve from "kestrel:tools/compiler/resolve"

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => prog
    Err(e) => throw e
  }

val opts = {
  fromFile = "/tmp/project/src/main.ks",
  stdlibDir = "/tmp/project/stdlib",
  cacheRoot = "/tmp/project/.cache",
  allowHttp = False
}

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/resolve", (s1: Suite) => {
    group(s1, "stdlib specifier", (sg: Suite) => {
      match (Resolve.resolveSpecifier("kestrel:data/list", opts)) {
        Ok(path) => eq(sg, "stdlib path", path, "/tmp/project/stdlib/kestrel/data/list.ks")
        Err(e) => {
          isTrue(sg, "unexpected error", False)
          eq(sg, "error detail", e, "")
        }
      }
    })

    group(s1, "relative specifier", (sg: Suite) => {
      match (Resolve.resolveSpecifier("./helper.ks", opts)) {
        Ok(path) => eq(sg, "relative path", path, "/tmp/project/src/./helper.ks")
        Err(_) => isTrue(sg, "expected relative success", False)
      }
    })

    group(s1, "unknown stdlib", (sg: Suite) => {
      match (Resolve.resolveSpecifier("kestrel:", opts)) {
        Ok(_) => isTrue(sg, "expected stdlib error", False)
        Err(_) => isTrue(sg, "unknown stdlib rejected", True)
      }
    })

    group(s1, "cross-origin escape blocked", (sg: Suite) => {
      val remoteOpts = {
        fromFile = "/tmp/project/cache/https_example_com_mod.ks",
        stdlibDir = opts.stdlibDir,
        cacheRoot = opts.cacheRoot,
        allowHttp = opts.allowHttp
      }
      match (Resolve.resolveSpecifier("../outside.ks", remoteOpts)) {
        Ok(_) => isTrue(sg, "expected cross-origin rejection", False)
        Err(msg) => isTrue(sg, "cross-origin message", msg == "cross-origin path traversal is not allowed")
      }
    })

    group(s1, "unique dependency paths", (sg: Suite) => {
      val p = program("import { map } from \"kestrel:data/list\"\nimport { foldl } from \"kestrel:data/list\"\nimport \"./helper.ks\"")
      match (Resolve.uniqueDependencyPaths(p, "/tmp/project/src/main.ks", opts)) {
        Ok(deps) => eq(sg, "distinct count", Lst.length(deps), 2)
        Err(_) => isTrue(sg, "expected deps success", False)
      }
    })
  })
