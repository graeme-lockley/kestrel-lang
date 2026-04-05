// Conway's Game of Life — functional grid evolution on a flat Array<Bool>.
//
// The live grid is a width×height boolean array indexed as y*width+x.
// stepGrid derives the next generation without mutating the current one.
// Prints several generations so you can watch patterns evolve.

import * as Arr from "kestrel:array"
import * as Str from "kestrel:data/string"

val width  = 40
val height = 20

// ── grid primitives ──────────────────────────────────────────────────────

fun mkGrid(): Array<Bool> = {
  val g = Arr.new()
  var i = 0
  while (i < width * height) {
    Arr.push(g, False)
    i := i + 1
  }
  g
}

fun alive(g: Array<Bool>, x: Int, y: Int): Bool =
  if (x < 0 | x >= width | y < 0 | y >= height) False
  else Arr.get(g, y * width + x)

fun countNeighbours(g: Array<Bool>, x: Int, y: Int): Int = {
  var n = 0
  var dy = 0 - 1
  while (dy <= 1) {
    var dx = 0 - 1
    while (dx <= 1) {
      if (!(dx == 0 & dy == 0) & alive(g, x + dx, y + dy))
        n := n + 1
      dx := dx + 1
    }
    dy := dy + 1
  }
  n
}

fun stepGrid(g: Array<Bool>): Array<Bool> = {
  val next = mkGrid()
  var y = 0
  while (y < height) {
    var x = 0
    while (x < width) {
      val n        = countNeighbours(g, x, y)
      val on       = alive(g, x, y)
      val survives = (on & (n == 2 | n == 3)) | (!on & n == 3)
      Arr.set(next, y * width + x, survives)
      x := x + 1
    }
    y := y + 1
  }
  next
}

// ── rendering ────────────────────────────────────────────────────────────

fun printRow(g: Array<Bool>, x: Int, y: Int, acc: String): String =
  if (x >= width) acc
  else {
    val ch = if (alive(g, x, y)) "█" else " "
    printRow(g, x + 1, y, "${acc}${ch}")
  }

fun printGrid(g: Array<Bool>, y: Int): Unit =
  if (y < height) {
    println("│${printRow(g, 0, y, "")}│")
    printGrid(g, y + 1)
  }

fun showGen(g: Array<Bool>, gen: Int): Unit = {
  println("┌── Generation ${Str.fromInt(gen)} ${Str.repeat(21, "─")}┐")
  printGrid(g, 0)
  println("└${Str.repeat(width + 2, "─")}┘")
}

// ── seeds ────────────────────────────────────────────────────────────────
// Seed cells as (x, y) coordinate pairs.

// Glider — moves diagonally down-right
val gliderCells = [
  (3, 1), (4, 2), (2, 3), (3, 3), (4, 3)
]

// Blinker — period-2 oscillator, starts horizontal
val blinkerCells = [
  (13, 10), (14, 10), (15, 10)
]

// Beacon — period-2 oscillator (two overlapping 2×2 blocks)
val beaconCells = [
  (24, 7), (25, 7), (24, 8),
  (27, 9), (26, 9), (27, 8)
]

// Toad — period-2 oscillator
val toadCells = [
  (31, 13), (32, 13), (33, 13),
  (30, 14), (31, 14), (32, 14)
]

// Still life: Block — stable 2×2 square
val blockCells = [
  (36, 17), (37, 17), (36, 18), (37, 18)
]

// ── initialise ───────────────────────────────────────────────────────────

fun plantCells(g: Array<Bool>, cells: List<(Int, Int)>): Unit = match (cells) {
  [] => ()
  h :: t => {
    Arr.set(g, h.1 * width + h.0, True)
    plantCells(g, t)
  }
}

fun initGrid(): Array<Bool> = {
  val g = mkGrid()
  plantCells(g, gliderCells)
  plantCells(g, blinkerCells)
  plantCells(g, beaconCells)
  plantCells(g, toadCells)
  plantCells(g, blockCells)
  g
}

// ── run ──────────────────────────────────────────────────────────────────

fun run(g: Array<Bool>, gen: Int, limit: Int): Unit =
  if (gen > limit) ()
  else {
    showGen(g, gen)
    run(stepGrid(g), gen + 1, limit)
  }

run(initGrid(), 0, 9)
