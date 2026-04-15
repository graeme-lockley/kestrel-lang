//! Kestrel CLI — self-hosted implementation.
//!
//! Implements all user-facing commands for the `kestrel` tool.
//! Executed via `runInProcess` from the Bash shim after `kestrel bootstrap` has seeded
//! the JVM class cache.

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Opt from "kestrel:data/option"
import * as Res from "kestrel:data/result"
import * as Fs from "kestrel:io/fs"
import * as Path from "kestrel:sys/path"
import { getProcess, getEnv, runProcessStream, runInProcess, setSystemProperty, ProcessSpawnError, exit } from "kestrel:sys/process"
import * as Maven from "kestrel:tools/cli/maven"

// ── Environment helpers ───────────────────────────────────────────────────────

fun envOr(name: String, fallback: String): String =
  match (getEnv(name)) { Some(v) => v  None => fallback }

// ── Script resolution ─────────────────────────────────────────────────────────

// Resolve a kestrel: module specifier (e.g. "kestrel:tools/test") to an absolute .ks path.
async fun resolveKestrelModule(spec: String, kestrelRoot: String): Task<Option<String>> = {
  val rest = Str.dropLeft(spec, 8)
  val candidate = "${kestrelRoot}/stdlib/kestrel/${rest}.ks"
  val exists = await Fs.fileExists(candidate)
  if (exists) Some(candidate) else None
}

// Resolve a file-path argument to an absolute .ks path, or None if not found.
async fun resolveScript(arg: String, cwd: String): Task<Option<String>> = {
  val absArg = if (Path.isAbsolute(arg)) arg else Path.resolve(cwd, arg)
  val existsExact = await Fs.fileExists(absArg)
  if (existsExact) Some(absArg)
  else {
    if (Str.endsWith(".ks", arg)) None
    else {
      val withExt = "${absArg}.ks"
      val existsExt = await Fs.fileExists(withExt)
      if (existsExt) Some(withExt) else None
    }
  }
}

// Resolve a kestrel: specifier or file path to an absolute .ks path.
async fun resolveArg(arg: String, kestrelRoot: String, cwd: String): Task<Option<String>> =
  if (Str.startsWith("kestrel:", arg)) await resolveKestrelModule(arg, kestrelRoot)
  else await resolveScript(arg, cwd)

// ── Incremental compilation check ────────────────────────────────────────────

// Return True if any dep in the list has mtime >= classMtime (i.e. is newer).
async fun anyDepNewer(deps: List<String>, classMtime: Int): Task<Bool> =
  match (deps) {
    [] => False
    dep :: rest => {
      val trimmed = Str.trim(dep)
      if (Str.isEmpty(trimmed)) {
        val next: Task<Bool> = anyDepNewer(rest, classMtime)
        await next
      } else {
        val statR = await Fs.stat(trimmed)
        match (statR) {
          Err(_) => {
            val next: Task<Bool> = anyDepNewer(rest, classMtime)
            await next
          }
          Ok(s) => {
            if (s.mtimeMs >= classMtime) True
            else {
              val next: Task<Bool> = anyDepNewer(rest, classMtime)
              await next
            }
          }
        }
      }
    }
  }

// Return True if the .ks file needs to be (re)compiled.
async fun needsCompile(absKsPath: String, jvmCache: String): Task<Bool> = {
  val classFile = Maven.classFileForSource(jvmCache, absKsPath)
  val exists = await Fs.fileExists(classFile)
  if (!exists) True
  else {
    val classStatR = await Fs.stat(classFile)
    match (classStatR) {
      Err(_) => True
      Ok(classStat) => {
        val depsFile = "${classFile}.deps"
        val depsResult = await Fs.readText(depsFile)
        match (depsResult) {
          Err(_) => {
            val ksStatR = await Fs.stat(absKsPath)
            match (ksStatR) {
              Err(_) => True
              Ok(ksStat) => ksStat.mtimeMs >= classStat.mtimeMs
            }
          }
          Ok(content) => await anyDepNewer(Str.lines(content), classStat.mtimeMs)
        }
      }
    }
  }
}

