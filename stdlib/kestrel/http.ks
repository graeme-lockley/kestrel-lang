// kestrel:http — HTTP server and client (spec 02 §kestrel:http, runtime model 05 §2–3).
// Opaque types: Server (HttpServer), Request (HttpExchange), Response (synthetic or HttpResponse).
// S03-05: get, bodyText, statusCode, makeResponse implemented via KRuntime helpers.
// S03-06: createServer, listen, requestBodyText, queryParam, requestId to be implemented.
import * as Basics from "kestrel:basics"

// ---------------------------------------------------------------------------
// Opaque types (backed by JDK classes via KRuntime helpers added in S03-05/S03-06)
// ---------------------------------------------------------------------------

// Server — wraps com.sun.net.httpserver.HttpServer
extern type Server = jvm("com.sun.net.httpserver.HttpServer")

// Request — wraps com.sun.net.httpserver.HttpExchange (server-side request/response handle)
extern type Request = jvm("com.sun.net.httpserver.HttpExchange")

// Response — wraps java.net.http.HttpResponse<String> (client) or Object[]{ status, body }
// (server-side, from makeResponse). Both are handled by KRuntime helpers.
extern type Response = jvm("java.lang.Object")

// ---------------------------------------------------------------------------
// Exception for unimplemented stubs (removed when S03-06 lands)
// ---------------------------------------------------------------------------

export exception HttpNotImplemented

// ---------------------------------------------------------------------------
// Re-exported utility
// ---------------------------------------------------------------------------

export fun nowMs(): Int = Basics.nowMs()

// ---------------------------------------------------------------------------
// KRuntime extern bindings (S03-05: HTTP GET client)
// ---------------------------------------------------------------------------

extern fun httpGetAsync_(url: String): Task<Response> =
  jvm("kestrel.runtime.KRuntime#httpGetAsync(java.lang.Object)")

extern fun httpBodyText_(resp: Response): String =
  jvm("kestrel.runtime.KRuntime#httpBodyText(java.lang.Object)")

extern fun httpStatusCode_(resp: Response): Int =
  jvm("kestrel.runtime.KRuntime#httpStatusCode(java.lang.Object)")

extern fun httpMakeResponse_(status: Int, body: String): Response =
  jvm("kestrel.runtime.KRuntime#httpMakeResponse(java.lang.Object,java.lang.Object)")

// ---------------------------------------------------------------------------
// Public HTTP client API (S03-05)
// ---------------------------------------------------------------------------

export async fun get(url: String): Task<Response> = await httpGetAsync_(url)

export fun bodyText(resp: Response): String = httpBodyText_(resp)

export fun statusCode(resp: Response): Int = httpStatusCode_(resp)

export fun makeResponse(status: Int, body: String): Response = httpMakeResponse_(status, body)

// ---------------------------------------------------------------------------
// Server-side stubs — implemented in S03-06.
// ---------------------------------------------------------------------------

// TODO(S03-06): implement createServer via KRuntime.httpCreateServer
export async fun createServer(_handler: (Request) -> Task<Response>): Task<Server> =
  throw HttpNotImplemented

// TODO(S03-06): implement listen via KRuntime.httpListen
export async fun listen(_server: Server, _opts: { host: String, port: Int }): Task<Unit> =
  throw HttpNotImplemented

// TODO(S03-06): implement requestBodyText via KRuntime.httpRequestBodyText
export async fun requestBodyText(_request: Request): Task<String> =
  throw HttpNotImplemented

// TODO(S03-06): implement queryParam via KRuntime.httpQueryParam
export fun queryParam(_request: Request, _name: String): Option<String> =
  throw HttpNotImplemented

// TODO(S03-06): implement requestId via KRuntime.httpRequestId
export fun requestId(_request: Request): String =
  throw HttpNotImplemented
