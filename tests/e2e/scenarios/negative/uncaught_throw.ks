// E2E_SKIP_PENDING_CODEGEN: temporary self-hosted main stub does not execute runtime-negative scenarios; re-enable with S17-37 and dependent codegen stories
// E2E_EXPECT_STACK_TRACE
// Expected phase: runtime — uncaught `throw`; stderr must show a usable fault (see run-e2e.sh).

fun f(): Int = throw(42)

f()
