// Value (JSON) — ADT with Null, Bool, Int, Float, String, Array, Object per spec 02. Constructors built-in.
export fun isNull(v: Value): Bool = match (v) {
  Null => True
  _ => False
}
export fun isBool(v: Value): Bool = match (v) {
  Bool(_) => True
  _ => False
}
export fun isInt(v: Value): Bool = match (v) {
  Int(_) => True
  _ => False
}
export fun isFloat(v: Value): Bool = match (v) {
  Float(_) => True
  _ => False
}
export fun isString(v: Value): Bool = match (v) {
  String(_) => True
  _ => False
}
export fun isArray(v: Value): Bool = match (v) {
  Array(_) => True
  _ => False
}
export fun isObject(v: Value): Bool = match (v) {
  Object(_) => True
  _ => False
}
