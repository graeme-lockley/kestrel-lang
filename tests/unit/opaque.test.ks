import { Suite, group, eq, isTrue, isFalse } from "kestrel:tools/test"

// Opaque ADT - within the same module, we have full access
opaque type Token = Num(Int) | Op(String) | Eof

fun tokenToInt(t: Token): Int = match (t) {
  Num(n) => n
  Op(s) => 0
  Eof => -1
}

// Opaque type with generic params (using different constructors to avoid built-in Result conflict)
opaque type MyResult<T> = MyOk(T) | MyErr

fun myResultIsOk<T>(r: MyResult<T>): Bool = match (r) {
  MyOk(_) => True
  MyErr => False
}

export async fun run(s: Suite): Task<Unit> =
  group(s, "opaque types", (s1: Suite) => {
    group(s1, "opaque ADT", (sg: Suite) => {
      eq(sg, "tokenToInt Num", tokenToInt(Num(42)), 42)
      eq(sg, "tokenToInt Op", tokenToInt(Op("plus")), 0)
      eq(sg, "tokenToInt Eof", tokenToInt(Eof), -1)
    })

    group(s1, "opaque generic", (sg: Suite) => {
      val r1 = MyOk(42)
      isTrue(sg, "myResultIsOk Ok", myResultIsOk(r1))
      val r2 = MyErr
      isFalse(sg, "myResultIsOk Err", myResultIsOk(r2))
    })
  })
