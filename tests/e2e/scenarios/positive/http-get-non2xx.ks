// E2E test: Http.get non-2xx response is a successful Task (not a failure) (S03-05).
// Requires network access. Tests that 404 does not throw an exception.
import * as Http from "kestrel:http"

async fun run(): Task<Unit> = {
  val resp = await Http.get("http://httpbin.org/status/404");
  println(Http.statusCode(resp));
  ()
}

run()
