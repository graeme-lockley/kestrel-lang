import { Suite, group, eq, isTrue } from "kestrel:test"
import * as Fs from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Process from "kestrel:process"
import * as Str from "kestrel:string"

fun entryContains(entries: List<String>, needle: String): Bool =
  Lst.any(entries, (e: String) => Str.contains(needle, e))

async fun readViaAwait(path: String): Task<String> = {
  val t = await Fs.readText(path);
  t
}

export async fun run(s: Suite): Task<Unit> = {
  group(s, "fs", (s1: Suite) => {
    val cwd = Process.getProcess().cwd;

    group(s1, "readText", (sg: Suite) => {
      val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
      val t = await Fs.readText(okPath);
      eq(sg, "fixture contents", t, "hello fixture\n");
    });

    group(s1, "readText missing", (sg: Suite) => {
      val bad = "${cwd}/tests/fixtures/fs/__missing__.no_such";
      val caught = try {
        await Fs.readText(bad);
        0
      } catch {
        e => 1
      };
      eq(sg, "exception surfaces", caught, 1);
    });

    group(s1, "readViaAwait helper", (sg: Suite) => {
      val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
      val t = await readViaAwait(okPath);
      eq(sg, "helper contents", t, "hello fixture\n");
    });

    group(s1, "writeText readText roundtrip", (sg: Suite) => {
      val path = "${cwd}/tests/fixtures/fs/tmp_write_roundtrip.txt";
      Fs.writeText(path, "roundtrip\n");
      val t = await Fs.readText(path);
      eq(sg, "read back", t, "roundtrip\n");
    });

    group(s1, "listDir", (sg: Suite) => {
      val dir = "${cwd}/tests/fixtures/fs/list_sample";
      val entries = Fs.listDir(dir);
      isTrue(sg, "has a.txt", entryContains(entries, "a.txt"));
      isTrue(sg, "has b.txt", entryContains(entries, "b.txt"));
      isTrue(sg, "tab file suffix", entryContains(entries, "\tfile"));
    });

    group(s1, "listDir missing", (sg: Suite) => {
      val entries = Fs.listDir("${cwd}/tests/fixtures/fs/__nope_dir_missing__");
      isTrue(sg, "empty", Lst.isEmpty(entries));
    });
  });
  ()
}
