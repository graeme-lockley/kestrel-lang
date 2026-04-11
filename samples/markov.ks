#!/usr/bin/env kestrel

// samples/markov.ks — character-level trigram language model
//
// Demonstrates the statistical core shared by all language models:
//   1. Slide a 3-character context window across training text and count
//      how often each character follows each triple.
//   2. To generate new text, repeatedly sample the next character
//      weighted by those counts, then slide the window one step right.
//
// This is exactly what a large language model does, scaled up:
//   context  :  3 chars            →  128 000 tokens
//   table    :  trigram count dict →  weight matrices (billions of params)
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
// Mixed corpus: Shakespeare, Poe, Melville, and a small technical passage.
// This gives the generator more varied transitions, punctuation, and rhythm.
// Even with only a 3-char context, the model starts to blend voices in a way
// that feels much more alive than training on one excerpt alone.

val corpus =
  Str.join("", [
    "to be or not to be that is the question whether tis nobler in the mind to suffer the slings and arrows of outrageous fortune or to take arms against a sea of troubles and by opposing end them to die to sleep no more and by a sleep to say we end the heartache and the thousand natural shocks that flesh is heir to tis a consummation devoutly to be wished to die to sleep to sleep perchance to dream ay there is the rub ",
    "once upon a midnight dreary while i pondered weak and weary over many a quaint and curious volume of forgotten lore while i nodded nearly napping suddenly there came a tapping as of some one gently rapping rapping at my chamber door only this and nothing more ",
    "call me ishmael some years ago never mind how long precisely having little or no money in my purse and nothing particular to interest me on shore i thought i would sail about a little and see the watery part of the world it is a way i have of driving off the spleen and regulating the circulation ",
    "the machine learns by observing sequences counting patterns and compressing surprise a prompt becomes context context becomes prediction and prediction becomes the next token tiny models count characters larger models shape probability across vast spaces of text both are trying to continue what comes next ",
    "in the workshop the lamp burned low the rain struck the window and the page filled slowly with symbols hypotheses and fragments of speech every sentence left a trail every trail suggested another turn and the system kept asking what kind of thing usually follows this one ",
    "deep in the archive old words met new ones fragments of theatre collided with sea journals and laboratory notes the result was not wisdom exactly but it had motion texture and a strange synthetic memory of storms candles engines and dreams "
  ])

// ── Training ────────────────────────────────────────────────────────────────

// Increment the count for key `ch` in a (String → Int) count dict.
fun incr(d: Dict<String, Int>, ch: String): Dict<String, Int> = {
  val cur = match (Dict.get(d, ch)) {
    None    => 0
    Some(c) => c
  }
  Dict.insert(d, ch, cur + 1)
}

// Record that the 3-char context `ctx` was followed by character `ch`.
fun observe(
  model: Dict<String, Dict<String, Int>>,
  ctx:   String,
  ch:    String
): Dict<String, Dict<String, Int>> = {
  val inner = match (Dict.get(model, ctx)) {
    None    => Dict.empty()
    Some(dd) => dd
  }
  Dict.insert(model, ctx, incr(inner, ch))
}

// Slide the 3-char window left-to-right, recording every (trigram → next) pair.
fun trainLoop(
  model: Dict<String, Dict<String, Int>>,
  a:     String,
  b:     String,
  c:     String,
  chars: List<String>
): Dict<String, Dict<String, Int>> =
  match (chars) {
    []     => model
    h :: t => trainLoop(observe(model, "${a}${b}${c}", h), b, c, h, t)
  }

// Build the model from a string.
fun train(text: String): Dict<String, Dict<String, Int>> = {
  val chars = Lst.map(Str.toList(text), (c: Char) => Chr.charToString(c))
  match (chars) {
    [] => Dict.empty()
    h :: rest =>
      match (rest) {
        [] => Dict.empty()
        s :: more =>
          match (more) {
            [] => Dict.empty()
            t :: tail => trainLoop(Dict.empty(), h, s, t, tail)
          }
      }
  }
}

// ── Sampling ────────────────────────────────────────────────────────────────

// Sum all counts in a (String → Int) dict.
fun totalCounts(ks: List<String>, d: Dict<String, Int>, acc: Int): Int =
  match (ks) {
    [] => acc
    k :: rest => {
      val cnt = match (Dict.get(d, k)) {
        None    => 0
        Some(c) => c
      }
      totalCounts(rest, d, acc + cnt)
    }
  }

// Walk keys until the random `roll` falls inside the current entry's bucket.
fun pickChar(ks: List<String>, d: Dict<String, Int>, roll: Int): String =
  match (ks) {
    [] => " "
    k :: rest => {
      val cnt = match (Dict.get(d, k)) {
        None    => 0
        Some(c) => c
      }
      if (roll < cnt) k else pickChar(rest, d, roll - cnt)
    }
  }

// Sample one character from a learned (next-char → count) distribution.
fun sampleFrom(d: Dict<String, Int>): String = {
  val ks    = Dict.keys(d)
  val total = totalCounts(ks, d, 0)
  if (total == 0) " " else pickChar(ks, d, Rnd.random(total))
}

// Predict the next character for a 3-char context.
fun nextChar(model: Dict<String, Dict<String, Int>>, ctx: String): String =
  match (Dict.get(model, ctx)) {
    None    => " "           // unseen context — emit a space
    Some(d) => sampleFrom(d)
  }

// Generate `n` characters, keeping a sliding 3-char context window.
fun genLoop(
  model: Dict<String, Dict<String, Int>>,
  ctx:   String,
  n:     Int,
  acc:   String
): String =
  if (n <= 0) acc
  else {
    val ch     = nextChar(model, ctx)
    val newCtx = Str.right("${ctx}${ch}", 3)
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
  val filled  = n * 28 / maxCount
  val full    = Str.repeat(filled, "█")
  val empty   = Str.repeat(28 - filled, "░")
  "${full}${empty}"
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
  println("   Unique trigrams: ${ctxCount} contexts learned")
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
  println("── Generated text  (3-char seed → 76 sampled chars) ──────")
  val seeds = ["the", "sle", "onc", "mac"]
  Lst.forEach(seeds, (seed: String) => {
    val text = generate(model, seed, 76)
    println("   [${seed}] ${text}")
  })
  println("")

  // ── How it works ──────────────────────────────────────────────────────
  println("── What this demonstrates ────────────────────────────────")
  println("   The model is just a lookup table:")
  println("     context → { next_char: count, ... }")
  println("   e.g.  \"the\" → { ' ':15, 'r':6, 'y':3, 'n':2 }")
  println("")
  println("   To generate, pick a random next char weighted by those")
  println("   counts, append it, then slide the window one step right.")
  println("")
  println("   A production LLM does the same thing — just scaled up:")
  println("     context  : 3 chars        →  128 000 tokens")
  println("     table    : count dict     →  billions of learned weights")
  println("     sampling : freq. counts   →  softmax( W · x + b )")
  println("     learning : counting       →  gradient descent")
  println("")
}

main()
