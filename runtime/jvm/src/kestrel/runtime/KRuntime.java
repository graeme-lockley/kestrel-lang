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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;
/**
 * Kestrel runtime primitives — equivalent to VM built-in CALL 0xFFFFFFxx.
 * Generated code sets mainArgs via setMainArgs() before running.
 */
public final class KRuntime {
    private static String[] mainArgs = new String[0];
    private static ExecutorService asyncExecutor;
    private static final Object asyncMonitor = new Object();
    private static int asyncTasksInFlight = 0;

    private KRuntime() {}

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
        synchronized (asyncMonitor) {
            asyncTasksInFlight++;
        }
        try {
            executor.submit(() -> {
                try {
                    future.complete(fn.apply(taskArgs));
                } catch (Throwable t) {
                    future.completeExceptionally(KTask.unwrapFailure(t));
                } finally {
                    synchronized (asyncMonitor) {
                        asyncTasksInFlight--;
                        asyncMonitor.notifyAll();
                    }
                }
            });
        } catch (RuntimeException e) {
            synchronized (asyncMonitor) {
                asyncTasksInFlight--;
                asyncMonitor.notifyAll();
            }
            throw e;
        }
        return KTask.fromFuture(future);
    }

    private static void awaitAsyncQuiescence() {
        synchronized (asyncMonitor) {
            while (asyncTasksInFlight > 0) {
                try {
                    asyncMonitor.wait();
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
        synchronized (asyncMonitor) {
            asyncTasksInFlight++;
        }

        try {
            executor.submit(() -> {
                try {
                    future.complete(new KOk(new String(Files.readAllBytes(Paths.get(resolvedPath)), StandardCharsets.UTF_8)));
                } catch (Throwable t) {
                    future.complete(new KErr(fsErrorCode(t)));
                } finally {
                    synchronized (asyncMonitor) {
                        asyncTasksInFlight--;
                        asyncMonitor.notifyAll();
                    }
                }
            });
        } catch (RuntimeException e) {
            synchronized (asyncMonitor) {
                asyncTasksInFlight--;
                asyncMonitor.notifyAll();
            }
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
        synchronized (asyncMonitor) {
            asyncTasksInFlight++;
        }

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
                    synchronized (asyncMonitor) {
                        asyncTasksInFlight--;
                        asyncMonitor.notifyAll();
                    }
                }
            });
        } catch (RuntimeException e) {
            synchronized (asyncMonitor) {
                asyncTasksInFlight--;
                asyncMonitor.notifyAll();
            }
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
        synchronized (asyncMonitor) {
            asyncTasksInFlight++;
        }

        try {
            executor.submit(() -> {
                try {
                    Files.writeString(Paths.get(resolvedPath), resolvedContent, StandardCharsets.UTF_8);
                    future.complete(new KOk(KUnit.INSTANCE));
                } catch (Throwable t) {
                    future.complete(new KErr(fsErrorCode(t)));
                } finally {
                    synchronized (asyncMonitor) {
                        asyncTasksInFlight--;
                        asyncMonitor.notifyAll();
                    }
                }
            });
        } catch (RuntimeException e) {
            synchronized (asyncMonitor) {
                asyncTasksInFlight--;
                asyncMonitor.notifyAll();
            }
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
        synchronized (asyncMonitor) {
            asyncTasksInFlight++;
        }

        try {
            executor.submit(() -> {
                try {
                    ProcessBuilder pb = new ProcessBuilder(cmd);
                    pb.redirectErrorStream(true);
                    Process p = pb.start();
                    try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = r.readLine()) != null) {
                            System.out.println(line);
                        }
                    }
                    future.complete(new KOk(Long.valueOf(p.waitFor())));
                } catch (Throwable t) {
                    future.complete(new KErr("process_error:" + messageOrDefault(t, "process failed")));
                } finally {
                    synchronized (asyncMonitor) {
                        asyncTasksInFlight--;
                        asyncMonitor.notifyAll();
                    }
                }
            });
        } catch (RuntimeException e) {
            synchronized (asyncMonitor) {
                asyncTasksInFlight--;
                asyncMonitor.notifyAll();
            }
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
}
