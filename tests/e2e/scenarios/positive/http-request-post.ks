// E2E test: Http.request() with POST method and body (S03-03).
// Starts an echo server on 127.0.0.1:0, sends POST with body via Http.request(),
// asserts the response body equals the sent body.
import * as Http from "kestrel:io/http"

async fun echoBody(req: Http.Request): Task<Http.Response> = {
  val body = await Http.requestBodyText(req);
  Http.makeResponse(200, body)
}

async fun run(): Task<Unit> = {
  val server = await Http.createServer(echoBody);
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);

  val resp = await Http.request({ method = "POST", url = "http://127.0.0.1:${port}/", headers = [], body = Some("hello post") });
  println(Http.statusCode(resp));
  println(Http.bodyText(resp));

  await Http.serverStop(server);
  ()
}

run()
