import { Suite, group, eq, isTrue } from "kestrel:test"
import { ProcessSpawnError } from "kestrel:process"
import * as Process from "kestrel:process"

export async fun run(s: Suite): Task<Unit> = {
  group(s, "process", (s1: Suite) => {
    group(s1, "runProcess success", (sg: Suite) => {
      val result = await Process.runProcess("sh", ["-c", "exit 7"]);
      val code =
        match (result) {
          Ok(v) => v,
          Err(_) => -1
        };
      eq(sg, "exit code", code, 7)
    });

    group(s1, "runProcess spawn error", (sg: Suite) => {
      val result = await Process.runProcess("__definitely_missing_binary_xyz__", []);
      val isErr =
        match (result) {
          Err(ProcessSpawnError(_)) => True,
          _ => False
        };
      isTrue(sg, "returns Err(ProcessSpawnError)", isErr)
    });
  });
  ()
}
