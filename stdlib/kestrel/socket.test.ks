// Tests for kestrel:socket TCP and TLS socket library (S03-02).
import { Suite, group, asyncGroup, eq, isTrue } from "kestrel:tools/test"
import * as Socket from "kestrel:socket"
import * as Task from "kestrel:sys/task"
import * as Str from "kestrel:data/string"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Accept one connection: read one line from client (request), send response line, close.
// Client sends first, so server can safely close without a RST race.
async fun serveOnce(ss: Socket.ServerSocket, response: String): Task<Unit> = {
  val conn = await Socket.accept(ss);
  val _ = await Socket.readLine(conn);
  await Socket.sendText(conn, "${response}\n");
  await Socket.close(conn)
}

// Connect as a client: send one request line, read one response line, close.
async fun requestOnce(host: String, port: Int, request: String): Task<String> = {
  val sock = await Socket.tcpConnect(host, port);
  await Socket.sendText(sock, "${request}\n");
  val resp = await Socket.readLine(sock);
  await Socket.close(sock);
  resp
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "kestrel:socket", async (s1: Suite) => {
    // Raw loopback: client sends, server reads all (EOF from client close), echoes back
    await asyncGroup(s1, "TCP loopback round-trip", async (sg: Suite) => {
      val ss = await Socket.listen("127.0.0.1", 0);
      val port = Socket.serverPort(ss);
      val serverTask = Task.map(Socket.accept(ss), (conn: Socket.Socket) => conn);
      val client = await Socket.tcpConnect("127.0.0.1", port);
      await Socket.sendText(client, "ping");
      await Socket.close(client);
      val conn = await serverTask;
      val received = await Socket.readAll(conn);
      await Socket.close(conn);
      await Socket.serverClose(ss);
      eq(sg, "received message matches sent", received, "ping")
    });

    // HTTP-shaped request/response: client sends first so server close is race-free
    await asyncGroup(s1, "TCP HTTP/1.0 exchange", async (sg: Suite) => {
      val ss = await Socket.listen("127.0.0.1", 0);
      val port = Socket.serverPort(ss);
      val serverTask = serveOnce(ss, "HTTP/1.0 200 OK");
      val resp = await requestOnce("127.0.0.1", port, "GET / HTTP/1.0");
      await serverTask;
      await Socket.serverClose(ss);
      isTrue(sg, "response starts with HTTP/", Str.startsWith("HTTP/", resp))
    });

    // Multiple sequential connections to the same server socket
    await asyncGroup(s1, "TCP multiple connections", async (sg: Suite) => {
      val ss = await Socket.listen("127.0.0.1", 0);
      val port = Socket.serverPort(ss);

      val c1 = await Socket.tcpConnect("127.0.0.1", port);
      val conn1 = await Socket.accept(ss);
      await Socket.sendText(c1, "first");
      await Socket.close(c1);
      val msg1 = await Socket.readAll(conn1);
      await Socket.close(conn1);

      val c2 = await Socket.tcpConnect("127.0.0.1", port);
      val conn2 = await Socket.accept(ss);
      await Socket.sendText(c2, "second");
      await Socket.close(c2);
      val msg2 = await Socket.readAll(conn2);
      await Socket.close(conn2);

      await Socket.serverClose(ss);
      eq(sg, "first connection message", msg1, "first");
      eq(sg, "second connection message", msg2, "second")
    })
  })
}
