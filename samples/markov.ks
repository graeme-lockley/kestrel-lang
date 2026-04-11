#!/usr/bin/env kestrel

// samples/markov.ks — character-level bigram language model
//
// Demonstrates the statistical core shared by all language models:
//   1. Slide a 2-character context window across training text and count
//      how often each character follows each pair.
//   2. To generate new text, repeatedly sample the next character
//      weighted by those counts, then slide the window one step right.
//
// This is exactly what a large language model does, scaled up:
//   context  :  2 chars           →  128 000 tokens
//   table    :  bigram count dict →  weight matrices (billions of params)
//   sampling :  frequency counts  →  softmax(W · x + b)
//   learning :  counting          →  gradient descent
//
// Usage:  ./kestrel run samples/markov.ks

import * as Dict from "kestrel:data/dict"
import * as Lst  from "kestrel:data/list"
import * as Str  from "kestrel:data/string"
import * as Chr  from "kestrel:data/char"
import * as Rnd  from "kestrel:data/int"

// ── Corpus ──────────────────────────────────────────────────────────────────
//
// Hamlet, Act III Scene I.  ~500 characters of training text.
// Even at this tiny scale the model learns:
//   • common bigrams: "th", "he", "in", "to", "an"
//   • word boundaries (space ↔ consonant transitions)
//   • short, recognisable fragments of the original text

val corpus =
  "to be or not to be that is the question " +
  "whether tis nobler in the mind to suffer " +
  "the slings and arrows of outrageous fortune " +
  "or to take arms against a sea of troubles " +
  "and by opposing end them to die to sleep " +
  "no more and by a sleep to say we end " +
  "the heartache and the thousand natural shocks " +
  "that flesh is heir to tis a consummation " +
  "devoutly to be wished to die to sleep " +
  "to sleep perchance to dream ay there is the rub "

// ── Training ────────────────────────────────────────────────────────────────

// Increment the count for key `ch` in a (String → Int) count dict.
fun incr(d: Dict<String, Int>, ch: String): Dict<String, Int> =
  Dict.update(d, ch, (opt) =>
    match (opt) {
      None    => Some(1)
      Some(n) => Some(n + 1)
    })

// Record that the 2-char context `ctx` was followed by character `ch`.
fun observe(
  model: Dict<String, Dict<String, Int>>,
  ctx:   String,
  ch:    String
): Dict<String, Dict<String, Int>> =
  Dict.update(model, ctx, (opt) =>
    match (opt) {
      None    => Some(incr(Dict.empty(), ch))
      Some(d) => Some(incr(d, ch))
    })

// Slide the 2-char window left-to-right, recording every (bigram → next) pair.
fun trainLoop(
  model: Dict<String, Dict<String, Int>>,
  a:     String,
  b:     String,
  chars: List<String>
): Dict<String, Dict<String, Int>> =
  match (chars) {
    []     => model
    h :: t => trainLoop(observe(model, "${a}${b}", h), b, h, t)
  }

// Build the model from a string.
fun train(text: String): Dict<String, Dict<String, Int>> = {
  val chars = Lst.map(Str.toList(text), (c: Char) => Chr.charToString(c))
  match (chars) {
    [] => Dict.empty()
    h :: rest =>
      match (rest) {
        []       => Dict.empty()
        s :: more => trainLoop(Dict.empty(), h, s, more)
      }
  }
}

// ── Sampling ────────────────────────────────────────────────────────────────

// Sum all counts in a (String → Int) dict.
fun totalCounts(ks: List<String>, d: Dict<String, Int>, acc: Int): Int =
  match (ks) {
    [] => acc
    k :: rest => {
      val n = match (Dict.get(d, k)) {
        None    => 0
        Some(v) => v
      }
      totalCounts(rest, d, acc + n)
    }
  }

// Walk keys until the random `roll` falls inside the current entry's bucket.
fun pickChar(ks: List<String>, d: Dict<String, Int>, roll: Int): String =
  match (ks) {
    [] => " "
    k :: rest => {
      val n = match (Dict.get(d, k)) {
        None    => 0
        Some(v) => v
      }
      if (roll < n) k else pickChar(rest, d, roll - n)
    }
  }

// Sample one character from a learned (next-char → count) distribution.
fun sampleFrom(d: Dict<String, Int>): String = {
  val ks    = Dict.keys(d)
  val total = totalCounts(ks, d, 0)
  if (total == 0) " " else pickChar(ks, d, Rnd.random(total))
}

// Predict the next character for a 2-char context.
fun nextChar(model: Dict<String, Dict<String, Int>>, ctx: String): String =
  match (Dict.get(model, ctx)) {
    None    => " "           // unseen context — emit a space
    Some(d) => sampleFrom(d)
  }

