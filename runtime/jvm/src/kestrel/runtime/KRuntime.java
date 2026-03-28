package kestrel.runtime;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.HashMap;

/**
 * Kestrel runtime primitives — equivalent to VM built-in CALL 0xFFFFFFxx.
 * Generated code sets mainArgs via setMainArgs() before running.
 */
public final class KRuntime {
    private static String[] mainArgs = new String[0];

    private KRuntime() {}

    /** Set command-line args (called by generated main). */
    public static void setMainArgs(String[] args) {
        mainArgs = args != null ? args : new String[0];
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

    public static KValue jsonParse(Object s) {
        if (!(s instanceof String)) throw new IllegalArgumentException("jsonParse expects String");
        // Minimal JSON parsing to produce KValue tree. For full impl use a JSON library.
        String str = ((String) s).trim();
        if (str.equals("null")) return KVNull.INSTANCE;
        if (str.equals("true")) return new KVBool(true);
        if (str.equals("false")) return new KVBool(false);
        if (str.startsWith("\"") && str.endsWith("\"")) {
            return new KVString(str.substring(1, str.length() - 1).replace("\\\"", "\""));
        }
        if (str.startsWith("[") && str.endsWith("]")) {
            List<Object> list = new ArrayList<>();
            String inner = str.substring(1, str.length() - 1).trim();
            if (!inner.isEmpty()) {
                // Simple split by comma (does not handle nested commas correctly)
                for (String part : splitTopLevel(inner, ',')) {
                    list.add(jsonParse(part.trim()));
                }
            }
            return new KVArray(list);
        }
        if (str.startsWith("{") && str.endsWith("}")) {
            Map<String, Object> map = new HashMap<>();
            String inner = str.substring(1, str.length() - 1).trim();
            if (!inner.isEmpty()) {
                for (String pair : splitTopLevel(inner, ',')) {
                    int colon = pair.indexOf(':');
                    if (colon < 0) continue;
                    String key = pair.substring(0, colon).trim();
                    Object val = jsonParse(pair.substring(colon + 1).trim());
                    if (key.startsWith("\"") && key.endsWith("\"")) {
                        key = key.substring(1, key.length() - 1);
                    }
                    map.put(key, val);
                }
            }
            return new KVObject(map);
        }
        try {
            if (str.contains(".")) {
                return new KVFloat(Double.parseDouble(str));
            }
            return new KVInt(Long.parseLong(str));
        } catch (NumberFormatException e) {
            return KVNull.INSTANCE;
        }
    }

    private static List<String> splitTopLevel(String s, char delim) {
        List<String> out = new ArrayList<>();
        int depth = 0;
        int start = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '{' || c == '[' || c == '"') {
                if (c == '"') {
                    i++;
                    while (i < s.length() && s.charAt(i) != '"') {
                        if (s.charAt(i) == '\\') i++;
                        i++;
                    }
                } else {
                    depth++;
                }
            } else if (c == '}' || c == ']') {
                depth--;
            } else if (c == delim && depth == 0) {
                out.add(s.substring(start, i));
                start = i + 1;
            }
        }
        out.add(s.substring(start));
        return out;
    }

    public static String jsonStringify(Object v) {
        if (v == null || v == KVNull.INSTANCE) return "null";
        if (v instanceof KVBool) return ((KVBool) v).value ? "true" : "false";
        if (v instanceof KVInt) return Long.toString(((KVInt) v).value);
        if (v instanceof KVFloat) return Double.toString(((KVFloat) v).value);
        if (v instanceof KVString) return "\"" + escapeJson(((KVString) v).value) + "\"";
        if (v instanceof KVArray) {
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            for (Object x : ((KVArray) v).value) {
                if (!first) sb.append(",");
                sb.append(jsonStringify(x));
                first = false;
            }
            sb.append("]");
            return sb.toString();
        }
        if (v instanceof KVObject) {
            StringBuilder sb = new StringBuilder("{");
            boolean first = true;
            for (Map.Entry<String, Object> e : ((KVObject) v).value.entrySet()) {
                if (!first) sb.append(",");
                sb.append("\"").append(escapeJson(e.getKey())).append("\":").append(jsonStringify(e.getValue()));
                first = false;
            }
            sb.append("}");
            return sb.toString();
        }
        return "\"" + escapeJson(formatOne(v)) + "\"";
    }

    private static String escapeJson(String s) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"') sb.append("\\\"");
            else if (c == '\\') sb.append("\\\\");
            else if (c == '\n') sb.append("\\n");
            else if (c == '\r') sb.append("\\r");
            else if (c == '\t') sb.append("\\t");
            else sb.append(c);
        }
        return sb.toString();
    }

    public static Object readFileAsync(Object path) {
        if (!(path instanceof String)) throw new IllegalArgumentException("readFileAsync expects String");
        try {
            return new String(Files.readAllBytes(Paths.get((String) path)), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new RuntimeException("readFileAsync: " + e.getMessage());
        }
    }

    public static KList listDir(Object path) {
        if (!(path instanceof String)) throw new IllegalArgumentException("listDir expects String");
        try {
            Path dir = Paths.get((String) path);
            List<String> entries = new ArrayList<>();
            Files.list(dir).forEach(p -> {
                String kind = Files.isDirectory(p) ? "dir" : "file";
                // Match VM contract: "<fullPath>\t<kind>"
                entries.add(p.toString() + "\t" + kind);
            });
            KList result = KNil.INSTANCE;
            for (int i = entries.size() - 1; i >= 0; i--) {
                result = new KCons(entries.get(i), result);
            }
            return result;
        } catch (Exception e) {
            throw new RuntimeException("listDir: " + e.getMessage());
        }
    }

    public static void writeText(Object path, Object content) {
        if (!(path instanceof String)) throw new IllegalArgumentException("writeText expects String");
        try {
            Files.writeString(Paths.get((String) path), formatOne(content), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new RuntimeException("writeText: " + e.getMessage());
        }
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

    public static Long runProcess(Object program, Object argsObj) {
        if (!(program instanceof String)) throw new IllegalArgumentException("runProcess expects String program");
        List<String> cmd = new ArrayList<>();
        cmd.add((String) program);
        if (argsObj instanceof KList) {
            KList xs = (KList) argsObj;
            while (xs instanceof KCons) {
                cmd.add(formatOne(((KCons) xs).head));
                xs = ((KCons) xs).tail;
            }
        }
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
            return Long.valueOf(p.waitFor());
        } catch (Exception e) {
            throw new RuntimeException("runProcess: " + e.getMessage());
        }
    }
}
