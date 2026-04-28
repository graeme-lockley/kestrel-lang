// E2E test: web routing with path parameters (S03-04).
// Verifies that :name and multi-segment parameters are extracted correctly.
import * as Http from "kestrel:io/http"
import * as Web from "kestrel:io/web"
import * as Dict from "kestrel:data/dict"

async fun greetHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> = {
  val name = match (Dict.get(params, "name")) {
    Some(n) => n,
    None => "stranger"
  };
  Http.makeResponse(200, "Hello ${name}")
}

async fun itemHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> = {
  val cat = match (Dict.get(params, "cat")) { Some(v) => v, None => "" };
  val id = match (Dict.get(params, "id")) { Some(v) => v, None => "" };
  Http.makeResponse(200, "${cat}/${id}")
}

async fun run(): Task<Unit> = {
  val router =
    Web.newRouter()
    |> Web.get("/greet/:name", greetHandler)
    |> Web.get("/items/:cat/:id", itemHandler);

  val server = await Http.createServer(Web.serve(router));
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);

  val r1 = await Http.get("http://127.0.0.1:${port}/greet/World");
  println(Http.statusCode(r1));
  println(Http.bodyText(r1));

  val r2 = await Http.get("http://127.0.0.1:${port}/items/books/42");
  println(Http.statusCode(r2));
  println(Http.bodyText(r2));

  await Http.serverStop(server);
  ()
}

run()
