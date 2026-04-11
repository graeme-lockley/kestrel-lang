export val ESC = "\u{1b}"
export val GREEN = "${ESC}[32m"
export val RED = "${ESC}[31m"
export val YELLOW = "${ESC}[33m"
export val DIM = "${ESC}[2m"
export val RESET = "${ESC}[0m"
export val CHECK = "\u{2713}"
export val CROSS = "\u{2717}"
export val SPINNER = "\u{28cb}"
export val CLEAR_LINE = "\r${ESC}[2K"

/** Terminal dimensions and TTY status. */
export type TerminalInfo = { width: Int, height: Int, isTty: Bool }

extern fun _terminalWidth(): Int =
  jvm("kestrel.runtime.KRuntime#terminalWidth()")

extern fun _terminalHeight(): Int =
  jvm("kestrel.runtime.KRuntime#terminalHeight()")

extern fun _isTtyStdout(): Bool =
  jvm("kestrel.runtime.KRuntime#isTtyStdout()")

/** Returns terminal dimensions and whether stdout is a TTY (falls back to 80×24 when not a TTY). */
export fun terminalInfo(): TerminalInfo =
  { width = _terminalWidth(), height = _terminalHeight(), isTty = _isTtyStdout() }

export extern fun printErr(s: String): Unit =
  jvm("kestrel.runtime.KRuntime#printErr(java.lang.Object)")

export fun eprintln(s: String): Unit = printErr(s)
