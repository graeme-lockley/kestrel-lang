import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');
const runtimeDir = join(kestrelRoot, 'runtime', 'jvm');
const runtimeJar = join(runtimeDir, 'kestrel-runtime.jar');

function compileAndRunKestrel(source: string): string {
  const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-jvm-async-'));
  const srcPath = join(tmpRoot, 'JvmAsyncRuntime.ks');
  writeFileSync(srcPath, source);

  try {
    const compileResult = compileFileJvm(srcPath, {
      projectRoot: kestrelRoot,
      stdlibDir,
      getClassOutputDir: () => tmpRoot,
    });
    expect(compileResult.ok).toBe(true);
    if (!compileResult.ok) return '';

    const mainClass = compileResult.mainClass.replace(/\//g, '.');
    return execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
      cwd: kestrelRoot,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } finally {
    rmSync(tmpRoot, { recursive: true, force: true });
  }
}

function compileAndRunJava(className: string, source: string, javaArgs: string[] = []): string {
  const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-jvm-async-java-'));
  const javaPath = join(tmpRoot, `${className}.java`);
  writeFileSync(javaPath, source);

  try {
    execSync(`javac --release 21 -cp "${runtimeJar}" -d "${tmpRoot}" "${javaPath}"`, {
      cwd: kestrelRoot,
      stdio: 'pipe',
    });
    const javaArgString = javaArgs.map((arg) => JSON.stringify(arg)).join(' ');
    const javaCommand = javaArgString.length > 0
      ? `java ${javaArgString} -cp "${runtimeJar}:${tmpRoot}" "${className}"`
      : `java -cp "${runtimeJar}:${tmpRoot}" "${className}"`;
    return execSync(javaCommand, {
      cwd: kestrelRoot,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } finally {
    rmSync(tmpRoot, { recursive: true, force: true });
  }
}

describe('JVM async runtime', () => {
  beforeAll(() => {
    execSync('./build.sh', {
      cwd: runtimeDir,
      stdio: 'pipe',
    });
  });

  it('await surfaces async exceptions through try/catch', () => {
    const stdout = compileAndRunKestrel(`export exception Boom

async fun fail(): Task<Int> = throw Boom

async fun run(): Task<Unit> = {
  val caught = try { await fail() } catch { Boom => 7 };
  println(caught);
  ()
}

run()
`);

    expect(stdout).toBe('7\n');
  });

  it('executes async lambda closures on the async runtime', () => {
    const stdout = compileAndRunKestrel(`async fun run(): Task<Unit> = {
  val offset = 1
  val inc = async (x: Int) => x + offset
  val id = async <T>(x: T) => x
  println(await inc(42));
  println(await id(7));
  ()
}

run()
`);

    expect(stdout).toBe('43\n7\n');
  });

  it('virtual-thread executor overlaps independent tasks', () => {
    const stdout = compileAndRunJava(
      'AsyncOverlapHarness',
      `import kestrel.runtime.KFunction;
import kestrel.runtime.KRuntime;
import kestrel.runtime.KTask;

public final class AsyncOverlapHarness {
    public static void main(String[] args) {
        long start = System.currentTimeMillis();
        try {
            KTask left = KRuntime.submitAsync(new KFunction() {
                @Override
                public Object apply(Object[] ignored) {
                    try {
                        Thread.sleep(250L);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new RuntimeException(e);
                    }
                    return Long.valueOf(1L);
                }
            }, new Object[0]);
            KTask right = KRuntime.submitAsync(new KFunction() {
                @Override
                public Object apply(Object[] ignored) {
                    try {
                        Thread.sleep(250L);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new RuntimeException(e);
                    }
                    return Long.valueOf(2L);
                }
            }, new Object[0]);
            long sum = ((Long) left.get()).longValue() + ((Long) right.get()).longValue();
            long elapsed = System.currentTimeMillis() - start;
            System.out.println(sum);
            System.out.println(elapsed < 450L ? "overlap" : "serial:" + elapsed);
        } finally {
            KRuntime.shutdownAsyncRuntime();
        }
    }
}
`
    );

    expect(stdout).toBe('3\noverlap\n');
  });

    it('runMain waits for pending async work by default', () => {
    const stdout = compileAndRunJava(
      'ExitWaitDefaultHarness',
      `import kestrel.runtime.KFunction;
  import kestrel.runtime.KRuntime;
  import kestrel.runtime.KUnit;

  public final class ExitWaitDefaultHarness {
    public static void main(String[] args) {
      KRuntime.runMain(new String[0], new KFunction() {
        @Override
        public Object apply(Object[] ignored) {
          KRuntime.submitAsync(new KFunction() {
            @Override
            public Object apply(Object[] ignored2) {
              try {
                Thread.sleep(250L);
                KRuntime.println("async-done");
              } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
              }
              return KUnit.INSTANCE;
            }
          }, new Object[0]);
          return KUnit.INSTANCE;
        }
      });
    }
  }
  `
    );

    expect(stdout).toBe('async-done\n');
    });

    it('runMain exits without waiting when kestrel.exitWait=false', () => {
    const stdout = compileAndRunJava(
      'ExitNoWaitHarness',
      `import kestrel.runtime.KFunction;
  import kestrel.runtime.KRuntime;
  import kestrel.runtime.KUnit;

  public final class ExitNoWaitHarness {
    public static void main(String[] args) {
      KRuntime.runMain(new String[0], new KFunction() {
        @Override
        public Object apply(Object[] ignored) {
          KRuntime.submitAsync(new KFunction() {
            @Override
            public Object apply(Object[] ignored2) {
              try {
                Thread.sleep(5000L);
                KRuntime.println("async-done");
              } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
              }
              return KUnit.INSTANCE;
            }
          }, new Object[0]);
          return KUnit.INSTANCE;
        }
      });
    }
  }
  `,
      ['-Dkestrel.exitWait=false']
    );

    expect(stdout).toBe('');
    });

    it('shutdownAsyncRuntimeNow interrupts pending virtual-thread tasks', () => {
    const stdout = compileAndRunJava(
      'ShutdownNowHarness',
      `import kestrel.runtime.KFunction;
  import kestrel.runtime.KRuntime;
  import kestrel.runtime.KUnit;

  public final class ShutdownNowHarness {
    public static void main(String[] args) {
      KRuntime.initAsyncRuntime();
      KRuntime.submitAsync(new KFunction() {
        @Override
        public Object apply(Object[] ignored) {
          try {
            Thread.sleep(5000L);
          } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
          }
          return KUnit.INSTANCE;
        }
      }, new Object[0]);
      KRuntime.shutdownAsyncRuntimeNow();
      System.out.println("shutdown-now");
    }
  }
  `
    );

    expect(stdout).toBe('shutdown-now\n');
    });
});