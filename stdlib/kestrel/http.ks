// kestrel:http — HTTP server and client (spec 02 §kestrel:http, runtime model 05 §2–3).
// S03-05: get, bodyText, statusCode, makeResponse implemented.
// S03-06: createServer, listen, queryParam, requestId, requestBodyText,
//         serverPort, serverStop implemented.
import * as Basics from "kestrel:basics"

// ---------------------------------------------------------------------------
// Opaque types (backed by JDK classes via KRuntime helpers)
// ---------------------------------------------------------------------------

// Server — wraps com.sun.net.httpserver.HttpServer
extern type Server = jvm("com.sun.net.httpserver.HttpServer")

// Request — wraps com.sun.net.httpserver.HttpExchange (server-side request/response handle)
extern type Request = jvm("com.sun.net.httpserver.HttpExchange")

// Response — wraps java.net.http.HttpResponse<String> (client) or Object[]{ status, body }
// (server-side, from makeResponse). Both are handled by KRuntime helpers.
extern type Response = jvm("java.lang.Object")

// ---------------------------------------------------------------------------
// Exception — thrown when calling a stub (should not appear in production)
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
// KRuntime extern bindings (S03-06: HTTP server)
// ---------------------------------------------------------------------------

extern fun httpCreateServer_(handler: (Request) -> Task<Response>): Task<Server> =
  jvm("kestrel.runtime.KRuntime#httpCreateServer(java.lang.Object)")

extern fun httpListenAsync_(server: Server, host: String, port: Int): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#httpListenAsync(java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun httpServerPort_(server: Server): Int =
  jvm("kestrel.runtime.KRuntime#httpServerPort(java.lang.Object)")

extern fun httpServerStop_(server: Server): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#httpServerStop(java.lang.Object)")

extern fun httpQueryParam_(request: Request, name: String): Option<String> =
  jvm("kestrel.runtime.KRuntime#httpQueryParam(java.lang.Object,java.lang.Object)")

extern fun httpRequestId_(request: Request): String =
  jvm("kestrel.runtime.KRuntime#httpRequestId(java.lang.Object)")

extern fun httpRequestBodyText_(request: Request): Task<String> =
  jvm("kestrel.runtime.KRuntime#httpRequestBodyText(java.lang.Object)")

// ---------------------------------------------------------------------------
// Public HTTP client API (S03-05)
// ---------------------------------------------------------------------------

export async fun get(url: String): Task<Response> = await httpGetAsync_(url)

export fun bodyText(resp: Response): String = httpBodyText_(resp)

export fun statusCode(resp: Response): Int = httpStatusCode_(resp)

export fun makeResponse(status: Int, body: String): Response = httpMakeResponse_(status, body)

// ---------------------------------------------------------------------------
// Public HTTP server API (S03-06)
// ---------------------------------------------------------------------------

export async fun createServer(handler: (Request) -> Task<Response>): Task<Server> =
  await httpCreateServer_(handler)

export async fun listen(server: Server, opts: { host: String, port: Int }): Task<Unit> =
  await httpListenAsync_(server, opts.host, opts.port)

export fun serverPort(server: Server): Int = httpServerPort_(server)

export async fun serverStop(server: Server): Task<Unit> = await httpServerStop_(server)

export fun queryParam(request: Request, name: String): Option<String> = httpQueryParam_(request, name)

export fun requestId(request: Request): String = httpRequestId_(request)

export async fun requestBodyText(request: Request): Task<String> =
  await httpRequestBodyText_(request)
