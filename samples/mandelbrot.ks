// Render a colour Mandelbrot set in the terminal (ANSI 256-colour + density chars).

import { slice } from "kestrel:data/string"
import { ESC, RESET } from "kestrel:io/console"

val maxIter = 50

val minRe = 0.0 - 2.0
val maxRe = 1.0
val minIm = 0.0 - 1.2
val maxIm = 1.2

val rangeRe = maxRe - minRe
val rangeIm = maxIm - minIm

val cols = 80.0
val rows = 24.0

val stepRe = rangeRe / cols
val stepIm = rangeIm / rows

val charset = " .:-=+*#%@"

// Map escape time to 256-colour index (deep blue → cyan → green → yellow → orange → red).
fun iterToFg256(iter: Int): Int =
  if (iter >= maxIter) {
    17
  } else {
    val x = iter * 220 / maxIter
    if (x < 25) {
      17 + x
    } else if (x < 70) {
      39 + (x - 25) / 2
    } else if (x < 120) {
      79 + (x - 70) / 2
    } else if (x < 165) {
      190 + (x - 120) / 3
    } else if (x < 200) {
      214 + (x - 165) / 4
    } else {
      196 + (x - 200) / 5
    }
  }

fun mandelIter(cRe: Float, cIm: Float, zRe: Float, zIm: Float, i: Int): Int =
  if (i >= maxIter) {
    i
  } else if ((zRe * zRe + zIm * zIm) > 4.0) {
    i
  } else {
    val newRe = zRe * zRe - zIm * zIm + cRe
    val newIm = 2.0 * zRe * zIm + cIm
    mandelIter(cRe, cIm, newRe, newIm, i + 1)
  }

fun pickCell(iter: Int): String =
  if (iter >= maxIter) {
    "${ESC}[48;5;17m ${RESET}"
  } else {
    val idx = iter % 10
    val ch = slice(charset, idx, idx + 1)
    val c = iterToFg256(iter)
    "${ESC}[38;5;${c}m${ch}${RESET}"
  }

fun renderRow(col: Float, im: Float, acc: String): String =
  if (col >= cols) acc
  else {
    val it = mandelIter(minRe + stepRe * col, im, 0.0, 0.0, 0)
    renderRow(col + 1.0, im, "${acc}${pickCell(it)}")
  }

fun render(row: Float): Unit =
  if (row < rows) {
    println(renderRow(0.0, minIm + stepIm * row, ""))
    render(row + 1.0)
  }

render(0.0)
