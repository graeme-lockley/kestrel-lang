import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "records", (s1: Suite) => {
    val point = { x = 10, y = 20 }
    eq(s1, "field access .x", point.x, 10)
    eq(s1, "field access .y", point.y, 20)

    group(s1, "mutable fields", (mf: Suite) => {
      val box = { mut value = 0 }
      eq(mf, "initial value", box.value, 0)
      box.value := 42
      eq(mf, "after mutation", box.value, 42)
      box.value := 99
      eq(mf, "second mutation", box.value, 99)
    })

    group(s1, "nested records", (nr: Suite) => {
      val nested = { outer = { inner = 77 } }
      eq(nr, "nested.outer.inner", nested.outer.inner, 77)
    })

    group(s1, "row polymorphism", (rp: Suite) => {
      val point2d = { x = 10, y = 20 }
      val point3d = { x = 5, y = 15, z = 25 }
      val pointWithExtra = { x = 1, y = 2, z = 3, w = 4 }
      eq(rp, "point2d.x", point2d.x, 10)
      eq(rp, "point3d.x", point3d.x, 5)
      eq(rp, "pointWithExtra.x", pointWithExtra.x, 1)
      eq(rp, "point2d.y", point2d.y, 20)
      eq(rp, "point3d.z", point3d.z, 25)
      eq(rp, "pointWithExtra.w", pointWithExtra.w, 4)
      eq(rp, "sum2d", point2d.x + point2d.y, 30)
      eq(rp, "sum3d", point3d.x + point3d.y + point3d.z, 45)
    })

    group(s1, "nested mutable", (nm: Suite) => {
      val r = { a = { mut b = 1 } }
      eq(nm, "initial", r.a.b, 1)
      r.a.b := 2
      eq(nm, "after mutation", r.a.b, 2)
    })

    group(s1, "many fields", (mf: Suite) => {
      val big = { a = 1, b = 2, c = 3, d = 4, e = 5 }
      eq(mf, "sum fields", big.a + big.b + big.c + big.d + big.e, 15)
    })

    group(s1, "record spread", (rs: Suite) => {
      // Requires compiler record-spread codegen (and typecheck for spread) to compile and run.
      val r = { x = 1 }
      val s = { ...r, y = 2 }
      eq(rs, "spread preserves base field", s.x, 1)
      eq(rs, "spread adds new field", s.y, 2)
      eq(rs, "spread override", { ...r, x = 99 }.x, 99)
    })
  })
