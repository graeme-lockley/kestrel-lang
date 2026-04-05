// E2E test: plain TCP socket connect to example.com (S03-02).
// Opens a TCP connection, sends an HTTP/1.0 GET request, checks the response.
import * as Socket from "kestrel:socket"
import * as Str from "kestrel:data/string"

async fun run(): Task<Unit> = {
  val sock = await Socket.tcpConnect("example.com", 80);
  await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
  val resp = await Socket.readAll(sock);
  await Socket.close(sock);
  val startsWithHttp = Str.startsWith("HTTP/", resp);
  println(startsWithHttp)
}

run()
