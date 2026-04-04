package kestrel.runtime;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.AccessDeniedException;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CancellationException;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.HashMap;
import java.util.stream.Stream;
import java.time.Duration;
/**
 * Kestrel runtime primitives — equivalent to VM built-in CALL 0xFFFFFFxx.
 * Generated code sets mainArgs via setMainArgs() before running.
 */
public final class KRuntime {
    private static String[] mainArgs = new String[0];
    private static ExecutorService asyncExecutor;
    /** Tracks in-flight async tasks — atomic counter for correct quiescence signalling. */
    private static final AtomicLong asyncTasksInFlight = new AtomicLong(0);
    /** Signalled only when asyncTasksInFlight reaches zero; held only by awaitAsyncQuiescence. */
    private static final Object quiescenceSignal = new Object();

    /** Shared HTTP client — reuses TCP connections and avoids per-request DNS cycling. */
    private static volatile java.net.http.HttpClient sharedHttpClient;

    private KRuntime() {}

    /** Return the shared HttpClient, creating it lazily if necessary. */
    private static java.net.http.HttpClient getSharedHttpClient() {
        java.net.http.HttpClient c = sharedHttpClient;
        if (c == null) {
            synchronized (KRuntime.class) {
                c = sharedHttpClient;
                if (c == null) {
                    c = java.net.http.HttpClient.newBuilder()
                            .connectTimeout(Duration.ofSeconds(5))
                            .followRedirects(java.net.http.HttpClient.Redirect.NORMAL)
                            .build();
                    sharedHttpClient = c;
                }
            }
        }
        return c;
    }

    /** Set command-line args (called by generated main). */
    public static void setMainArgs(String[] args) {
        mainArgs = args != null ? args : new String[0];
    }

    public static synchronized void initAsyncRuntime() {
        if (asyncExecutor == null || asyncExecutor.isShutdown()) {
            asyncExecutor = Executors.newVirtualThreadPerTaskExecutor();
        }
    }

    public static synchronized void shutdownAsyncRuntime() {
        ExecutorService executor = asyncExecutor;
        asyncExecutor = null;
        if (executor == null) return;
        executor.shutdown();
        try {
            if (!executor.awaitTermination(30, TimeUnit.SECONDS)) {
                executor.shutdownNow();
            }
        } catch (InterruptedException e) {
            executor.shutdownNow();
            Thread.currentThread().interrupt();
            throw new RuntimeException("Interrupted while shutting down async runtime", e);
        }
    }

    public static synchronized void shutdownAsyncRuntimeNow() {
        ExecutorService executor = asyncExecutor;
        asyncExecutor = null;
        if (executor == null) return;
        executor.shutdownNow();
    }

    private static boolean exitWaitEnabled() {
        return Boolean.parseBoolean(System.getProperty("kestrel.exitWait", "true"));
    }

    public static KTask submitAsync(KFunction fn, Object[] args) {
        if (fn == null) throw new IllegalArgumentException("submitAsync expects KFunction");
        initAsyncRuntime();
        Object[] taskArgs = args != null ? args : new Object[0];
        CompletableFuture<Object> future = new CompletableFuture<>();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }
        asyncTasksInFlight.incrementAndGet();
        try {
            executor.submit(() -> {
                try {
                    future.complete(fn.apply(taskArgs));
                } catch (Throwable t) {
                    future.completeExceptionally(KTask.unwrapFailure(t));
                } finally {
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }
        return KTask.fromFuture(future);
    }

    /** Decrement the in-flight counter and notify quiescence waiters if it reaches zero. */
    private static void decrementAndSignal() {
        long remaining = asyncTasksInFlight.decrementAndGet();
        if (remaining <= 0) {
            synchronized (quiescenceSignal) {
                quiescenceSignal.notifyAll();
            }
        }
    }

    private static void awaitAsyncQuiescence() {
        synchronized (quiescenceSignal) {
            while (asyncTasksInFlight.get() > 0) {
                try {
                    quiescenceSignal.wait();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new RuntimeException("Interrupted while waiting for async tasks", e);
                }
            }
        }
    }

    public static void runMain(String[] args, KFunction init) {
        setMainArgs(args);
        initAsyncRuntime();
        boolean waitForAsync = exitWaitEnabled();
        try {
            init.apply(new Object[0]);
            if (waitForAsync) {
                awaitAsyncQuiescence();
            }
        } finally {
            if (waitForAsync) {
                shutdownAsyncRuntime();
            } else {
                shutdownAsyncRuntimeNow();
            }
        }
    }

    public static void println(Object... args) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append(' ');
            sb.append(formatOne(args[i]));
        }
        System.out.println(sb.toString());
    }

