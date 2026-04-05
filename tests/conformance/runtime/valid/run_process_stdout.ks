// Runtime conformance: runProcess captures stdout into ProcessResult
import * as Process from "kestrel:sys/process"
import { ProcessSpawnError } from "kestrel:sys/process"

async fun run(): Task<Unit> = {
  match (await Process.runProcess("sh", ["-c", "echo hello; echo world; exit 3"])) {
    Ok(r) => {
      println(r.exitCode);
      println(r.stdout);
      ()
    },
    Err(_) => {
      println("error");
      ()
    }
  }
}

run()
// 3
// hello
// world
//
