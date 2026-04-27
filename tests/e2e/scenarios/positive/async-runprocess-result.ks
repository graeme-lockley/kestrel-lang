// E2E_SKIP_PENDING_CODEGEN: self-hosted codegen does not yet emit $init/main; re-enable in S17-37/S17-42
import * as Process from "kestrel:sys/process"
import { ProcessSpawnError } from "kestrel:sys/process"

async fun run(): Task<Unit> = {
  val code =
    match (await Process.runProcess("sh", ["-c", "echo e2e-out; echo e2e-err 1>&2; exit 9"])) {
      Ok(r) => r.exitCode,
      Err(_) => -1
    };
  println("marker-exit:${code}");

  val spawn =
    match (await Process.runProcess("__definitely_missing_binary_xyz__", [])) {
      Err(ProcessSpawnError(_)) => "spawn-error",
      _ => "unexpected"
    };
  println(spawn);

  ()
}

run()
