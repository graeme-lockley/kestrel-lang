// kestrel:http — HTTP server and client (spec 02 §kestrel:http, runtime model 05 §2–3).
// Opaque types: Server (HttpServer), Request (HttpExchange), Response (synthetic or HttpResponse).
// Implementations of createServer, listen, get, bodyText, statusCode, makeResponse,
// requestBodyText, queryParam, requestId land in S03-05 (client) and S03-06 (server).
import * as Basics from "kestrel:basics"

// ---------------------------------------------------------------------------
// Opaque types (backed by JDK classes via KRuntime helpers added in S03-05/S03-06)
// ---------------------------------------------------------------------------

// Server — wraps com.sun.net.httpserver.HttpServer
extern type Server = jvm("com.sun.net.httpserver.HttpServer")

// Request — wraps com.sun.net.httpserver.HttpExchange (server-side request/response handle)
extern type Request = jvm("com.sun.net.httpserver.HttpExchange")

// Response — wraps java.net.http.HttpResponse (client) or a synthetic { status, body } record
// (server). Both paths are unified behind this opaque type.
extern type Response = jvm("java.lang.Object")

// ---------------------------------------------------------------------------
// Exception for unimplemented stubs (removed when S03-05/S03-06 land)
// ---------------------------------------------------------------------------

export exception HttpNotImplemented

// ---------------------------------------------------------------------------
// Re-exported utility
// ---------------------------------------------------------------------------

export fun nowMs(): Int = Basics.nowMs()

// ---------------------------------------------------------------------------
// Stub declarations — implemented in S03-05 (client) and S03-06 (server).
// These stubs typecheck against the declared signatures; calling them throws
// HttpNotImplemented until the corresponding story lands.
// ---------------------------------------------------------------------------

// TODO(S03-06): implement createServer via KRuntime.httpCreateServer
export async fun createServer(_handler: (Request) -> Task<Response>): Task<Server> =
  throw HttpNotImplemented

// TODO(S03-06): implement listen via KRuntime.httpListen
export async fun listen(_server: Server, _opts: { host: String, port: Int }): Task<Unit> =
  throw HttpNotImplemented

// TODO(S03-05): implement get via KRuntime.httpGetAsync
export async fun get(_url: String): Task<Response> =
  throw HttpNotImplemented

// TODO(S03-05): implement bodyText via KRuntime.httpBodyText
export fun bodyText(_response: Response): String =
  throw HttpNotImplemented

// TODO(S03-05): implement statusCode via KRuntime.httpStatusCode
export fun statusCode(_response: Response): Int =
  throw HttpNotImplemented

// TODO(S03-05): implement makeResponse via KRuntime.httpMakeResponse
export fun makeResponse(_status: Int, _body: String): Response =
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
