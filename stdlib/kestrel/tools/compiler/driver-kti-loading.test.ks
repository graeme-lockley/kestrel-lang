import { Suite, asyncGroup, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"
import * as Driver from "kestrel:tools/compiler/driver"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as Fs from "kestrel:io/fs"

fun ktiOpts(outDir: String): Driver.CompileOptions = {
  outDir = outDir,
  stdlibDir = "/nonexistent/stdlib",
  cacheRoot = "/tmp/kestrel_cache",
  allowHttp = False,
  writeKti = True,
  refresh = False
}

export async fun run(s: Suite): Task<Unit> = {
  await asyncGroup(s, "kestrel:tools/compiler/driver KTI loading", async (sg: Suite) => {
    await asyncGroup(sg, "compileFile - named import dep KTI loads", async (s1: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_namedep_src"
      val outDir = "/tmp/kestrel_driver_test_s17_namedep_out"
      val depPath = "${srcDir}/dep.ks"
      val mainPath = "${srcDir}/main.ks"
      val depSrc = "export fun answer(): Int = 42"
      val mainSrc = "import { answer } from \"./dep\"\nexport fun main(): Int = answer()"
      val opts = ktiOpts(outDir)
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(s1, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(s1, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(depPath, depSrc)) {
                Err(_) => isTrue(s1, "writeText dep failed", False)
                Ok(()) => {
                  val depResult = await Driver.compileFile(depPath, opts)
                  isTrue(s1, "dep compile ok", depResult.ok)
                  match (await Fs.writeText(mainPath, mainSrc)) {
                    Err(_) => isTrue(s1, "writeText main failed", False)
                    Ok(()) => {
                      val mainResult = await Driver.compileFile(mainPath, opts)
                      isTrue(s1, "main compile ok", mainResult.ok)
                      isTrue(s1, "main no diagnostics", Lst.isEmpty(mainResult.diagnostics))
                    }
                  }
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(sg, "compileFile - missing dep KTI returns error", async (s1: Suite) => {
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
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(s1, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(s1, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(mainPath, mainSrc)) {
                Err(_) => isTrue(s1, "writeText main failed", False)
                Ok(()) => {
                  val result = await Driver.compileFile(mainPath, opts)
                  isTrue(s1, "missing dep ok=False", !result.ok)
                  isTrue(s1, "missing dep has diagnostic", Lst.length(result.diagnostics) > 0)
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(sg, "compileFile - namespace import dep KTI loads", async (s1: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_nsdep_src"
      val outDir = "/tmp/kestrel_driver_test_s17_nsdep_out"
      val depPath = "${srcDir}/nsdep.ks"
      val mainPath = "${srcDir}/nsmain.ks"
      val depSrc = "export fun value(): Int = 7"
      val mainSrc = "import * as Ns from \"./nsdep\"\nexport fun main(): Int = Ns.value()"
      val opts = ktiOpts(outDir)
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(s1, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(s1, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(depPath, depSrc)) {
                Err(_) => isTrue(s1, "writeText dep failed", False)
                Ok(()) => {
                  val depResult = await Driver.compileFile(depPath, opts)
                  isTrue(s1, "dep compile ok", depResult.ok)
                  match (await Fs.writeText(mainPath, mainSrc)) {
                    Err(_) => isTrue(s1, "writeText main failed", False)
                    Ok(()) => {
                      val mainResult = await Driver.compileFile(mainPath, opts)
                      isTrue(s1, "ns import compile ok", mainResult.ok)
                      isTrue(s1, "ns import no diagnostics", Lst.isEmpty(mainResult.diagnostics))
                    }
                  }
                }
              }
            }
          }
        }
      }
    });

    await asyncGroup(sg, "compileFile - ADT ctor exhaustiveness via KTI", async (s1: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s1722_adt_src"
      val outDir = "/tmp/kestrel_driver_test_s1722_adt_out"
      val depPath = "${srcDir}/adtdep.ks"
      val okPath = "${srcDir}/adtmain_ok.ks"
      val badPath = "${srcDir}/adtmain_bad.ks"
      val depSrc = "export type Color = Red | Green"
      val okSrc = "import { Color, Red, Green } from \"./adtdep\"\nexport fun f(c: Color): Int = match (c) { Red => 1  Green => 2 }"
      val badSrc = "import { Color, Red, Green } from \"./adtdep\"\nexport fun f(c: Color): Int = match (c) { Red => 1 }"
      val opts = ktiOpts(outDir)
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(s1, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(s1, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(depPath, depSrc)) {
                Err(_) => isTrue(s1, "writeText dep failed", False)
                Ok(()) => {
                  val depResult = await Driver.compileFile(depPath, opts)
                  isTrue(s1, "dep compile ok", depResult.ok);
                  // complete match compiles ok
                  match (await Fs.writeText(okPath, okSrc)) {
                    Err(_) => isTrue(s1, "writeText ok main failed", False)
                    Ok(()) => {
                      val okResult = await Driver.compileFile(okPath, opts)
                      isTrue(s1, "complete match ok", okResult.ok);
                      isTrue(s1, "complete match no diagnostics", Lst.isEmpty(okResult.diagnostics))
                    }
                  };
                  // incomplete match fails with nonExhaustiveMatch
                  match (await Fs.writeText(badPath, badSrc)) {
                    Err(_) => isTrue(s1, "writeText bad main failed", False)
                    Ok(()) => {
                      val badResult = await Driver.compileFile(badPath, opts)
                      isTrue(s1, "incomplete match rejected", !badResult.ok);
                      isTrue(s1, "has nonExhaustiveMatch diag",
                        Lst.any(badResult.diagnostics, (d: Diag.Diagnostic) => d.code == Diag.CODES.type_.nonExhaustiveMatch))
                    }
                  }
                }
              }
            }
          }
        }
      }
    })

    await asyncGroup(sg, "compileFile - missing import codegen meta surfaces unknown identifier diagnostic", async (s1: Suite) => {
      val srcDir = "/tmp/kestrel_driver_test_s17_codegen_diag_src"
      val outDir = "/tmp/kestrel_driver_test_s17_codegen_diag_out"
      val depPath = "${srcDir}/dep.ks"
      val mainPath = "${srcDir}/main.ks"
      val depSrc = "export fun answer(): Int = 42"
      val mainSrc = "import { answer } from \"./dep\"\nexport fun main(): Int = answer()"
      val opts = ktiOpts(outDir)
      match (await Fs.mkdirAll(srcDir)) {
        Err(_) => isTrue(s1, "mkdirAll src failed", False)
        Ok(()) => {
          match (await Fs.mkdirAll(outDir)) {
            Err(_) => isTrue(s1, "mkdirAll out failed", False)
            Ok(()) => {
              match (await Fs.writeText(depPath, depSrc)) {
                Err(_) => isTrue(s1, "writeText dep failed", False)
                Ok(()) => {
                  val depResult = await Driver.compileFile(depPath, opts)
                  isTrue(s1, "dep compile ok", depResult.ok)
                  val depClass = Driver.classNameForPath(depPath)
                  val depKtiPath = "${outDir}/${depClass}.kti"
                  match (await Kti.readKtiFile(depKtiPath)) {
                    Err(_) => isTrue(s1, "read dep kti failed", False)
                    Ok(depKti) => {
                      val strippedMeta: Kti.KtiCodegenMeta = {
                        funArities = Dict.emptyStringDict(),
                        asyncFunNames = [],
                        varNames = [],
                        valOrVarNames = [],
                        adtConstructors = [],
                        exceptionDecls = []
                      }
                      val strippedKti: Kti.KtiV4 = {
                        version = depKti.version,
                        functions = depKti.functions,
                        types = depKti.types,
                        sourceHash = depKti.sourceHash,
                        depHashes = depKti.depHashes,
                        codegenMeta = strippedMeta
                      }
                      match (await Kti.writeKtiFile(depKtiPath, strippedKti)) {
                        Err(_) => isTrue(s1, "write stripped dep kti failed", False)
                        Ok(()) => {
                          match (await Fs.writeText(mainPath, mainSrc)) {
                            Err(_) => isTrue(s1, "writeText main failed", False)
                            Ok(()) => {
                              val result = await Driver.compileFile(mainPath, opts)
                              isTrue(s1, "main compile fails", !result.ok)
                              isTrue(s1, "reports unknown_variable codegen diagnostic",
                                Lst.any(result.diagnostics, (d: Diag.Diagnostic) => d.code == Diag.CODES.type_.unknownVariable))
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