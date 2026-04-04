// E2E test: Http.get returns a response with the correct status code (S03-05).
// Requires network access. Tests HTTP GET (plain http) against httpbin.org.
import * as Http from "kestrel:http"

async fun run(): Task<Unit> = {
  val resp = await Http.get("http://httpbin.org/status/200");
  println(Http.statusCode(resp));
  ()
}

run()
