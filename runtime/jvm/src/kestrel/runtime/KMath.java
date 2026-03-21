package kestrel.runtime;

/**
 * Kestrel integer arithmetic with 61-bit signed semantics.
 * Throws ArithmeticException on overflow (matching Zig VM behavior).
 */
public final class KMath {
    private static final long MAX_61 = (1L << 60) - 1;
    private static final long MIN_61 = -(1L << 60);

    private KMath() {}

    private static void check61(long v) {
        if (v > MAX_61 || v < MIN_61) {
            throw new ArithmeticException("61-bit integer overflow");
        }
    }

    public static Long add(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long y = b.longValue();
        long r = x + y;
        if (((x ^ r) & (y ^ r)) < 0) {
            throw new ArithmeticException("61-bit integer overflow");
        }
        check61(r);
        return Long.valueOf(r);
    }

    public static Long sub(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long y = b.longValue();
        long r = x - y;
        if (((x ^ y) & (x ^ r)) < 0) {
            throw new ArithmeticException("61-bit integer overflow");
        }
        check61(r);
        return Long.valueOf(r);
    }

    public static Long mul(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long y = b.longValue();
        long r = x * y;
        if (y != 0 && r / y != x) {
            throw new ArithmeticException("61-bit integer overflow");
        }
        check61(r);
        return Long.valueOf(r);
    }

    public static Long div(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long y = b.longValue();
        if (y == 0) {
            throw new ArithmeticException("division by zero");
        }
        return Long.valueOf(x / y);
    }

    public static Long mod(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long y = b.longValue();
        if (y == 0) {
            throw new ArithmeticException("division by zero");
        }
        return Long.valueOf(x % y);
    }

    public static Long pow(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        long x = a.longValue();
        long n = b.longValue();
        if (n < 0) {
            throw new ArithmeticException("negative exponent");
        }
        long r = 1;
        while (n > 0) {
            if ((n & 1) != 0) {
                r = r * x;
                check61(r);
            }
            n >>= 1;
            if (n > 0) {
                x = x * x;
                check61(x);
            }
        }
        return Long.valueOf(r);
    }

    /** JVM-mangled names for comparison (codegen uses $less, $greater, etc.). */
    public static java.lang.Boolean $less(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.longValue() < b.longValue());
    }

    public static java.lang.Boolean $less$eq(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.longValue() <= b.longValue());
    }

    public static java.lang.Boolean $greater(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.longValue() > b.longValue());
    }

    public static java.lang.Boolean $greater$eq(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.longValue() >= b.longValue());
    }

    public static Double addFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Double.valueOf(a.doubleValue() + b.doubleValue());
    }

    public static Double subFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Double.valueOf(a.doubleValue() - b.doubleValue());
    }

    public static Double mulFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Double.valueOf(a.doubleValue() * b.doubleValue());
    }

    public static Double divFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        double y = b.doubleValue();
        if (y == 0.0) {
            throw new ArithmeticException("division by zero");
        }
        return Double.valueOf(a.doubleValue() / y);
    }

    public static java.lang.Boolean $lessFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.doubleValue() < b.doubleValue());
    }

    public static java.lang.Boolean $less$eqFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.doubleValue() <= b.doubleValue());
    }

    public static java.lang.Boolean $greaterFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.doubleValue() > b.doubleValue());
    }

    public static java.lang.Boolean $greater$eqFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(a.doubleValue() >= b.doubleValue());
    }
}