// Generate `n` characters, keeping a sliding 2-char context window.
fun genLoop(
  model: Dict<String, Dict<String, Int>>,
  ctx:   String,
  n:     Int,
  acc:   String
): String =
  if (n <= 0) acc
  else {
    val ch     = nextChar(model, ctx)
    val newCtx = Str.right("${ctx}${ch}", 2)
    genLoop(model, newCtx, n - 1, "${acc}${ch}")
  }

fun generate(model: Dict<String, Dict<String, Int>>, seed: String, len: Int): String =
  genLoop(model, seed, len, seed)

// ── Statistics helpers ──────────────────────────────────────────────────────

// Accumulate character counts across a list of single-char strings.
fun countCharsLoop(chars: List<String>, d: Dict<String, Int>): Dict<String, Int> =
  match (chars) {
    []     => d
    h :: t => countCharsLoop(t, incr(d, h))
  }

fun countChars(text: String): Dict<String, Int> = {
  val chars = Lst.map(Str.toList(text), (c: Char) => Chr.charToString(c))
  countCharsLoop(chars, Dict.empty())
}

// Insertion sort, descending by count — for the frequency display.
fun insertByCount(
  p:  (String, Int),
  xs: List<(String, Int)>
): List<(String, Int)> =
  match (xs) {
    []     => [p]
    h :: t => if (p.1 >= h.1) p :: xs else h :: insertByCount(p, t)
  }

fun sortByCount(ps: List<(String, Int)>): List<(String, Int)> =
  Lst.foldl(ps, [], (acc: List<(String, Int)>, p: (String, Int)) => insertByCount(p, acc))

// Render a 28-column bar chart entry scaled to `maxCount`.
fun bar(n: Int, maxCount: Int): String = {
  val filled = n * 28 / maxCount
  "${Str.repeat(filled, "█")}${Str.repeat(28 - filled, "░")}"
}

// Print one frequency row.
fun printFreqRow(p: (String, Int), maxCount: Int): Unit = {
  val label = if (p.0 == " ") "' '" else " ${p.0} "
  println("   ${label}  ${bar(p.1, maxCount)}  ${p.1}")
}

fun printFreqs(rows: List<(String, Int)>, maxCount: Int): Unit =
  match (rows) {
    []     => ()
    h :: t => { printFreqRow(h, maxCount); printFreqs(t, maxCount) }
  }

// ── Main ────────────────────────────────────────────────────────────────────

fun main(): Unit = {
  println("╔══════════════════════════════════════════════════════╗")
  println("║   Markov Chain  —  character-level language model   ║")
  println("╚══════════════════════════════════════════════════════╝")
  println("")

  // ── Train ────────────────────────────────────────────────────────────
  println("── Training ─────────────────────────────────────────────")
  val model     = train(corpus)
  val corpusLen = Str.length(corpus)
  val ctxCount  = Dict.size(model)
  println("   Corpus length : ${corpusLen} characters")
  println("   Unique bigrams: ${ctxCount} contexts learned")
  println("")

  // ── Character frequency chart ─────────────────────────────────────────
  println("── Top-10 character frequency ────────────────────────────")
  val freqs    = countChars(corpus)
  val sorted   = sortByCount(Dict.toList(freqs))
  val top10    = Lst.take(sorted, 10)
  val maxCount = match (Lst.head(top10)) {
    None    => 1
    Some(p) => p.1
  }
  printFreqs(top10, maxCount)
  println("")

  // ── Generate samples ──────────────────────────────────────────────────
  println("── Generated text  (2-char seed → 76 sampled chars) ──────")
  val seeds = ["to", "th", "sl", "qu"]
  Lst.forEach(seeds, (seed: String) => {
    val text = generate(model, seed, 76)
    println("   [${seed}] ${text}")
  })
  println("")

  // ── How it works ──────────────────────────────────────────────────────
  println("── What this demonstrates ────────────────────────────────")
  println("   The model is just a lookup table:")
  println("     context → { next_char: count, ... }")
  println("   e.g.  \"th\" → { 'e':20, 'a':3, 'i':5, 'o':2 }")
  println("")
  println("   To generate, pick a random next char weighted by those")
  println("   counts, append it, then slide the window one step right.")
  println("")
  println("   A production LLM does the same thing — just scaled up:")
  println("     context  : 2 chars        →  128 000 tokens")
  println("     table    : count dict     →  billions of learned weights")
  println("     sampling : freq. counts   →  softmax( W · x + b )")
  println("     learning : counting       →  gradient descent")
  println("")
}

main()
