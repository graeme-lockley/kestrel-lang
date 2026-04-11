// Tests for the file-watching primitive in kestrel:io/fs
import { Suite, group, eq, isTrue, isFalse } from "kestrel:dev/test"
import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"
import * as List from "kestrel:data/list"

val tmpDir = "/tmp/kestrel_watch_test"
val watchFile = "${tmpDir}/test.ks"
val subDir = "${tmpDir}/sub"
val subFile = "${subDir}/child.ks"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:io/fs Watcher", (sg: Suite) => {

    // ── Setup ─────────────────────────────────────────────────────────────────
    group(sg, "setup temp directory", (g: Suite) => {
      val r = await Fs.mkdirAll(tmpDir);
      isTrue(g, "mkdirAll ok", match (r) { Ok(_) => True, Err(_) => False })
    });

    // ── watchDir on missing path returns Err ──────────────────────────────────
    group(sg, "watchDir missing path returns Err", (g: Suite) => {
      val r = await Fs.watchDir("/tmp/no_such_dir_kestrel_12345", 200);
      isFalse(g, "is Err", match (r) { Ok(_) => True, Err(_) => False })
    });

    // ── watchDir on existing dir returns Ok ───────────────────────────────────
    group(sg, "watchDir existing dir returns Ok(Watcher)", (g: Suite) => {
      val r = await Fs.watchDir(tmpDir, 300);
      isTrue(g, "is Ok", match (r) { Ok(_) => True, Err(_) => False });
      match (r) {
        Err(_) => ()
        Ok(w) => {
          val _ = await Fs.watcherClose(w);
          ()
        }
      }
    });

    // ── watcherNext returns changed path ──────────────────────────────────────
    group(sg, "watcherNext detects file write", (g: Suite) => {
      val wr = await Fs.watchDir(tmpDir, 300);
      match (wr) {
        Err(_) => isTrue(g, "watcher should open", False)
        Ok(w) => {
          val _ = await Fs.writeText(watchFile, "// hello");
          val paths = await Fs.watcherNext(w);
          val _ = await Fs.watcherClose(w);
          isTrue(g, "paths non-empty", !List.isEmpty(paths));
          isTrue(g, "contains watch file path", List.any(paths, (p: String) => Str.contains("test.ks", p)))
        }
      }
    });

    // ── watcherNext detects sub-directory creation ────────────────────────────
    group(sg, "watcherNext detects child in new subdirectory", (g: Suite) => {
      val wr = await Fs.watchDir(tmpDir, 300);
      match (wr) {
        Err(_) => isTrue(g, "watcher should open", False)
        Ok(w) => {
          val _ = await Fs.mkdirAll(subDir);
          val _ = await Fs.writeText(subFile, "// child");
          val paths = await Fs.watcherNext(w);
          val _ = await Fs.watcherClose(w);
          isTrue(g, "paths non-empty", !List.isEmpty(paths))
        }
      }
    });

    // ── watcherClose: subsequent next returns empty ───────────────────────────
    group(sg, "watcherClose causes next to return empty", (g: Suite) => {
      val wr = await Fs.watchDir(tmpDir, 100);
      match (wr) {
        Err(_) => isTrue(g, "watcher should open", False)
        Ok(w) => {
          val _ = await Fs.watcherClose(w);
          val paths = await Fs.watcherNext(w);
          isTrue(g, "paths empty after close", List.isEmpty(paths))
        }
      }
    })

  })
