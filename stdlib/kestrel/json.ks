// kestrel:json — parse, stringify wrapping __json_parse / __json_stringify (spec 02).
export fun parse(s: String): Value = __json_parse(s)
export fun stringify(v: Value): String = __json_stringify(v)
