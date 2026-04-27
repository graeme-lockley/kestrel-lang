// E2E_SKIP_PENDING_CODEGEN: self-hosted codegen does not yet emit $init/main; re-enable in S17-37/S17-42
import { hello_a } from "../../../fixtures/lazy_side_a.ks"
import { hello_b } from "../../../fixtures/lazy_side_b.ks"
val result = hello_a()
println(result)
