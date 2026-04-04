import { Suite, group, eq, isTrue } from "kestrel:test"
import { NotFound, PermissionDenied, IoError, DirEntry, File, Dir } from "kestrel:fs"
import * as Fs from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Process from "kestrel:process"
import * as Str from "kestrel:string"

fun entryHasName(entries: List<DirEntry>, name: String): Bool =
  Lst.any(entries, (e: DirEntry) => match (e) {
    File(p) => Str.contains(name, p),
    Dir(p) => Str.contains(name, p)
  })

async fun readViaAwait(path: String): Task<Result<String, Fs.FsError>> = {
  val t = await Fs.readText(path);
  t
}

export async fun run(s: Suite): Task<Unit> = {
  val cwd = Process.getProcess().cwd;
  val okPath = "${cwd}/tests/fixtures/fs/read_fixture.txt";
  val readFixture = await Fs.readText(okPath);
  val readMissing = await Fs.readText("${cwd}/tests/fixtures/fs/__missing__.no_such");
  val readDirectory = await Fs.readText("${cwd}/tests/fixtures/fs/list_sample");
  val roundtripPath = "${cwd}/tests/fixtures/fs/tmp_write_roundtrip.txt";
  val roundtripWrite = await Fs.writeText(roundtripPath, "roundtrip\n");
  val roundtripRead = await Fs.readText(roundtripPath);
  val writeMissingParent = await Fs.writeText("${cwd}/tests/fixtures/fs/__no_such_parent__/out.txt", "x");
  val listDirResult = await Fs.listDir("${cwd}/tests/fixtures/fs/list_sample");
  val listDirMissing = await Fs.listDir("${cwd}/tests/fixtures/fs/__nope_dir_missing__");
  val readViaAwaitResult = await readViaAwait(okPath);

  group(s, "fs", (s1: Suite) => {
    group(s1, "readText", (sg: Suite) => {
      val text = match (readFixture) {
        Ok(contents) => contents,
        Err(_) => ""
      };
      eq(sg, "fixture contents", text, "hello fixture\n");
    });

    group(s1, "readText missing", (sg: Suite) => {
      val isNotFound =
        match (readMissing) {
          Err(NotFound) => True,
          _ => False
        };
      isTrue(sg, "returns Err(NotFound)", isNotFound)
    });

    group(s1, "readText directory", (sg: Suite) => {
      val isIoError =
        match (readDirectory) {
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
      val writeOk =
        match (roundtripWrite) {
          Ok(_) => True,
          _ => False
        };
      isTrue(sg, "write ok", writeOk);
      val text =
        match (roundtripRead) {
          Ok(contents) => contents,
          Err(_) => ""
        };
      eq(sg, "read back", text, "roundtrip\n");
    });

    group(s1, "writeText missing parent returns Err(NotFound)", (sg: Suite) => {
      val isNotFound =
        match (writeMissingParent) {
          Err(NotFound) => True,
          _ => False
        };
      isTrue(sg, "returns Err(NotFound)", isNotFound)
    });

    group(s1, "listDir", (sg: Suite) => {
      val entries =
        match (listDirResult) {
          Ok(v) => v,
          Err(_) => []
        };
      eq(sg, "entry count", Lst.length(entries), 2);
      isTrue(sg, "has a.txt", entryHasName(entries, "a.txt"));
      isTrue(sg, "has b.txt", entryHasName(entries, "b.txt"));
      isTrue(sg, "entries are File", Lst.all(entries, (e: DirEntry) => match (e) { File(_) => True, Dir(_) => False }));
    });

    group(s1, "listDir missing", (sg: Suite) => {
      val isNotFound =
        match (listDirMissing) {
          Err(NotFound) => True,
          _ => False
        };
      isTrue(sg, "returns Err(NotFound)", isNotFound)
    });

    group(s1, "readViaAwait helper", (sg: Suite) => {
      val text =
        match (readViaAwaitResult) {
          Ok(contents) => contents,
          Err(_) => ""
        };
      eq(sg, "helper contents", text, "hello fixture\n");
    });
  });
  ()
}
