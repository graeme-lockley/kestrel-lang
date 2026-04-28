// Provenance: tests/conformance/typecheck/valid/primitive_literal_matches.ks (baseline S17-50)
val n = match (1) { 0 => 10, _ => 20 }
val x = match (1.5) { 1.5 => 10, _ => 20 }
val s = match ("hello") { "hello" => 1, _ => 0 }
val c = match ('a') { 'a' => 1, _ => 0 }
