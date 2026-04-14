import { Suite, group, eq } from "kestrel:dev/test"
import { mainClassFor, classFileForSource } from "kestrel:tools/cli/maven"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/cli/maven", (s1: Suite) => {
    group(s1, "mainClassFor", (m: Suite) => {
      eq(m, "hello.ks in root", mainClassFor("/hello.ks"), "Hello")
      eq(m, "hello.ks in dir", mainClassFor("/Users/foo/hello.ks"), "Users.foo.Hello")
      eq(m, "capitalizes first letter", mainClassFor("/foo/world.ks"), "foo.World")
      eq(m, "sanitizes hyphens", mainClassFor("/foo/my-module.ks"), "foo.My_module")
      eq(m, "sanitizes dots in filename", mainClassFor("/foo/a.b.ks"), "foo.A_b")
      eq(m, "deep path", mainClassFor("/a/b/c/d.ks"), "a.b.c.D")
    })

    group(s1, "classFileForSource", (c: Suite) => {
      eq(c, "root file", classFileForSource("/cache", "/hello.ks"), "/cache/Hello.class")
      eq(c, "nested file", classFileForSource("/cache", "/Users/foo/hello.ks"), "/cache/Users/foo/Hello.class")
      eq(c, "sanitized name", classFileForSource("/cache", "/foo/my-module.ks"), "/cache/foo/My_module.class")
    })
  })
