// Runtime behavioral tests for await semantics.
// Compile-time rejection tests (await in non-async contexts) live in
// tests/conformance/typecheck/invalid/.

import { Suite, group, eq, isTrue } from "kestrel:dev/test"

// --- Helpers ---

async fun asyncAdd(a: Int, b: Int): Task<Int> = a + b

async fun asyncMul(a: Int, b: Int): Task<Int> = a * b

// Async helper that itself uses await
async fun asyncAddTen(x: Int): Task<Int> = await asyncAdd(x, 10)

// Chained: awaits two tasks and combines
async fun asyncSumPair(a: Int, b: Int): Task<Int> = {
  val x = await asyncAdd(a, 1);
  val y = await asyncAdd(b, 2);
  x + y
}

// Exception in async context
export exception AsyncTestError

async fun asyncFail(msg: String): Task<Int> = throw AsyncTestError

// Try/catch over an awaited failing task
async fun asyncCatch(): Task<Int> =
  try { await asyncFail("boom") }
  catch { AsyncTestError => -1 }

export async fun run(s: Suite): Task<Unit> = {
  val addResult        = await asyncAdd(5, 3)
  val mulResult        = await asyncMul(4, 6)
  val helperResult     = await asyncAddTen(10)
  val chainResult      = await asyncSumPair(5, 7)
  val caughtResult     = await asyncCatch()

  group(s, "await behavior validation", (sg: Suite) => {
    group(sg, "basic await results", (s1: Suite) => {
      eq(s1, "asyncAdd 5+3", addResult, 8);
      eq(s1, "asyncMul 4*6", mulResult, 24)
    });

    group(sg, "async helper using await", (s2: Suite) => {
      eq(s2, "asyncAddTen(10)", helperResult, 20)
    });

    group(sg, "chained await in async body", (s3: Suite) => {
      eq(s3, "asyncSumPair(5,7) = (5+1)+(7+2)", chainResult, 15)
    });

    group(sg, "try/catch over awaited failing task", (s4: Suite) => {
      eq(s4, "caught async exception returns -1", caughtResult, -1)
    });
  });
  ()
}
