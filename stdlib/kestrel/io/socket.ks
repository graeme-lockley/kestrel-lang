// kestrel:io/socket — TCP and TLS socket library (S03-02).
// Provides plain TCP and TLS client/server sockets backed by JDK
// java.net.Socket / javax.net.ssl.SSLSocket via extern type / extern fun.
// All I/O operations return Task<T> and run on virtual threads.
//
// Usage (TCP client):
//   import * as Socket from "kestrel:io/socket"
//   val sock = await Socket.tcpConnect("example.com", 80)
//   await Socket.sendText(sock, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")
//   val resp = await Socket.readAll(sock)
//   await Socket.close(sock)
//
// Usage (TLS client):
//   val sock = await Socket.tlsConnect("example.com", 443)
//   await Socket.sendText(sock, "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")
//   val resp = await Socket.readAll(sock)
//   await Socket.close(sock)
//
// Usage (TCP server):
//   val ss = await Socket.listen("127.0.0.1", 0)
//   val port = Socket.serverPort(ss)
//   val conn = await Socket.accept(ss)
//   val data = await Socket.readAll(conn)
//   await Socket.close(conn)
//   await Socket.serverClose(ss)

// ---------------------------------------------------------------------------
// Opaque types
// ---------------------------------------------------------------------------

// A connected TCP or TLS socket (client side or accepted server connection).
export extern type Socket = jvm("java.net.Socket")

// A bound TCP server socket waiting to accept connections.
export extern type ServerSocket = jvm("java.net.ServerSocket")

// ---------------------------------------------------------------------------
// TCP client
// ---------------------------------------------------------------------------

extern fun tcpConnect_(host: String, port: Int): Task<Socket> =
  jvm("kestrel.runtime.KRuntime#tcpConnect(java.lang.Object,java.lang.Object)")

// Connect a plain TCP socket to host:port.
// Returns a Task<Socket>; fails with an IOException on connection error.
export fun tcpConnect(host: String, port: Int): Task<Socket> = tcpConnect_(host, port)

// ---------------------------------------------------------------------------
// TLS client
// ---------------------------------------------------------------------------

extern fun tlsConnect_(host: String, port: Int): Task<Socket> =
  jvm("kestrel.runtime.KRuntime#tlsConnect(java.lang.Object,java.lang.Object)")

// Connect a TLS socket to host:port using the JDK default SSLContext.
// Performs a full TLS handshake. Uses the system trust store; hostname
// verification is enabled. Returns a Task<Socket>.
export fun tlsConnect(host: String, port: Int): Task<Socket> = tlsConnect_(host, port)

// ---------------------------------------------------------------------------
// I/O
// ---------------------------------------------------------------------------

extern fun socketSendText_(sock: Socket, text: String): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#socketSendText(java.lang.Object,java.lang.Object)")

extern fun socketReadAll_(sock: Socket): Task<String> =
  jvm("kestrel.runtime.KRuntime#socketReadAll(java.lang.Object)")

extern fun socketReadLine_(sock: Socket): Task<String> =
  jvm("kestrel.runtime.KRuntime#socketReadLine(java.lang.Object)")

extern fun socketClose_(sock: Socket): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#socketClose(java.lang.Object)")

// Send text (UTF-8) over the socket.
export fun sendText(sock: Socket, text: String): Task<Unit> = socketSendText_(sock, text)

// Read all bytes until EOF (the remote closes its write side). Returns UTF-8 text.
// Use for protocols that close the connection after the response (HTTP/1.0, etc.).
export fun readAll(sock: Socket): Task<String> = socketReadAll_(sock)

// Read one line (terminated by \n or \r\n). Returns the line without trailing newline.
// Returns "" at EOF. Useful for line-oriented protocols (SMTP, FTP, etc.).
export fun readLine(sock: Socket): Task<String> = socketReadLine_(sock)

// Close the socket. Further I/O is an error.
export fun close(sock: Socket): Task<Unit> = socketClose_(sock)

// ---------------------------------------------------------------------------
// TCP server
// ---------------------------------------------------------------------------

extern fun tcpListen_(host: String, port: Int): Task<ServerSocket> =
  jvm("kestrel.runtime.KRuntime#tcpListen(java.lang.Object,java.lang.Object)")

extern fun serverSocketAccept_(ss: ServerSocket): Task<Socket> =
  jvm("kestrel.runtime.KRuntime#serverSocketAccept(java.lang.Object)")

extern fun serverSocketPort_(ss: ServerSocket): Int =
  jvm("kestrel.runtime.KRuntime#serverSocketPort(java.lang.Object)")

extern fun serverSocketClose_(ss: ServerSocket): Task<Unit> =
  jvm("kestrel.runtime.KRuntime#serverSocketClose(java.lang.Object)")

// Bind a TCP server socket on host:port. Use port=0 for OS-assigned ephemeral port.
export fun listen(host: String, port: Int): Task<ServerSocket> = tcpListen_(host, port)

// Accept one incoming connection. Returns a connected Socket for I/O.
export fun accept(ss: ServerSocket): Task<Socket> = serverSocketAccept_(ss)

// Return the local port the ServerSocket is bound to.
export fun serverPort(ss: ServerSocket): Int = serverSocketPort_(ss)

// Close the server socket. Pending accept() calls will fail.
export fun serverClose(ss: ServerSocket): Task<Unit> = serverSocketClose_(ss)
