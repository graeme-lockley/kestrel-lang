// Public type - constructors available to importers
export type PublicToken = PubNum(Int) | PubOp(String) | PubEof

export fun publicTokenToInt(t: PublicToken): Int = match (t) {
  PubNum(n) => n
  PubOp(s) => 0
  PubEof => -1
}

// Opaque type - constructors NOT available to importers
opaque type SecretToken = SecNum(Int) | SecOp(String) | SecEof

export fun secretTokenToInt(t: SecretToken): Int = match (t) {
  SecNum(n) => n
  SecOp(s) => 0
  SecEof => -1
}

export fun makeSecretToken(n: Int): SecretToken = SecNum(n)

// Opaque type alias - underlying type is Int but hidden from importers
opaque type UserId = Int

export fun userIdToInt(id: UserId): Int = id

export fun makeUserId(n: Int): UserId = n
