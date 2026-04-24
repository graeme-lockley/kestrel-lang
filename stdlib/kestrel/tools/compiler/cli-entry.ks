//! Self-hosted compiler CLI entrypoint.
//!
//! Forwards process argv to [`kestrel:tools/compiler/cli-main`](/docs/kestrel:tools/compiler/cli-main).

import { getProcess } from "kestrel:sys/process"
import { main } from "kestrel:tools/compiler/cli-main"

main(getProcess().args)