// E2E_EXPECT_STACK_TRACE
// Expected phase: runtime — uncaught `throw`; stderr must show a usable fault (see run-e2e.sh).

fun f(): Int = throw(42)

f()
