#!/usr/bin/env kestrel

// Expression tree — algebraic data types, pattern matching, and recursive evaluation.
//
// An Expr is either a literal integer or a composite operation.
// eval reduces any expression to its Int value; pretty prints it
// in fully-parenthesised infix notation so the structure is unambiguous.
import * as Str from "kestrel:data/string"

type Expr =
    Lit(Int)
  | Add(Expr, Expr)
  | Sub(Expr, Expr)
  | Mul(Expr, Expr)
  | Neg(Expr)

fun eval(e: Expr): Int =
  match (e) {
    Lit(n) =>
      n,
    Add(l, r) =>
      eval(l) + eval(r),
    Sub(l, r) =>
      eval(l) - eval(r),
    Mul(l, r) =>
      eval(l) * eval(r),
    Neg(e) =>
      0 - eval(e)
  }

fun pretty(e: Expr): String =
  match (e) {
    Lit(n) =>
      Str.fromInt(n),
    Add(l, r) =>
      "(${pretty(l)} + ${pretty(r)})",
    Sub(l, r) =>
      "(${pretty(l)} - ${pretty(r)})",
    Mul(l, r) =>
      "(${pretty(l)} * ${pretty(r)})",
    Neg(e) =>
      "(-${pretty(e)})"
  }

fun show(label: String, e: Expr): Unit =
  println("${label}:  ${pretty(e)}  =  ${Str.fromInt(eval(e))}")

// ── examples ───────────────────────────────────────────────────────────────
// (2 + 3) * 4  =  20
show("multiply sum", Mul(Add(Lit(2), Lit(3)), Lit(4)))

// (10 - 3) * (4 + 1)  =  35
show("product of diffs", Mul(Sub(Lit(10), Lit(3)), Add(Lit(4), Lit(1))))

// -(8 + (4 * 3))  =  -20
show("negated sum", Neg(Add(Lit(8), Mul(Lit(4), Lit(3)))))

// (3 * (3 * 3)) - (-(10 + 7))  =  27 + 17  =  44
show("deep nest", Sub(Mul(Lit(3), Mul(Lit(3), Lit(3))), Neg(Add(Lit(10), Lit(7)))))

// Towers of arithmetic: ((((2+3)*4) - (6*2)) * ((7-1) + (2*2)))  =  (20-12) * (6+4)  =  80
show("towers",
  Mul(Sub(Mul(Add(Lit(2), Lit(3)), Lit(4)), Mul(Lit(6), Lit(2))), Add(Sub(Lit(7), Lit(1)), Mul(Lit(2), Lit(2)))))
