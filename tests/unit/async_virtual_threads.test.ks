import { Suite, group, eq } from "kestrel:test"
import * as Fs from "kestrel:fs"
import * as Process from "kestrel:process"
import * as Task from "kestrel:task"
import * as AsyncHelper from "../fixtures/async_helper.ks"

export exception AsyncBoom

async fun plusOne(n: Int): Task<Int> = n + 1
async fun fail(): Task<Int> = throw AsyncBoom
async fun delayedValue(): Task<Int> = {
  val _ = await Process.runProcess("sh", ["-c", "sleep 0.05"]);
  99
}
async fun slowTask(): Task<Int> = {
  val _ = await Process.runProcess("sh", ["-c", "sleep 1"]);
  2
}
async fun fastTask(): Task<Int> = 1

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
  val raceWinner = await Task.race([fastTask(), slowTask()])
  val raceEmptyResult = try { val _ = await Task.race([]); 0 } catch { _ => 1 }

  // S06-11: cross-module async (AC1)
  val crossModule = await AsyncHelper.asyncDouble(21)

  // S06-11: Task.all with two failing tasks (AC2)
  val allFailed: Int = try { val _ = await Task.all([fail(), fail()]); 0 } catch { _ => 1 }

  // S06-11: Task.race with all tasks failing (AC3)
  val raceFailed: Int = try { val _ = await Task.race([fail(), fail()]); 0 } catch { _ => 1 }

  // S06-11: cancel propagation through Task.map (AC4)
  val slowSource = Process.runProcess("sh", ["-c", "sleep 10"])
  val mapped = Task.map(slowSource, (r) => 0)
  Task.cancel(mapped)
  val cancelPropagated: Int = try { val _ = await slowSource; 0 } catch { _ => 1 }

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

    group(s1, "Task.race", (sg: Suite) => {
      eq(sg, "race returns winner value", raceWinner, 1);
      eq(sg, "race empty list is catchable", raceEmptyResult, 1)
    });

    group(s1, "Task edge cases (S06-11)", (sg: Suite) => {
      eq(sg, "cross-module async double", crossModule, 42);
      eq(sg, "Task.all all-fail is catchable", allFailed, 1);
      eq(sg, "Task.race all-fail is catchable", raceFailed, 1);
      eq(sg, "cancel mapped task cancels source", cancelPropagated, 1)
    });
  });
  ()
}