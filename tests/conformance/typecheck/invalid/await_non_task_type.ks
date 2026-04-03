// Applying await to a non-Task type should report the actual type in the error
async fun run(): Task<Unit> = {
  val x = 42
  val y = await x
}
// EXPECT: got Int
