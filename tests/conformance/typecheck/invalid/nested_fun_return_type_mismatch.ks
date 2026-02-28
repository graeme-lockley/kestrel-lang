// EXPECT: vs
fun f(): Int = { fun bad(): Int = True; bad() }
