import { message as message1 } from "./m1.ks"
import { message as message2 } from "./m2.ks"
import * as Http from "kestrel:http"
import * as Str from "kestrel:string"

import { hello } from "./m3.ks"

import "maven:org.apache.commons:commons-lang3:3.17.0"

extern fun reverse(str: String): String =
  jvm("org.apache.commons.lang3.StringUtils#reverse(java.lang.String)")

extern fun upperCase(str: String): String =
  jvm("org.apache.commons.lang3.StringUtils#upperCase(java.lang.String)")

extern fun swapCase(str: String): String =
  jvm("org.apache.commons.lang3.StringUtils#swapCase(java.lang.String)")

println(message1())
println(message2())

// --- Apache Commons Lang3: StringUtils demo ---
val word = "Kestrel"
println(reverse(word))
println(upperCase(word))
println(swapCase(word))

hello := "hello"

println({a = 1, b = hello})
println([1, 2, 3, 123, 5])
println(Some("hello"))

async fun fetchNews(): Task<Unit> = {
  try {
    val resp = await Http.get("https://www.google.com");
    println(Http.statusCode(resp));
    println(Str.left(Http.bodyText(resp), 200))
  } catch {
    HttpNotImplemented => println("fetchNews: Http not yet implemented"),
    _ => println("fetchNews: HTTP request failed (network error or timeout)")
  }
}

fetchNews()