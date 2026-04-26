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

async fun fileMtimeMs(path: String): Task<Int> =
  match (await Fs.stat(path)) {
    Err(_) => -1
    Ok(st) => st.mtimeMs
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

    await asyncGroup(s1, "compileFile - bad import specifier fails resolution", async (sg: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_badspec_src"
      val outDir = "/tmp/kestrel_driver_test_s17_badspec_out"
      val srcPath = "${srcDir}/badspec.ks"
      // kestrel:../bad contains '..' which is not a safe stdlib segment
      val src = "import * as X from \"kestrel:../bad\"\nexport fun f(): Int = 1"
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
                  isTrue(sg, "bad specifier ok=False", !result.ok)
                  isTrue(sg, "bad specifier has diagnostic", Lst.length(result.diagnostics) > 0)
                }
              }
            }
          }
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
        writeKti = False
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(mainPath, mainSrc)) {
                Err(_) => isTrue(sg, "writeText main failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(mainPath, opts)
                  isTrue(sg, "missing dep ok=False", !result.ok)
                  isTrue(sg, "missing dep has diagnostic", Lst.length(result.diagnostics) > 0)
                }
              }
            }
          }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(helperPath, helperSrc)) {
                Err(_) => isTrue(sg, "writeText helper failed", False)
                Ok(()) => {
                  match (await Fs.writeText(mainPath, mainSrc)) {
                    Err(_) => isTrue(sg, "writeText main failed", False)
                    Ok(()) => {
                      val result = await Driver.compileFile(mainPath, opts)
                      isTrue(sg, "two-module compile ok", result.ok)
                      isTrue(sg, "two-module no diagnostics", Lst.isEmpty(result.diagnostics))
                      val helperClass = "${outDir}/${Driver.classNameForPath(helperPath)}.class"
                      val helperBuilt = await Fs.fileExists(helperClass)
                      isTrue(sg, "helper class emitted", helperBuilt)
                    }
                  }
                }
              }
            }
          }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(aPath, aSrc)) {
                Err(_) => isTrue(sg, "writeText a failed", False)
                Ok(()) => {
                  match (await Fs.writeText(bPath, bSrc)) {
                    Err(_) => isTrue(sg, "writeText b failed", False)
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
                }
              }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(cPath, cSrc)) {
                Err(_) => isTrue(sg, "writeText c failed", False)
                Ok(()) => {
                  match (await Fs.writeText(bPath, bSrc)) {
                    Err(_) => isTrue(sg, "writeText b failed", False)
                    Ok(()) => {
                      match (await Fs.writeText(dPath, dSrc)) {
                        Err(_) => isTrue(sg, "writeText d failed", False)
                        Ok(()) => {
                          match (await Fs.writeText(aPath, aSrc)) {
                            Err(_) => isTrue(sg, "writeText a failed", False)
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(cPath, cSrc)) {
                Err(_) => isTrue(sg, "writeText c failed", False)
                Ok(()) => {
                  match (await Fs.writeText(bPath, bSrc)) {
                    Err(_) => isTrue(sg, "writeText b failed", False)
                    Ok(()) => {
                      match (await Fs.writeText(aPath, aSrc)) {
                        Err(_) => isTrue(sg, "writeText a failed", False)
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
                    }
                  }
                }
              }
            }
          }
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(cPath, cSrc1)) {
                Err(_) => isTrue(sg, "writeText c1 failed", False)
                Ok(()) => {
                  match (await Fs.writeText(bPath, bSrc)) {
                    Err(_) => isTrue(sg, "writeText b failed", False)
                    Ok(()) => {
                      match (await Fs.writeText(aPath, aSrc)) {
                        Err(_) => isTrue(sg, "writeText a failed", False)
                        Ok(()) => {
                          val first = await Driver.compileFile(aPath, opts)
                          isTrue(sg, "first compile ok", first.ok)
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
                                            Some(v2) => isTrue(sg, "a dep hash updated", v1 != v2)
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
                    }
                  }
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(s1, "compileFile - depHashes are sha256 of direct dep kti content", async (sg: Suite) => {
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
        writeKti = True
      }
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(sg, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(sg, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(cPath, cSrc)) {
                Err(_) => isTrue(sg, "writeText c failed", False)
                Ok(()) => {
                  match (await Fs.writeText(bPath, bSrc)) {
                    Err(_) => isTrue(sg, "writeText b failed", False)
                    Ok(()) => {
                      match (await Fs.writeText(aPath, aSrc)) {
                        Err(_) => isTrue(sg, "writeText a failed", False)
                        Ok(()) => {
                          val result = await Driver.compileFile(aPath, opts)
                          isTrue(sg, "compile ok", result.ok)
                          val bKtiPath = "${outDir}/${Driver.classNameForPath(bPath)}.kti"
                          val cKtiPath = "${outDir}/${Driver.classNameForPath(cPath)}.kti"
                          val aKtiPath = "${outDir}/${Driver.classNameForPath(aPath)}.kti"
                          val bKti = await Kti.readKtiFile(bKtiPath)
                          val aKti = await Kti.readKtiFile(aKtiPath)
                          match (await Fs.readText(cKtiPath)) {
                            Err(_) => isTrue(sg, "failed to read generated kti artifacts", False)
                            Ok(cKtiText) => {
                              match (bKti) {
                                Err(_) => isTrue(sg, "failed to read generated kti artifacts", False)
                                Ok(kb) => {
                                  match (aKti) {
                                    Err(_) => isTrue(sg, "failed to read generated kti artifacts", False)
                                    Ok(ka) => {
                                      val expected = Crypto.sha256(cKtiText)
                                      match (Dict.get(kb.depHashes, cPath)) {
                                        Some(actual) => eq(sg, "b stores hash of c.kti content", actual, expected)
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
  })
}

