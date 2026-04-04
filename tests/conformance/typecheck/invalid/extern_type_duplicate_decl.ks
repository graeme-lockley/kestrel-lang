// EXPECT: Duplicate type declaration
extern type HashMap = jvm("java.util.HashMap")
extern type HashMap = jvm("java.util.concurrent.ConcurrentHashMap")
