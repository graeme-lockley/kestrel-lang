import { Suite, group, eq } from "kestrel:test"

export exception AsyncBoom

async fun plusOne(n: Int): Task<Int> = n + 1
async fun fail(): Task<Int> = throw AsyncBoom

export async fun run(s: Suite): Task<Unit> = {
  group(s, "async virtual threads", (s1: Suite) => {
    group(s1, "await success", (sg: Suite) => {
      val value = await plusOne(41);
      eq(sg, "await plusOne", value, 42)
    });

    group(s1, "await try catch", (sg: Suite) => {
      val caught = try { await fail() } catch { AsyncBoom => 7 };
      eq(sg, "catch async exception", caught, 7)
    });
  });
  ()
}