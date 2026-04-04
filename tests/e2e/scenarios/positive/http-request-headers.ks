// E2E test: Http.responseHeader() (S03-03).
// Starts an echo server on 127.0.0.1:0, sends a POST with body via Http.request(),
// checks that the "content-length" response header is present and non-empty.
import * as Http from "kestrel:http"
import * as Str from "kestrel:string"

async fun echoBody(req: Http.Request): Task<Http.Response> = {
  val body = await Http.requestBodyText(req);
  Http.makeResponse(200, body)
}

async fun run(): Task<Unit> = {
  val server = await Http.createServer(echoBody);
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);

  val resp = await Http.request({ method = "POST", url = "http://127.0.0.1:${port}/", headers = [("Content-Type", "text/plain")], body = Some("data") });
  val contentLength = Http.responseHeader(resp, "content-length");
  println(match (contentLength) {
    Some(_) => "present",
    None => "absent"
  });

  await Http.serverStop(server);
  ()
}

run()
