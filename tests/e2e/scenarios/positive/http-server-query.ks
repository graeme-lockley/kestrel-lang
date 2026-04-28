// E2E test: queryParam end-to-end (S03-06).
// Server handler reads queryParam(req, "name") and responds "hello <name>".
// Client calls the server with ?name=world and asserts body is "hello world".
import * as Http from "kestrel:io/http"

async fun handler(req: Http.Request): Task<Http.Response> = {
  val name = Http.queryParam(req, "name");
  val body = match (name) {
    Some(n) => "hello ${n}",
    None => "no name"
  };
  Http.makeResponse(200, body)
}

async fun run(): Task<Unit> = {
  val server = await Http.createServer(handler);
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);
  val resp = await Http.get("http://127.0.0.1:${port}/?name=world");
  println(Http.bodyText(resp));
  await Http.serverStop(server);
  ()
}

run()
