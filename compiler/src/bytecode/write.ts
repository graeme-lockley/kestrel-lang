/**
 * Write .kbc file (spec 03). Full sections: string table, constant pool, function table, code, debug, shape, ADT.
 */
import type { ConstantEntry } from './constants.js';
import { encodeConstant } from './constants.js';

const KBC1 = new Uint8Array([0x4b, 0x42, 0x43, 0x31]);
const RET = 0x11;

function writeU32(dv: DataView, offset: number, value: number): void {
  dv.setUint32(offset, value, true);
}

function align4(n: number): number {
  return (n + 3) & ~3;
}

/** Build section 0 (string table): count + length-prefixed UTF-8 strings, 4-byte aligned. */
function sizeStringTable(strings: string[]): number {
  let n = 4; // count
  for (const s of strings) {
    const bytes = new TextEncoder().encode(s);
    n = align4(n) + 4 + bytes.length;
  }
  return align4(n);
}

function writeStringTable(buf: ArrayBuffer, offset: number, strings: string[]): number {
  const dv = new DataView(buf);
  const u8 = new Uint8Array(buf);
  writeU32(dv, offset, strings.length);
  let o = offset + 4;
  for (const s of strings) {
    o = align4(o);
    const bytes = new TextEncoder().encode(s);
    writeU32(dv, o, bytes.length);
    u8.set(bytes, o + 4);
    o += 4 + bytes.length;
  }
  return o - offset;
}

/** Build section 1 (constant pool): count + entries (tag, 3 pad, payload), 4-aligned. */
function sizeConstantPool(constants: ConstantEntry[]): number {
  let n = 4; // count
  for (const c of constants) {
    n = align4(n);
    let entry = 4; // tag + 3 pad
    switch (c.tag) {
      case 0: entry += 8; break; // Int
      case 1: entry += 8; break; // Float
      case 2: case 3: case 4: break; // False, True, Unit
      case 5: entry += 4; break; // Char
      case 6: entry += 4; break; // String
      default: break;
    }
    n += align4(entry);
  }
  return n;
}

function writeConstantPool(buf: ArrayBuffer, offset: number, constants: ConstantEntry[]): number {
  const dv = new DataView(buf);
  writeU32(dv, offset, constants.length);
  let o = offset + 4;
  for (const c of constants) {
    o = align4(o);
    o += encodeConstant(dv, o, c);
  }
  return o - offset;
}

/** Section 2: function table, type blob, exported types, import table, imported function table (03 §6.6). */
export interface ImportedFunctionEntry {
  importIndex: number;
  functionIndex: number;
}

function sizeSection2(
  nGlobals: number,
  functionTable: { nameIndex: number; arity: number; codeOffset: number }[],
  importSpecifierIndices: number[],
  importedFunctionTable: ImportedFunctionEntry[] = []
): number {
  const fnCount = functionTable.length;
  const typeCount = 1;
  const typeBlobLen = 1;
  const afterTypeBlob = 4 + (typeCount + 1) * 4 + typeBlobLen;
  const pad = (4 - (afterTypeBlob % 4)) % 4;
  const exportedCount = 0;
  const importCount = importSpecifierIndices.length;
  const importedFnCount = importedFunctionTable.length;
  return (
    4 + // n_globals
    4 +
    fnCount * 24 +
    4 +
    (typeCount + 1) * 4 +
    typeBlobLen +
    pad +
    4 +
    exportedCount * 8 +
    4 +
    importCount * 4 +
    4 +
    importedFnCount * 8
  );
}

