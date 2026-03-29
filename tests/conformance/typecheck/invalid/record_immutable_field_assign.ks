// EXPECT: immutable
val r = { x = 1 }
val _ = { r.x := 2; () }
