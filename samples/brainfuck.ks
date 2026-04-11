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
//   fib     — first 8 Fibonacci numbers

import * as Arr from "kestrel:data/array"
import * as Str from "kestrel:data/string"
import * as Chr from "kestrel:data/char"

// ── Bracket pre-compilation ───────────────────────────────────────────────────

// Returns an array where jumps[pc] = matching bracket position for '[' and ']'.
fun buildJumps(prog: Array<Char>): Array<Int> = {
  val n = Arr.length(prog)
  val jumps = Arr.fromList(Lst.generate(n, (_) => -1))
  val stack: Array<Int> = Arr.new()
  var i = 0
  while (i < n) {
    match (Arr.get(prog, i)) {
      '[' => {
        Arr.push(stack, i)
        i := i + 1
      }
      ']' => {
        val open = Arr.get(stack, Arr.length(stack) - 1)
        Arr.set(jumps, open, i)
        Arr.set(jumps, i, open)
        // pop stack: rebuild without last element
        var j = 0
        val tmp: Array<Int> = Arr.new()
        while (j < Arr.length(stack) - 1) {
          Arr.push(tmp, Arr.get(stack, j))
          j := j + 1
        }
        var k = 0
        while (k < Arr.length(stack)) {
          if (k < Arr.length(tmp))
            Arr.set(stack, k, Arr.get(tmp, k))
          k := k + 1
        }
        // shrink stack length by re-creating it
        j := 0
        val stk2: Array<Int> = Arr.new()
        while (j < Arr.length(tmp)) {
          Arr.push(stk2, Arr.get(tmp, j))
          j := j + 1
        }
        i := i + 1
      }
      _ => i := i + 1
    }
  }
  jumps
}

// ── Interpreter ────────────────────────────────────────────────────────────────

fun run(source: String): Unit = {
  val chars = Arr.fromList(Str.toList(source))
  val prog: Array<Char> = Arr.new()
  var ci = 0
  while (ci < Arr.length(chars)) {
    val c = Arr.get(chars, ci)
    if (c == '+' || c == '-' || c == '>' || c == '<' || c == '.' || c == ',' || c == '[' || c == ']')
      Arr.push(prog, c)
    ci := ci + 1
  }

  val n = Arr.length(prog)
  val jumps = buildJumps(prog)

  val tape: Array<Int> = Arr.fromList(Lst.generate(30000, (_) => 0))
  var dp = 0   // data pointer
  var pc = 0   // program counter
  var out = "" // accumulated output

  while (pc < n) {
    match (Arr.get(prog, pc)) {
      '>' => { dp := dp + 1;                          pc := pc + 1 }
      '<' => { dp := dp - 1;                          pc := pc + 1 }
      '+' => { Arr.set(tape, dp, Arr.get(tape, dp) + 1); pc := pc + 1 }
      '-' => { Arr.set(tape, dp, Arr.get(tape, dp) - 1); pc := pc + 1 }
      '.' => {
        out := out ++ Chr.toString(Chr.intToChar(Arr.get(tape, dp)))
        pc := pc + 1
      }
      '[' => {
        if (Arr.get(tape, dp) == 0)
          pc := Arr.get(jumps, pc) + 1
        else
          pc := pc + 1
      }
      ']' => {
        if (Arr.get(tape, dp) != 0)
          pc := Arr.get(jumps, pc) + 1
        else
          pc := pc + 1
      }
      _   => pc := pc + 1
    }
  }
  println(out)
}

// ── Programs ──────────────────────────────────────────────────────────────────

val hello = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

val fib = "+++++++++++>+>>>>++++++++++++++++++++++++++++++++++++++++++++>++++++++++++++++++++++++++++++++<<<<<<[>[>>>>>>+>+<<<<<<<-]>>>>>>>[<<<<<<<+>>>>>>>-]<[>++++++++++[-<-[>>+>+<<<-]>>>[<<<+>>>-]+<[>[-]<[-]]>[<<[>>>+<<<-]>>[-]]<<]>>>[>>+>+<<<-]>>>[<<<+>>>-]+<[>[-]<[-]]>[<<+>>[-]]<<<<<<<]>>>>>[++++++++++++++++++++++++++++++++++++++++++++++++.[-]]++++++++++<[->-<]>[-]<<<<<<<<<<<[<]<<[>[>+>+<<-]>>[<<+>>-]<-]>[<<<<<<<<[<]<<[>[>+>+<<-]>>[<<+>>-]<-]>]<<<<<<<<[<]>>>>>>>>>>>>>>>>>>>>>>>>>>>"

println("=== Hello, World! ===")
run(hello)

println("=== Fibonacci ===")
run(fib)
