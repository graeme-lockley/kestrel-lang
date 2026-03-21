package kestrel.runtime;

import java.lang.reflect.Method;

/** Non-capturing function reference — wraps a static method. */
public final class KFunctionRef implements KFunction {
    private final Object receiver;  // null for static
    private final Method method;

    public KFunctionRef(Method method) {
        this(null, method);
    }

    public KFunctionRef(Object receiver, Method method) {
        this.receiver = receiver;
        this.method = method;
        this.method.setAccessible(true);
    }

    @Override
    public Object apply(Object[] args) {
        try {
            if (args == null) args = new Object[0];
            return invokeSpread(receiver, method, args);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static Object invokeSpread(Object receiver, Method m, Object[] args) throws Exception {
        int n = args.length;
        switch (n) {
            case 0: return m.invoke(receiver);
            case 1: return m.invoke(receiver, args[0]);
            case 2: return m.invoke(receiver, args[0], args[1]);
            case 3: return m.invoke(receiver, args[0], args[1], args[2]);
            case 4: return m.invoke(receiver, args[0], args[1], args[2], args[3]);
            case 5: return m.invoke(receiver, args[0], args[1], args[2], args[3], args[4]);
            case 6: return m.invoke(receiver, args[0], args[1], args[2], args[3], args[4], args[5]);
            case 7: return m.invoke(receiver, args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
            case 8: return m.invoke(receiver, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
            default:
                return m.invoke(receiver, args);
        }
    }
}
