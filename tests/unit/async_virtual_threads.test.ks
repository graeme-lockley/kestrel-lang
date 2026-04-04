import { Suite, group, eq } from "kestrel:test"
import * as Fs from "kestrel:fs"
import * as Process from "kestrel:process"

export exception AsyncBoom

async fun plusOne(n: Int): Task<Int> = n + 1
async fun fail(): Task<Int> = throw AsyncBoom
async fun delayedValue(): Task<Int> = {
  val _ = await Process.runProcess("sh", ["-c", "sleep 0.05"]);
  99
}

export async fun run(s: Suite): Task<Unit> = {
  val plusOneValue = await plusOne(41)
  val caughtValue = try { await fail() } catch { AsyncBoom => 7 }
  val fileOk =
    match (await Fs.readText("tests/fixtures/fs/read_fixture.txt")) {
      Ok(_) => 1,
      Err(_) => 0
    }
  val processOk =
    match (await Process.runProcess("sh", ["-c", "exit 0"])) {
      Ok(r) => if (r.exitCode == 0) 1 else 0,
      _ => 0
    }
  val delayed = await delayedValue()

  group(s, "async virtual threads", (s1: Suite) => {
    group(s1, "await success", (sg: Suite) => {
      eq(sg, "await plusOne", plusOneValue, 42)
    });

    group(s1, "await try catch", (sg: Suite) => {
      eq(sg, "catch async exception", caughtValue, 7)
    });

    group(s1, "await fs/process result", (sg: Suite) => {
      eq(sg, "fs ok", fileOk, 1);
      eq(sg, "process ok", processOk, 1)
    });

    group(s1, "await delayed task", (sg: Suite) => {
      eq(sg, "delayed task value", delayed, 99)
    });
  });
  ()
}