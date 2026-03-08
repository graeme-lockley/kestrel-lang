export fun inc(rec: { x: mut Int }): Unit = {
  rec.x := rec.x + 1;
  ()
}
