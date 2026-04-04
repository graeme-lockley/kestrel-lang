// E2E test: createServer + listen + plain text response (S03-06).
// Starts a server on 127.0.0.1:0 (OS-assigned port), uses Http.get to call it,
// asserts response status 200 and body "hello".
import * as Http from "kestrel:http"

async fun handler(req: Http.Request): Task<Http.Response> =
  Http.makeResponse(200, "hello")

async fun run(): Task<Unit> = {
  val server = await Http.createServer(handler);
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);
  val resp = await Http.get("http://127.0.0.1:${port}/");
  println(Http.statusCode(resp));
  println(Http.bodyText(resp));
  await Http.serverStop(server);
  ()
}

run()
