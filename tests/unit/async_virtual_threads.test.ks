import { Suite, group, eq } from "kestrel:test"
import * as Fs from "kestrel:fs"
import * as Process from "kestrel:process"

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

    group(s1, "await fs/process result", (sg: Suite) => {
      val fileOk =
        match (await Fs.readText("tests/fixtures/fs/read_fixture.txt")) {
          Ok(_) => 1,
          Err(_) => 0
        };
      val processOk =
        match (await Process.runProcess("sh", ["-c", "exit 0"])) {
          Ok(0) => 1,
          _ => 0
        };
      eq(sg, "fs ok", fileOk, 1);
      eq(sg, "process ok", processOk, 1)
    });
  });
  ()
}