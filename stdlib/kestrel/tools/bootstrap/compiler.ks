// kestrel:tools/bootstrap/compiler — compile cli-entry.ks to the JVM class cache.

import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Fs from "kestrel:io/fs"
import { runProcessStream, ProcessSpawnError } from "kestrel:sys/process"

// ─── Paths ────────────────────────────────────────────────────────────────────

export fun runtimeJarPath(rootDir: String): String =
  "${rootDir}/runtime/jvm/kestrel-runtime.jar"

export fun compilerCliPath(rootDir: String): String =
  "${rootDir}/compiler/dist/cli.js"

export fun cliEntryPath(rootDir: String): String =
  "${rootDir}/stdlib/kestrel/tools/compiler/cli-entry.ks"

// ─── Compilation ──────────────────────────────────────────────────────────────

fun isCliEntryClass(p: String): Bool = Str.endsWith("Cli_entry.class", p)
fun isCliMainClass(p: String): Bool  = Str.endsWith("Cli_main.class", p)
fun noExclude(_: String): Bool = False

async fun verifyClasses(jvmCache: String): Task<Int> = {
  val entryFiles = await Fs.collectFiles(jvmCache, isCliEntryClass, noExclude)
  val mainFiles  = await Fs.collectFiles(jvmCache, isCliMainClass,  noExclude)
  if (Lst.isEmpty(entryFiles)) {
    println("kestrel bootstrap: missing Cli_entry.class in ${jvmCache} after compilation");
    1
  } else if (Lst.isEmpty(mainFiles)) {
    println("kestrel bootstrap: missing Cli_main.class in ${jvmCache} after compilation");
    1
  } else {
    println("kestrel bootstrap: self-hosted compiler compiled successfully");
    println("  output classes: ${jvmCache}");
    0
  }
}

/** Compile cli-entry.ks using the node/TypeScript compiler backend.
 *  Returns 0 on success, 1 on failure. */
export async fun compileCliEntry(rootDir: String, jvmCache: String): Task<Int> = {
  val runtimeJar = runtimeJarPath(rootDir)
  val compilerCli = compilerCliPath(rootDir)
  val cliEntry    = cliEntryPath(rootDir)

  val runtimeOk  = await Fs.fileExists(runtimeJar)
  val compilerOk = await Fs.fileExists(compilerCli)

  if (!runtimeOk) {
    println("kestrel bootstrap: missing runtime jar: ${runtimeJar}");
    println("kestrel bootstrap: run ./kestrel build to generate runtime artifacts");
    1
  } else if (!compilerOk) {
    println("kestrel bootstrap: missing TypeScript compiler CLI: ${compilerCli}");
    println("kestrel bootstrap: run cd compiler && npm run build");
    1
  } else {
    val _ = await Fs.mkdirAll(jvmCache);
    val result = await runProcessStream("node", [compilerCli, cliEntry, "--target", "jvm", "-o", jvmCache])
    match (result) {
      Err(ProcessSpawnError(_)) => {
        println("kestrel bootstrap: compilation process error");
        1
      }
      Ok(code) =>
        if (code != 0) {
          println("kestrel bootstrap: compilation failed");
          1
        } else
          await verifyClasses(jvmCache)
    }
  }
}
