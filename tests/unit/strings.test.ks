import { Suite, group, eq } from "kestrel:dev/test"

fun add(a: Int, b: Int): Int = a + b

export async fun run(s: Suite): Task<Unit> =
  group(s, "strings", (s1: Suite) => {
    eq(s1, "greeting", "Hello, World!", "Hello, World!")
    eq(s1, "message", "Kestrel strings work!", "Kestrel strings work!")
    eq(s1, "empty string", "", "")
    eq(s1, "with spaces", "  spaces  ", "  spaces  ")
    eq(s1, "newline", "Line1\nLine2", "Line1\nLine2")
    eq(s1, "tab", "Tab\there", "Tab\there")
    eq(s1, "quote", "She said \"hello\"", "She said \"hello\"")

    group(s1, "template interpolation", (sg: Suite) => {
      eq(sg, "${42}", "${42}", "42")
      val name = "Kestrel"
      eq(sg, "hello ${name}", "hello ${name}", "hello Kestrel")
      eq(sg, "${1+1}", "${1 + 1}", "2")
      eq(sg, "${add(1,2)}", "${add(1, 2)}", "3")
      val ch = 'A'
      eq(sg, "char in template", "${ch}", "A")
      // Braced `\u{...}` inside `${...}` cannot be parsed (inner `}` closes the template hole).
      val grin = '\u{1F600}'
      eq(sg, "char emoji", "${grin}", "\u{1F600}")
    })

    group(s1, "unicode literals", (sg: Suite) => {
      eq(sg, "emoji", "\u{1F600}", "\u{1F600}")
      eq(sg, "e-acute", "\u{00E9}", "\u{00E9}")
      eq(sg, "CJK", "\u{4E2D}\u{6587}", "\u{4E2D}\u{6587}")
      eq(sg, "accented word", "caf\u{00E9}", "caf\u{00E9}")
    })
  })
