//! HTTP client and server primitives.
//!
//! Provides request execution, response accessors, and server lifecycle helpers.
//! Higher-level routing is available in [`kestrel:io/web`](/docs/kestrel:io/web).
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Http from "kestrel:io/http"
//!
//! val resp = await Http.get("https://example.com")
//! val code = Http.statusCode(resp)
//! val body = Http.bodyText(resp)
//! ```

import * as Basics from "kestrel:data/basics"

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

extern fun httpMakeResponseWithHeaders_(status: Int, body: String, headers: List<(String, String)>): Response =
  jvm("kestrel.runtime.KRuntime#httpMakeResponseWithHeaders(java.lang.Object,java.lang.Object,java.lang.Object)")

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

extern fun httpParkAsync_(): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#parkAsync()")

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

export fun makeResponseWithHeaders(status: Int, body: String, headers: List<(String, String)>): Response =
  httpMakeResponseWithHeaders_(status, body, headers)

// ---------------------------------------------------------------------------
// Public HTTP server API (S03-06)
// ---------------------------------------------------------------------------

export async fun createServer(handler: (Request) -> Task<Response>): Task<Server> =
  await httpCreateServer_(handler)

export async fun listen(server: Server, opts: { host: String, port: Int }): Task<Unit> =
  await httpListenAsync_(server, opts.host, opts.port)

export fun serverPort(server: Server): Int = httpServerPort_(server)

export async fun serverStop(server: Server): Task<Unit> = await httpServerStop_(server)

/// Block the current task indefinitely (until process shutdown / SIGINT).
/// Call after `Http.listen` to prevent the process from exiting due to quiescence.
export async fun park(): Task<Unit> = await httpParkAsync_()

export fun queryParam(request: Request, name: String): Option<String> = httpQueryParam_(request, name)

export fun requestId(request: Request): String = httpRequestId_(request)

export async fun requestBodyText(request: Request): Task<String> =
  await httpRequestBodyText_(request)

// ---------------------------------------------------------------------------
// KRuntime extern bindings (S03-03: full HTTP client — method/headers/body)
// ---------------------------------------------------------------------------

extern fun httpRequestAsync_(method: String, url: String, headers: List<(String, String)>, body: Option<String>): Task<Response> =
  jvm("kestrel.runtime.KRuntime#httpRequestAsync(java.lang.Object,java.lang.Object,java.lang.Object,java.lang.Object)")

extern fun httpResponseHeaders_(resp: Response): List<(String, String)> =
  jvm("kestrel.runtime.KRuntime#httpResponseHeaders(java.lang.Object)")

extern fun httpResponseHeader_(resp: Response, name: String): Option<String> =
  jvm("kestrel.runtime.KRuntime#httpResponseHeader(java.lang.Object,java.lang.Object)")

// ---------------------------------------------------------------------------
// Public HTTP client API (S03-03)
// ---------------------------------------------------------------------------

export async fun request(opts: { method: String, url: String, headers: List<(String, String)>, body: Option<String> }): Task<Response> =
  await httpRequestAsync_(opts.method, opts.url, opts.headers, opts.body)

export fun responseHeaders(resp: Response): List<(String, String)> = httpResponseHeaders_(resp)

export fun responseHeader(resp: Response, name: String): Option<String> = httpResponseHeader_(resp, name)

// ---------------------------------------------------------------------------
// KRuntime extern bindings (S03-04: request inspection — method and path)
// ---------------------------------------------------------------------------

extern fun httpRequestMethod_(req: Request): String =
  jvm("kestrel.runtime.KRuntime#httpRequestMethod(java.lang.Object)")

extern fun httpRequestPath_(req: Request): String =
  jvm("kestrel.runtime.KRuntime#httpRequestPath(java.lang.Object)")

// ---------------------------------------------------------------------------
// Public HTTP server request-inspection API (S03-04)
// ---------------------------------------------------------------------------

export fun requestMethod(req: Request): String = httpRequestMethod_(req)

export fun requestPath(req: Request): String = httpRequestPath_(req)
