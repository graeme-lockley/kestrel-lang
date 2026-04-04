// Tests for Kestrel's Java interop features:
//   - extern fun: binding to a JVM static or instance method
//   - extern type: naming a JVM class
//   - extern import: auto-generating bindings from JVM class metadata

import { Suite, group, eq } from "kestrel:test"

// ---------------------------------------------------------------------------
// extern fun — static method: String.valueOf(Object)
// ---------------------------------------------------------------------------

extern fun intToString(n: Int): String = jvm("java.lang.String#valueOf(java.lang.Object)")

// ---------------------------------------------------------------------------
// extern fun — instance methods on String
// ---------------------------------------------------------------------------

// concat is an instance method; the first param is the receiver, the second is the arg
extern fun concatStrings(a: String, b: String): String = 
  jvm("java.lang.String#concat(java.lang.String)")

// toUpperCase: instance method with no extra args; single param is the String receiver
extern fun strToUpper(s: String): String =
  jvm("java.lang.String#toUpperCase()")

// ---------------------------------------------------------------------------
// extern type — bind a JVM class as a Kestrel type
// ---------------------------------------------------------------------------

extern type StringBuilder = jvm("java.lang.StringBuilder")

extern fun newStringBuilder(): StringBuilder =
  jvm("java.lang.StringBuilder#<init>()")

// append returns StringBuilder so the codegen can emit the correct JVM descriptor
extern fun sbAppend(sb: StringBuilder, s: String): StringBuilder =
  jvm("java.lang.StringBuilder#append(java.lang.String)")

extern fun sbToString(sb: StringBuilder): String =
  jvm("java.lang.StringBuilder#toString()")

// ---------------------------------------------------------------------------
// extern import — auto-bind java.lang.StringBuilder (with a fresh alias to
// keep names distinct from the manual bindings above).  The override block
// supplies the correct Kestrel return type for append so the JVM descriptor
// matches the real method signature.
// ---------------------------------------------------------------------------

extern import "java:java.lang.StringBuilder" as SB {
  fun append(instance: SB, p0: String): SB
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

export async fun run(s: Suite): Task<Unit> =
  group(s, "java interop", (s1: Suite) => {
    group(s1, "extern fun: static method", (sg: Suite) => {
      eq(sg, "intToString(42)", intToString(42), "42")
      eq(sg, "intToString(0)", intToString(0), "0")
    })

    group(s1, "extern fun: instance method", (sg: Suite) => {
      eq(sg, "concat", concatStrings("Hello", " World"), "Hello World")
      eq(sg, "toUpperCase", strToUpper("kestrel"), "KESTREL")
    })

    group(s1, "extern type: StringBuilder (manual binding)", (sg: Suite) => {
      val sb = newStringBuilder()
        |> sbAppend("Hello")
        |> sbAppend(", World")

      eq(sg, "build string", sbToString(sb), "Hello, World")
    })

    group(s1, "extern import: StringBuilder auto-binding", (sg: Suite) => {
      val sb = newSB()
        |> append("Kestrel")
        |> append(" interop")

      eq(sg, "auto-generated bindings", toString(sb), "Kestrel interop")
    })
  })
