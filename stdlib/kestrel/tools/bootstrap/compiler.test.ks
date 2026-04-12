import { Suite, group, eq } from "kestrel:dev/test"
import * as Compiler from "kestrel:tools/bootstrap/compiler"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/bootstrap/compiler", (s1: Suite) => {
    group(s1, "paths", (sg: Suite) => {
      eq(sg, "runtimeJarPath",
        Compiler.runtimeJarPath("/my/root"),
        "/my/root/runtime/jvm/kestrel-runtime.jar")

      eq(sg, "compilerCliPath",
        Compiler.compilerCliPath("/my/root"),
        "/my/root/compiler/dist/cli.js")

      eq(sg, "cliEntryPath",
        Compiler.cliEntryPath("/my/root"),
        "/my/root/stdlib/kestrel/tools/compiler/cli-entry.ks")
    })
  })
