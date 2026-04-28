// Provenance: tests/conformance/typecheck/valid/await_recursive_direct_call.ks (baseline S17-50)
// Regression test: direct `await` on a recursive async call must be accepted.
// Previously the type checker threw "await expects Task<T> but got α" because
// the unresolved type variable for the recursive callee was not constrained
// to Task<T> via unification before the kind check.

import * as Lst from "kestrel:data/list"

// Recursive async function that directly awaits its own recursive call.
async fun deleteFiles(files: List<String>): Task<Unit> =
  match (files) {
    [] => ()
    _ :: rest => {
      await deleteFiles(rest)
    }
  }

// Recursive async function returning Task<Bool>, directly awaits recursive call.
async fun anyNewer(deps: List<String>, threshold: Int): Task<Bool> =
  match (deps) {
    [] => False
    _ :: rest => await anyNewer(rest, threshold)
  }
