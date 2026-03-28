import { Suite, group, eq } from "kestrel:test"

export fun run(s: Suite): Unit =
  group(s, "comparison", (s1: Suite) => {
    group(s1, "equality (==) and inequality (!=) — ints", (sg: Suite) => {
      eq(sg, "5 == 5", 5 == 5, True)
      eq(sg, "5 == 3 is false", 5 == 3, False)
      eq(sg, "0 == 0", 0 == 0, True)
      eq(sg, "5 != 3", 5 != 3, True)
      eq(sg, "5 != 5 is false", 5 != 5, False)
      eq(sg, "!= negates == (int)", (7 == 7) != (7 != 7), True)
    })

    group(s1, "bools", (sg: Suite) => {
      eq(sg, "True == True", True == True, True)
      eq(sg, "False == False", False == False, True)
      eq(sg, "True != False", True != False, True)
      eq(sg, "True == False is false", True == False, False)
      eq(sg, "!= negates == (bool)", (True == True) != (True != True), True)
    })

    group(s1, "floats", (sg: Suite) => {
      eq(sg, "1.5 == 1.5", 1.5 == 1.5, True)
      eq(sg, "1.5 == 2.5 is false", 1.5 == 2.5, False)
      eq(sg, "1.5 != 2.5", 1.5 != 2.5, True)
      eq(sg, "1.5 != 1.5 is false", 1.5 != 1.5, False)
      eq(sg, "!= negates == (float)", (0.0 == 0.0) != (0.0 != 0.0), True)
    })

    group(s1, "strings (value equality)", (sg: Suite) => {
      eq(sg, "same literal", "hello" == "hello", True)
      eq(sg, "different text", "a" == "b", False)
      eq(sg, "!= opposite", "x" != "y", True)
      eq(sg, "empty == empty", "" == "", True)
      eq(sg, "unicode same", "\u{00E9}" == "\u{00E9}", True)
      eq(sg, "!= negates == (string)", ("hi" == "hi") != ("hi" != "hi"), True)
    })

    group(s1, "unit", (sg: Suite) => {
      eq(sg, "() == ()", () == (), True)
      eq(sg, "() != () is false", () != (), False)
    })

    group(s1, "char (Unicode scalar)", (sg: Suite) => {
      eq(sg, "same literal", 'a' == 'a', True)
      eq(sg, "different literal", 'a' == 'b', False)
      eq(sg, "!= ", 'x' != 'y', True)
      eq(sg, "emoji equal", '\u{1F600}' == '\u{1F600}', True)
      eq(sg, "order a < b", 'a' < 'b', True)
      eq(sg, "order b < a is false", 'b' < 'a', False)
      eq(sg, "<= equal", 'z' <= 'z', True)
      eq(sg, "> ", 'z' > 'a', True)
      eq(sg, ">= equal", 'm' >= 'm', True)
    })

    group(s1, "lists (structural)", (sg: Suite) => {
      eq(sg, "nil == nil", [] == [], True)
      eq(sg, "same elements", [1, 2, 3] == [1, 2, 3], True)
      eq(sg, "different last", [1, 2] == [1, 3], False)
      eq(sg, "nested", [[1], [2]] == [[1], [2]], True)
      eq(sg, "!= empty vs cons", [] != [1], True)
      eq(sg, "!= negates == (list)", ([1] == [1]) != ([1] != [1]), True)
    })

    group(s1, "tuples (structural, record-backed)", (sg: Suite) => {
      eq(sg, "(1,2) == (1,2)", (1, 2) == (1, 2), True)
      eq(sg, "(1,2) != (1,3)", (1, 2) != (1, 3), True)
      eq(sg, "!= negates == (tuple)", ((0, 0) == (0, 0)) != ((0, 0) != (0, 0)), True)
    })

    group(s1, "records (structural)", (sg: Suite) => {
      val r1 = { x = 1, y = 2 }
      val r2 = { x = 1, y = 2 }
      val r3 = { x = 1, y = 3 }
      eq(sg, "same fields", r1 == r2, True)
      eq(sg, "different field", r1 == r3, False)
      eq(sg, "!=", r1 != r3, True)
      eq(sg, "!= negates == (record)", (r1 == r2) != (r1 != r2), True)
    })

    group(s1, "Option", (sg: Suite) => {
      eq(sg, "None == None", None == None, True)
      eq(sg, "Some same payload", Some(5) == Some(5), True)
      eq(sg, "Some different", Some(1) == Some(2), False)
      eq(sg, "Some vs None", Some(1) == None, False)
      eq(sg, "!= Some vs None", Some(1) != None, True)
      eq(sg, "!= negates == (Option)", (None == None) != (None != None), True)
    })

    group(s1, "Result", (sg: Suite) => {
      eq(sg, "Ok == Ok", Ok(3) == Ok(3), True)
      eq(sg, "Ok != Ok different", Ok(1) != Ok(2), True)
      eq(sg, "Err == Err", Err(0) == Err(0), True)
      eq(sg, "Ok vs Err", Ok(1) == Err(1), False)
      eq(sg, "!= Ok vs Err", Ok(1) != Err(1), True)
      eq(sg, "!= negates == (Result)", (Ok(0) == Ok(0)) != (Ok(0) != Ok(0)), True)
    })

    group(s1, "less than", (sg: Suite) => {
      eq(sg, "3 < 5", 3 < 5, True)
      eq(sg, "5 < 3 is false", 5 < 3, False)
      eq(sg, "-1 < 0", 0 - 1 < 0, True)
    })

    group(s1, "greater than", (sg: Suite) => {
      eq(sg, "7 > 4", 7 > 4, True)
      eq(sg, "4 > 7 is false", 4 > 7, False)
    })

    group(s1, "less or equal", (sg: Suite) => {
      eq(sg, "3 <= 3", 3 <= 3, True)
      eq(sg, "3 <= 5", 3 <= 5, True)
      eq(sg, "4 <= 3 is false", 4 <= 3, False)
    })

    group(s1, "greater or equal", (sg: Suite) => {
      eq(sg, "5 >= 5", 5 >= 5, True)
      eq(sg, "7 >= 4", 7 >= 4, True)
      eq(sg, "4 >= 5 is false", 4 >= 5, False)
    })
  })
