//! Hashing helpers for strings.
//!
//! Provides SHA-256, SHA-1, and MD5 wrappers for non-cryptographic identity,
//! checksums, and interoperability. Prefer SHA-256 for new code.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Crypto from "kestrel:io/crypto"
//!
//! val digest = Crypto.sha256("kestrel")
//! ```

extern fun sha256Impl(s: String): String =
  jvm("kestrel.runtime.KRuntime#sha256(java.lang.Object)")

extern fun sha1Impl(s: String): String =
  jvm("kestrel.runtime.KRuntime#sha1(java.lang.Object)")

extern fun md5Impl(s: String): String =
  jvm("kestrel.runtime.KRuntime#md5(java.lang.Object)")

export fun sha256(s: String): String = sha256Impl(s)
export fun sha1(s: String): String = sha1Impl(s)
export fun md5(s: String): String = md5Impl(s)
