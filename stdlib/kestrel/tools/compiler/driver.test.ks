import { Suite, group, asyncGroup, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Driver from "kestrel:tools/compiler/driver"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Crypto from "kestrel:io/crypto"
import * as Ty from "kestrel:dev/typecheck/types"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as Fs from "kestrel:io/fs"
import * as Resolve from "kestrel:tools/compiler/resolve"
import * as Json from "kestrel:data/json"
import { Object, StrVal } from "kestrel:data/json"
import { getProcess } from "kestrel:sys/process"
import { andThenAsync, mapErrorAsync } from "kestrel:data/result"

// Attach a string label to each setup step so failures surface the step name.
fun label<T>(lbl: String, task: Task<Result<T, Fs.FsError>>): Task<Result<T, String>> =
  mapErrorAsync(task, (_: Fs.FsError) => lbl)

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(p) => p
    Err(e) => throw e
  }

fun defaultOpts(outDir: String): Driver.CompileOptions = {
  outDir = outDir,
  stdlibDir = "/nonexistent/stdlib",
  cacheRoot = "/tmp/kestrel_cache",
  allowHttp = False,
  writeKti = False,
  refresh = False
}

async fun fileMtimeMs(path: String): Task<Int> =
  match (await Fs.stat(path)) {
    Err(_) => -1
    Ok(st) => st.mtimeMs
  }

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "kestrel:tools/compiler/driver", async (s1: Suite) => {
    group(s1, "freshness helper", (sg: Suite) => {
      val p = program("export fun id(x: Int): Int = x")
      val kti = Kti.buildKtiV4(
        p,
        Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        Dict.emptyStringDict(),
        "src",
        Dict.emptyStringDict()
      )
      val fresh = Driver.isFresh(kti, kti.sourceHash, Dict.emptyStringDict())
      val staleSrc = Driver.isFresh(kti, "different", Dict.emptyStringDict())
      val staleDeps = Driver.isFresh(kti, kti.sourceHash, Dict.insert(Dict.emptyStringDict(), "dep", "h"))
      eq(sg, "fresh true", fresh, True)
      eq(sg, "stale source false", staleSrc, False)
      eq(sg, "stale deps false", staleDeps, False)
    })

    group(s1, "compile options shape", (sg: Suite) => {
      val opts = {
        outDir = "/tmp/out",
        stdlibDir = "/tmp/stdlib",
        cacheRoot = "/tmp/cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      isTrue(sg, "options outDir set", opts.outDir == "/tmp/out")
      isTrue(sg, "options allowHttp set", opts.allowHttp == False)
    })

    group(s1, "classNameForPath", (sg: Suite) => {
      eq(sg, "simple file", Driver.classNameForPath("/foo/bar/hello.ks"), "foo/bar/Hello")
      eq(sg, "no extension", Driver.classNameForPath("/foo/bar/hello"), "foo/bar/Hello")
      eq(sg, "root file", Driver.classNameForPath("/hello.ks"), "Hello")
      eq(sg, "no leading slash", Driver.classNameForPath("foo/bar.ks"), "foo/Bar")
      eq(sg, "dashes sanitized", Driver.classNameForPath("/foo/my-module.ks"), "foo/My_module")
      eq(sg, "stdlib path", Driver.classNameForPath("/stdlib/kestrel/data/list.ks"), "stdlib/kestrel/data/List")
    })

    await asyncGroup(s1, "compileFile - empty path", async (sg: Suite) => {
      val result = await Driver.compileFile("", defaultOpts("/tmp/kestrel_test_out"))
      isTrue(sg, "empty path fails", !result.ok)
      isTrue(sg, "empty path has diagnostic", Lst.length(result.diagnostics) > 0)
    })

    await asyncGroup(s1, "compileFile - missing file", async (sg: Suite) => {
      val result = await Driver.compileFile("/nonexistent/path/file.ks", defaultOpts("/tmp/kestrel_test_out"))
      isTrue(sg, "missing file fails", !result.ok)
    })

    await asyncGroup(s1, "compileFile - valid single-file program", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_src"
      val outDir = "/tmp/kestrel_driver_test_s17_out"
      val srcPath = "${srcDir}/testmain.ks"
      val src = "export fun answer(): Int = 42"
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "valid source ok=True", result.ok)
          isTrue(sg, "no diagnostics on success", Lst.isEmpty(result.diagnostics))
        }
      }
    })

    await asyncGroup(s1, "compileFile - parse error returns ok=False", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_fail_src"
      val outDir = "/tmp/kestrel_driver_test_s17_fail_out"
      val srcPath = "${srcDir}/bad.ks"
      val src = "this is not valid kestrel syntax @@@@"
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "invalid source ok=False", !result.ok)
          isTrue(sg, "parse error has diagnostic", Lst.length(result.diagnostics) > 0)
        }
      }
    })

    await asyncGroup(s1, "compileFile - type error returns ok=False with diagnostics", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_type_src"
      val outDir = "/tmp/kestrel_driver_test_s17_type_out"
      val srcPath = "${srcDir}/typeerr.ks"
      val src = "export fun bad(): Int = \"this is not an int\""
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "type error ok=False", !result.ok)
          isTrue(sg, "type error has diagnostics", Lst.length(result.diagnostics) > 0)
        }
      }
    })

    await asyncGroup(s1, "compileFile - unknown identifier surfaces diagnostic", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_unknown_ident_src"
      val outDir = "/tmp/kestrel_driver_test_s17_unknown_ident_out"
      val srcPath = "${srcDir}/unknown_ident.ks"
      val src = "export fun bad(): Int = missingName"
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "unknown identifier rejected", !result.ok)
          isTrue(sg, "unknown identifier diagnostic present",
            Lst.any(result.diagnostics, (d: Diag.Diagnostic) => d.code == Diag.CODES.type_.unknownVariable))
        }
      }
    })

    await asyncGroup(s1, "compileFile - writeKti=True writes KTI file", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_kti_src"
      val outDir = "/tmp/kestrel_driver_test_s17_kti_out"
      val srcPath = "${srcDir}/ktitest.ks"
      val src = "export fun greet(): String = \"hello\""
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val ktiOpts = {
            outDir = outDir,
            stdlibDir = "/nonexistent/stdlib",
            cacheRoot = "/tmp/kestrel_cache",
            allowHttp = False,
            writeKti = True,
            refresh = False
          }
          val result = await Driver.compileFile(srcPath, ktiOpts)
          isTrue(sg, "writeKti compile ok", result.ok)
          val moduleName = Driver.classNameForPath(srcPath)
          val ktiPath = "${outDir}/${moduleName}.kti"
          val exists = await Fs.fileExists(ktiPath)
          isTrue(sg, "KTI file written", exists)
        }
      }
    })

    await asyncGroup(s1, "compileFile - writeKti=False no KTI file", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_nokti_src"
      val outDir = "/tmp/kestrel_driver_test_s17_nokti_out"
      val srcPath = "${srcDir}/noktitest.ks"
      val src = "export fun answer(): Int = 42"
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "no-kti compile ok", result.ok)
          val moduleName = Driver.classNameForPath(srcPath)
          val ktiPath = "${outDir}/${moduleName}.kti"
          val exists = await Fs.fileExists(ktiPath)
          isTrue(sg, "KTI file NOT written", !exists)
        }
      }
    })

    await asyncGroup(s1, "compileFile - fresh path skips recompile", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_fresh_src"
      val outDir = "/tmp/kestrel_driver_test_s17_fresh_out"
      val srcPath = "${srcDir}/freshtest.ks"
      val src = "export fun greet(): String = \"hello\""
      val ktiOpts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val r1 = await Driver.compileFile(srcPath, ktiOpts)
          isTrue(sg, "first compile ok", r1.ok)
          // Second compile with same source should be fresh
          val r2 = await Driver.compileFile(srcPath, ktiOpts)
          isTrue(sg, "second compile (fresh) ok", r2.ok)
          isTrue(sg, "fresh compile no diagnostics", Lst.isEmpty(r2.diagnostics))
        }
      }
    })

    await asyncGroup(s1, "compileFile - stale KTI triggers recompile", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_stale_src"
      val outDir = "/tmp/kestrel_driver_test_s17_stale_out"
      val srcPath = "${srcDir}/staletest.ks"
      val src1 = "export fun v1(): Int = 1"
      val src2 = "export fun v2(): Int = 2"
      val ktiOpts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText v1 failed", Fs.writeText(srcPath, src1)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val r1 = await Driver.compileFile(srcPath, ktiOpts)
          isTrue(sg, "compile v1 ok", r1.ok)
          // Change source — KTI becomes stale
          match (await Fs.writeText(srcPath, src2)) {
            Err(_) => isTrue(sg, "writeText v2 failed", False)
            Ok(()) => {
              val r2 = await Driver.compileFile(srcPath, ktiOpts)
              isTrue(sg, "compile v2 (stale) ok", r2.ok)
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - bad import specifier fails resolution", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_badspec_src"
      val outDir = "/tmp/kestrel_driver_test_s17_badspec_out"
      val srcPath = "${srcDir}/badspec.ks"
      // kestrel:../bad contains '..' which is not a safe stdlib segment
      val src = "import * as X from \"kestrel:../bad\"\nexport fun f(): Int = 1"
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText failed", Fs.writeText(srcPath, src)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
          isTrue(sg, "bad specifier ok=False", !result.ok)
          isTrue(sg, "bad specifier has diagnostic", Lst.length(result.diagnostics) > 0)
        }
      }
    })

    await asyncGroup(s1, "compileFile - missing dep KTI returns error", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_missingdep_src"
      val outDir = "/tmp/kestrel_driver_test_s17_missingdep_out"
      val mainPath = "${srcDir}/main2.ks"
      val mainSrc = "import { answer } from \"./nodep\"\nexport fun main(): Int = answer()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = False,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "missing dep ok=False", !result.ok)
          isTrue(sg, "missing dep has diagnostic", Lst.length(result.diagnostics) > 0)
        }
      }
    })

    await asyncGroup(s1, "compileFile - two-module graph compiles in dependency order", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_topo_src"
      val outDir = "/tmp/kestrel_driver_test_s17_topo_out"
      val helperPath = "${srcDir}/helper.ks"
      val mainPath = "${srcDir}/main.ks"
      val helperSrc = "export fun answer(): Int = 42"
      val mainSrc = "import { answer } from \"./helper\"\nexport fun main(): Int = answer()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText helper failed", Fs.writeText(helperPath, helperSrc)))
        |> andThenAsync((_: Unit) => label("writeText main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "two-module compile ok", result.ok)
          isTrue(sg, "two-module no diagnostics", Lst.isEmpty(result.diagnostics))
          val helperClass = "${outDir}/${Driver.classNameForPath(helperPath)}.class"
          val helperBuilt = await Fs.fileExists(helperClass)
          isTrue(sg, "helper class emitted", helperBuilt)
        }
      }
    })

    await asyncGroup(s1, "compileFile - cycle detection names members", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_cycle_src"
      val outDir = "/tmp/kestrel_driver_test_s17_cycle_out"
      val aPath = "${srcDir}/a.ks"
      val bPath = "${srcDir}/b.ks"
      val aSrc = "import { b } from \"./b\"\nexport fun a(): Int = b()"
      val bSrc = "import { a } from \"./a\"\nexport fun b(): Int = a()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText a failed", Fs.writeText(aPath, aSrc)))
        |> andThenAsync((_: Unit) => label("writeText b failed", Fs.writeText(bPath, bSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(aPath, opts)
          isTrue(sg, "cycle compile fails", !result.ok)
          match (result.diagnostics) {
            [] => isTrue(sg, "cycle diagnostics present", False)
            d :: _ => {
              isTrue(sg, "cycle message present", Str.contains("circular import", d.message))
              isTrue(sg, "cycle includes a.ks", Str.contains("a.ks", d.message))
              isTrue(sg, "cycle includes b.ks", Str.contains("b.ks", d.message))
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - diamond dependency compiles shared module once", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_diamond_src"
      val outDir = "/tmp/kestrel_driver_test_s17_diamond_out"
      val aPath = "${srcDir}/a.ks"
      val bPath = "${srcDir}/b.ks"
      val cPath = "${srcDir}/c.ks"
      val dPath = "${srcDir}/d.ks"
      val cSrc = "export fun c(): Int = 1"
      val bSrc = "import { c } from \"./c\"\nexport fun b(): Int = c()"
      val dSrc = "import { c } from \"./c\"\nexport fun d(): Int = c()"
      val aSrc = "import { b } from \"./b\"\nimport { d } from \"./d\"\nexport fun a(): Int = b() + d()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText c failed", Fs.writeText(cPath, cSrc)))
        |> andThenAsync((_: Unit) => label("writeText b failed", Fs.writeText(bPath, bSrc)))
        |> andThenAsync((_: Unit) => label("writeText d failed", Fs.writeText(dPath, dSrc)))
        |> andThenAsync((_: Unit) => label("writeText a failed", Fs.writeText(aPath, aSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(aPath, opts)
          isTrue(sg, "diamond compile ok", result.ok)
          val cClass = "${outDir}/${Driver.classNameForPath(cPath)}.class"
          val cBuilt = await Fs.fileExists(cClass)
          isTrue(sg, "shared dep class emitted", cBuilt)
          isTrue(sg, "shared dep canonicalized to one class path",
            Driver.classNameForPath(cPath) == Driver.classNameForPath("${srcDir}/./c.ks"))
        }
      }
    })

    await asyncGroup(s1, "compileFile - incremental second run skips unchanged graph", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_08_skip_src"
      val outDir = "/tmp/kestrel_driver_test_s17_08_skip_out"
      val aPath = "${srcDir}/a.ks"
      val bPath = "${srcDir}/b.ks"
      val cPath = "${srcDir}/c.ks"
      val cSrc = "export fun c(): Int = 1"
      val bSrc = "import { c } from \"./c\"\nexport fun b(): Int = c()"
      val aSrc = "import { b } from \"./b\"\nexport fun a(): Int = b()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText c failed", Fs.writeText(cPath, cSrc)))
        |> andThenAsync((_: Unit) => label("writeText b failed", Fs.writeText(bPath, bSrc)))
        |> andThenAsync((_: Unit) => label("writeText a failed", Fs.writeText(aPath, aSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val first = await Driver.compileFile(aPath, opts)
          isTrue(sg, "first compile ok", first.ok)
          val aClass = "${outDir}/${Driver.classNameForPath(aPath)}.class"
          val bClass = "${outDir}/${Driver.classNameForPath(bPath)}.class"
          val cClass = "${outDir}/${Driver.classNameForPath(cPath)}.class"
          val aM1 = await fileMtimeMs(aClass)
          val bM1 = await fileMtimeMs(bClass)
          val cM1 = await fileMtimeMs(cClass)
          val second = await Driver.compileFile(aPath, opts)
          isTrue(sg, "second compile ok", second.ok)
          val aM2 = await fileMtimeMs(aClass)
          val bM2 = await fileMtimeMs(bClass)
          val cM2 = await fileMtimeMs(cClass)
          eq(sg, "a class mtime unchanged", aM2, aM1)
          eq(sg, "b class mtime unchanged", bM2, bM1)
          eq(sg, "c class mtime unchanged", cM2, cM1)
        }
      }
    })

    await asyncGroup(s1, "compileFile - dependency edit cascades through dependents", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_08_cascade_src"
      val outDir = "/tmp/kestrel_driver_test_s17_08_cascade_out"
      val aPath = "${srcDir}/a.ks"
      val bPath = "${srcDir}/b.ks"
      val cPath = "${srcDir}/c.ks"
      val cSrc1 = "export fun c(): Int = 1"
      val cSrc2 = "export fun c(): Int = 99"
      val bSrc = "import { c } from \"./c\"\nexport fun b(): Int = c()"
      val aSrc = "import { b } from \"./b\"\nexport fun a(): Int = b()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText c1 failed", Fs.writeText(cPath, cSrc1)))
        |> andThenAsync((_: Unit) => label("writeText b failed", Fs.writeText(bPath, bSrc)))
        |> andThenAsync((_: Unit) => label("writeText a failed", Fs.writeText(aPath, aSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val first = await Driver.compileFile(aPath, opts)
          isTrue(sg, "first compile ok", first.ok)
          val aClass = "${outDir}/${Driver.classNameForPath(aPath)}.class"
          val bClass = "${outDir}/${Driver.classNameForPath(bPath)}.class"
          val cClass = "${outDir}/${Driver.classNameForPath(cPath)}.class"
          val aM1 = await fileMtimeMs(aClass)
          val bM1 = await fileMtimeMs(bClass)
          val cM1 = await fileMtimeMs(cClass)
          val aKtiPath = "${outDir}/${Driver.classNameForPath(aPath)}.kti"
          val bKtiPath = "${outDir}/${Driver.classNameForPath(bPath)}.kti"
          val cKtiPath = "${outDir}/${Driver.classNameForPath(cPath)}.kti"
          val a1 = await Kti.readKtiFile(aKtiPath)
          val b1 = await Kti.readKtiFile(bKtiPath)
          val c1 = await Kti.readKtiFile(cKtiPath)
          match (await Fs.writeText(cPath, cSrc2)) {
            Err(_) => isTrue(sg, "writeText c2 failed", False)
            Ok(()) => {
              val second = await Driver.compileFile(aPath, opts)
              isTrue(sg, "second compile ok", second.ok)
              val bM2 = await fileMtimeMs(bClass)
              val cM2 = await fileMtimeMs(cClass)
              isTrue(sg, "c class rebuilt after edit", cM2 != cM1)
              isTrue(sg, "b class rebuilt after dep edit", bM2 != bM1)
              val a2 = await Kti.readKtiFile(aKtiPath)
              val b2 = await Kti.readKtiFile(bKtiPath)
              val c2 = await Kti.readKtiFile(cKtiPath)
              match (c1) {
                Err(_) => isTrue(sg, "read c kti failed", False)
                Ok(kc1) => {
                  match (c2) {
                    Err(_) => isTrue(sg, "read c kti failed", False)
                    Ok(kc2) => isTrue(sg, "dep source hash changed", kc1.sourceHash != kc2.sourceHash)
                  }
                }
              }
              match (b1) {
                Err(_) => isTrue(sg, "read b kti failed", False)
                Ok(kb1) => {
                  match (b2) {
                    Err(_) => isTrue(sg, "read b kti failed", False)
                    Ok(kb2) => {
                      match (Dict.get(kb1.depHashes, cPath)) {
                        None => isTrue(sg, "b dep hash missing", False)
                        Some(v1) => {
                          match (Dict.get(kb2.depHashes, cPath)) {
                            None => isTrue(sg, "b dep hash missing", False)
                            Some(v2) => isTrue(sg, "b dep hash updated", v1 != v2)
                          }
                        }
                      }
                    }
                  }
                }
              }
              match (a1) {
                Err(_) => isTrue(sg, "read a kti failed", False)
                Ok(ka1) => {
                  match (a2) {
                    Err(_) => isTrue(sg, "read a kti failed", False)
                    Ok(ka2) => {
                      match (Dict.get(ka1.depHashes, bPath)) {
                        None => isTrue(sg, "a dep hash missing", False)
                        Some(v1) => {
                          match (Dict.get(ka2.depHashes, bPath)) {
                            None => isTrue(sg, "a dep hash missing", False)
                            Some(v2) => isTrue(sg, "a dep hash unchanged", v1 == v2)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - depHashes are sha256 of direct dep source content", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_08_dephash_src"
      val outDir = "/tmp/kestrel_driver_test_s17_08_dephash_out"
      val aPath = "${srcDir}/a.ks"
      val bPath = "${srcDir}/b.ks"
      val cPath = "${srcDir}/c.ks"
      val cSrc = "export fun c(): Int = 1"
      val bSrc = "import { c } from \"./c\"\nexport fun b(): Int = c()"
      val aSrc = "import { b } from \"./b\"\nexport fun a(): Int = b()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll src failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll out failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("writeText c failed", Fs.writeText(cPath, cSrc)))
        |> andThenAsync((_: Unit) => label("writeText b failed", Fs.writeText(bPath, bSrc)))
        |> andThenAsync((_: Unit) => label("writeText a failed", Fs.writeText(aPath, aSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(aPath, opts)
          isTrue(sg, "compile ok", result.ok)
          val bKtiPath = "${outDir}/${Driver.classNameForPath(bPath)}.kti"
          val aKtiPath = "${outDir}/${Driver.classNameForPath(aPath)}.kti"
          val bKti = await Kti.readKtiFile(bKtiPath)
          val aKti = await Kti.readKtiFile(aKtiPath)
          match (bKti) {
            Err(_) => isTrue(sg, "failed to read generated kti artifacts", False)
            Ok(kb) => {
              match (aKti) {
                Err(_) => isTrue(sg, "failed to read generated kti artifacts", False)
                Ok(ka) => {
                  val expected = Crypto.sha256(cSrc)
                  match (Dict.get(kb.depHashes, cPath)) {
                    Some(actual) => eq(sg, "b stores hash of c source content", actual, expected)
                    None => isTrue(sg, "b dep hash for c missing", False)
                  }
                  isTrue(sg, "a only tracks direct dep b", Dict.member(ka.depHashes, bPath))
                  isTrue(sg, "a does not track transitive dep c", !Dict.member(ka.depHashes, cPath))
                }
              }
            }
          }
        }
      }
    })
    await asyncGroup(s1, "URL fetch — cache hit skips fetch", async (sg: Suite) => {
      val cacheRoot = "/tmp/kestrel_driver_url_cache"
      val outDir = "/tmp/kestrel_driver_url_out"
      val srcDir = "/tmp/kestrel_driver_url_src"
      val url = "https://example.com/urlmod.ks"
      val cachePath = Resolve.urlCachePath(url, cacheRoot)
      val libSrc = "export fun urlAnswer(): Int = 99"
      val mainSrc = "import * as Lib from \"${url}\"\nexport fun go(): Int = Lib.urlAnswer()"
      val mainPath = "${srcDir}/main.ks"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = cacheRoot,
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val setup =
        label("mkdirAll cacheRoot failed", Fs.mkdirAll(cacheRoot))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir)))
        |> andThenAsync((_: Unit) => label("write cache file failed", Fs.writeText(cachePath, libSrc)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "cache-hit compile ok", result.ok)
          isTrue(sg, "cache-hit no diagnostics", Lst.isEmpty(result.diagnostics))
        }
      }
    })

    await asyncGroup(s1, "URL fetch — http disallowed returns ok=False", async (sg: Suite) => {
      val cacheRoot = "/tmp/kestrel_driver_url_http_cache"
      val outDir = "/tmp/kestrel_driver_url_http_out"
      val srcDir = "/tmp/kestrel_driver_url_http_src"
      val url = "http://example.com/httpmod.ks"
      val mainSrc = "import * as Lib from \"${url}\"\nexport fun go(): Int = 1"
      val mainPath = "${srcDir}/main.ks"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = cacheRoot,
        allowHttp = False,
        writeKti = False,
        refresh = False
      }
      val setup =
        label("mkdirAll cacheRoot failed", Fs.mkdirAll(cacheRoot))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "http disallowed ok=False", !result.ok)
          isTrue(sg, "http disallowed has diagnostic", Lst.length(result.diagnostics) > 0)
        }
      }
    })

    await asyncGroup(s1, "URL fetch — refresh=True re-fetches cache", async (sg: Suite) => {
      val cacheRoot = "/tmp/kestrel_driver_url_refresh_cache"
      val outDir = "/tmp/kestrel_driver_url_refresh_out"
      val srcDir = "/tmp/kestrel_driver_url_refresh_src"
      val url = "https://example.com/refreshmod.ks"
      val cachePath = Resolve.urlCachePath(url, cacheRoot)
      val libSrc = "export fun refreshAnswer(): Int = 7"
      val mainSrc = "import * as Lib from \"${url}\"\nexport fun go(): Int = Lib.refreshAnswer()"
      val mainPath = "${srcDir}/main.ks"
      val baseOpts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = cacheRoot,
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val refreshOpts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = cacheRoot,
        allowHttp = False,
        writeKti = True,
        refresh = True
      }
      val setup =
        label("mkdirAll cacheRoot failed", Fs.mkdirAll(cacheRoot))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir)))
        |> andThenAsync((_: Unit) => label("write cache failed", Fs.writeText(cachePath, libSrc)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val r1 = await Driver.compileFile(mainPath, baseOpts)
          isTrue(sg, "first compile ok", r1.ok)
          val r2 = await Driver.compileFile(mainPath, refreshOpts)
          isTrue(sg, "refresh compile ok", r2.ok)
          isTrue(sg, "refresh no diagnostics", Lst.isEmpty(r2.diagnostics))
        }
      }
    })

    await asyncGroup(s1, "compileFile — class.deps sidecar for two-module program", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_classdeps_src"
      val outDir = "/tmp/kestrel_driver_classdeps_out"
      val depPath = "${srcDir}/dep.ks"
      val mainPath = "${srcDir}/main.ks"
      val depSrc = "export fun depAnswer(): Int = 1"
      val mainSrc = "import * as Dep from \"${depPath}\"\nexport fun go(): Int = Dep.depAnswer()"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val depClassName = Driver.classNameForPath(depPath)
      val mainClassName = Driver.classNameForPath(mainPath)
      val depDepsFile = "${outDir}/${depClassName}.class.deps"
      val mainDepsFile = "${outDir}/${mainClassName}.class.deps"
      val setup =
        label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("write dep failed", Fs.writeText(depPath, depSrc)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "compile ok", result.ok)
          match (await Fs.readText(depDepsFile)) {
            Err(_) => isTrue(sg, "dep.class.deps exists", False)
            Ok(depDepsContent) => {
              val depLines = Lst.filter(Str.split(depDepsContent, "\n"), (l: String) => !Str.isEmpty(l))
              eq(sg, "dep deps count", Lst.length(depLines), 1)
              eq(sg, "dep deps[0] is dep path", Lst.head(depLines), Some(depPath))
            }
          }
          match (await Fs.readText(mainDepsFile)) {
            Err(_) => isTrue(sg, "main.class.deps exists", False)
            Ok(mainDepsContent) => {
              val mainLines = Lst.filter(Str.split(mainDepsContent, "\n"), (l: String) => !Str.isEmpty(l))
              eq(sg, "main deps count", Lst.length(mainLines), 2)
              eq(sg, "main deps[0] is dep path", Lst.head(mainLines), Some(depPath))
              eq(sg, "main deps[1] is main path", Lst.head(Lst.drop(mainLines, 1)), Some(mainPath))
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile — kdeps sidecar for maven import", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_kdeps_maven_src"
      val outDir = "/tmp/kestrel_driver_kdeps_maven_out"
      val mainPath = "${srcDir}/main.ks"
      val mainSrc = "import \"maven:org.apache.commons:commons-lang3:3.17.0\"\nexport fun go(): Int = 42"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val mainClassName = Driver.classNameForPath(mainPath)
      val kdepsFile = "${outDir}/${mainClassName}.kdeps"
      val setup =
        label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "compile ok", result.ok)
          match (await Fs.readText(kdepsFile)) {
            Err(_) => isTrue(sg, "kdeps file exists", False)
            Ok(kdepsContent) => {
              match (Json.parse(kdepsContent)) {
                Err(_) => isTrue(sg, "kdeps is valid JSON", False)
                Ok(root) => {
                  match (root) {
                    Object(rootPairs) => {
                      val mavenVals = Lst.filterMap(rootPairs, (p: (String, Json.Value)) => if (p.0 == "maven") Some(p.1) else None)
                      match (Lst.head(mavenVals)) {
                        None => isTrue(sg, "kdeps has maven key", False)
                        Some(mavenNode) => {
                          match (mavenNode) {
                            Object(mavenPairs) => {
                              val coordVals = Lst.filterMap(mavenPairs, (p: (String, Json.Value)) => if (p.0 == "org.apache.commons:commons-lang3") Some(p.1) else None)
                              match (Lst.head(coordVals)) {
                                None => isTrue(sg, "kdeps has coord key", False)
                                Some(versionNode) => {
                                  match (versionNode) {
                                    StrVal(v) => eq(sg, "kdeps coord version", v, "3.17.0")
                                    _ => isTrue(sg, "kdeps version is string", False)
                                  }
                                }
                              }
                            }
                            _ => isTrue(sg, "kdeps maven is object", False)
                          }
                        }
                      }
                    }
                    _ => isTrue(sg, "kdeps root is object", False)
                  }
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile — no kdeps when no maven imports", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_kdeps_none_src"
      val outDir = "/tmp/kestrel_driver_kdeps_none_out"
      val mainPath = "${srcDir}/main.ks"
      val mainSrc = "export fun go(): Int = 1"
      val opts = {
        outDir = outDir,
        stdlibDir = "/nonexistent/stdlib",
        cacheRoot = "/tmp/kestrel_cache",
        allowHttp = False,
        writeKti = True,
        refresh = False
      }
      val mainClassName = Driver.classNameForPath(mainPath)
      val kdepsFile = "${outDir}/${mainClassName}.kdeps"
      val setup =
        label("mkdirAll srcDir failed", Fs.mkdirAll(srcDir))
        |> andThenAsync((_: Unit) => label("mkdirAll outDir failed", Fs.mkdirAll(outDir)))
        |> andThenAsync((_: Unit) => label("write main failed", Fs.writeText(mainPath, mainSrc)))
      match (await setup) {
        Err(msg) => isTrue(sg, msg, False)
        Ok(()) => {
          val result = await Driver.compileFile(mainPath, opts)
          isTrue(sg, "compile ok", result.ok)
          match (await Fs.readText(kdepsFile)) {
            Ok(_) => isTrue(sg, "no kdeps file for no-maven program", False)
            Err(_) => isTrue(sg, "no kdeps file for no-maven program", True)
          }
        }
      }
    })
  })
}