// ── Compilation ───────────────────────────────────────────────────────────────

// Invoke `node <compilerCli> <entrySource> --target jvm -o <outDir> <flags>` as a subprocess.
// Returns the compiler exit code.
async fun compileScript(entrySource: String, outDir: String, compilerCli: String, flags: List<String>): Task<Int> = {
  val _ = await Fs.mkdirAll(outDir)
  val args = Lst.append([compilerCli, entrySource, "--target", "jvm", "-o", outDir], flags)
  match (await runProcessStream("node", args)) {
    Ok(code) => code
    Err(ProcessSpawnError(_)) => {
      println("kestrel: compile failed (node not found or failed to start)");
      1
    }
  }
}

// ── In-process execution ──────────────────────────────────────────────────────

// Build the classpath and execute the compiled script's main class in-process.
// This calls runInProcess which invokes System.exit — it does not return.
async fun runScript(
  absKsPath: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  userArgs: List<String>,
  exitNoWait: Bool
): Task<Unit> = {
  val mainClass = Maven.mainClassFor(absKsPath)
  val mavenResult = await Maven.resolveMavenClasspath(absKsPath, jvmCache, mavenCache)
  match (mavenResult) {
    Err(msg) => {
      println("kestrel: ${msg}");
      exit(1)
    }
    Ok(mavenJars) => {
      val classpath = Lst.append([mavenRuntimeJar, jvmCache], mavenJars)
      if (exitNoWait) setSystemProperty("kestrel.exitWait", "false") else setSystemProperty("kestrel.exitWait", "true")
      runInProcess(classpath, mainClass, userArgs)
    }
  }
}

// ── Selfhost check ────────────────────────────────────────────────────────────

// Return True if the self-hosted compiler classes are available in the JVM cache.
async fun isSelfhostReady(kestrelRoot: String, jvmCache: String): Task<Bool> = {
  val cliEntryKs = "${kestrelRoot}/stdlib/kestrel/tools/compiler/cli-entry.ks"
  val classFile = Maven.classFileForSource(jvmCache, cliEntryKs)
  await Fs.fileExists(classFile)
}

// ── cmd_run ───────────────────────────────────────────────────────────────────

type RunOpts = {
  exitNoWait: Bool,
  refresh: Bool,
  allowHttp: Bool,
  clean: Bool
}

fun parseRunArgs(args: List<String>, opts: RunOpts): Result<(RunOpts, String, List<String>), String> =
  match (args) {
    [] => Err("kestrel run: script path required")
    arg :: rest =>
      if (arg == "--help" | arg == "-h")
        Err("Usage: kestrel run [--exit-wait|--exit-no-wait] [--refresh] [--allow-http] [--clean] <script.ks> [args...]")
      else if (arg == "--exit-wait")
        parseRunArgs(rest, { exitNoWait = False, refresh = opts.refresh, allowHttp = opts.allowHttp, clean = opts.clean })
      else if (arg == "--exit-no-wait")
        parseRunArgs(rest, { exitNoWait = True, refresh = opts.refresh, allowHttp = opts.allowHttp, clean = opts.clean })
      else if (arg == "--refresh")
        parseRunArgs(rest, { exitNoWait = opts.exitNoWait, refresh = True, allowHttp = opts.allowHttp, clean = opts.clean })
      else if (arg == "--allow-http")
        parseRunArgs(rest, { exitNoWait = opts.exitNoWait, refresh = opts.refresh, allowHttp = True, clean = opts.clean })
      else if (arg == "--clean")
        parseRunArgs(rest, { exitNoWait = opts.exitNoWait, refresh = opts.refresh, allowHttp = opts.allowHttp, clean = True })
      else Ok((opts, arg, rest))
  }

fun buildCompilerFlags(refresh: Bool, allowHttp: Bool, clean: Bool): List<String> =
  Lst.append(
    Lst.append(
      if (refresh) ["--refresh"] else [],
      if (allowHttp) ["--allow-http"] else []
    ),
    if (clean) ["--clean"] else []
  )

