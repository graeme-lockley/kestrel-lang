import { compile } from './dist/src/index.js';

const HTTP_STUBS = `
export exception HttpNotImplemented
extern type Server = jvm("com.sun.net.httpserver.HttpServer")
extern type Request = jvm("com.sun.net.httpserver.HttpExchange")
extern type Response = jvm("java.lang.Object")
fun createServer(handler: (Request) -> Task<Response>): Task<Server> = throw HttpNotImplemented
fun listen(server: Server, opts: { host: String, port: Int }): Task<Unit> = throw HttpNotImplemented
fun get(url: String): Task<Response> = throw HttpNotImplemented
fun bodyText(resp: Response): String = throw HttpNotImplemented
fun statusCode(resp: Response): Int = throw HttpNotImplemented
fun makeResponse(status: Int, body: String): Response = throw HttpNotImplemented
fun requestBodyText(req: Request): Task<String> = throw HttpNotImplemented
fun queryParam(req: Request, name: String): Option<String> = throw HttpNotImplemented
fun requestId(req: Request): String = throw HttpNotImplemented
`;

function test(label, code) {
  const r = compile(code);
  if (!r.ok) {
    console.error(`FAIL [${label}]:`);
    r.diagnostics.forEach(d => console.error('  -', d.message, JSON.stringify(d.location)));
  } else {
    console.log(`PASS [${label}]`);
  }
}

test('all stubs', HTTP_STUBS);

test('createServer', HTTP_STUBS + `
fun handler(req: Request): Task<Response> = throw HttpNotImplemented
val _server: Task<Server> = createServer(handler)
`);

test('get returns Task<Response>', HTTP_STUBS + `
val resp: Task<Response> = get("http://example.com")
`);

test('makeResponse', HTTP_STUBS + `
val r: Response = makeResponse(200, "ok")
`);
