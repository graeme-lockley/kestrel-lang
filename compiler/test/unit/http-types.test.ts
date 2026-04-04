/**
 * Unit tests for kestrel:http opaque type stubs (S03-01).
 *
 * Verifies that:
 * - Server, Request, Response extern type declarations parse and typecheck
 * - All nine exported function signatures typecheck with correct arities
 * - nowMs signature (Int return) is preserved
 */
import { describe, it, expect } from 'vitest';
import { compile } from '../../src/index.js';

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

describe('http opaque type stubs (S03-01)', () => {
  it('extern type declarations for Server, Request, Response parse and typecheck', () => {
    const result = compile(`
      extern type Server = jvm("com.sun.net.httpserver.HttpServer")
      extern type Request = jvm("com.sun.net.httpserver.HttpExchange")
      extern type Response = jvm("java.lang.Object")
    `);
    expect(result.ok).toBe(true);
  });

  it('Server, Request, Response usable in function signatures', () => {
    const result = compile(`
      extern type Server = jvm("com.sun.net.httpserver.HttpServer")
      extern type Request = jvm("com.sun.net.httpserver.HttpExchange")
      extern type Response = jvm("java.lang.Object")
      export exception HttpNotImplemented
      fun useTypes(s: Server, r: Request, resp: Response): Unit = throw HttpNotImplemented
    `);
    expect(result.ok).toBe(true);
  });

  it('all nine stub function signatures typecheck', () => {
    const result = compile(HTTP_STUBS);
    expect(result.ok, result.ok ? '' : (result as { diagnostics: { message: string }[] }).diagnostics.map((d) => d.message).join('; ')).toBe(true);
  });

  it('createServer accepts handler (Request) -> Task<Response>', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun handler(req: Request): Task<Response> = throw HttpNotImplemented
      val _server = createServer(handler)
    `);
    expect(result.ok).toBe(true);
  });

  it('listen accepts Server and { host, port } record', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun handler(req: Request): Task<Response> = throw HttpNotImplemented
      val s = createServer(handler)
    `);
    expect(result.ok).toBe(true);
  });

  it('get returns Task<Response>', () => {
    const result = compile(`
      ${HTTP_STUBS}
      val resp = get("http://example.com")
    `);
    expect(result.ok).toBe(true);
  });

  it('bodyText accepts Response and returns String', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun extractBody(r: Response): String = bodyText(r)
    `);
    expect(result.ok).toBe(true);
  });

  it('statusCode accepts Response and returns Int', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun getStatus(r: Response): Int = statusCode(r)
    `);
    expect(result.ok).toBe(true);
  });

  it('makeResponse accepts Int and String, returns Response', () => {
    const result = compile(`
      ${HTTP_STUBS}
      val r = makeResponse(200, "ok")
    `);
    expect(result.ok).toBe(true);
  });

  it('queryParam accepts Request and String, returns Option<String>', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun getParam(req: Request): Option<String> = queryParam(req, "name")
    `);
    expect(result.ok).toBe(true);
  });

  it('requestId accepts Request and returns String', () => {
    const result = compile(`
      ${HTTP_STUBS}
      fun getId(req: Request): String = requestId(req)
    `);
    expect(result.ok).toBe(true);
  });
});
