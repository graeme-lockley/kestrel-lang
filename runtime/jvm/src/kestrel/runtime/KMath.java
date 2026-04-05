package kestrel.runtime;

/**
 * Kestrel integer arithmetic with signed 64-bit (Long) semantics.
 * Throws ArithmeticException on overflow.
 */
public final class KMath {

    private KMath() {}

    public static Long add(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        try {
            return Math.addExact(a.longValue(), b.longValue());
        } catch (ArithmeticException e) {
            throw new ArithmeticException("integer overflow");
        }
    }

    public static Long sub(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        try {
            return Math.subtractExact(a.longValue(), b.longValue());
        } catch (ArithmeticException e) {
            throw new ArithmeticException("integer overflow");
        }
    }

    public static Long mul(Long a, Long b) {
        if (a == null || b == null) throw new NullPointerException();
        try {
            return Math.multiplyExact(a.longValue(), b.longValue());
        } catch (ArithmeticException e) {
            throw new ArithmeticException("integer overflow");
        }
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
        try {
            while (n > 0) {
                if ((n & 1) != 0) {
                    r = Math.multiplyExact(r, x);
                }
                n >>= 1;
                if (n > 0) {
                    x = Math.multiplyExact(x, x);
                }
            }
        } catch (ArithmeticException e) {
            throw new ArithmeticException("integer overflow");
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

    /** Char (Integer code point): ordered comparison by Unicode scalar (unsigned). */
    public static java.lang.Boolean charLess(Integer a, Integer b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(Integer.compareUnsigned(a.intValue(), b.intValue()) < 0);
    }

    public static java.lang.Boolean charLessEq(Integer a, Integer b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(Integer.compareUnsigned(a.intValue(), b.intValue()) <= 0);
    }

    public static java.lang.Boolean charGreater(Integer a, Integer b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(Integer.compareUnsigned(a.intValue(), b.intValue()) > 0);
    }

    public static java.lang.Boolean charGreaterEq(Integer a, Integer b) {
        if (a == null || b == null) throw new NullPointerException();
        return Boolean.valueOf(Integer.compareUnsigned(a.intValue(), b.intValue()) >= 0);
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

    public static Double powFloat(Double a, Double b) {
        if (a == null || b == null) throw new NullPointerException();
        return Double.valueOf(Math.pow(a.doubleValue(), b.doubleValue()));
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
