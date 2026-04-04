// E2E test: TCP server socket loopback round-trip (S03-02).
// Binds a server socket, accepts one connection, reads the message, and verifies it.
import * as Socket from "kestrel:socket"

async fun acceptOnce(ss: Socket.ServerSocket): Task<String> = {
  val conn = await Socket.accept(ss);
  val msg = await Socket.readAll(conn);
  await Socket.close(conn);
  msg
}

async fun run(): Task<Unit> = {
  val ss = await Socket.listen("127.0.0.1", 0);
  val port = Socket.serverPort(ss);
  val serverTask = acceptOnce(ss);
  val client = await Socket.tcpConnect("127.0.0.1", port);
  await Socket.sendText(client, "hello socket");
  await Socket.close(client);
  val received = await serverTask;
  await Socket.serverClose(ss);
  println(received)
}

run()
