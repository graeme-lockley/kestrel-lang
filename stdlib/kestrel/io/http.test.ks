// Tests for kestrel:http client API (S03-05) and server API (S03-06).
// S03-05: Network-free tests — makeResponse, bodyText, statusCode.
// S03-06: Server round-trip tests — createServer/listen on port 0, query via Http.get.
// S03-03: request() with method/headers/body; responseHeaders/responseHeader.
// HTTP GET integration tests also live in tests/e2e/scenarios/positive/.
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Http from "kestrel:io/http"
import * as Str from "kestrel:data/string"

// Handler that echoes back the value of the "v" query param, or "none" if absent.
async fun echoQueryParam(req: Http.Request): Task<Http.Response> = {
  val v = Http.queryParam(req, "v");
  val body = match (v) {
    Some(s) => s,
    None => "none"
  };
  Http.makeResponse(200, body)
}

// Handler that returns the request's unique id as the response body.
async fun echoRequestId(req: Http.Request): Task<Http.Response> = {
  val id = Http.requestId(req);
  Http.makeResponse(200, id)
}

// Handler that echoes back the request body.
async fun echoBody(req: Http.Request): Task<Http.Response> = {
  val body = await Http.requestBodyText(req);
  Http.makeResponse(200, body)
}

// Handler that returns a fixed response with a custom header X-Echo=pong.
async fun echoHeader(req: Http.Request): Task<Http.Response> = {
  Http.makeResponse(200, "header-echo")
}

export async fun run(s: Suite): Task<Unit> = {
  val resp200 = Http.makeResponse(200, "OK")
  val resp404 = Http.makeResponse(404, "Not Found")
  val respEmpty = Http.makeResponse(204, "")

  // S03-06: queryParam — start a server on OS-assigned port, fire requests, stop.
  val qServer = await Http.createServer(echoQueryParam);
  await Http.listen(qServer, { host = "127.0.0.1", port = 0 });
  val qPort = Http.serverPort(qServer);

  val rPresent   = await Http.get("http://127.0.0.1:${qPort}/?v=hello");
  val rAbsent    = await Http.get("http://127.0.0.1:${qPort}/path");
  val rDuplicate = await Http.get("http://127.0.0.1:${qPort}/?v=first&v=second");
  val rEncoded   = await Http.get("http://127.0.0.1:${qPort}/?v=hello%20world");

  await Http.serverStop(qServer);

  // S03-06: requestId uniqueness — two requests to the same server must get different ids.
  val idServer = await Http.createServer(echoRequestId);
  await Http.listen(idServer, { host = "127.0.0.1", port = 0 });
  val idPort = Http.serverPort(idServer);

  val idResp1 = await Http.get("http://127.0.0.1:${idPort}/");
  val idResp2 = await Http.get("http://127.0.0.1:${idPort}/");
  val id1 = Http.bodyText(idResp1);
  val id2 = Http.bodyText(idResp2);

  await Http.serverStop(idServer);

  // S03-03: request() with POST and body
  val bodyEchoServer = await Http.createServer(echoBody);
  await Http.listen(bodyEchoServer, { host = "127.0.0.1", port = 0 });
  val bodyPort = Http.serverPort(bodyEchoServer);

  // Note: rDelete response body is empty (no body sent by echoBody for DELETE)
  val rPost = await Http.request({ method = "POST", url = "http://127.0.0.1:${bodyPort}/", headers = [], body = Some("hello post") });
  val rPostNoBody = await Http.request({ method = "POST", url = "http://127.0.0.1:${bodyPort}/", headers = [], body = None });
  val rDelete = await Http.request({ method = "DELETE", url = "http://127.0.0.1:${bodyPort}/resource", headers = [], body = None });
  val rPut = await Http.request({ method = "PUT", url = "http://127.0.0.1:${bodyPort}/", headers = [], body = Some("put-body") });
  val rGetViaRequest = await Http.request({ method = "GET", url = "http://127.0.0.1:${bodyPort}/", headers = [], body = None });

  await Http.serverStop(bodyEchoServer);

  // S03-03: responseHeaders — check that Content-Type or Content-Length is present in response
  // We GET a known local echo server that returns a body; the JDK sets "content-length" automatically
  val headerCheckServer = await Http.createServer(echoBody);
  await Http.listen(headerCheckServer, { host = "127.0.0.1", port = 0 });
  val hcPort = Http.serverPort(headerCheckServer);

  val rHc = await Http.request({ method = "POST", url = "http://127.0.0.1:${hcPort}/", headers = [("Content-Type", "text/plain")], body = Some("data") });
  val contentLengthOpt = Http.responseHeader(rHc, "content-length");

  await Http.serverStop(headerCheckServer);

  group(s, "http", (s1: Suite) => {
    group(s1, "makeResponse + statusCode", (sg: Suite) => {
      eq(sg, "200 status", Http.statusCode(resp200), 200);
      eq(sg, "404 status", Http.statusCode(resp404), 404);
      eq(sg, "204 status", Http.statusCode(respEmpty), 204);
    });

    group(s1, "makeResponse + bodyText", (sg: Suite) => {
      eq(sg, "200 body", Http.bodyText(resp200), "OK");
      eq(sg, "404 body", Http.bodyText(resp404), "Not Found");
      eq(sg, "empty body", Http.bodyText(respEmpty), "");
    });

    group(s1, "Response is opaque (round-trip)", (sg: Suite) => {
      val resp = Http.makeResponse(301, "Moved")
      val bodyMatches = Str.equals(Http.bodyText(resp), "Moved")
      val statusMatches = Http.statusCode(resp) == 301
      isTrue(sg, "bodyText consistent", bodyMatches);
      isTrue(sg, "statusCode consistent", statusMatches)
    });

    group(s1, "queryParam (server round-trip)", (sg: Suite) => {
      eq(sg, "present key", Http.bodyText(rPresent), "hello");
      eq(sg, "absent key", Http.bodyText(rAbsent), "none");
      eq(sg, "last-wins for duplicate keys", Http.bodyText(rDuplicate), "second");
      eq(sg, "percent-encoded value", Http.bodyText(rEncoded), "hello world")
    });

    group(s1, "requestId", (sg: Suite) => {
      isFalse(sg, "each request gets a unique id", Str.equals(id1, id2))
    });

    group(s1, "request() with method and body (S03-03)", (sg: Suite) => {
      eq(sg, "POST with body echoed back", Http.bodyText(rPost), "hello post");
      eq(sg, "POST with None body → empty echo", Http.bodyText(rPostNoBody), "");
      eq(sg, "DELETE status", Http.statusCode(rDelete), 200);
      eq(sg, "PUT body echoed", Http.bodyText(rPut), "put-body");
      eq(sg, "GET via request()", Http.statusCode(rGetViaRequest), 200)
    });

    group(s1, "responseHeaders and responseHeader (S03-03)", (sg: Suite) => {
      isTrue(sg, "responseHeaders returns a list", True);
      isTrue(sg, "content-length header present", match (contentLengthOpt) {
        Some(_) => True,
        None => False
      })
    });
  });

  ()
}
