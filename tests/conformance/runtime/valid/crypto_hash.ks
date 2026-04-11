// Runtime conformance: sha256, sha1, md5
import { sha256, sha1, md5 } from "kestrel:io/crypto"

println(sha256("hello"))
// 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
println(sha1("hello"))
// aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
println(md5("hello"))
// 5d41402abc4b2a76b9719d911017c592
println(sha256(""))
// e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
