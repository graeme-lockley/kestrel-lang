import { Suite, asyncGroup, isTrue } from "kestrel:dev/test"
import * as Lst from "kestrel:data/list"
import * as Driver from "kestrel:tools/compiler/driver"
import * as Fs from "kestrel:io/fs"

fun ktiOpts(outDir: String): Driver.CompileOptions = {
  outDir = outDir,
  stdlibDir = "/nonexistent/stdlib",
  cacheRoot = "/tmp/kestrel_cache",
  allowHttp = False,
  writeKti = True
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
        writeKti = False
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
    })
  })
}