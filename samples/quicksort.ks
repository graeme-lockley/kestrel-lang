#!/usr/bin/env kestrel

// Quicksort — the classic divide-and-conquer sort made elegant
// with pattern matching on list structure.
//
// Each call partitions the tail around the head (pivot), recursively
// sorts each half, then concatenates.  No indices, no swaps, no mutation.
//
// Generates 30 random integers in [0, 100] to sort.
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as RInt from "kestrel:data/int"

fun qsort(xs: List<Int>): List<Int> =
  match (xs) {
    [] =>
      [],
    h :: t =>
      [...qsort(Lst.filter(t, (x) => x <= h)), h, ...qsort(Lst.filter(t, (x) => x > h))]
  }

val input = Lst.generate(30, (_) => RInt.randomRange(0, 100))

val sorted = qsort(input)

println("Input:  ${Str.join(", ", Lst.map(input, Str.fromInt))}")

println("Sorted: ${Str.join(", ", Lst.map(sorted, Str.fromInt))}")
