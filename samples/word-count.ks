// Word frequency counter — Dict, higher-order list functions, and the |> pipe.
//
// Tokenises a text into lowercase alphabetic words, counts frequencies with
// a Dict, then prints the top-15 words sorted by count descending.
import * as Dct from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Chr from "kestrel:data/char"

// ── helpers ──────────────────────────────────────────────────────────────
// Strip non-alpha characters from a word after lowercasing.
fun clean(w: String): String =
  Str.filterChars(w, (c) => Chr.isAlpha(c))

// Increment the count for word w in the frequency dict.
fun tally(freq: Dict<String, Int>, w: String): Dict<String, Int> = {
  val word = clean(w)
  if (Str.isEmpty(word))
    freq
  else
    match (Dct.get(freq, word)) {
      None =>
        Dct.insert(freq, word, 1),
      Some(n) =>
        Dct.insert(freq, word, n + 1)
    }
}

// Insertion sort on (word, count) pairs, descending by count.
fun insertDesc(pair: String * Int, xs: List<String * Int>): List<String * Int> =
  match (xs) {
    [] =>
      [pair],
    h :: t =>
      if (pair.1 >= h.1) pair :: h :: t else h :: insertDesc(pair, t)
  }

fun sortDesc(xs: List<String * Int>): List<String * Int> =
  match (xs) {
    [] =>
      [],
    h :: t =>
      insertDesc(h, sortDesc(t))
  }

// ── text ─────────────────────────────────────────────────────────────────
// Opening of the Gettysburg Address (public domain).
val text = Str.concat(["Four score and seven years ago our fathers brought forth on this continent a new nation conceived in liberty ",
    "and dedicated to the proposition that all men are created equal. Now we are engaged in a great civil war ",
    "testing whether that nation or any nation so conceived and so dedicated can long endure. We are met on a ",
    "great battle-field of that war. We have come to dedicate a portion of that field as a final resting place ",
    "for those who here gave their lives that that nation might live. It is altogether fitting and proper that ",
    "we should do this. But in a larger sense we can not dedicate we can not consecrate we can not hallow this ",
    "ground. The brave men living and dead who struggled here have consecrated it far above our poor power to ",
    "add or detract. The world will little note nor long remember what we say here but it can never forget what ",
    "they did here. It is for us the living rather to be dedicated here to the unfinished work which they who ",
    "fought here have thus far so nobly advanced."])

// ── display ──────────────────────────────────────────────────────────────
fun printRow(pair: String * Int): Unit =
  println("  ${Str.padRight(18, " ", pair.0)} ${pair.1}")

println("Word               Count")

println("─────────────────────────")

text
  |> Str.toLower
  |> Str.words
  |> Lst.foldl(Dct.empty(), tally)
  |> Dct.toList
  |> sortDesc
  |> Lst.take(15)
  |> Lst.forEach(printRow)