async fun cmdRun(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> = {
  val defaultOpts = { exitNoWait = False, refresh = False, allowHttp = False, clean = False }
  match (parseRunArgs(args, defaultOpts)) {
    Err(msg) => {
      println(msg);
      1
    }
    Ok(parsed) => {
      val opts = parsed.0
      val scriptArg = parsed.1
      val userArgs = parsed.2
      val cwd = getProcess().cwd
      val resolvedOpt = await resolveArg(scriptArg, kestrelRoot, cwd)
      match (resolvedOpt) {
        None => {
          println("kestrel: script not found: ${scriptArg}");
          1
        }
        Some(absPath) => {
          val shouldCompile = opts.clean | await needsCompile(absPath, jvmCache)
          if (shouldCompile) {
            val flags = buildCompilerFlags(opts.refresh, opts.allowHttp, opts.clean)
            val code = await compileScript(absPath, jvmCache, compilerCli, flags)
            if (code != 0) code
            else {
              await runScript(absPath, jvmCache, mavenCache, mavenRuntimeJar, userArgs, opts.exitNoWait);
              0
            }
          } else {
            await runScript(absPath, jvmCache, mavenCache, mavenRuntimeJar, userArgs, opts.exitNoWait);
            0
          }
        }
      }
    }
  }
}

// ── cmd_dis ───────────────────────────────────────────────────────────────────

type DisOpts = { verbose: Bool, codeOnly: Bool, script: Option<String> }

fun parseDisArgs(args: List<String>, opts: DisOpts): Result<DisOpts, String> =
  match (args) {
    [] => Ok(opts)
    arg :: rest =>
      if (arg == "--verbose")
        parseDisArgs(rest, { verbose = True, codeOnly = opts.codeOnly, script = opts.script })
      else if (arg == "--code-only")
        parseDisArgs(rest, { verbose = opts.verbose, codeOnly = True, script = opts.script })
      else if (Str.startsWith("-", arg))
        Err("kestrel: unknown dis flag: ${arg}")
      else
        parseDisArgs(rest, { verbose = opts.verbose, codeOnly = opts.codeOnly, script = Some(arg) })
  }

async fun runDis(
  absPath: String,
  jvmCache: String,
  mavenRuntimeJar: String,
  verbose: Bool,
  codeOnly: Bool
): Task<Int> = {
  val mainClass = Maven.mainClassFor(absPath)
  val classPathArg = "${mavenRuntimeJar}:${jvmCache}"
  val verbArgs = if (verbose) ["-verbose"] else []
  val lineArgs = if (codeOnly) [] else ["-l"]
  val javapArgs = Lst.append(
    Lst.append(["-classpath", classPathArg, "-c"], lineArgs),
    Lst.append(verbArgs, [mainClass])
  )
  match (await runProcessStream("javap", javapArgs)) {
    Ok(code) => code
    Err(ProcessSpawnError(_)) => {
      println("kestrel: javap failed to start");
      1
    }
  }
}

async fun cmdDis(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> = {
  val defaultOpts = { verbose = False, codeOnly = False, script = None }
  match (parseDisArgs(args, defaultOpts)) {
    Err(msg) => {
      println(msg);
      1
    }
    Ok(opts) => match (opts.script) {
      None => {
        println("kestrel dis: script required");
        1
      }
      Some(scriptArg) => {
        val resolvedOpt = await resolveScript(scriptArg, getProcess().cwd)
        match (resolvedOpt) {
          None => {
            println("kestrel: script not found: ${scriptArg}");
            1
          }
          Some(absPath) => {
            val shouldCompile = await needsCompile(absPath, jvmCache)
            if (shouldCompile) {
              val code = await compileScript(absPath, jvmCache, compilerCli, [])
              if (code != 0) code
              else await runDis(absPath, jvmCache, mavenRuntimeJar, opts.verbose, opts.codeOnly)
            } else
              await runDis(absPath, jvmCache, mavenRuntimeJar, opts.verbose, opts.codeOnly)
          }
        }
      }
    }
  }
}

// ── cmd_build ─────────────────────────────────────────────────────────────────

// Build the TypeScript compiler and JVM runtime from source.
async fun buildCompilerAndRuntime(kestrelRoot: String, mavenRuntimeJar: String): Task<Int> = {
  val compilerDir = "${kestrelRoot}/compiler"
  val npmResult = await runProcessStream("npm", ["--prefix", compilerDir, "run", "build"])
  val npmCode = match (npmResult) {
    Ok(c) => c
    Err(ProcessSpawnError(_)) => {
      println("kestrel build: npm failed to start");
      1
    }
  }
  if (npmCode != 0) {
    println("kestrel build: compiler build failed");
    npmCode
  } else {
    val runtimeDir = "${kestrelRoot}/runtime/jvm"
    val buildResult = await runProcessStream("bash", ["-c", "cd ${runtimeDir} && bash build.sh"])
    val buildCode = match (buildResult) {
      Ok(c) => c
      Err(ProcessSpawnError(_)) => {
        println("kestrel build: JVM runtime build failed");
        1
      }
    }
    if (buildCode != 0) {
      println("kestrel build: JVM runtime build failed");
      buildCode
    } else {
      val runtimeJarSrc = "${kestrelRoot}/runtime/jvm/kestrel-runtime.jar"
      val mavenDir = Path.dirname(mavenRuntimeJar)
      val _ = await Fs.mkdirAll(mavenDir)
      val cpResult = await runProcessStream("cp", [runtimeJarSrc, mavenRuntimeJar])
      match (cpResult) {
        Ok(c) => c
        Err(ProcessSpawnError(_)) => {
          println("kestrel build: failed to install runtime JAR");
          1
        }
      }
    }
  }
}

fun parseBuildFlags(remaining: List<String>, refresh: Bool, allowHttp: Bool, clean: Bool): Result<(Bool, Bool, Bool, String), String> =
  match (remaining) {
    [] => Err("kestrel build: script path required after flags")
    a :: rest =>
      if (a == "--refresh") parseBuildFlags(rest, True, allowHttp, clean)
      else if (a == "--allow-http") parseBuildFlags(rest, refresh, True, clean)
      else if (a == "--clean") parseBuildFlags(rest, refresh, allowHttp, True)
      else Ok((refresh, allowHttp, clean, a))
  }

async fun cmdBuild(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> =
  match (args) {
    [] => await buildCompilerAndRuntime(kestrelRoot, mavenRuntimeJar)
    _ =>
      match (parseBuildFlags(args, False, False, False)) {
        Err(msg) => {
          println(msg);
          1
        }
        Ok(parsed) => {
          val refresh = parsed.0
          val allowHttp = parsed.1
          val clean = parsed.2
          val scriptArg = parsed.3
          val resolvedOpt = await resolveScript(scriptArg, getProcess().cwd)
          match (resolvedOpt) {
            None => {
              println("kestrel: script not found: ${scriptArg}");
              1
            }
            Some(absPath) => {
              val flags = buildCompilerFlags(refresh, allowHttp, clean)
              val code = await compileScript(absPath, jvmCache, compilerCli, flags)
              if (code != 0) code
              else {
                println("Built ${jvmCache} (JVM)");
                0
              }
            }
          }
        }
      }
  }

// ── cmd_status ────────────────────────────────────────────────────────────────

async fun cmdStatus(kestrelRoot: String, jvmCache: String): Task<Int> = {
  val selfhost = await isSelfhostReady(kestrelRoot, jvmCache)
  if (selfhost) {
    println("compiler mode: self-hosted");
    println("  classes: ${jvmCache}");
    0
  } else {
    println("compiler mode: bootstrap-required");
    println("hint: run ./scripts/build-bootstrap-jar.sh && ./kestrel bootstrap");
    0
  }
}

// ── cmd_bootstrap ─────────────────────────────────────────────────────────────

async fun cmdBootstrap(kestrelRoot: String, jvmCache: String, mavenCache: String): Task<Int> = {
  val mavenBootstrapJar = "${mavenCache}/lang/kestrel/compile/1.0/compile-1.0.jar"
  val jvmCacheAbs = if (Path.isAbsolute(jvmCache)) jvmCache else Path.resolve(getProcess().cwd, jvmCache)
  val _ = await Fs.mkdirAll(jvmCacheAbs)
  val jarExists = await Fs.fileExists(mavenBootstrapJar)
  if (!jarExists) {
    println("kestrel bootstrap: missing bootstrap compiler JAR: ${mavenBootstrapJar}");
    println("kestrel bootstrap: run ./scripts/build-bootstrap-jar.sh");
    1
  } else {
    val extractResult = await runProcessStream("bash", ["-c", "cd ${jvmCacheAbs} && jar xf ${mavenBootstrapJar}"])
    val extractCode = match (extractResult) {
      Ok(c) => c
      Err(ProcessSpawnError(_)) => {
        println("kestrel bootstrap: failed to extract bootstrap JAR");
        1
      }
    }
    if (extractCode != 0) {
      println("kestrel bootstrap: failed to extract bootstrap JAR");
      extractCode
    } else {
      val ready = await isSelfhostReady(kestrelRoot, jvmCacheAbs)
      if (!ready) {
        println("kestrel bootstrap: Cli_entry.class not found after extraction");
        1
      } else {
        println("kestrel bootstrap: self-hosted compiler classes installed successfully");
        println("  source jar: ${mavenBootstrapJar}");
        println("  output classes: ${jvmCacheAbs}");
        0
      }
    }
  }
}

// ── cmd_test ──────────────────────────────────────────────────────────────────

async fun cmdTest(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> = {
  val testScript = "${kestrelRoot}/stdlib/kestrel/tools/test.ks"
  val exists = await Fs.fileExists(testScript)
  if (!exists) {
    println("kestrel test: test runner not found: ${testScript}");
    1
  } else {
    val shouldCompile = await needsCompile(testScript, jvmCache)
    if (shouldCompile) {
      val code = await compileScript(testScript, jvmCache, compilerCli, [])
      if (code != 0) code
      else {
        await runScript(testScript, jvmCache, mavenCache, mavenRuntimeJar, args, True);
        0
      }
    } else {
      await runScript(testScript, jvmCache, mavenCache, mavenRuntimeJar, args, True);
      0
    }
  }
}

// ── cmd_fmt ───────────────────────────────────────────────────────────────────

async fun cmdFmt(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> = {
  val fmtScript = "${kestrelRoot}/stdlib/kestrel/tools/format.ks"
  val exists = await Fs.fileExists(fmtScript)
  if (!exists) {
    println("kestrel fmt: formatter not found: ${fmtScript}");
    1
  } else {
    val shouldCompile = await needsCompile(fmtScript, jvmCache)
    if (shouldCompile) {
      val code = await compileScript(fmtScript, jvmCache, compilerCli, [])
      if (code != 0) code
      else {
        await runScript(fmtScript, jvmCache, mavenCache, mavenRuntimeJar, args, False);
        0
      }
    } else {
      await runScript(fmtScript, jvmCache, mavenCache, mavenRuntimeJar, args, False);
      0
    }
  }
}

// ── cmd_doc ───────────────────────────────────────────────────────────────────

async fun cmdDoc(
  args: List<String>,
  kestrelRoot: String,
  jvmCache: String,
  mavenCache: String,
  mavenRuntimeJar: String,
  compilerCli: String
): Task<Int> = {
  val docScript = "${kestrelRoot}/stdlib/kestrel/tools/doc.ks"
  val exists = await Fs.fileExists(docScript)
  if (!exists) {
    println("kestrel doc: doc browser not found: ${docScript}");
    1
  } else {
    val shouldCompile = await needsCompile(docScript, jvmCache)
    if (shouldCompile) {
      val code = await compileScript(docScript, jvmCache, compilerCli, [])
      if (code != 0) code
      else {
        await runScript(docScript, jvmCache, mavenCache, mavenRuntimeJar, args, False);
        0
      }
    } else {
      await runScript(docScript, jvmCache, mavenCache, mavenRuntimeJar, args, False);
      0
    }
  }
}

// ── cmd_lock ──────────────────────────────────────────────────────────────────

fun cmdLock(): Int = {
  println("kestrel lock: delegated to self-hosted CLI scaffold when available");
  0
}

// ── cmd_ts_compile ────────────────────────────────────────────────────────────

// Internal command: invoke the TypeScript compiler directly (gate-flagged).
async fun cmdTsCompile(args: List<String>, compilerCli: String): Task<Int> =
  match (args) {
    [] => {
      println("kestrel __ts-compile: usage: kestrel __ts-compile <entry.ks> <out-dir> [compiler-args...]");
      1
    }
    entry :: rest => match (rest) {
      [] => {
        println("kestrel __ts-compile: out-dir required");
        1
      }
      outDir :: flags => await compileScript(entry, outDir, compilerCli, flags)
    }
  }

// ── usage ─────────────────────────────────────────────────────────────────────

fun usage(): String =
  Str.concat([
    "Usage: kestrel <command> [options]\n",
    "  run   [--exit-wait|--exit-no-wait] <script[.ks]> [args...]  Compile if needed, then execute on JVM\n",
    "  dis   [--verbose|--code-only] <script[.ks]>  Compile if needed, then disassemble JVM bytecode\n",
    "  build [script.ks]  Build compiler and JVM runtime; optionally compile script\n",
    "  bootstrap  Build self-hosted compiler classes from bootstrap compiler JAR\n",
    "  status  Show compiler mode and bootstrap provenance state\n",
    "  test  [--verbose|--summary] [--clean] [--refresh] [--allow-http] [files...]   Run unit tests on JVM\n",
    "  fmt   [--check] [--stdin] [files-or-dirs...]  Format Kestrel source files\n",
    "  doc   [--port PORT] [--project-root PATH]  Start the documentation browser\n",
    "  lock  <lockfile>  Update URL lockfile"
  ])

// ── main ──────────────────────────────────────────────────────────────────────

export async fun main(allArgs: List<String>): Task<Unit> = {
  val kestrelRoot = envOr("KESTREL_ROOT", ".")
  val home = envOr("HOME", ".")
  val jvmCache = envOr("KESTREL_JVM_CACHE", "${home}/.kestrel/jvm")
  val mavenCache = envOr("KESTREL_MAVEN_CACHE", "${home}/.kestrel/maven")
  val mavenRuntimeJar = "${mavenCache}/lang/kestrel/runtime/1.0/runtime-1.0.jar"
  val compilerCli = "${kestrelRoot}/compiler/dist/cli.js"

  val code =
    match (allArgs) {
      [] => {
        println(usage());
        1
      }
      cmd :: rest =>
        if (cmd == "run") await cmdRun(rest, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "dis") await cmdDis(rest, kestrelRoot, jvmCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "build") await cmdBuild(rest, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "bootstrap") await cmdBootstrap(kestrelRoot, jvmCache, mavenCache)
        else if (cmd == "status") await cmdStatus(kestrelRoot, jvmCache)
        else if (cmd == "test") await cmdTest(rest, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "fmt") await cmdFmt(rest, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "doc") await cmdDoc(rest, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
        else if (cmd == "__ts-compile") await cmdTsCompile(rest, compilerCli)
        else if (cmd == "lock") cmdLock()
        else {
          // Implicit run: when first arg is a .ks file (shebang support)
          if (Str.endsWith(".ks", cmd)) await cmdRun(allArgs, kestrelRoot, jvmCache, mavenCache, mavenRuntimeJar, compilerCli)
          else {
            println("kestrel: unknown command: ${cmd}\n${usage()}");
            1
          }
        }
    }
  exit(code)
}

// ─── Entry point ─────────────────────────────────────────────────────────────

main(getProcess().args)
