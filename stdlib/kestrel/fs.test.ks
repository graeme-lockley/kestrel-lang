import { Suite, group, eq, isTrue } from "kestrel:test"
import { NotFound, PermissionDenied, IoError } from "kestrel:fs"
import * as Fs from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Process from "kestrel:process"
import * as Str from "kestrel:string"

fun entryContains(entries: List<String>, needle: String): Bool =
  Lst.any(entries, (e: String) => Str.contains(needle, e))

async fun readViaAwait(path: String): Task<Result<String, Fs.FsError>> = {
  val t = await Fs.readText(path);
  t
}

export async fun run(s: Suite): Task<Unit> = {
  group(s, "fs", (s1: Suite) => {
    val cwd = Process.getProcess().cwd;

    group(s1, "readText", (sg: Suite) => {
      val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
      val t = await Fs.readText(okPath);
      val text = match (t) {
        Ok(contents) => contents,
        Err(_) => ""
      };
      eq(sg, "fixture contents", text, "hello fixture\n");
    });

    group(s1, "readText missing", (sg: Suite) => {
      val bad = "${cwd}/tests/fixtures/fs/__missing__.no_such";
      val isNotFound =
        match (await Fs.readText(bad)) {
          Err(NotFound) => True,
          _ => False
        };
      isTrue(sg, "returns Err(NotFound)", isNotFound)
    });

    group(s1, "readText directory", (sg: Suite) => {
      val dirPath = "${cwd}/tests/fixtures/fs/list_sample";
      val isIoError =
        match (await Fs.readText(dirPath)) {
          Err(IoError(_)) => True,
          _ => False
        };
      isTrue(sg, "returns Err(IoError)", isIoError)
    });

    group(s1, "readText permission pattern", (sg: Suite) => {
      val synthetic = Err(PermissionDenied);
      val matches =
        match (synthetic) {
          Err(PermissionDenied) => True,
          _ => False
        };
      isTrue(sg, "Err(PermissionDenied) match works", matches)
    });

    group(s1, "writeText readText roundtrip", (sg: Suite) => {
      val path = "${cwd}/tests/fixtures/fs/tmp_write_roundtrip.txt";
      val writeOk =
        match (await Fs.writeText(path, "roundtrip\n")) {
          Ok(_) => True,
          _ => False
        };
      isTrue(sg, "write ok", writeOk);
      val text =
        match (await Fs.readText(path)) {
          Ok(contents) => contents,
          Err(_) => ""
        };
      eq(sg, "read back", text, "roundtrip\n");
    });

    group(s1, "listDir", (sg: Suite) => {
      val dir = "${cwd}/tests/fixtures/fs/list_sample";
      val entries =
        match (await Fs.listDir(dir)) {
          Ok(v) => v,
          Err(_) => []
        };
      eq(sg, "entry count", Lst.length(entries), 2);
      isTrue(sg, "has a.txt", entryContains(entries, "a.txt"));
      isTrue(sg, "has b.txt", entryContains(entries, "b.txt"));
      isTrue(sg, "tab file suffix", entryContains(entries, "\tfile"));
    });

    group(s1, "listDir missing", (sg: Suite) => {
      val missing = await Fs.listDir("${cwd}/tests/fixtures/fs/__nope_dir_missing__");
      val isNotFound =
        match (missing) {
          Err(NotFound) => True,
          _ => False
        };
      isTrue(sg, "returns Err(NotFound)", isNotFound)
    });

    group(s1, "readViaAwait helper", (sg: Suite) => {
      val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
      val t = await readViaAwait(okPath);
      val text =
        match (t) {
          Ok(contents) => contents,
          Err(_) => ""
        };
      eq(sg, "helper contents", text, "hello fixture\n");
    });
  });
  ()
}
