// Conway's Game of Life — functional grid evolution on a flat Array<Int>.
//
// The live grid is a width×height integer array indexed as y*width+x.
// 1 = alive, 0 = dead. stepGrid derives the next generation without
// mutating the current one.  Prints several generations so you can
// watch patterns evolve.
import * as Arr from "kestrel:data/array"
import * as Str from "kestrel:data/string"
import * as Basics from "kestrel:data/basics"
import * as Console from "kestrel:io/console"

val term = Console.terminalInfo()
val width = Basics.clamp(40, 200, term.width)
val height = Basics.clamp(20, 60, term.height - 4)

// ── grid primitives ──────────────────────────────────────────────────────
fun mkGrid(): Array<Int> = {
  val g = Arr.new()
  var i = 0
  while (i < width * height) {
    Arr.push(g, 0)
    i := i + 1
  }
  g
}

fun alive(g: Array<Int>, x: Int, y: Int): Bool =
  if (x < 0 | x >= width | y < 0 | y >= height) False else Arr.get(g, y * width + x) != 0

fun countNeighbours(g: Array<Int>, x: Int, y: Int): Int = {
  var n = 0
  var dy = 0 - 1
  while (dy <= 1) {
    var dx = 0 - 1
    while (dx <= 1) {
      if (!(dx == 0 & dy == 0) & alive(g, x + dx, y + dy)) {
        n := n + 1
      }
      dx := dx + 1
    }
    dy := dy + 1
  }
  n
}

fun stepGrid(g: Array<Int>): Array<Int> = {
  val next = mkGrid()
  var y = 0
  while (y < height) {
    var x = 0
    while (x < width) {
      var n = countNeighbours(g, x, y)
      var on = Arr.get(g, y * width + x)
      if (on != 0 & (n == 2 | n == 3) | on == 0 & n == 3) {
        Arr.set(next, y * width + x, 1)
      }
      x := x + 1
    }
    y := y + 1
  }
  next
}

// ── rendering ────────────────────────────────────────────────────────────
fun printGrid(g: Array<Int>): Unit = {
  var y = 0
  while (y < height) {
    var x = 0
    var row = "│"
    while (x < width) {
      val v = Arr.get(g, y * width + x)
      val ch = if (v != 0) "█" else " "
      row := "${row}${ch}"
      x := x + 1
    }
    println("${row}│")
    y := y + 1
  }
}

fun showGen(g: Array<Int>, gen: Int): Unit = {
  println("┌── Generation ${Str.fromInt(gen)} ${Str.repeat(width - 14, "─")}┐")
  printGrid(g)
  println("└${Str.repeat(width + 2, "─")}┘")
}

// ── seeds ────────────────────────────────────────────────────────────────
// Seed cells as (x, y) coordinate pairs.
// Glider — moves diagonally down-right
val gliderCells = [(3, 1), (4, 2), (2, 3), (3, 3), (4, 3)]

// Blinker — period-2 oscillator, starts horizontal
val blinkerCells = [(13, 10), (14, 10), (15, 10)]

// Beacon — period-2 oscillator (two overlapping 2×2 blocks)
val beaconCells = [(24, 7), (25, 7), (24, 8), (27, 9), (26, 9), (27, 8)]

// Toad — period-2 oscillator
val toadCells = [(31, 13), (32, 13), (33, 13), (30, 14), (31, 14), (32, 14)]

// Still life: Block — stable 2×2 square
val blockCells = [(36, 17), (37, 17), (36, 18), (37, 18)]

// ── initialise ───────────────────────────────────────────────────────────
fun plantCells(g: Array<Int>, cells: List<Int * Int>): Unit =
  match (cells) {
    [] =>
      (),
    h :: t => {
      Arr.set(g, h.1 * width + h.0, 1)
      plantCells(g, t)
    }
  }

fun initGrid(): Array<Int> = {
  val g = mkGrid()
  plantCells(g, gliderCells)
  plantCells(g, blinkerCells)
  plantCells(g, beaconCells)
  plantCells(g, toadCells)
  plantCells(g, blockCells)
  g
}

// ── run ──────────────────────────────────────────────────────────────────
fun run(g: Array<Int>, gen: Int, limit: Int): Unit =
  if (gen > limit)
    ()
  else {
    showGen(g, gen)
    run(stepGrid(g), gen + 1, limit)
  }

run(initGrid(), 0, 9)
