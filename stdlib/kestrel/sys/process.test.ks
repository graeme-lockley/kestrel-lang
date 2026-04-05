import { Suite, group, eq, isTrue } from "kestrel:tools/test"
import { ProcessSpawnError } from "kestrel:sys/process"
import * as Process from "kestrel:sys/process"

export async fun run(s: Suite): Task<Unit> = {
  val successResult = await Process.runProcess("sh", ["-c", "exit 7"]);
  val spawnErrorResult = await Process.runProcess("__definitely_missing_binary_xyz__", []);

  group(s, "process", (s1: Suite) => {
    group(s1, "runProcess success", (sg: Suite) => {
      val code =
        match (successResult) {
          Ok(r) => r.exitCode,
          Err(_) => -1
        };
      eq(sg, "exit code", code, 7)
    });

    group(s1, "runProcess spawn error", (sg: Suite) => {
      val isErr =
        match (spawnErrorResult) {
          Err(ProcessSpawnError(_)) => True,
          _ => False
        };
      isTrue(sg, "returns Err(ProcessSpawnError)", isErr)
    });
  });
  ()
}
