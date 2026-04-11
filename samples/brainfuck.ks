#!/usr/bin/env kestrel

// Brainfuck interpreter — a complete interpreter for the Brainfuck esoteric
// language, written in ~60 lines of pure Kestrel.
//
// Brainfuck has eight commands operating on a 30 000-cell integer tape:
//   >  move pointer right        <  move pointer left
//   +  increment current cell    -  decrement current cell
//   .  print current cell        ,  read one byte (not used here)
//   [  jump past ] if cell = 0   ]  jump back to [ if cell ≠ 0
//
// This interpreter pre-compiles the bracket pairs into a jump table so
// that loops run in O(1) per bracket rather than O(program length).
//
// Included programs:
//   hello   — the classic "Hello, World!"
//   count   — prints 12345678 using a small setup loop
//   fact5   — computes 5! on the tape, then prints 120
import * as Arr from "kestrel:data/array"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Chr from "kestrel:data/char"

// ── Bracket pre-compilation ───────────────────────────────────────────────────
fun filledInts(size: Int, value: Int): Array<Int> = {
  val arr: Array<Int> = Arr.new()
  var i = 0
  while (i < size) {
    Arr.push(arr, value)
    i := i + 1
  }
  arr
}

// Returns an array where jumps[pc] = matching bracket position for '[' and ']'.
fun buildJumpsLoop(prog: Array<Char>, jumps: Array<Int>, stack: List<Int>, i: Int, n: Int): Array<Int> =
  if (i >= n) {
    jumps
  }
  else {
    match (Arr.get(prog, i)) {
      '[' =>
        buildJumpsLoop(prog, jumps, i :: stack, i + 1, n),
      ']' =>
        match (stack) {
          [] =>
            buildJumpsLoop(prog, jumps, stack, i + 1, n),
          open :: rest => {
            Arr.set(jumps, open, i)
            Arr.set(jumps, i, open)
            buildJumpsLoop(prog, jumps, rest, i + 1, n)
          }
        },
      _ =>
        buildJumpsLoop(prog, jumps, stack, i + 1, n)
    }
  }

fun buildJumps(prog: Array<Char>): Array<Int> = {
  val n = Arr.length(prog)
  val jumps = filledInts(n, -1)
  buildJumpsLoop(prog, jumps, [], 0, n)
}

fun isInstruction(c: Char): Bool =
  c == '+' | c == '-' | c == '>' | c == '<' | c == '.' | c == ',' | c == '[' | c == ']'

// ── Interpreter ────────────────────────────────────────────────────────────────
fun run(source: String): Unit = {
  val chars = Arr.fromList(Str.toList(source))
  val prog: Array<Char> = Arr.new()
  var ci = 0
  while (ci < Arr.length(chars)) {
    val c = Arr.get(chars, ci)
    if (isInstruction(c)) Arr.push(prog, c)
    ci := ci + 1
  }
  val n = Arr.length(prog)
  val jumps = buildJumps(prog)
  val tape = filledInts(30000, 0)
  var dp = 15000  // data pointer starts mid-tape so programs can move left
  var pc = 0  // program counter
  var out = ""  // accumulated output
  while (pc < n) {
    match (Arr.get(prog, pc)) {
      '>' => {
        dp := dp + 1
        pc := pc + 1
      },
      '<' => {
        dp := dp - 1
        pc := pc + 1
      },
      '+' => {
        Arr.set(tape, dp, Arr.get(tape, dp) + 1)
        pc := pc + 1
      },
      '-' => {
        Arr.set(tape, dp, Arr.get(tape, dp) - 1)
        pc := pc + 1
      },
      '.' => {
        out := Str.append(out, Chr.charToString(Chr.intToChar(Arr.get(tape, dp))))
        pc := pc + 1
      },
      '[' => {
        val nextPc = if (Arr.get(tape, dp) == 0) Arr.get(jumps, pc) + 1 else pc + 1
        pc := nextPc
      },
      ']' => {
        val nextPc = if (Arr.get(tape, dp) != 0) Arr.get(jumps, pc) else pc + 1
        pc := nextPc
      },
      _ => {
        pc := pc + 1
      }
    }
  }
  println(out)
}

val hello = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

val count = "++++++[>++++++++<-]>+.+.+.+.+.+.+.+."

val fact5 = "++++>+++++<[>[-<[->>+>+<<<]>>>[<<<+>>>-]<<]>[<+>-]<<-]>>++++++++++[>++++++++++<-]+>[<<->>-]<>++++++[<++++++++>-]<.<---------->>+<<---------->>+>++++++[<++++++++>-]<.--."

println("=== Hello, World! ===")

// ── Programs ──────────────────────────────────────────────────────────────────
run(hello)

println("=== Counter ===")

run(count)

println("=== Factorial (5! = 120) ===")

run(fact5)
