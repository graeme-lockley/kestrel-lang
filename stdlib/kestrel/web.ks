// kestrel:web — Lightweight routing framework (S03-04).
// Sinatra-style multi-route HTTP server built on top of kestrel:http.
// Pure Kestrel implementation — no new JVM primitives.
//
// Usage:
//   import * as Web from "kestrel:web"
//   import * as Http from "kestrel:http"
//
//   val router =
//     Web.newRouter()
//     |> Web.get("/hello", (req, _params) => Http.makeResponse(200, "Hello!"))
//
//   val server = await Http.createServer(Web.serve(router));
//   await Http.listen(server, { host = "127.0.0.1", port = 8080 });

import * as Http from "kestrel:http"
import * as List from "kestrel:list"
import * as Str from "kestrel:string"
import * as Dict from "kestrel:dict"

// ---------------------------------------------------------------------------
// Path matching
// ---------------------------------------------------------------------------

// A path segment is either a literal string, a named parameter (:name), or a wildcard (*).
type PathSegment = Literal(String) | Param(String) | Wildcard

// Parse a route pattern like "/user/:id/profile" into a list of segments.
fun parsePattern(pattern: String): List<PathSegment> = {
  val raw = if (Str.startsWith("/", pattern)) Str.dropLeft(pattern, 1) else pattern;
  val parts = if (Str.isEmpty(raw)) [] else Str.split(raw, "/");
  List.map(parts, (part: String) => {
    if (Str.startsWith(":", part)) Param(Str.dropLeft(part, 1))
    else if (Str.equals(part, "*")) Wildcard
    else Literal(part)
  })
}

// Split a request path into URL path segments (no query string).
fun splitPath(path: String): List<String> = {
  val raw = if (Str.startsWith("/", path)) Str.dropLeft(path, 1) else path;
  if (Str.isEmpty(raw)) [] else Str.split(raw, "/")
}

// Try to match pattern segments against request segments.
// Returns Some(params) on success where params is a list of (name, value) pairs.
fun matchSegments(patterns: List<PathSegment>, segs: List<String>, acc: List<(String, String)>): Option<List<(String, String)>> =
  match (patterns) {
    [] => match (segs) {
      [] => Some(List.reverse(acc)),
      _ => None
    },
    Wildcard :: _ => Some(List.reverse(acc)),
    Literal(p) :: restP => match (segs) {
      [] => None,
      s :: restS =>
        if (Str.equals(p, s)) matchSegments(restP, restS, acc)
        else None
    },
    Param(name) :: restP => match (segs) {
      [] => None,
      s :: restS => matchSegments(restP, restS, (name, s) :: acc)
    }
  }

// ---------------------------------------------------------------------------
// Route type (internal)
// ---------------------------------------------------------------------------

type Route = {
  method: String,
  pattern: String,
  segments: List<PathSegment>,
  handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>
}

// ---------------------------------------------------------------------------
// Router type
// ---------------------------------------------------------------------------

// Router holds an ordered list of routes (first match wins).
export type Router = {
  routes: List<Route>
}

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

export fun newRouter(): Router = { routes = [] }

// ---------------------------------------------------------------------------
// Route registration
// ---------------------------------------------------------------------------

// Add a route for the given method and path pattern (method is case-insensitive).
export fun route(router: Router, method: String, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router = {
  val r: Route = {
    method = Str.toUpper(method),
    pattern = pattern,
    segments = parsePattern(pattern),
    handler = handler
  };
  { routes = List.append(router.routes, [r]) }
}

// Convenience wrappers for common HTTP methods.
export fun get(router: Router, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router =
  route(router, "GET", pattern, handler)

export fun post(router: Router, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router =
  route(router, "POST", pattern, handler)

export fun put(router: Router, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router =
  route(router, "PUT", pattern, handler)

export fun delete(router: Router, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router =
  route(router, "DELETE", pattern, handler)

export fun patch(router: Router, pattern: String, handler: (Http.Request, Dict<String, String>) -> Task<Http.Response>): Router =
  route(router, "PATCH", pattern, handler)

// ---------------------------------------------------------------------------
// Dispatch helpers
// ---------------------------------------------------------------------------

// Internal: holds a matched route and its extracted path params.
type RouteMatch = RouteMatch(Route, Dict<String, String>)

// Find the first route matching both method and path.
fun findRoute(routes: List<Route>, method: String, segs: List<String>): Option<RouteMatch> =
  match (routes) {
    [] => None,
    r :: rest =>
      if (Str.equals(r.method, method)) {
        match (matchSegments(r.segments, segs, [])) {
          Some(pairs) => Some(RouteMatch(r, Dict.fromStringList(pairs))),
          None => findRoute(rest, method, segs)
        }
      } else findRoute(rest, method, segs)
  }

// Check if any route (any method) matches the path — used to distinguish 404 vs 405.
fun hasPathMatch(routes: List<Route>, segs: List<String>): Bool =
  match (routes) {
    [] => False,
    r :: rest => match (matchSegments(r.segments, segs, [])) {
      Some(_) => True,
      None => hasPathMatch(rest, segs)
    }
  }

// ---------------------------------------------------------------------------
// Serve
// ---------------------------------------------------------------------------

// serve(router) returns a request handler suitable for Http.createServer.
// Unmatched paths → 404 Not Found; matched path but wrong method → 405 Method Not Allowed.
export fun serve(router: Router): (Http.Request) -> Task<Http.Response> =
  (req: Http.Request) => dispatchRequest(router, req)

async fun callHandler(r: Route, params: Dict<String, String>, req: Http.Request): Task<Http.Response> = {
  val t: Task<Http.Response> = r.handler(req, params);
  await t
}

async fun dispatchRequest(router: Router, req: Http.Request): Task<Http.Response> = {
  val method = Http.requestMethod(req);
  val path = Http.requestPath(req);
  val segs = splitPath(path);
  val matched: Option<RouteMatch> = findRoute(router.routes, method, segs);
  match (matched) {
    Some(RouteMatch(r, params)) => await callHandler(r, params, req),
    None =>
      if (hasPathMatch(router.routes, segs))
        Http.makeResponse(405, "Method Not Allowed")
      else
        Http.makeResponse(404, "Not Found")
  }
}

