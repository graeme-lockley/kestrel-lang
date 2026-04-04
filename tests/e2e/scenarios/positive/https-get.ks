// E2E test: Http.get works over HTTPS (S03-05 HTTPS acceptance criterion).
// Requires network access. Verifies system trust store, SNI, TLS 1.2+ all work.
import * as Http from "kestrel:http"

async fun run(): Task<Unit> = {
  val resp = await Http.get("https://httpbin.org/status/200");
  println(Http.statusCode(resp));
  ()
}

run()
