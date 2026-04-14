import { Suite, group, eq } from "kestrel:dev/test"
import * as Str from "kestrel:data/string"
import { mainClassFor, classFileForSource } from "kestrel:tools/cli/maven"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/cli", (s1: Suite) => {

    group(s1, "mainClassFor (as used by cli)", (m: Suite) => {
      eq(m, "simple script",
        mainClassFor("/home/user/hello.ks"),
        "home.user.Hello")
      eq(m, "script with hyphen",
        mainClassFor("/project/my-script.ks"),
        "project.My_script")
      eq(m, "nested path",
        mainClassFor("/Users/foo/bar/baz.ks"),
        "Users.foo.bar.Baz")
      eq(m, "stdlib module",
        mainClassFor("/root/stdlib/kestrel/tools/test.ks"),
        "root.stdlib.kestrel.tools.Test")
      eq(m, "cli-entry module",
        mainClassFor("/root/stdlib/kestrel/tools/compiler/cli-entry.ks"),
        "root.stdlib.kestrel.tools.compiler.Cli_entry")
    })

    group(s1, "classFileForSource (as used by cli)", (c: Suite) => {
      eq(c, "simple",
        classFileForSource("/cache", "/project/hello.ks"),
        "/cache/project/Hello.class")
      eq(c, "nested",
        classFileForSource("/home/cache", "/root/stdlib/kestrel/tools/test.ks"),
        "/home/cache/root/stdlib/kestrel/tools/Test.class")
      eq(c, "cli entry",
        classFileForSource("/jvm", "/root/stdlib/kestrel/tools/compiler/cli-entry.ks"),
        "/jvm/root/stdlib/kestrel/tools/compiler/Cli_entry.class")
    })

  })
