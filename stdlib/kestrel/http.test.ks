// Tests for kestrel:http client API (S03-05).
// Tests in this file are network-free: only makeResponse, bodyText, and statusCode
// are exercised here. HTTP GET integration tests live in tests/e2e/scenarios/positive/.
import { Suite, group, eq, isTrue } from "kestrel:test"
import * as Http from "kestrel:http"
import * as Str from "kestrel:string"

export async fun run(s: Suite): Task<Unit> = {
  val resp200 = Http.makeResponse(200, "OK")
  val resp404 = Http.makeResponse(404, "Not Found")
  val respEmpty = Http.makeResponse(204, "")

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
  });

  ()
}
