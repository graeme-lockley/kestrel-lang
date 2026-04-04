// Typecheck conformance test for kestrel:http opaque types and function signatures (S03-01).
// Declares extern types inline (no stdlib import) to verify Server, Request, Response
// are usable as types and all function signatures from docs/specs/02-stdlib.md §kestrel:http
// typecheck correctly.

export exception HttpNotImplemented

extern type Server = jvm("com.sun.net.httpserver.HttpServer")
extern type Request = jvm("com.sun.net.httpserver.HttpExchange")
extern type Response = jvm("java.lang.Object")

// createServer: ((Request) -> Task<Response>) -> Task<Server>
fun createServer(handler: (Request) -> Task<Response>): Task<Server> =
  throw HttpNotImplemented

// listen: (Server, { host: String, port: Int }) -> Task<Unit>
fun listen(server: Server, opts: { host: String, port: Int }): Task<Unit> =
  throw HttpNotImplemented

// get: (String) -> Task<Response>
fun get(url: String): Task<Response> =
  throw HttpNotImplemented

// bodyText: (Response) -> String
fun bodyText(resp: Response): String =
  throw HttpNotImplemented

// statusCode: (Response) -> Int
fun statusCode(resp: Response): Int =
  throw HttpNotImplemented

// makeResponse: (Int, String) -> Response
fun makeResponse(status: Int, body: String): Response =
  throw HttpNotImplemented

// requestBodyText: (Request) -> Task<String>
fun requestBodyText(req: Request): Task<String> =
  throw HttpNotImplemented

// queryParam: (Request, String) -> Option<String>
fun queryParam(req: Request, name: String): Option<String> =
  throw HttpNotImplemented

// requestId: (Request) -> String
fun requestId(req: Request): String =
  throw HttpNotImplemented
