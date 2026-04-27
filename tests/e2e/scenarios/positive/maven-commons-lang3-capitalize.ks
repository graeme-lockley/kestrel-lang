// E2E_SKIP_PENDING_CODEGEN: self-hosted codegen does not yet emit $init/main; re-enable in S17-37/S17-42
// E2E_REQUIRE_NETWORK
// Tests the full Maven + extern import pipeline using commons-lang3.
// Requires commons-lang3:3.17.0 to be in the maven cache.
// Skip by setting KESTREL_MAVEN_OFFLINE=1 in environments without network.
import "maven:org.apache.commons:commons-lang3:3.17.0"
extern import "maven:org.apache.commons:commons-lang3:3.17.0#org.apache.commons.lang3.StringUtils" as SU {}

// capitalize is a static method generated as a top-level extern fun
println(capitalize("hello world"))
