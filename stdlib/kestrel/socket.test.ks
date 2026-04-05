// Tests for kestrel:socket TCP and TLS socket library (S03-02).
import { Suite, group, asyncGroup, eq, isTrue, isFalse } from "kestrel:test"
import * as Socket from "kestrel:socket"
import * as Str from "kestrel:string"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async fun acceptOnce(ss: Socket.ServerSocket): Task<String> = {
  val conn = await Socket.accept(ss);
  val msg = await Socket.readAll(conn);
  await Socket.close(conn);
  msg
}

async fun tcpGetExample(): Task<String> = {
  val sock = await Socket.tcpConnect("example.com", 80);
  await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
  val resp = await Socket.readAll(sock);
  await Socket.close(sock);
  resp
}

async fun tlsGetExample(): Task<String> = {
  val sock = await Socket.tlsConnect("example.com", 443);
  await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
  val resp = await Socket.readAll(sock);
  await Socket.close(sock);
  resp
}

async fun loopbackRoundTrip(): Task<String> = {
  val ss = await Socket.listen("127.0.0.1", 0);
  val port = Socket.serverPort(ss);
  val serverTask = acceptOnce(ss);
  val client = await Socket.tcpConnect("127.0.0.1", port);
  await Socket.sendText(client, "ping");
  await Socket.close(client);
  val received = await serverTask;
  await Socket.serverClose(ss);
  received
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "kestrel:socket", async (s1: Suite) => {
    await asyncGroup(s1, "TCP connect to example.com:80", async (sg: Suite) => {
      val tcpOk = await tcpGetExample();
      isTrue(sg, "response starts with HTTP/", Str.startsWith("HTTP/", tcpOk))
    });
    await asyncGroup(s1, "TLS connect to example.com:443", async (sg: Suite) => {
      val tlsOk = await tlsGetExample();
      isTrue(sg, "TLS response starts with HTTP/", Str.startsWith("HTTP/", tlsOk))
    });
    await asyncGroup(s1, "TCP loopback round-trip", async (sg: Suite) => {
      val roundTripMsg = await loopbackRoundTrip();
      eq(sg, "received message matches sent", roundTripMsg, "ping")
    })
  })
}
