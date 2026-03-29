import { Suite, group, eq, isTrue } from "kestrel:test"
import { readText, writeText, listDir } from "kestrel:fs"
import { getProcess } from "kestrel:process"

fun entryContains(entries: List<String>, needle: String): Bool =
  match (entries) {
    [] => False,
    hd :: tl =>
      if (__string_index_of(hd, needle) >= 0) True
      else entryContains(tl, needle)
  }

fun isEmptyList(entries: List<String>): Bool =
  match (entries) {
    [] => True,
    _ => False
  }

export async fun run(s: Suite): Task<Unit> = {
  group(s, "fs", (s1: Suite) => {
    val cwd = getProcess().cwd;

    group(s1, "readText", (sg: Suite) => {
      val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
      val t = await readText(okPath);
      eq(sg, "fixture contents", t, "hello fixture\n");
    });

    group(s1, "readText missing", (sg: Suite) => {
      val bad = "${cwd}/tests/fixtures/fs/__missing__.no_such";
      val t = await readText(bad);
      eq(sg, "empty string", t, "");
    });

    group(s1, "writeText readText roundtrip", (sg: Suite) => {
      val path = "${cwd}/tests/fixtures/fs/tmp_write_roundtrip.txt";
      writeText(path, "roundtrip\n");
      val t = await readText(path);
      eq(sg, "read back", t, "roundtrip\n");
    });

    group(s1, "listDir", (sg: Suite) => {
      val dir = "${cwd}/tests/fixtures/fs/list_sample";
      val entries = listDir(dir);
      isTrue(sg, "has a.txt", entryContains(entries, "a.txt"));
      isTrue(sg, "has b.txt", entryContains(entries, "b.txt"));
      isTrue(sg, "tab file suffix", entryContains(entries, "\tfile"));
    });

    group(s1, "listDir missing", (sg: Suite) => {
      val entries = listDir("${cwd}/tests/fixtures/fs/__nope_dir_missing__");
      eq(sg, "empty", isEmptyList(entries), True);
    });
  });
  ()
}