function writeSection2(
  buf: ArrayBuffer,
  offset: number,
  nGlobals: number,
  functionTable: { nameIndex: number; arity: number; codeOffset: number }[],
  importSpecifierIndices: number[],
  importedFunctionTable: ImportedFunctionEntry[] = []
): void {
  const dv = new DataView(buf);
  let o = offset;
  writeU32(dv, o, nGlobals);
  o += 4;
  writeU32(dv, o, functionTable.length);
  o += 4;
  for (const fn of functionTable) {
    writeU32(dv, o, fn.nameIndex);
    o += 4;
    writeU32(dv, o, fn.arity);
    o += 4;
    writeU32(dv, o, fn.codeOffset);
    o += 4;
    writeU32(dv, o, 0); // flags
    o += 4;
    writeU32(dv, o, 0); // reserved
    o += 4;
    writeU32(dv, o, 0); // type_index
    o += 4;
  }
  writeU32(dv, o, 1); // type_count
  o += 4;
  writeU32(dv, o, 0); // offsets[0]
  o += 4;
  writeU32(dv, o, 1); // offsets[1] = blob length
  o += 4;
  dv.setUint8(o, 0); // type blob: tag 0 = Int
  o += 1;
  while (o % 4 !== 0) o++;
  writeU32(dv, o, 0); // exported_type_count
  o += 4;
  writeU32(dv, o, importSpecifierIndices.length); // import_count
  o += 4;
  for (const idx of importSpecifierIndices) {
    writeU32(dv, o, idx);
    o += 4;
  }
  writeU32(dv, o, importedFunctionTable.length); // imported_function_count (03 §6.6)
  o += 4;
  for (const entry of importedFunctionTable) {
    writeU32(dv, o, entry.importIndex);
    writeU32(dv, o + 4, entry.functionIndex);
    o += 8;
  }
}

/** Section 5: shape table (spec 03 §9). */
function sizeSection5(shapes: { nameIndices: number[] }[]): number {
  let n = 4; // shape_count
  for (const s of shapes) {
    n = align4(n);
    n += 4 + s.nameIndices.length * 8; // field_count + pairs
  }
  return align4(n);
}

function writeSection5(buf: ArrayBuffer, offset: number, shapes: { nameIndices: number[] }[]): void {
  const dv = new DataView(buf);
  let o = offset;
  writeU32(dv, o, shapes.length);
  o += 4;
  for (const s of shapes) {
    o = align4(o);
    writeU32(dv, o, s.nameIndices.length);
    o += 4;
    for (const nameIdx of s.nameIndices) {
      writeU32(dv, o, nameIdx);
      writeU32(dv, o + 4, 0); // type_index
      o += 8;
    }
  }
}

/** Section 6: ADT table (spec 03 §10). */
function sizeSection6(adts: { nameIndex: number; constructors: { nameIndex: number; payloadTypeIndex: number }[] }[]): number {
  let n = 4; // adt_count
  for (const adt of adts) {
    n += 4; // name_index
    n += 4; // constructor_count
    n += adt.constructors.length * 8; // constructor entries (2 × u32 each)
    n = align4(n); // Pad after constructors before next ADT
  }
  return n;
}

function writeSection6(
  buf: ArrayBuffer,
  offset: number,
  adts: { nameIndex: number; constructors: { nameIndex: number; payloadTypeIndex: number }[] }[]
): void {
  const dv = new DataView(buf);
  writeU32(dv, offset, adts.length);
  let o = offset + 4;
  for (const adt of adts) {
    writeU32(dv, o, adt.nameIndex);
    o += 4;
    writeU32(dv, o, adt.constructors.length);
    o += 4;
    for (const ctor of adt.constructors) {
      writeU32(dv, o, ctor.nameIndex);
      o += 4;
      writeU32(dv, o, ctor.payloadTypeIndex);
      o += 4;
    }
    o = align4(o); // Pad after constructors
  }
}

/** Debug entry for section 4 (spec 03 §8): code_offset, file_index, line. */
export interface DebugEntryForWrite {
  codeOffset: number;
  fileIndex: number;
  line: number;
}

