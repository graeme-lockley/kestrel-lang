// await outside async context should fail
fun bad(): Int = {
  val task = someAsyncFn()
  await task
}
