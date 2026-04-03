import { Suite, group, eq, isTrue, isFalse } from "kestrel:test"

export async fun run(s: Suite): Task<Unit> =
  group(s, "comparison", (s1: Suite) => {
    group(s1, "equality (==) and inequality (!=) — ints", (sg: Suite) => {
      isTrue(sg, "5 == 5", 5 == 5)
      isFalse(sg, "5 == 3 is false", 5 == 3)
      isTrue(sg, "0 == 0", 0 == 0)
      isTrue(sg, "5 != 3", 5 != 3)
      isFalse(sg, "5 != 5 is false", 5 != 5)
      isTrue(sg, "!= negates == (int)", (7 == 7) != (7 != 7))
    })

    group(s1, "bools", (sg: Suite) => {
      isTrue(sg, "True == True", True == True)
      isTrue(sg, "False == False", False == False)
      isTrue(sg, "True != False", True != False)
      isFalse(sg, "True == False is false", True == False)
      isTrue(sg, "!= negates == (bool)", (True == True) != (True != True))
    })

    group(s1, "floats", (sg: Suite) => {
      isTrue(sg, "1.5 == 1.5", 1.5 == 1.5)
      isFalse(sg, "1.5 == 2.5 is false", 1.5 == 2.5)
      isTrue(sg, "1.5 != 2.5", 1.5 != 2.5)
      isFalse(sg, "1.5 != 1.5 is false", 1.5 != 1.5)
      isTrue(sg, "!= negates == (float)", (0.0 == 0.0) != (0.0 != 0.0))
    })

    group(s1, "strings (value equality)", (sg: Suite) => {
      isTrue(sg, "same literal", "hello" == "hello")
      isFalse(sg, "different text", "a" == "b")
      isTrue(sg, "!= opposite", "x" != "y")
      isTrue(sg, "empty == empty", "" == "")
      isTrue(sg, "unicode same", "\u{00E9}" == "\u{00E9}")
      isTrue(sg, "!= negates == (string)", ("hi" == "hi") != ("hi" != "hi"))
    })

    group(s1, "unit", (sg: Suite) => {
      isTrue(sg, "() == ()", () == ())
      isFalse(sg, "() != () is false", () != ())
    })

    group(s1, "char (Unicode scalar)", (sg: Suite) => {
      isTrue(sg, "same literal", 'a' == 'a')
      isFalse(sg, "different literal", 'a' == 'b')
      isTrue(sg, "!= ", 'x' != 'y')
      isTrue(sg, "emoji equal", '\u{1F600}' == '\u{1F600}')
      isTrue(sg, "order a < b", 'a' < 'b')
      isFalse(sg, "order b < a is false", 'b' < 'a')
      isTrue(sg, "<= equal", 'z' <= 'z')
      isTrue(sg, "> ", 'z' > 'a')
      isTrue(sg, ">= equal", 'm' >= 'm')
    })

    group(s1, "lists (structural)", (sg: Suite) => {
      isTrue(sg, "nil == nil", [] == [])
      isTrue(sg, "same elements", [1, 2, 3] == [1, 2, 3])
      isFalse(sg, "different last", [1, 2] == [1, 3])
      isTrue(sg, "nested", [[1], [2]] == [[1], [2]])
      isTrue(sg, "!= empty vs cons", [] != [1])
      isTrue(sg, "!= negates == (list)", ([1] == [1]) != ([1] != [1]))
    })

    group(s1, "tuples (structural, record-backed)", (sg: Suite) => {
      isTrue(sg, "(1,2) == (1,2)", (1, 2) == (1, 2))
      isTrue(sg, "(1,2) != (1,3)", (1, 2) != (1, 3))
      isTrue(sg, "!= negates == (tuple)", ((0, 0) == (0, 0)) != ((0, 0) != (0, 0)))
    })

    group(s1, "records (structural)", (sg: Suite) => {
      val r1 = { x = 1, y = 2 }
      val r2 = { x = 1, y = 2 }
      val r3 = { x = 1, y = 3 }
      isTrue(sg, "same fields", r1 == r2)
      isFalse(sg, "different field", r1 == r3)
      isTrue(sg, "!=", r1 != r3)
      isTrue(sg, "!= negates == (record)", (r1 == r2) != (r1 != r2))
    })

    group(s1, "Option", (sg: Suite) => {
      isTrue(sg, "None == None", None == None)
      isTrue(sg, "Some same payload", Some(5) == Some(5))
      isFalse(sg, "Some different", Some(1) == Some(2))
      isFalse(sg, "Some vs None", Some(1) == None)
      isTrue(sg, "!= Some vs None", Some(1) != None)
      isTrue(sg, "!= negates == (Option)", (None == None) != (None != None))
    })

    group(s1, "Result", (sg: Suite) => {
      isTrue(sg, "Ok == Ok", Ok(3) == Ok(3))
      isTrue(sg, "Ok != Ok different", Ok(1) != Ok(2))
      isTrue(sg, "Err == Err", Err(0) == Err(0))
      isFalse(sg, "Ok vs Err", Ok(1) == Err(1))
      isTrue(sg, "!= Ok vs Err", Ok(1) != Err(1))
      isTrue(sg, "!= negates == (Result)", (Ok(0) == Ok(0)) != (Ok(0) != Ok(0)))
    })

    group(s1, "less than", (sg: Suite) => {
      isTrue(sg, "3 < 5", 3 < 5)
      isFalse(sg, "5 < 3 is false", 5 < 3)
      isTrue(sg, "-1 < 0", -1 < 0)
    })

    group(s1, "greater than", (sg: Suite) => {
      isTrue(sg, "7 > 4", 7 > 4)
      isFalse(sg, "4 > 7 is false", 4 > 7)
    })

    group(s1, "less or equal", (sg: Suite) => {
      isTrue(sg, "3 <= 3", 3 <= 3)
      isTrue(sg, "3 <= 5", 3 <= 5)
      isFalse(sg, "4 <= 3 is false", 4 <= 3)
    })

    group(s1, "greater or equal", (sg: Suite) => {
      isTrue(sg, "5 >= 5", 5 >= 5)
      isTrue(sg, "7 >= 4", 7 >= 4)
      isFalse(sg, "4 >= 5 is false", 4 >= 5)
    })
  })
