// Value (JSON) — Phase 5: ADT Null/Bool/Int/Float/String/Array/Object per spec 02. Helpers in Kestrel.
export fun isNull(v: Value): Bool = match (v) {
  Null => True
  _ => False
}
