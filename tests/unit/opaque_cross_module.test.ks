import { Suite, group, eq } from "kestrel:tools/test"
import { SecretToken, secretTokenToInt, makeSecretToken, UserId, userIdToInt, makeUserId } from "../fixtures/opaque_pkg/lib.ks"

// Using opaque ADT via its exported functions
fun useOpaqueToken(): Int = secretTokenToInt(makeSecretToken(100))

// Using opaque type alias via its exported functions
fun useOpaqueAlias(): Int = userIdToInt(makeUserId(999))

export async fun run(s: Suite): Task<Unit> =
  group(s, "cross-module opaque types", (s1: Suite) => {
    eq(s1, "use opaque token", useOpaqueToken(), 100)
    eq(s1, "use opaque alias", useOpaqueAlias(), 999)
  })