    public static void print(Object... args) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append(' ');
            sb.append(formatOne(args[i]));
        }
        System.out.print(sb.toString());
    }

    public static void exit(Object code) {
        int c = 0;
        if (code instanceof Long) {
            c = ((Long) code).intValue();
        } else if (code instanceof Number) {
            c = ((Number) code).intValue();
        }
        System.exit(c);
    }

    public static String formatOne(Object v) {
        if (v == null) return "null";
        if (v == KUnit.INSTANCE) return "()";
        if (v instanceof Boolean) return (Boolean) v ? "True" : "False";
        // Char is boxed as Integer (Kestrel Int uses Long); show the Unicode scalar, not a decimal.
        if (v instanceof Integer) return charToString(v);
        if (v instanceof Long) return Long.toString((Long) v);
        if (v instanceof Double) return formatDouble((Double) v);
        if (v instanceof String) return (String) v;
        if (v instanceof KRecord) {
            KRecord r = (KRecord) v;
            if (r.getFields().size() == 2 && r.get("value") != null && r.get("frames") != null) {
                return formatCapturedStackTrace(r);
            }
            StringBuilder sb = new StringBuilder("{ ");
            boolean first = true;
            for (Map.Entry<String, Object> e : r.getFields().entrySet()) {
                if (!first) sb.append(", ");
                sb.append(e.getKey()).append(" = ").append(formatOne(e.getValue()));
                first = false;
            }
            sb.append(" }");
            return sb.toString();
        }
        if (v instanceof KList) {
            StringBuilder sb = new StringBuilder("[");
            KList xs = (KList) v;
            boolean first = true;
            while (xs instanceof KCons) {
                KCons c = (KCons) xs;
                if (!first) sb.append(", ");
                sb.append(formatOne(c.head));
                first = false;
                xs = c.tail;
            }
            sb.append("]");
            return sb.toString();
        }
        if (v instanceof KOption) {
            if (v instanceof KNone) return "None";
            if (v instanceof KSome) return "Some(" + formatOne(((KSome) v).value) + ")";
        }
        if (v instanceof KResult) {
            if (v instanceof KErr) return "Err(" + formatOne(((KErr) v).value) + ")";
            if (v instanceof KOk) return "Ok(" + formatOne(((KOk) v).value) + ")";
        }
        if (v instanceof KAdt) {
            KAdt a = (KAdt) v;
            Object[] p = a.payload();
            if (p.length == 0) return v.getClass().getSimpleName();
            StringBuilder sb = new StringBuilder(v.getClass().getSimpleName()).append("(");
            for (int i = 0; i < p.length; i++) {
                if (i > 0) sb.append(", ");
                sb.append(formatOne(p[i]));
            }
            sb.append(")");
            return sb.toString();
        }
        return String.valueOf(v);
    }

    /** Stdlib `__print_one`: format to stdout without newline. */
    public static void printOne(Object x) {
        System.out.print(formatOne(x));
    }

    /**
     * Stdlib `__capture_trace`: JVM uses Java stack frames; shape matches VM ({@code value} + {@code frames} list of records).
     */
    public static Object captureTrace(Object value) {
        StackTraceElement[] st = Thread.currentThread().getStackTrace();
        int start = 0;
        while (start < st.length) {
            String cn = st[start].getClassName();
            String mn = st[start].getMethodName();
            if ("getStackTrace".equals(mn) && "java.lang.Thread".equals(cn)) {
                start++;
                continue;
            }
            if ("captureTrace".equals(mn) && "kestrel.runtime.KRuntime".equals(cn)) {
                start++;
                continue;
            }
            break;
        }
        KList list = KNil.INSTANCE;
        for (int i = st.length - 1; i >= start; i--) {
            StackTraceElement e = st[i];
            String file = e.getFileName() != null ? e.getFileName() : "?";
            long line = e.getLineNumber() >= 0 ? (long) e.getLineNumber() : 0L;
            KRecord fr = new KRecord();
            fr.set("file", file);
            fr.set("line", Long.valueOf(line));
            fr.set("function", "<unknown>");
            list = new KCons(fr, list);
        }
        KRecord tr = new KRecord();
        tr.set("value", value);
        tr.set("frames", list);
        return tr;
    }

    private static String formatCapturedStackTrace(KRecord r) {
        StringBuilder sb = new StringBuilder();
        sb.append(formatOne(r.get("value")));
        sb.append('\n');
        Object frames = r.get("frames");
        if (frames instanceof KList) {
            KList xs = (KList) frames;
            while (xs instanceof KCons) {
                KCons c = (KCons) xs;
                Object head = c.head;
                if (head instanceof KRecord) {
                    KRecord fr = (KRecord) head;
                    sb.append("  at ");
                    sb.append(formatOne(fr.get("file")));
                    sb.append(':');
                    sb.append(formatOne(fr.get("line")));
                    sb.append('\n');
                }
                xs = c.tail;
            }
        }
        return sb.toString();
    }

    private static String formatDouble(Double d) {
        double x = d.doubleValue();
        if (Double.isNaN(x)) return "NaN";
        if (Double.isInfinite(x)) return x > 0 ? "Infinity" : "-Infinity";
        return Double.toString(x);
    }

    public static String concat(Object a, Object b) {
        return formatOne(a) + formatOne(b);
    }

    public static Boolean equals(Object a, Object b) {
        return Boolean.valueOf(deepEquals(a, b));
    }

    /**
     * Normalize a caught JVM throwable into a Kestrel payload object.
     * - KException => payload
     * - ArithmeticException => DivideByZero/ArithmeticOverflow singleton when class names are provided
     * - CancellationException => Cancelled singleton when cancelledClass is provided
     * - otherwise rethrow
     */
    public static Object normalizeCaught(Throwable t, String arithmeticOverflowClass, String divideByZeroClass, String cancelledClass) throws Throwable {
        if (t instanceof KException) {
            return ((KException) t).getPayload();
        }
        if (t instanceof ArithmeticException && arithmeticOverflowClass != null && divideByZeroClass != null) {
            String msg = t.getMessage();
            String className = "division by zero".equals(msg) ? divideByZeroClass : arithmeticOverflowClass;
            try {
                Class<?> cls = Class.forName(className.replace('/', '.'));
                return cls.getField("INSTANCE").get(null);
            } catch (ReflectiveOperationException ex) {
                throw t;
            }
        }
        if (t instanceof CancellationException && cancelledClass != null) {
            try {
                Class<?> cls = Class.forName(cancelledClass.replace('/', '.'));
                return cls.getField("INSTANCE").get(null);
            } catch (ReflectiveOperationException ex) {
                throw t;
            }
        }
        throw t;
    }

    /**
     * Runtime probe for {@code e is T} when T is a primitive or record heap kind (matches VM KIND_IS / compiler).
     * Discriminant: 0 Int (Long), 1 Bool, 2 Unit, 3 Char (Integer), 4 String, 5 Float (Double), 6 KRecord.
     */
    public static boolean isValueKind(Object v, int disc) {
        switch (disc) {
            case 0:
                return v instanceof Long;
            case 1:
                return v instanceof Boolean;
            case 2:
                return v == KUnit.INSTANCE;
            case 3:
                return v instanceof Integer;
            case 4:
                return v instanceof String;
            case 5:
                return v instanceof Double;
            case 6:
                return v instanceof KRecord;
            default:
                return false;
        }
    }

    /** True if {@code rec} is a record with {@code field} whose value matches {@link #isValueKind(Object, int)}. */
    public static boolean recordFieldIsKind(Object rec, String field, int disc) {
        if (!(rec instanceof KRecord)) return false;
        Object x = ((KRecord) rec).getFields().get(field);
        if (x == null) return false;
        return isValueKind(x, disc);
    }

    /** User-defined (or any) ADT constructor class simple name match, e.g. value is {@code Red}. */
    public static boolean isAdtNamedCtor(Object v, String ctorName) {
        if (v == null || ctorName == null) return false;
        return ctorName.equals(v.getClass().getSimpleName());
    }

    private static boolean deepEquals(Object a, Object b) {
        if (a == b) return true;
        if (a == null || b == null) return false;
        if (a instanceof Long && b instanceof Long) return ((Long) a).longValue() == ((Long) b).longValue();
        if (a instanceof Double && b instanceof Double) return Double.compare(((Double) a).doubleValue(), ((Double) b).doubleValue()) == 0;
        if (a instanceof Boolean && b instanceof Boolean) return a.equals(b);
        if (a instanceof String && b instanceof String) return a.equals(b);
        if (a == KUnit.INSTANCE && b == KUnit.INSTANCE) return true;
        if (a instanceof KRecord && b instanceof KRecord) {
            Map<String, Object> fa = ((KRecord) a).getFields();
            Map<String, Object> fb = ((KRecord) b).getFields();
            if (fa.size() != fb.size()) return false;
            for (Map.Entry<String, Object> e : fa.entrySet()) {
                if (!deepEquals(e.getValue(), fb.get(e.getKey()))) return false;
            }
            return true;
        }
        if (a instanceof KList && b instanceof KList) {
            KList x = (KList) a;
            KList y = (KList) b;
            while (x instanceof KCons && y instanceof KCons) {
                if (!deepEquals(((KCons) x).head, ((KCons) y).head)) return false;
                x = ((KCons) x).tail;
                y = ((KCons) y).tail;
            }
            return (x instanceof KNil && y instanceof KNil);
        }
        if (a instanceof KOption && b instanceof KOption) {
            if (a instanceof KNone && b instanceof KNone) return true;
            if (a instanceof KSome && b instanceof KSome) return deepEquals(((KSome) a).value, ((KSome) b).value);
            return false;
        }
        if (a instanceof KResult && b instanceof KResult) {
            if (a instanceof KErr && b instanceof KErr) return deepEquals(((KErr) a).value, ((KErr) b).value);
            if (a instanceof KOk && b instanceof KOk) return deepEquals(((KOk) a).value, ((KOk) b).value);
            return false;
        }
            if (a instanceof KAdt && b instanceof KAdt) {
                KAdt ka = (KAdt) a;
                KAdt kb = (KAdt) b;
                if (!ka.getClass().equals(kb.getClass())) return false;
                Object[] pa = ka.payload();
                Object[] pb = kb.payload();
                if (pa.length != pb.length) return false;
                for (int i = 0; i < pa.length; i++) {
                    if (!deepEquals(pa[i], pb[i])) return false;
                }
                return true;
            }
        return a.equals(b);
    }

    public static Long stringLength(Object s) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringLength expects String");
        return Long.valueOf(((String) s).codePointCount(0, ((String) s).length()));
    }

    public static String stringSlice(Object s, Object start, Object end) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringSlice expects String");
        String str = (String) s;
        int si = intFrom(start);
        int ei = intFrom(end);
        if (si < 0 || ei > str.codePointCount(0, str.length()) || si > ei) {
            return "";
        }
        int byteStart = str.offsetByCodePoints(0, si);
        int byteEnd = str.offsetByCodePoints(0, ei);
        return str.substring(byteStart, byteEnd);
    }

    public static Long stringIndexOf(Object s, Object sub) {
        if (!(s instanceof String) || !(sub instanceof String)) throw new IllegalArgumentException("stringIndexOf expects String");
        String str = (String) s;
        String subStr = (String) sub;
        int byteIdx = str.indexOf(subStr);
        if (byteIdx < 0) return Long.valueOf(-1);
        return Long.valueOf(str.codePointCount(0, byteIdx));
    }

    public static Boolean stringEquals(Object a, Object b) {
        if (!(a instanceof String) || !(b instanceof String)) return Boolean.FALSE;
        return Boolean.valueOf(((String) a).equals((String) b));
    }

    public static String stringUpper(Object s) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringUpper expects String");
        return ((String) s).toUpperCase(Locale.ROOT);
    }

    public static String stringLower(Object s) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringLower expects String");
        return ((String) s).toLowerCase(Locale.ROOT);
    }

    private static boolean isAsciiWhitespace(int cp) {
        return cp == ' ' || cp == '\t' || cp == '\n' || cp == '\r' || cp == 0x0B || cp == 0x0C;
    }

    /** Trim leading/trailing ASCII whitespace by Unicode code point (matches VM). */
    public static String stringTrim(Object s) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringTrim expects String");
        String str = (String) s;
        int len = str.length();
        int start = 0;
        while (start < len) {
            int cp = str.codePointAt(start);
            if (!isAsciiWhitespace(cp)) break;
            start += Character.charCount(cp);
        }
        int end = len;
        while (end > start) {
            int cp = str.codePointBefore(end);
            if (!isAsciiWhitespace(cp)) break;
            end -= Character.charCount(cp);
        }
        return str.substring(start, end);
    }

    /** Code point at character index, or -1 if out of range. */
    public static Long stringCodePointAt(Object s, Object index) {
        if (!(s instanceof String)) throw new IllegalArgumentException("stringCodePointAt expects String");
        String str = (String) s;
        int i = intFrom(index);
        if (i < 0) return Long.valueOf(-1L);
        int cpCount = str.codePointCount(0, str.length());
        if (i >= cpCount) return Long.valueOf(-1L);
        int offset = str.offsetByCodePoints(0, i);
        return Long.valueOf((long) str.codePointAt(offset));
    }

    /** Unicode scalar value for a Char (boxed as Integer on JVM; Int remains Long). */
    public static Long charCodePoint(Object c) {
        if (c instanceof Integer) return Long.valueOf(((Integer) c).longValue());
        if (c instanceof Long) return (Long) c;
        if (c instanceof Number) return Long.valueOf(((Number) c).longValue());
        return Long.valueOf(0L);
    }

    /** Char at code-point index `i` (boxed Integer code point), or U+0000 if out of range. */
    public static Integer stringCharAt(Object s, Object index) {
        Long cp = stringCodePointAt(s, index);
        if (cp == null || cp.longValue() < 0) return Integer.valueOf(0);
        return Integer.valueOf(cp.intValue());
    }

    /** Single-code-point string from Char (Integer code point on JVM). */
    public static String charToString(Object c) {
        long cp = charCodePoint(c).longValue();
        if (cp < 0 || cp > 0x10FFFFL) return "";
        return new String(Character.toChars((int) cp));
    }

    /** Int code point to Char (boxed Integer); invalid or surrogate range -> U+0000. */
    public static Integer charFromCode(Object n) {
        long code = longFrom(n);
        if (code < 0 || code > 0x10FFFFL) return Integer.valueOf(0);
        if (code >= 0xD800L && code <= 0xDFFFL) return Integer.valueOf(0);
        return Integer.valueOf((int) code);
    }

    public static Double intToFloat(Object n) {
        return Double.valueOf((double) longFrom(n));
    }

    public static Long floatToInt(Object f) {
        double x = doubleFrom(f);
        return Long.valueOf((long) x);
    }

    public static Long floatFloor(Object f) {
        return Long.valueOf((long) Math.floor(doubleFrom(f)));
    }

    public static Long floatCeil(Object f) {
        return Long.valueOf((long) Math.ceil(doubleFrom(f)));
    }

    /** Round to nearest integer; ties to even (matches IEEE / Zig @round). */
    public static Long floatRound(Object f) {
        return Long.valueOf((long) Math.rint(doubleFrom(f)));
    }

    public static Double floatSqrt(Object f) {
        double x = doubleFrom(f);
        if (Double.isNaN(x) || x < 0.0) return Double.valueOf(Double.NaN);
        return Double.valueOf(Math.sqrt(x));
    }

    public static Boolean floatIsNan(Object f) {
        return Boolean.valueOf(Double.isNaN(doubleFrom(f)));
    }

    public static Boolean floatIsInfinite(Object f) {
        return Boolean.valueOf(Double.isInfinite(doubleFrom(f)));
    }

    public static Double floatAbs(Object f) {
        return Double.valueOf(Math.abs(doubleFrom(f)));
    }

    private static long longFrom(Object o) {
        if (o instanceof Long) return ((Long) o).longValue();
        if (o instanceof Integer) return ((Integer) o).longValue();
        if (o instanceof Number) return ((Number) o).longValue();
        throw new IllegalArgumentException("expected number");
    }

    private static double doubleFrom(Object o) {
        if (o instanceof Double) return ((Double) o).doubleValue();
        if (o instanceof Float) return ((Float) o).doubleValue();
        if (o instanceof Number) return ((Number) o).doubleValue();
        throw new IllegalArgumentException("expected float");
    }

    private static int intFrom(Object o) {
        if (o instanceof Long) return ((Long) o).intValue();
        if (o instanceof Number) return ((Number) o).intValue();
        throw new IllegalArgumentException("expected number");
    }

    public static KTask completedTask(Object value) {
        return KTask.completed(value);
    }

    public static KTask readFileAsync(Object path) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(path instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("readText expects String"));
            return KTask.fromFuture(future);
        }

        initAsyncRuntime();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }

        String resolvedPath = (String) path;
        asyncTasksInFlight.incrementAndGet();

        try {
            executor.submit(() -> {
                try {
                    future.complete(new KOk(new String(Files.readAllBytes(Paths.get(resolvedPath)), StandardCharsets.UTF_8)));
                } catch (Throwable t) {
                    future.complete(new KErr(fsErrorCode(t)));
                } finally {
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }

        return KTask.fromFuture(future);
    }

    public static KTask listDirAsync(Object path) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(path instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("listDir expects String"));
            return KTask.fromFuture(future);
        }

        initAsyncRuntime();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }

        String resolvedPath = (String) path;
        asyncTasksInFlight.incrementAndGet();

        try {
            executor.submit(() -> {
                try {
                    Path dir = Paths.get(resolvedPath);
                    List<String> entries = new ArrayList<>();
                    try (Stream<Path> stream = Files.list(dir)) {
                        stream.forEach(p -> {
                            String kind = Files.isDirectory(p) ? "dir" : "file";
                            // Match VM contract: "<fullPath>\t<kind>"
                            entries.add(p.toString() + "\t" + kind);
                        });
                    }
                    KList result = KNil.INSTANCE;
                    for (int i = entries.size() - 1; i >= 0; i--) {
                        result = new KCons(entries.get(i), result);
                    }
                    future.complete(new KOk(result));
                } catch (Throwable t) {
                    future.complete(new KErr(fsErrorCode(t)));
                } finally {
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }

        return KTask.fromFuture(future);
    }

    public static KTask writeTextAsync(Object path, Object content) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(path instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("writeText expects String"));
            return KTask.fromFuture(future);
        }

        initAsyncRuntime();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }

        String resolvedPath = (String) path;
        String resolvedContent = formatOne(content);
        asyncTasksInFlight.incrementAndGet();

        try {
            executor.submit(() -> {
                try {
                    Files.writeString(Paths.get(resolvedPath), resolvedContent, StandardCharsets.UTF_8);
                    future.complete(new KOk(KUnit.INSTANCE));
                } catch (Throwable t) {
                    future.complete(new KErr(fsErrorCode(t)));
                } finally {
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }

        return KTask.fromFuture(future);
    }

    public static Long nowMs() {
        return Long.valueOf(System.currentTimeMillis());
    }

    public static String getOs() {
        String name = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        if (name.contains("win")) return "windows";
        if (name.contains("mac")) return "darwin";
        if (name.contains("nux")) return "linux";
        return "unknown";
    }

    public static KList getArgs() {
        KList result = KNil.INSTANCE;
        for (int i = mainArgs.length - 1; i >= 0; i--) {
            result = new KCons(mainArgs[i], result);
        }
        return result;
    }

    public static String getCwd() {
        return System.getProperty("user.dir", "");
    }

    public static KTask runProcessAsync(Object program, Object argsObj) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(program instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("runProcess expects String program"));
            return KTask.fromFuture(future);
        }

        List<String> cmd = new ArrayList<>();
        cmd.add((String) program);
        if (argsObj instanceof KList) {
            KList xs = (KList) argsObj;
            while (xs instanceof KCons) {
                cmd.add(formatOne(((KCons) xs).head));
                xs = ((KCons) xs).tail;
            }
        }

        initAsyncRuntime();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }
        asyncTasksInFlight.incrementAndGet();

        try {
            executor.submit(() -> {
                Process proc = null;
                try {
                    if (future.isCancelled()) return;
                    ProcessBuilder pb = new ProcessBuilder(cmd);
                    pb.redirectErrorStream(true);
                    proc = pb.start();
                    final Process finalProc = proc;
                    // Destroy the OS process if the future is cancelled after start.
                    future.whenComplete((v, ex) -> {
                        if (future.isCancelled()) finalProc.destroyForcibly();
                    });
                    // Re-check after registering the callback to close the race window.
                    if (future.isCancelled()) {
                        proc.destroyForcibly();
                        return;
                    }
                    StringBuilder sb = new StringBuilder();
                    try (BufferedReader r = new BufferedReader(new InputStreamReader(finalProc.getInputStream(), StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = r.readLine()) != null) {
                            sb.append(line).append('\n');
                        }
                    }
                    int exitCode = finalProc.waitFor();
                    KRecord result = new KRecord(java.util.Map.of(
                        "exitCode", Long.valueOf(exitCode),
                        "stdout", sb.toString()
                    ));
                    future.complete(new KOk(result));
                } catch (Throwable t) {
                    future.complete(new KErr("process_error:" + messageOrDefault(t, "process failed")));
                } finally {
                    if (proc != null) proc.destroyForcibly();
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }

        return KTask.fromFuture(future);
    }

    private static String fsErrorCode(Throwable t) {
        Throwable u = KTask.unwrapFailure(t);
        if (u instanceof NoSuchFileException) return "not_found";
        if (u instanceof AccessDeniedException) return "permission_denied";
        return "io_error:" + messageOrDefault(u, "io failure");
    }

    private static String messageOrDefault(Throwable t, String fallback) {
        String msg = t.getMessage();
        if (msg == null || msg.isBlank()) return fallback;
        return msg;
    }

    // ── HashMap helpers for kestrel:dict ─────────────────────────────────────

    @SuppressWarnings("unchecked")
    public static HashMap<Object, Object> hashMapNew() {
        return new HashMap<>();
    }

    @SuppressWarnings("unchecked")
    public static HashMap<Object, Object> hashMapCopy(Object mapObj) {
        return new HashMap<>((HashMap<Object, Object>) mapObj);
    }

    @SuppressWarnings("unchecked")
    public static void hashMapPut(Object mapObj, Object key, Object value) {
        ((HashMap<Object, Object>) mapObj).put(key, value);
    }

    @SuppressWarnings("unchecked")
    public static void hashMapRemove(Object mapObj, Object key) {
        ((HashMap<Object, Object>) mapObj).remove(key);
    }

    @SuppressWarnings("unchecked")
    public static Object hashMapGet(Object mapObj, Object key) {
        return ((HashMap<Object, Object>) mapObj).get(key);
    }

    @SuppressWarnings("unchecked")
    public static Boolean hashMapContainsKey(Object mapObj, Object key) {
        return ((HashMap<Object, Object>) mapObj).containsKey(key);
    }

    @SuppressWarnings("unchecked")
    public static Long hashMapSize(Object mapObj) {
        return (long) ((HashMap<Object, Object>) mapObj).size();
    }

    @SuppressWarnings("unchecked")
    public static KList hashMapKeys(Object mapObj) {
        KList result = KNil.INSTANCE;
        for (Object k : ((HashMap<Object, Object>) mapObj).keySet()) {
            result = new KCons(k, result);
        }
        return result;
    }

    @SuppressWarnings("unchecked")
    public static KList hashMapValues(Object mapObj) {
        KList result = KNil.INSTANCE;
        for (Object v : ((HashMap<Object, Object>) mapObj).values()) {
            result = new KCons(v, result);
        }
        return result;
    }

    // ── HTTP client helpers for kestrel:http (S03-05) ────────────────────────

    /** Maximum number of times to retry an HTTP request when a connect timeout occurs. */
    private static final int HTTP_CONNECT_RETRIES = 2;

    /**
     * Send an HTTP request with automatic retry on connect timeout.
     * Java's HttpClient does not implement Happy Eyeballs (RFC 8305), so when
     * DNS returns multiple addresses and one is unreachable the first attempt
     * may hit a bad IP and wait the full connect timeout.  Retrying with a
     * fresh client forces a new DNS resolution and address selection.
     */
    private static CompletableFuture<java.net.http.HttpResponse<String>> sendWithRetry(
            java.net.http.HttpClient client,
            java.net.http.HttpRequest request,
            int retriesLeft) {
        return client.sendAsync(request, java.net.http.HttpResponse.BodyHandlers.ofString())
                .orTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                .thenApply(resp -> (java.net.http.HttpResponse<String>) resp)
                .exceptionallyCompose(error -> {
                    Throwable cause = error;
                    while (cause instanceof CompletionException && cause.getCause() != null) {
                        cause = cause.getCause();
                    }
                    if (retriesLeft > 0 && cause instanceof java.net.http.HttpConnectTimeoutException) {
                        // Build a fresh client so DNS is re-resolved and a different address may be tried.
                        java.net.http.HttpClient freshClient = java.net.http.HttpClient.newBuilder()
                                .connectTimeout(Duration.ofSeconds(5))
                                .followRedirects(java.net.http.HttpClient.Redirect.NORMAL)
                                .build();
                        return sendWithRetry(freshClient, request, retriesLeft - 1);
                    }
                    return CompletableFuture.failedFuture(error);
                });
    }

    /**
     * Perform an HTTP GET request asynchronously and return a KTask&lt;Response&gt;.
     * The completed value is a {@code java.net.http.HttpResponse&lt;String&gt;} object,
     * which is the backing type for the Kestrel {@code Response} opaque type.
     * Network/TLS errors propagate as KTask failures.
     */
    public static KTask httpGetAsync(Object url) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(url instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("Http.get expects String url"));
            return KTask.fromFuture(future);
        }

        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();

        final String urlStr = (String) url;
        try {
            java.net.http.HttpClient client = getSharedHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(urlStr))
                    .GET()
                    .build();
            sendWithRetry(client, request, HTTP_CONNECT_RETRIES)
                    .whenComplete((response, error) -> {
                        try {
                            if (error != null) {
                                future.completeExceptionally(KTask.unwrapFailure(error));
                            } else {
                                future.complete(response);
                            }
                        } finally {
                            decrementAndSignal();
                        }
                    });
        } catch (Exception e) {
            decrementAndSignal();
            future.completeExceptionally(e);
        }

        return KTask.fromFuture(future);
    }

    /**
     * General HTTP request: method, URL, headers (KList of (String,String) tuples), body (KSome(String) or KNone).
     * Returns a {@code Task<Response>}.
     * Non-2xx responses are not errors; network/TLS failures are.
     */
    public static KTask httpRequestAsync(Object method, Object url, Object headers, Object body) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(method instanceof String) || !(url instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("Http.request expects String method and url"));
            return KTask.fromFuture(future);
        }

        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();

        final String methodStr = ((String) method).toUpperCase(java.util.Locale.ROOT);
        final String urlStr = (String) url;

        try {
            java.net.http.HttpClient client = getSharedHttpClient();
            java.net.http.HttpRequest.Builder builder = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(urlStr));

            // Apply headers from List<(String,String)> — tuples are KRecord{0→k, 1→v}
            KList xs = (KList) headers;
            while (xs instanceof KCons) {
                KRecord pair = (KRecord) ((KCons) xs).head;
                String k = (String) pair.get("0");
                String v = (String) pair.get("1");
                builder.header(k, v);
                xs = ((KCons) xs).tail;
            }

            // Body
            java.net.http.HttpRequest.BodyPublisher bodyPublisher;
            if (body instanceof KSome) {
                String bodyStr = (String) ((KSome) body).value;
                bodyPublisher = java.net.http.HttpRequest.BodyPublishers.ofString(bodyStr, StandardCharsets.UTF_8);
            } else {
                bodyPublisher = java.net.http.HttpRequest.BodyPublishers.noBody();
            }

            builder.method(methodStr, bodyPublisher);
            sendWithRetry(client, builder.build(), HTTP_CONNECT_RETRIES)
                    .whenComplete((response, error) -> {
                        try {
                            if (error != null) {
                                future.completeExceptionally(KTask.unwrapFailure(error));
                            } else {
                                future.complete(response);
                            }
                        } finally {
                            decrementAndSignal();
                        }
                    });
        } catch (Exception e) {
            decrementAndSignal();
            future.completeExceptionally(e);
        }

        return KTask.fromFuture(future);
    }

    /**
     * Extract response headers from a {@code Response} as a list of (String, String) tuples.
     * Works for client responses ({@code HttpResponse&lt;String&gt;}). Returns empty list for server-side responses.
     * Each tuple is a KRecord with fields "0" (header name) and "1" (first value for that name).
     */
    @SuppressWarnings("unchecked")
    public static Object httpResponseHeaders(Object response) {
        if (response instanceof java.net.http.HttpResponse) {
            java.net.http.HttpResponse<String> resp = (java.net.http.HttpResponse<String>) response;
            KList result = KNil.INSTANCE;
            // Build list in reverse to maintain insertion order after reverse
            List<KRecord> pairs = new ArrayList<>();
            for (Map.Entry<String, List<String>> entry : resp.headers().map().entrySet()) {
                if (!entry.getValue().isEmpty()) {
                    KRecord pair = new KRecord(java.util.Map.of(
                        "0", entry.getKey(),
                        "1", entry.getValue().get(0)
                    ));
                    pairs.add(pair);
                }
            }
            // Build KList from pairs (append to front, so reversed)
            for (int i = pairs.size() - 1; i >= 0; i--) {
                result = new KCons(pairs.get(i), result);
            }
            return result;
        }
        return KNil.INSTANCE;
    }

    /**
     * Extract a single named response header value from a {@code Response}.
     * Returns {@code KSome(value)} for the first matching header (case-insensitive), or {@code KNone}.
     */
    @SuppressWarnings("unchecked")
    public static Object httpResponseHeader(Object response, Object name) {
        if (!(response instanceof java.net.http.HttpResponse) || !(name instanceof String)) {
            return KNone.INSTANCE;
        }
        java.net.http.HttpResponse<String> resp = (java.net.http.HttpResponse<String>) response;
        String headerName = (String) name;
        java.util.Optional<String> val = resp.headers().firstValue(headerName);
        return val.isPresent() ? new KSome(val.get()) : KNone.INSTANCE;
    }

    /**
     * Create a synthetic server-side {@code Response} value.
     * Stored internally as {@code Object[]{Long status, String body}}.
     * Both {@link #httpBodyText} and {@link #httpStatusCode} handle this form
     * as well as the client-side {@code HttpResponse&lt;String&gt;} form.
     */
    public static Object httpMakeResponse(Object status, Object body) {
        if (!(status instanceof Long)) {
            throw new IllegalArgumentException("makeResponse expects Int status");
        }
        if (!(body instanceof String)) {
            throw new IllegalArgumentException("makeResponse expects String body");
        }
        return new Object[]{status, body};
    }

    /**
     * Extract the body text from a {@code Response}.
     * Works for both client responses ({@code HttpResponse&lt;String&gt;}) and
     * server-side responses created via {@link #httpMakeResponse}.
     */
    @SuppressWarnings("unchecked")
    public static String httpBodyText(Object response) {
        if (response instanceof java.net.http.HttpResponse) {
            return ((java.net.http.HttpResponse<String>) response).body();
        }
        if (response instanceof Object[]) {
            return (String) ((Object[]) response)[1];
        }
        throw new IllegalArgumentException("bodyText: expected Response from get() or makeResponse()");
    }

    /**
     * Extract the HTTP status code from a {@code Response} as a Kestrel {@code Int} (Long).
     * Works for both client responses and server-side responses created via {@link #httpMakeResponse}.
     */
    public static Long httpStatusCode(Object response) {
        if (response instanceof java.net.http.HttpResponse) {
            return (long) ((java.net.http.HttpResponse<?>) response).statusCode();
        }
        if (response instanceof Object[]) {
            return (Long) ((Object[]) response)[0];
        }
        throw new IllegalArgumentException("statusCode: expected Response from get() or makeResponse()");
    }

    // ── HTTP server helpers for kestrel:http (S03-06) ────────────────────────

    /**
     * Create an HTTP server that dispatches each incoming request to the given Kestrel handler.
     * Uses a virtual-thread-per-request executor. The server is not yet bound; call
     * {@link #httpListenAsync} to bind and start it.
     *
     * <p>The handler is a Kestrel {@code (Request) -> Task&lt;Response&gt;} function.
     * Each call runs on a virtual thread (from the server executor); the handler's
     * {@code Task&lt;Response&gt;} is awaited synchronously on that virtual thread, then the
     * {@code Response} is written back to the {@code HttpExchange}.
     *
     * <p>If the handler throws or returns a failed task, a 500 response is sent.
     */
    public static KTask httpCreateServer(Object handler) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        try {
            KFunction kHandler = (KFunction) handler;
            com.sun.net.httpserver.HttpServer server =
                    com.sun.net.httpserver.HttpServer.create();
            server.setExecutor(java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor());
            server.createContext("/", (exchange) -> {
                try {
                    Object result = kHandler.apply(new Object[]{ exchange });
                    Object response = (result instanceof KTask) ? ((KTask) result).get() : result;
                    String body = httpBodyText(response);
                    int status = (int)(long) httpStatusCode(response);
                    byte[] bodyBytes = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
                    exchange.sendResponseHeaders(status, bodyBytes.length);
                    try (java.io.OutputStream os = exchange.getResponseBody()) {
                        os.write(bodyBytes);
                    }
                } catch (Throwable t) {
                    try {
                        byte[] errBytes = "Internal Server Error"
                                .getBytes(java.nio.charset.StandardCharsets.UTF_8);
                        exchange.sendResponseHeaders(500, errBytes.length);
                        try (java.io.OutputStream os = exchange.getResponseBody()) {
                            os.write(errBytes);
                        }
                    } catch (Throwable ignored) {}
                }
            });
            future.complete(server);
        } catch (Throwable t) {
            future.completeExceptionally(KTask.unwrapFailure(t));
        }
        return KTask.fromFuture(future);
    }

    /**
     * Bind the server to host:port and start accepting connections.
     * Returns a {@code Task&lt;Unit&gt;} that completes immediately once the server is listening.
     * Use port 0 to let the OS assign a free port; retrieve it with {@link #httpServerPort}.
     */
    public static KTask httpListenAsync(Object server, Object host, Object port) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(server instanceof com.sun.net.httpserver.HttpServer)) {
            future.completeExceptionally(new IllegalArgumentException("listen: expected Server"));
            return KTask.fromFuture(future);
        }
        if (!(host instanceof String)) {
            future.completeExceptionally(new IllegalArgumentException("listen: expected String host"));
            return KTask.fromFuture(future);
        }
        if (!(port instanceof Long)) {
            future.completeExceptionally(new IllegalArgumentException("listen: expected Int port"));
            return KTask.fromFuture(future);
        }
        try {
            com.sun.net.httpserver.HttpServer httpServer =
                    (com.sun.net.httpserver.HttpServer) server;
            int portInt = (int)(long)(Long) port;
            java.net.InetSocketAddress addr = new java.net.InetSocketAddress((String) host, portInt);
            httpServer.bind(addr, 0);
            httpServer.start();
            future.complete(KUnit.INSTANCE);
        } catch (Throwable t) {
            future.completeExceptionally(KTask.unwrapFailure(t));
        }
        return KTask.fromFuture(future);
    }

    /**
     * Return the actual port the server is bound to.
     * Useful when the server was started with port 0 (OS-assigned).
     */
    public static Long httpServerPort(Object server) {
        return (long) ((com.sun.net.httpserver.HttpServer) server).getAddress().getPort();
    }

    /**
     * Stop the server asynchronously.
     * Runs {@code HttpServer.stop(1)} on a virtual thread and returns a
     * {@code Task<Unit>} that resolves once the server has fully stopped.
     * Using a background thread avoids blocking the caller on the platform-thread
     * dispatcher join inside {@code HttpServer.stop()}.
     */
    public static KTask httpServerStop(Object server) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        com.sun.net.httpserver.HttpServer httpServer =
                (com.sun.net.httpserver.HttpServer) server;
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                httpServer.stop(1); // wait up to 1s for in-flight exchanges
                future.complete(KUnit.INSTANCE);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Extract a named query parameter from an incoming server {@code Request}.
     * Last-wins for duplicate keys. Handles percent-encoded keys and values.
     * Returns {@code KSome(value)} if found, {@code KNone.INSTANCE} if absent.
     */
    public static Object httpQueryParam(Object exchange, Object name) {
        if (!(exchange instanceof com.sun.net.httpserver.HttpExchange) || !(name instanceof String)) {
            return KNone.INSTANCE;
        }
        com.sun.net.httpserver.HttpExchange ex = (com.sun.net.httpserver.HttpExchange) exchange;
        String rawQuery = ex.getRequestURI().getRawQuery();
        if (rawQuery == null || rawQuery.isEmpty()) {
            return KNone.INSTANCE;
        }
        String keyName = (String) name;
        String found = null;
        for (String pair : rawQuery.split("&", -1)) {
            String[] kv = pair.split("=", 2);
            String k;
            try {
                k = java.net.URLDecoder.decode(kv[0], java.nio.charset.StandardCharsets.UTF_8);
            } catch (Exception e) {
                k = kv[0];
            }
            if (k.equals(keyName)) {
                if (kv.length > 1) {
                    try {
                        found = java.net.URLDecoder.decode(kv[1], java.nio.charset.StandardCharsets.UTF_8);
                    } catch (Exception e) {
                        found = kv[1];
                    }
                } else {
                    found = "";
                }
            }
        }
        return found != null ? new KSome(found) : KNone.INSTANCE;
    }

    /**
     * Return a unique identifier string for this request (UUID v4, in standard form).
     */
    public static String httpRequestId(Object exchange) {
        return java.util.UUID.randomUUID().toString();
    }

    /**
     * Read the full body of an incoming server {@code Request} as a UTF-8 string.
     * Returns a {@code KTask&lt;String&gt;} because body reading is I/O.
     */
    public static KTask httpRequestBodyText(Object exchange) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        if (!(exchange instanceof com.sun.net.httpserver.HttpExchange)) {
            future.completeExceptionally(
                    new IllegalArgumentException("requestBodyText: expected Request"));
            return KTask.fromFuture(future);
        }
        initAsyncRuntime();
        ExecutorService executor;
        synchronized (KRuntime.class) {
            executor = asyncExecutor;
        }
        asyncTasksInFlight.incrementAndGet();
        final com.sun.net.httpserver.HttpExchange ex =
                (com.sun.net.httpserver.HttpExchange) exchange;
        try {
            executor.submit(() -> {
                try {
                    byte[] bytes = ex.getRequestBody().readAllBytes();
                    future.complete(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
                } catch (Throwable t) {
                    future.completeExceptionally(KTask.unwrapFailure(t));
                } finally {
                    decrementAndSignal();
                }
            });
        } catch (RuntimeException e) {
            decrementAndSignal();
            throw e;
        }
        return KTask.fromFuture(future);
    }

    /**
     * Return the HTTP method of an incoming server {@code Request} as an uppercase string
     * (e.g. {@code "GET"}, {@code "POST"}).
     */
    public static String httpRequestMethod(Object exchange) {
        if (!(exchange instanceof com.sun.net.httpserver.HttpExchange)) {
            return "GET";
        }
        return ((com.sun.net.httpserver.HttpExchange) exchange).getRequestMethod().toUpperCase(java.util.Locale.ROOT);
    }

    /**
     * Return the URL path (without query string) of an incoming server {@code Request}.
     * e.g. {@code "/user/42"} for a request to {@code "/user/42?lang=en"}.
     */
    public static String httpRequestPath(Object exchange) {
        if (!(exchange instanceof com.sun.net.httpserver.HttpExchange)) {
            return "/";
        }
        return ((com.sun.net.httpserver.HttpExchange) exchange).getRequestURI().getPath();
    }

    // -----------------------------------------------------------------------
    // TCP socket primitives (kestrel:socket)
    // -----------------------------------------------------------------------

    /**
     * Connect a plain TCP socket to {@code host:port} asynchronously.
     * Returns a {@code Task<Socket>} that resolves with the connected socket
     * or fails with a {@code java.io.IOException} on connection error.
     */
    public static KTask tcpConnect(Object host, Object port) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                java.net.Socket sock = new java.net.Socket((String) host, (int)(long)(Long) port);
                future.complete(sock);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Connect a TLS socket to {@code host:port} using the default SSLContext
     * (system trust store, hostname verification enabled).
     * Returns a {@code Task<Socket>} that resolves with the connected TLS socket.
     */
    public static KTask tlsConnect(Object host, Object port) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        String hostStr = (String) host;
        int portInt = (int)(long)(Long) port;
        asyncExecutor.submit(() -> {
            try {
                javax.net.ssl.SSLSocketFactory factory =
                        (javax.net.ssl.SSLSocketFactory) javax.net.ssl.SSLSocketFactory.getDefault();
                javax.net.ssl.SSLSocket sock =
                        (javax.net.ssl.SSLSocket) factory.createSocket(hostStr, portInt);
                sock.startHandshake();
                future.complete(sock);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Send a UTF-8 text string over an open socket.
     * Returns a {@code Task<Unit>}.
     */
    public static KTask socketSendText(Object socket, Object text) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                java.net.Socket sock = (java.net.Socket) socket;
                byte[] bytes = ((String) text).getBytes(java.nio.charset.StandardCharsets.UTF_8);
                sock.getOutputStream().write(bytes);
                sock.getOutputStream().flush();
                future.complete(KUnit.INSTANCE);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Read all available bytes from the socket input stream until EOF or the remote
     * closes its write side. Returns a {@code Task<String>} (UTF-8 decoded).
     *
     * <p>Note: this reads until EOF. For protocols that keep the connection open
     * (HTTP/1.1 keep-alive), use {@link #socketReadLine} instead.
     */
    public static KTask socketReadAll(Object socket) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                java.net.Socket sock = (java.net.Socket) socket;
                byte[] bytes = sock.getInputStream().readAllBytes();
                future.complete(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Read one line (terminated by {@code \n} or {@code \r\n}) from the socket.
     * Returns a {@code Task<String>} (line without the trailing newline).
     * Returns an empty string at EOF.
     */
    public static KTask socketReadLine(Object socket) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                java.net.Socket sock = (java.net.Socket) socket;
                BufferedReader reader = new BufferedReader(
                        new InputStreamReader(sock.getInputStream(), java.nio.charset.StandardCharsets.UTF_8));
                String line = reader.readLine();
                future.complete(line != null ? line : "");
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Close the socket. Returns a {@code Task<Unit>}.
     */
    public static KTask socketClose(Object socket) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                ((java.net.Socket) socket).close();
                future.complete(KUnit.INSTANCE);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    // -----------------------------------------------------------------------
    // TCP server socket primitives (kestrel:socket)
    // -----------------------------------------------------------------------

    /**
     * Bind a {@code ServerSocket} on {@code host:port}.
     * Pass {@code port = 0} for an OS-assigned ephemeral port.
     * Returns a {@code Task<ServerSocket>}.
     */
    public static KTask tcpListen(Object host, Object port) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                int portInt = (int)(long)(Long) port;
                java.net.ServerSocket ss = new java.net.ServerSocket();
                ss.setReuseAddress(true);
                ss.bind(new java.net.InetSocketAddress((String) host, portInt));
                future.complete(ss);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Accept one incoming connection on a bound {@code ServerSocket}.
     * Returns a {@code Task<Socket>}.
     */
    public static KTask serverSocketAccept(Object serverSocket) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                java.net.Socket conn = ((java.net.ServerSocket) serverSocket).accept();
                future.complete(conn);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }

    /**
     * Return the local port that the {@code ServerSocket} is bound to.
     */
    public static Long serverSocketPort(Object serverSocket) {
        return (long) ((java.net.ServerSocket) serverSocket).getLocalPort();
    }

    /**
     * Close a {@code ServerSocket}. Returns a {@code Task<Unit>}.
     */
    public static KTask serverSocketClose(Object serverSocket) {
        CompletableFuture<Object> future = new CompletableFuture<>();
        initAsyncRuntime();
        asyncTasksInFlight.incrementAndGet();
        asyncExecutor.submit(() -> {
            try {
                ((java.net.ServerSocket) serverSocket).close();
                future.complete(KUnit.INSTANCE);
            } catch (Throwable t) {
                future.completeExceptionally(KTask.unwrapFailure(t));
            } finally {
                decrementAndSignal();
            }
        });
        return KTask.fromFuture(future);
    }
}
