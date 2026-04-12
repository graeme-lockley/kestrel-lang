import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Lst from "kestrel:data/list"
import * as CliMain from "kestrel:tools/compiler/cli-main"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/cli-main", (s1: Suite) => {
    group(s1, "parseCommand", (sg: Suite) => {
      val empty = CliMain.parseCommand([])
      val okBuild = CliMain.parseCommand(["build", "hello.ks"])
      val bad = CliMain.parseCommand(["unknown"])

      eq(sg, "empty argv fails", match (empty) { Ok(_) => False, Err(_) => True }, True)
      eq(sg, "unknown command fails", match (bad) { Ok(_) => False, Err(_) => True }, True)
      eq(sg, "build command parses", match (okBuild) { Ok(_) => True, Err(_) => False }, True)
    })

    group(s1, "forwardArgs", (sg: Suite) => {
      val parsed = { command = "run", args = ["hello.ks", "--refresh"] }
      val fwd = CliMain.forwardArgs(parsed)
      eq(sg, "program", fwd.0, "./kestrel")
      eq(sg, "argv count", Lst.length(fwd.1), 3)
      eq(sg, "first argv is command", Lst.head(fwd.1), Some("run"))
    })

    group(s1, "build command forwards", (sg: Suite) => {
      val parsed = { command = "build", args = ["samples/expr.ks"] }
      val fwd = CliMain.forwardArgs(parsed)
      eq(sg, "program", fwd.0, "./kestrel")
      eq(sg, "first arg", Lst.head(fwd.1), Some("build"))
      isTrue(sg, "has script arg", Lst.any(fwd.1, (x: String) => x == "samples/expr.ks"))
    })
  })