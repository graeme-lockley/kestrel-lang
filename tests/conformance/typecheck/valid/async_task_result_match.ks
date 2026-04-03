async fun load(ok: Bool): Task<Result<Int, Int>> = {
  if (ok) Ok(1) else Err(0)
}

async fun score(ok: Bool): Task<Int> = {
  val r = await load(ok);
  match (r) {
    Ok(v) => v,
    Err(e) => e
  }
}

val t = score(True)
