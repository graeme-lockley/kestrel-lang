// Tests for kestrel:io/web routing framework (S03-04).
// Tests cover route matching, method dispatch, path parameters, 404/405 defaults.
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Http from "kestrel:io/http"
import * as Web from "kestrel:io/web"
import * as Dict from "kestrel:data/dict"
import * as Str from "kestrel:data/string"

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fun helloHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> =
  Http.makeResponse(200, "Hello")

async fun echoMethodHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> =
  Http.makeResponse(200, Http.requestMethod(req))

async fun greetParamHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> = {
  val name = match (Dict.get(params, "name")) {
    Some(n) => n,
    None => "stranger"
  };
  Http.makeResponse(200, "Hello ${name}")
}

async fun multiParamHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> = {
  val a = match (Dict.get(params, "a")) { Some(v) => v, None => "" };
  val b = match (Dict.get(params, "b")) { Some(v) => v, None => "" };
  Http.makeResponse(200, "${a}/${b}")
}

async fun wildcardHandler(req: Http.Request, params: Dict<String, String>): Task<Http.Response> =
  Http.makeResponse(200, "wildcard")

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

export async fun run(s: Suite): Task<Unit> = {
  // Start a multi-route server once for all tests.
  val router =
    Web.newRouter()
    |> Web.get("/hello", helloHandler)
    |> Web.post("/hello", echoMethodHandler)
    |> Web.get("/greet/:name", greetParamHandler)
    |> Web.get("/items/:a/sub/:b", multiParamHandler)
    |> Web.get("/files/*", wildcardHandler);

  val server = await Http.createServer(Web.serve(router));
  await Http.listen(server, { host = "127.0.0.1", port = 0 });
  val port = Http.serverPort(server);

  // --- GET route matches exact path ---
  val rGet = await Http.get("http://127.0.0.1:${port}/hello");

  // --- POST route matches same path ---
  val rPost = await Http.request({ method = "POST", url = "http://127.0.0.1:${port}/hello", headers = [], body = None });

  // --- Method mismatch returns 405 ---
  val rDelete = await Http.request({ method = "DELETE", url = "http://127.0.0.1:${port}/hello", headers = [], body = None });

  // --- Unmatched path returns 404 ---
  val rMissing = await Http.get("http://127.0.0.1:${port}/missing");

  // --- Path parameter extracted correctly ---
  val rGreet = await Http.get("http://127.0.0.1:${port}/greet/Alice");

  // --- Multiple path parameters ---
  val rMulti = await Http.get("http://127.0.0.1:${port}/items/foo/sub/bar");

  // --- Wildcard matches any suffix ---
  val rWild = await Http.get("http://127.0.0.1:${port}/files/a/b/c");

  // --- Root path 404 (no route registered) ---
  val rRoot = await Http.get("http://127.0.0.1:${port}/");

  await Http.serverStop(server);

  group(s, "kestrel:io/web routing", (s1: Suite) => {
    group(s1, "GET route matches exact path", (sg: Suite) => {
      eq(sg, "status 200", Http.statusCode(rGet), 200);
      eq(sg, "body Hello", Http.bodyText(rGet), "Hello")
    });
    group(s1, "POST route matches same path", (sg: Suite) => {
      eq(sg, "status 200", Http.statusCode(rPost), 200);
      eq(sg, "body POST", Http.bodyText(rPost), "POST")
    });
    group(s1, "method mismatch returns 405", (sg: Suite) => {
      eq(sg, "status 405", Http.statusCode(rDelete), 405)
    });
    group(s1, "unmatched path returns 404", (sg: Suite) => {
      eq(sg, "status 404", Http.statusCode(rMissing), 404)
    });
    group(s1, "path parameter extracted correctly", (sg: Suite) => {
      eq(sg, "status 200", Http.statusCode(rGreet), 200);
      eq(sg, "body greet", Http.bodyText(rGreet), "Hello Alice")
    });
    group(s1, "multiple path parameters", (sg: Suite) => {
      eq(sg, "status 200", Http.statusCode(rMulti), 200);
      eq(sg, "body multi", Http.bodyText(rMulti), "foo/bar")
    });
    group(s1, "wildcard matches any suffix", (sg: Suite) => {
      eq(sg, "status 200", Http.statusCode(rWild), 200);
      eq(sg, "body wildcard", Http.bodyText(rWild), "wildcard")
    });
    group(s1, "root path 404 when not registered", (sg: Suite) => {
      eq(sg, "status 404", Http.statusCode(rRoot), 404)
    })
  })
}
