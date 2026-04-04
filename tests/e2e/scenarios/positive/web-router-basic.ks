// E2E test: basic web routing with GET and POST routes (S03-04).
// Verifies 200 for matched routes, 404 for unmatched path, 405 for wrong method.
import * as Http from "kestrel:http"
import * as Web from "kestrel:web"

async fun helloHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> =
  Http.makeResponse(200, "hello")

async fun echoHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> =
  Http.makeResponse(200, "post-ok")

async fun run(): Task<Unit> = {
  val router =
    Web.newRouter()
    |> Web.get("/hello", helloHandler)
    |> Web.post("/echo", echoHandler);

  val server = await Http.createServer(Web.serve(router));
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);

  val r1 = await Http.get("http://127.0.0.1:${port}/hello");
  println(Http.statusCode(r1));
  println(Http.bodyText(r1));

  val r2 = await Http.request({ method = "POST", url = "http://127.0.0.1:${port}/echo", headers = [], body = None });
  println(Http.statusCode(r2));
  println(Http.bodyText(r2));

  val r3 = await Http.get("http://127.0.0.1:${port}/missing");
  println(Http.statusCode(r3));

  val r4 = await Http.request({ method = "DELETE", url = "http://127.0.0.1:${port}/hello", headers = [], body = None });
  println(Http.statusCode(r4));

  await Http.serverStop(server);
  ()
}

run()
