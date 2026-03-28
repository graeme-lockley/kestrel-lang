// Contract tests for kestrel:test. Subprocess fixture: tests/fixtures/kestrel_test_printsummary_exit1.ks
import { Suite, group, eq, neq, isTrue, isFalse, gt, lt, gte, lte, throws } from "kestrel:test"
import { runProcess } from "kestrel:process"

export fun run(s: Suite): Unit = {
  group(s, "kestrel:test", (s1: Suite) => {
    group(s1, "eq and neq", (sg: Suite) => {
      eq(sg, "eq same int", 7, 7)
      neq(sg, "neq ints", 0, 1)
      neq(sg, "neq bool vs bool", True, False)
      eq(sg, "bool distinct from int in print", True, True)
      neq(sg, "string neq", "a", "b")
    })

    group(s1, "neq failure updates counts (summaryOnly, no extra noise)", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val sx = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      neq(sx, "forced fail both unit", (), ());
      eq(sg, "failed count after neq fail", c.failed, 1);
      eq(sg, "passed count after neq fail", c.passed, 0)
    })

    group(s1, "eq failure updates counts", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val sx = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      eq(sx, "forced fail", 1, 2);
      eq(sg, "failed count", c.failed, 1);
      eq(sg, "passed after fail line", c.passed, 0)
    })

    group(s1, "isTrue / isFalse", (sg: Suite) => {
      isTrue(sg, "true", True)
      isFalse(sg, "false", False)
    })

    group(s1, "isTrue failure counts", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val sx = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      isTrue(sx, "expect true got false", False);
      eq(sg, "one failure", c.failed, 1)
    })

    group(s1, "Int ordering", (sg: Suite) => {
      gt(sg, "strict above", 2, 1)
      lt(sg, "strict below", 1, 2)
      gte(sg, "equal gte", 3, 3)
      lte(sg, "equal lte", -1, -1)
      gte(sg, "greater gte", 5, 4)
      lte(sg, "lesser lte", 4, 9)
      gt(sg, "negative order", -1, -2)
      lt(sg, "negative order 2", -2, -1)
    })

    group(s1, "ordering failure counts", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val sx = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      gt(sx, "fail gt", 1, 2);
      eq(sg, "gt fail recorded", c.failed, 1)
    })

    group(s1, "throws", (sg: Suite) => {
      throws(sg, "divide by zero throws", (_: Unit) => {
        val x = 1 / 0;
        ()
      })
    })

    group(s1, "throws when no throw", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val sx = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      throws(sx, "should have thrown", (_: Unit) => ());
      eq(sg, "throws miss counts as fail", c.failed, 1)
    })

    group(s1, "nested groups aggregate counts", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val root = { depth = sg.depth + 1, summaryOnly = True, counts = c };
      group(root, "outer", (s2: Suite) => {
        eq(s2, "pass a", 0, 0);
        group(s2, "inner", (s3: Suite) => {
          eq(s3, "pass b", 1, 1);
          eq(s3, "fail c", 1, 2)
        })
      });
      eq(sg, "two passes one fail", c.passed, 2);
      eq(sg, "one failed assertion", c.failed, 1)
    })

    group(s1, "summaryOnly nested: manual quiet suite shares counts", (sg: Suite) => {
      val c = { mut passed = 0, mut failed = 0, mut startTime = 0 };
      val loud = { depth = sg.depth + 1, summaryOnly = False, counts = c };
      group(loud, "verbose outer", (s2: Suite) => {
        val quiet = { depth = s2.depth, summaryOnly = True, counts = c };
        eq(quiet, "only counts", 1, 1)
      });
      eq(sg, "assertion counted despite summaryOnly", c.passed, 1)
    })

    group(s1, "printSummary exits 1 (subprocess fixture)", (sg: Suite) => {
      val code = runProcess("./scripts/kestrel", ["run", "tests/fixtures/kestrel_test_printsummary_exit1.ks"]);
      eq(sg, "fixture exit code", code, 1)
    })
  })
}
