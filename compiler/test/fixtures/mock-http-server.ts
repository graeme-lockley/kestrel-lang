/**
 * Minimal mock HTTP server for URL import integration tests.
 * Serves .ks source files from an in-memory map.
 * Records which paths were requested (to verify cache-hit bypasses network).
 */
import http from 'node:http';
import { AddressInfo } from 'node:net';

export interface MockServer {
  /** Base URL of the server (e.g. http://127.0.0.1:PORT) */
  url: string;
  /** Ordered list of URL paths that were requested (e.g. ['/fred.ks', '/dir/mary.ks']) */
  requestedPaths: string[];
  /** Reset the request log */
  resetLog(): void;
  /** Stop the server */
  close(): Promise<void>;
}

/**
 * Start a local HTTP server serving the given file map.
 * Keys are URL paths (e.g. '/fred.ks'), values are .ks source text.
 */
export async function startMockServer(files: Map<string, string>): Promise<MockServer> {
  const requestedPaths: string[] = [];

  const server = http.createServer((req, res) => {
    const path = req.url ?? '/';
    requestedPaths.push(path);
    const body = files.get(path);
    if (body === undefined) {
      res.writeHead(404);
      res.end('not found');
    } else {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(body, 'utf-8');
    }
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));

  const addr = server.address() as AddressInfo;
  const baseUrl = `http://127.0.0.1:${addr.port}`;

  return {
    url: baseUrl,
    requestedPaths,
    resetLog() {
      requestedPaths.splice(0);
    },
    close() {
      return new Promise((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve()))
      );
    },
  };
}