/** Build full .kbc from sections. */
export function writeKbc(
  stringTable: string[],
  constantPool: ConstantEntry[],
  code: Uint8Array,
  functionTable: { nameIndex: number; arity: number; codeOffset: number }[] = [],
  importSpecifierIndices: number[] = [],
  importedFunctionTable: ImportedFunctionEntry[] = [],
  shapes: { nameIndices: number[] }[] = [],
  adts: { nameIndex: number; constructors: { nameIndex: number; payloadTypeIndex: number }[] }[] = [],
  nGlobals: number = 0,
  debugFileStringIndices: number[] = [],
  debugEntries: DebugEntryForWrite[] = []
): Uint8Array {
  const section0Len = sizeStringTable(stringTable);
  const section1Len = sizeConstantPool(constantPool);
  const section2Len = sizeSection2(nGlobals, functionTable, importSpecifierIndices, importedFunctionTable);
  const section3Len = align4(code.length); // Code section padded per spec 03 §1 (4-byte alignment)
  const debugFileCount = debugFileStringIndices.length;
  const debugEntryCount = debugEntries.length;
  const section4Len = 4 + debugFileCount * 4 + 4 + debugEntryCount * 12;
  const section5Len = sizeSection5(shapes);
  const section6Len = sizeSection6(adts);

  const headerLen = 36;
  const section0Start = headerLen;
  const section1Start = section0Start + section0Len;
  const section2Start = section1Start + section1Len;
  const section3Start = section2Start + section2Len;
  const section4Start = section3Start + section3Len;
  const section5Start = section4Start + section4Len;
  const section6Start = section5Start + section5Len;

  const total = section6Start + section6Len;
  const buf = new ArrayBuffer(total);
  const dv = new DataView(buf);

  new Uint8Array(buf).set(KBC1, 0);
  writeU32(dv, 4, 1);
  writeU32(dv, 8, section0Start);
  writeU32(dv, 12, section1Start);
  writeU32(dv, 16, section2Start);
  writeU32(dv, 20, section3Start);
  writeU32(dv, 24, section4Start);
  writeU32(dv, 28, section5Start);
  writeU32(dv, 32, section6Start);

  writeStringTable(buf, section0Start, stringTable);
  writeConstantPool(buf, section1Start, constantPool);
  writeSection2(buf, section2Start, nGlobals, functionTable, importSpecifierIndices, importedFunctionTable);
  new Uint8Array(buf, section3Start, code.length).set(code);
  let o4 = section4Start;
  writeU32(dv, o4, debugFileCount);
  o4 += 4;
  for (const idx of debugFileStringIndices) {
    writeU32(dv, o4, idx);
    o4 += 4;
  }
  writeU32(dv, o4, debugEntryCount);
  o4 += 4;
  for (const e of debugEntries) {
    writeU32(dv, o4, e.codeOffset);
    writeU32(dv, o4 + 4, e.fileIndex);
    writeU32(dv, o4 + 8, e.line);
    o4 += 12;
  }
  writeSection5(buf, section5Start, shapes);
  writeSection6(buf, section6Start, adts);

  return new Uint8Array(buf);
}

/** Build a minimal .kbc with empty sections and code = single RET (for E2E). */
export function writeMinimalKbc(): Uint8Array {
  const section0Len = 4;
  const section1Len = 4;
  const section2Len = 4 + 20; // n_globals + rest
  const codeLen = 1;
  const codeSectionLen = align4(codeLen);
  const section4Len = 8;
  const section5Len = 4;
  const section6Len = 4;

  const headerLen = 36;
  const section0Start = headerLen;
  const section1Start = section0Start + section0Len;
  const section2Start = section1Start + section1Len;
  const section3StartAligned = section2Start + section2Len;
  const section4Start = section3StartAligned + codeSectionLen;
  const section5Start = section4Start + section4Len;
  const section6Start = section5Start + section5Len;

  const total =
    headerLen +
    section0Len +
    section1Len +
    section2Len +
    codeSectionLen +
    section4Len +
    section5Len +
    section6Len;

  const buf = new ArrayBuffer(total);
  const dv = new DataView(buf);
  let o = 0;

  new Uint8Array(buf).set(KBC1, 0);
  o = 4;
  writeU32(dv, o, 1);
  o = 8;
  const offsets = [
    section0Start,
    section1Start,
    section2Start,
    section3StartAligned,
    section4Start,
    section5Start,
    section6Start,
  ];
  for (let i = 0; i < 7; i++) {
    writeU32(dv, o + i * 4, offsets[i]!);
  }

  o = section0Start;
  writeU32(dv, o, 0);

  o = section1Start;
  writeU32(dv, o, 0);

  o = section2Start;
  writeU32(dv, o, 0); // n_globals
  writeU32(dv, o + 4, 0); // function_count
  writeU32(dv, o + 8, 0);
  writeU32(dv, o + 12, 0);
  writeU32(dv, o + 16, 0);
  writeU32(dv, o + 20, 0);

  o = section3StartAligned;
  new Uint8Array(buf, o, 1)[0] = RET;

  o = section4Start;
  writeU32(dv, o, 0);
  writeU32(dv, o + 4, 0);

  o = section5Start;
  writeU32(dv, o, 0);

  o = section6Start;
  writeU32(dv, o, 0);

  return new Uint8Array(buf);
}
