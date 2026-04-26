import { Suite, group, asyncGroup, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Driver from "kestrel:tools/compiler/driver"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Ty from "kestrel:dev/typecheck/types"
import * as Fs from "kestrel:io/fs"
import { getProcess } from "kestrel:sys/process"

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
  writeKti = False
}

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "kestrel:tools/compiler/driver", async (s1: Suite) => {
    group(s1, "freshness helper", (sg: Suite) => {
      val p = program("export fun id(x: Int): Int = x")
      val kti = Kti.buildKtiV4(p, Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)), "src", Dict.emptyStringDict())
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
        writeKti = True
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
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
                  isTrue(sg, "valid source ok=True", result.ok)
                  isTrue(sg, "no diagnostics on success", Lst.isEmpty(result.diagnostics))
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - parse error returns ok=False", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_fail_src"
      val outDir = "/tmp/kestrel_driver_test_s17_fail_out"
      val srcPath = "${srcDir}/bad.ks"
      val src = "this is not valid kestrel syntax @@@@"
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
                  isTrue(sg, "invalid source ok=False", !result.ok)
                  isTrue(sg, "parse error has diagnostic", Lst.length(result.diagnostics) > 0)
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - type error returns ok=False with diagnostics", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_type_src"
      val outDir = "/tmp/kestrel_driver_test_s17_type_out"
      val srcPath = "${srcDir}/typeerr.ks"
      val src = "export fun bad(): Int = \"this is not an int\""
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
                  isTrue(sg, "type error ok=False", !result.ok)
                  isTrue(sg, "type error has diagnostics", Lst.length(result.diagnostics) > 0)
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - writeKti=True writes KTI file", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_kti_src"
      val outDir = "/tmp/kestrel_driver_test_s17_kti_out"
      val srcPath = "${srcDir}/ktitest.ks"
      val src = "export fun greet(): String = \"hello\""
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val ktiOpts = {
                    outDir = outDir,
                    stdlibDir = "/nonexistent/stdlib",
                    cacheRoot = "/tmp/kestrel_cache",
                    allowHttp = False,
                    writeKti = True
                  }
                  val result = await Driver.compileFile(srcPath, ktiOpts)
                  isTrue(sg, "writeKti compile ok", result.ok)
                  val moduleName = Driver.classNameForPath(srcPath)
                  val ktiPath = "${outDir}/${moduleName}.kti"
                  val exists = await Fs.fileExists(ktiPath)
                  isTrue(sg, "KTI file written", exists)
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - writeKti=False no KTI file", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_nokti_src"
      val outDir = "/tmp/kestrel_driver_test_s17_nokti_out"
      val srcPath = "${srcDir}/noktitest.ks"
      val src = "export fun answer(): Int = 42"
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(srcPath, defaultOpts(outDir))
                  isTrue(sg, "no-kti compile ok", result.ok)
                  val moduleName = Driver.classNameForPath(srcPath)
                  val ktiPath = "${outDir}/${moduleName}.kti"
                  val exists = await Fs.fileExists(ktiPath)
                  isTrue(sg, "KTI file NOT written", !exists)
                }
              }
            }
          }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src)) {
                Err(_) => isTrue(sg, "writeText failed", False)
                Ok(()) => {
                  val r1 = await Driver.compileFile(srcPath, ktiOpts)
                  isTrue(sg, "first compile ok", r1.ok)
                  // Second compile with same source should be fresh
                  val r2 = await Driver.compileFile(srcPath, ktiOpts)
                  isTrue(sg, "second compile (fresh) ok", r2.ok)
                  isTrue(sg, "fresh compile no diagnostics", Lst.isEmpty(r2.diagnostics))
                }
              }
            }
          }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(srcPath, src1)) {
                Err(_) => isTrue(sg, "writeText v1 failed", False)
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
            }
          }
        }
      }
    })
  })
}

