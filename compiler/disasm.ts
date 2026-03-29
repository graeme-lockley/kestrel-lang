#!/usr/bin/env node
/**
 * Disassembler: reads .kbc and prints bytecode mnemonics (spec 04).
 * Usage: node disasm.js <file.kbc>
 */
import { readFileSync } from 'fs';

const KBC1 = new Uint8Array([0x4b, 0x42, 0x43, 0x31]);

const OP_NAMES: Record<number, string> = {
  0x01: 'LOAD_CONST',
  0x02: 'LOAD_LOCAL',
  0x03: 'STORE_LOCAL',
  0x04: 'ADD',
  0x05: 'SUB',
  0x06: 'MUL',
  0x07: 'DIV',
  0x08: 'MOD',
  0x09: 'POW',
  0x0a: 'EQ',
  0x0b: 'NE',
  0x0c: 'LT',
  0x0d: 'LE',
  0x0e: 'GT',
  0x0f: 'GE',
  0x10: 'CALL',
  0x11: 'RET',
  0x12: 'JUMP',
  0x13: 'JUMP_IF_FALSE',
  0x14: 'CONSTRUCT',
  0x15: 'MATCH',
  0x16: 'ALLOC_RECORD',
  0x17: 'GET_FIELD',
  0x18: 'SET_FIELD',
  0x19: 'SPREAD',
  0x1a: 'THROW',
  0x1b: 'TRY',
  0x1c: 'END_TRY',
  0x1d: 'AWAIT',
  0x1e: 'LOAD_GLOBAL',
  0x1f: 'STORE_GLOBAL',
  0x20: 'CALL_INDIRECT',
  0x21: 'LOAD_FN',
  0x22: 'MAKE_CLOSURE',
  0x23: 'LOAD_IMPORTED_FN',
  0x24: 'CONSTRUCT_IMPORT',
  0x25: 'KIND_IS',
};

function readU32(data: Uint8Array, offset: number): number {
  return (data[offset]! | (data[offset + 1]! << 8) | (data[offset + 2]! << 16) | (data[offset + 3]! << 24)) >>> 0;
}

function readI32(data: Uint8Array, offset: number): number {
  const u = readU32(data, offset);
  return u | 0;
}

function readI64(data: Uint8Array, offset: number): bigint {
  const lo = readU32(data, offset);
  const hi = readU32(data, offset + 4);
  return BigInt(lo) | (BigInt(hi) << 32n);
}

function align4(n: number): number {
  return (n + 3) & ~3;
}

/** Parse section 0 (string table) and return array of UTF-8 decoded strings. */
function parseStringTable(data: Uint8Array, sectionStart: number, sectionEnd: number): string[] {
  const strings: string[] = [];
  if (sectionStart + 4 > sectionEnd) return strings;
  const count = readU32(data, sectionStart);
  let o = sectionStart + 4;
  for (let i = 0; i < count && o + 4 <= sectionEnd; i++) {
    o = align4(o);
    const len = readU32(data, o);
    o += 4;
    if (o + len > sectionEnd) break;
    strings.push(new TextDecoder().decode(data.subarray(o, o + len)));
    o += len;
  }
  return strings;
}

/** Parse section 1 (constant pool) and return comment strings for each constant (for LOAD_CONST). */
function parseConstantPool(data: Uint8Array, sectionStart: number, sectionEnd: number, strings: string[]): string[] {
  const comments: string[] = [];
  if (sectionStart + 4 > sectionEnd) return comments;
  const count = readU32(data, sectionStart);
  let o = sectionStart + 4;
  for (let i = 0; i < count && o + 4 <= sectionEnd; i++) {
    o = align4(o);
    const entryStart = o;
    const tag = data[o];
    o += 4;
    let payloadLen = 0;
    let comment = '';
    switch (tag) {
      case 0: // Int
        if (o + 8 <= sectionEnd) {
          const v = Number(readI64(data, o));
          comment = String(v);
        }
        payloadLen = 8;
        break;
      case 1: // Float
        if (o + 8 <= sectionEnd && data.buffer) {
          const v = new DataView(data.buffer, data.byteOffset + o, 8).getFloat64(0, true);
          comment = String(v);
        }
        payloadLen = 8;
        break;
      case 2:
        comment = 'false';
        break;
      case 3:
        comment = 'true';
        break;
      case 4:
        comment = '()';
        break;
      case 5: // Char
        if (o + 4 <= sectionEnd) {
          const cp = readU32(data, o);
          comment = cp <= 0xffff ? JSON.stringify(String.fromCodePoint(cp)) : `\\u{${cp.toString(16)}}`;
        }
        payloadLen = 4;
        break;
      case 6: // String
        if (o + 4 <= sectionEnd) {
          const idx = readU32(data, o);
          comment = idx < strings.length ? JSON.stringify(strings[idx]) : '?';
        }
        payloadLen = 4;
        break;
      default:
        break;
    }
    comments.push(comment);
    o = align4(entryStart + 4 + payloadLen);
  }
  return comments;
}

/** Parse section 4 (debug): return map from code_offset (relative to code section) to { file, line }. */
function parseDebugSection(
  data: Uint8Array,
  section4Start: number,
  section4End: number,
  strings: string[]
): Map<number, { file: string; line: number }> {
  const map = new Map<number, { file: string; line: number }>();
  if (section4Start + 4 > section4End) return map;
  const fileCount = readU32(data, section4Start);
  let o = section4Start + 4;
  const files: string[] = [];
  for (let i = 0; i < fileCount && o + 4 <= section4End; i++) {
    const strIdx = readU32(data, o);
    o += 4;
    files.push(strIdx < strings.length ? strings[strIdx]! : '?');
  }
  if (o + 4 > section4End) return map;
  const entryCount = readU32(data, o);
  o += 4;
  for (let i = 0; i < entryCount && o + 12 <= section4End; i++) {
    const codeOffset = readU32(data, o);
    const fileIndex = readU32(data, o + 4);
    const line = readU32(data, o + 8);
    o += 12;
    const file = fileIndex < files.length ? files[fileIndex]! : '?';
    map.set(codeOffset, { file, line });
  }
  return map;
}

/** Parse section 2 (function table and related) and return metadata. */
function parseSection2(
  data: Uint8Array,
  section2Start: number,
  section2End: number,
  strings: string[]
): {
  functions: Array<{ name: string; arity: number; codeOffset: number; flags: number; typeIndex: number }>;
  imports: string[];
  shapeTable: Array<{ fields: Array<{ name: string; typeIndex: number }> }>;
  adtTable: Array<{ name: string; constructors: Array<{ name: string; payloadTypeIndex: number }> }>;
} {
  const result = {
    functions: [] as Array<{ name: string; arity: number; codeOffset: number; flags: number; typeIndex: number }>,
    imports: [] as string[],
    shapeTable: [] as Array<{ fields: Array<{ name: string; typeIndex: number }> }>,
    adtTable: [] as Array<{ name: string; constructors: Array<{ name: string; payloadTypeIndex: number }> }>
  };

  if (section2Start + 8 > section2End) return result;

  // n_globals (u32), function_count (u32)
  const nGlobals = readU32(data, section2Start);
  const functionCount = readU32(data, section2Start + 4);
  let o = section2Start + 8;

  // Function table: function_count × 24 bytes
  for (let i = 0; i < functionCount && o + 24 <= section2End; i++) {
    const nameIndex = readU32(data, o);
    const arity = readU32(data, o + 4);
    const codeOffset = readU32(data, o + 8);
    const flags = readU32(data, o + 12);
    const reserved = readU32(data, o + 16);
    const typeIndex = readU32(data, o + 20);
    const name = nameIndex < strings.length ? strings[nameIndex]! : `?(${nameIndex})`;
    result.functions.push({ name, arity, codeOffset, flags, typeIndex });
    o += 24;
  }

  // Type table: type_count (u32), then offsets (u32 × (type_count + 1)), then blob
  if (o + 4 > section2End) return result;
  const typeCount = readU32(data, o);
  o += 4;
  if (o + (typeCount + 1) * 4 > section2End) return result;
  const typeOffsets: number[] = [];
  for (let i = 0; i <= typeCount; i++) {
    typeOffsets.push(readU32(data, o));
    o += 4;
  }
  const blobStart = o;
  const blobEnd = Math.min(blobStart + typeOffsets[typeCount]!, section2End);
  o = align4(blobEnd);

  // Exported type declarations: exported_type_count (u32), then pairs
  if (o + 4 > section2End) return result;
  const exportedTypeCount = readU32(data, o);
  o += 4;
  o += exportedTypeCount * 8; // Skip name_index, type_index pairs
  o = align4(o);

  // Import table: import_count (u32), then import_count × u32
  if (o + 4 > section2End) return result;
  const importCount = readU32(data, o);
  o += 4;
  for (let i = 0; i < importCount && o + 4 <= section2End; i++) {
    const strIndex = readU32(data, o);
    o += 4;
    const importName = strIndex < strings.length ? strings[strIndex]! : `?(${strIndex})`;
    result.imports.push(importName);
  }

  // Imported function table: imported_function_count (u32), then pairs
  if (o + 4 > section2End) return result;
  const importedFunctionCount = readU32(data, o);
  o += 4;
  o += importedFunctionCount * 8; // Skip import_index, function_index pairs

  return result;
}

/** Parse section 5 (shape table). */
function parseShapeTable(
  data: Uint8Array,
  section5Start: number,
  section5End: number,
  strings: string[]
): Array<{ fields: Array<{ name: string; typeIndex: number }> }> {
  const shapes: Array<{ fields: Array<{ name: string; typeIndex: number }> }> = [];
  if (section5Start + 4 > section5End) return shapes;
  const shapeCount = readU32(data, section5Start);
  let o = section5Start + 4;
  for (let i = 0; i < shapeCount && o + 4 <= section5End; i++) {
    o = align4(o);
    if (o + 4 > section5End) break;
    const fieldCount = readU32(data, o);
    o += 4;
    const fields: Array<{ name: string; typeIndex: number }> = [];
    for (let j = 0; j < fieldCount && o + 8 <= section5End; j++) {
      const nameIndex = readU32(data, o);
      const typeIndex = readU32(data, o + 4);
      o += 8;
      const name = nameIndex < strings.length ? strings[nameIndex]! : `?(${nameIndex})`;
      fields.push({ name, typeIndex });
    }
    shapes.push({ fields });
  }
  return shapes;
}

/** Parse section 6 (ADT table). */
function parseAdtTable(
  data: Uint8Array,
  section6Start: number,
  section6End: number,
  strings: string[]
): Array<{ name: string; constructors: Array<{ name: string; payloadTypeIndex: number }> }> {
  const adts: Array<{ name: string; constructors: Array<{ name: string; payloadTypeIndex: number }> }> = [];
  if (section6Start + 4 > section6End) return adts;
  const adtCount = readU32(data, section6Start);
  let o = section6Start + 4;
  for (let i = 0; i < adtCount && o + 8 <= section6End; i++) {
    o = align4(o);
    if (o + 8 > section6End) break;
    const nameIndex = readU32(data, o);
    const constructorCount = readU32(data, o + 4);
    o += 8;
    const name = nameIndex < strings.length ? strings[nameIndex]! : `?(${nameIndex})`;
    const constructors: Array<{ name: string; payloadTypeIndex: number }> = [];
    for (let j = 0; j < constructorCount && o + 8 <= section6End; j++) {
      const ctorNameIndex = readU32(data, o);
      const payloadTypeIndex = readU32(data, o + 4);
      o += 8;
      const ctorName = ctorNameIndex < strings.length ? strings[ctorNameIndex]! : `?(${ctorNameIndex})`;
      constructors.push({ name: ctorName, payloadTypeIndex });
    }
    adts.push({ name, constructors });
  }
  return adts;
}

function disasm(
  data: Uint8Array,
  codeStart: number,
  codeEnd: number,
  constantComments: string[] = [],
  debugByOffset: Map<number, { file: string; line: number }> = new Map(),
  functions: Array<{ name: string; arity: number; codeOffset: number; flags: number; typeIndex: number }> = [],
  verbose: boolean = false
): string[] {
  const lines: string[] = [];
  let pc = codeStart;
  let lastLine: { file: string; line: number } | null = null;

  // Sort functions by code offset for boundary detection
  const sortedFunctions = [...functions].sort((a, b) => a.codeOffset - b.codeOffset);

  // Check if there's a function at offset 0 (module initializer)
  const hasInitializerFunction = sortedFunctions.some(f => f.codeOffset === 0);

  /** Find debug info for code offset (relative to code section): last entry with code_offset <= offset. */
  function getDebug(codeOffset: number): { file: string; line: number } | undefined {
    let best: { file: string; line: number } | undefined;
    let bestOffset = -1;
    for (const [off, loc] of debugByOffset) {
      if (off <= codeOffset && off > bestOffset) {
        bestOffset = off;
        best = loc;
      }
    }
    return best;
  }

  // When debug reports line 1 but we've already seen a higher line, treat as fallback (e.g. getter/lambda with no span)
  const effectiveDebug = (debug: { file: string; line: number } | undefined, codeOffset: number) => {
    if (!debug) return debug;
    if (debug.line === 1 && lastLine && lastLine.line > 1 && codeOffset > 50) {
      return { file: debug.file, line: lastLine.line };
    }
    return debug;
  };

  while (pc < codeEnd) {
    const base = pc;
    const codeOffset = base - codeStart;

    // Check for module initializer at offset 0
    if (codeOffset === 0 && !hasInitializerFunction) {
      lines.push(`; --- function "<module>" (arity 0, offset 0x00000000) ---`);
    }

    // Check for function boundary
    const funcAtOffset = sortedFunctions.find(f => f.codeOffset === codeOffset);
    if (funcAtOffset) {
      lines.push(`; --- function "${funcAtOffset.name}" (arity ${funcAtOffset.arity}, offset 0x${funcAtOffset.codeOffset.toString(16).padStart(8, '0')}) ---`);
    }

    const rawDebug = getDebug(codeOffset);
    const debug = effectiveDebug(rawDebug ?? undefined, codeOffset);
    if (debug && (!lastLine || lastLine.line !== debug.line || lastLine.file !== debug.file)) {
      if (lastLine) lines.push('');
      lines.push(`; --- ${debug.file}:${debug.line} ---`);
      lastLine = debug;
    } else if (!rawDebug) lastLine = null;

    const op = data[pc];
    pc += 1;

    const name = OP_NAMES[op];
    if (name === undefined) {
      if (op === 0x00) break;
      lines.push(`  ${String(base).padStart(6)}  ??? 0x${op.toString(16).padStart(2, '0')}`);
      continue;
    }

    let operands = '';
    let constComment = '';
    switch (op) {
      case 0x01: // LOAD_CONST
        {
          const idx = readU32(data, pc);
          operands = ` ${idx}`;
          if (idx < constantComments.length && constantComments[idx] !== '') {
            constComment = `  ; ${constantComments[idx]}`;
          }
          pc += 4;
        }
        break;
      case 0x02: // LOAD_LOCAL
      case 0x03: // STORE_LOCAL
      case 0x16: // ALLOC_RECORD
      case 0x17: // GET_FIELD
      case 0x18: // SET_FIELD
      case 0x19: // SPREAD
      case 0x1e: // LOAD_GLOBAL
      case 0x1f: // STORE_GLOBAL
      case 0x21: // LOAD_FN
      case 0x22: // MAKE_CLOSURE
      case 0x23: // LOAD_IMPORTED_FN
      case 0x25: // KIND_IS
        operands = ` ${readU32(data, pc)}`;
        pc += 4;
        break;
      case 0x20: // CALL_INDIRECT
        operands = ` ${readU32(data, pc)}`;
        pc += 4;
        break;
      case 0x10: // CALL
        operands = ` ${readU32(data, pc)}, ${readU32(data, pc + 4)}`;
        pc += 8;
        break;
      case 0x12: // JUMP
      case 0x13: // JUMP_IF_FALSE
      case 0x1b: // TRY
        operands = ` ${readI32(data, pc)}`;
        pc += 4;
        break;
      case 0x14: // CONSTRUCT
        operands = ` ${readU32(data, pc)}, ${readU32(data, pc + 4)}, ${readU32(data, pc + 8)}`;
        pc += 12;
        break;
      case 0x24: // CONSTRUCT_IMPORT
        operands = ` ${readU32(data, pc)}, ${readU32(data, pc + 4)}, ${readU32(data, pc + 8)}, ${readU32(data, pc + 12)}`;
        pc += 16;
        break;
      case 0x15: // MATCH
        {
          const count = readU32(data, pc);
          pc += 4;
          const offs: number[] = [];
          for (let i = 0; i < count; i++) {
            offs.push(readI32(data, pc));
            pc += 4;
          }
          operands = ` ${offs.join(', ')}`;
        }
        break;
      default:
        // ADD, SUB, MUL, etc. - no operands
        break;
    }

    let lineComment = '';
    if (debug && lastLine && debug.line !== lastLine.line) lineComment = `  ; line ${debug.line}`;
    lines.push(`  ${String(base).padStart(6)}  ${name}${operands}${constComment}${lineComment}`);
  }

  return lines;
}

function main(): void {
  const args = process.argv.slice(2);
  let verbose = false;
  let codeOnly = false;
  let inputPath = '';

  // Parse flags
  for (const arg of args) {
    if (arg === '--verbose') {
      verbose = true;
    } else if (arg === '--code-only') {
      codeOnly = true;
    } else if (!arg.startsWith('-')) {
      inputPath = arg;
    } else {
      process.stderr.write(`disasm: unknown flag ${arg}\n`);
      process.stderr.write('Usage: disasm [--verbose|--code-only] <file.kbc>\n');
      process.exit(1);
    }
  }

  if (!inputPath) {
    process.stderr.write('Usage: disasm [--verbose|--code-only] <file.kbc>\n');
    process.exit(1);
  }

  const path = inputPath;
  let data: Uint8Array;
  try {
    const buf = readFileSync(path);
    data = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  } catch (e) {
    process.stderr.write(`disasm: cannot read ${path}: ${(e as Error).message}\n`);
    process.exit(1);
  }

  if (data.length < 36) {
    process.stderr.write('disasm: file too short for .kbc header\n');
    process.exit(1);
  }
  if (data[0] !== KBC1[0] || data[1] !== KBC1[1] || data[2] !== KBC1[2] || data[3] !== KBC1[3]) {
    process.stderr.write('disasm: invalid magic (expected KBC1)\n');
    process.exit(1);
  }
  const version = readU32(data, 4);
  if (version !== 1) {
    process.stderr.write(`disasm: unsupported version ${version}\n`);
    process.exit(1);
  }

  const section0 = readU32(data, 8);
  const section1 = readU32(data, 12);
  const section2 = readU32(data, 16);
  const section3 = readU32(data, 20);
  const section4 = readU32(data, 24);
  const section5 = readU32(data, 28);
  const section6 = readU32(data, 32);
  const codeEnd = Math.min(section4, data.length);
  const section4End = Math.min(section5, data.length);
  const section5End = Math.min(section6, data.length);
  const section6End = Math.min(data.length, data.length); // Last section goes to end

  const strings =
    section0 < data.length && section1 > section0
      ? parseStringTable(data, section0, section1)
      : [];
  const constantComments =
    section1 < data.length && section2 > section1
      ? parseConstantPool(data, section1, section2, strings)
      : [];
  const section2Data =
    section2 < data.length && section3 > section2
      ? parseSection2(data, section2, section3, strings)
      : { functions: [], imports: [], shapeTable: [], adtTable: [] };
  const debugByOffset =
    section4 < data.length && section4End > section4
      ? parseDebugSection(data, section4, section4End, strings)
      : new Map<number, { file: string; line: number }>();

  // Output verbose sections if requested
  if (verbose && !codeOnly) {
    // Import table
    if (section2Data.imports.length > 0) {
      process.stdout.write('; Imports:\n');
      for (let i = 0; i < section2Data.imports.length; i++) {
        process.stdout.write(`;   ${i}: ${section2Data.imports[i]}\n`);
      }
      process.stdout.write('\n');
    }

    // Shape table
    const shapeTable =
      section5 < data.length && section5End > section5
        ? parseShapeTable(data, section5, section5End, strings)
        : [];
    if (shapeTable.length > 0) {
      process.stdout.write('; Shape table:\n');
      for (let i = 0; i < shapeTable.length; i++) {
        process.stdout.write(`;   Shape ${i}:\n`);
        for (const field of shapeTable[i]!.fields) {
          process.stdout.write(`;     ${field.name}: type ${field.typeIndex}\n`);
        }
      }
      process.stdout.write('\n');
    }

    // ADT table
    const adtTable =
      section6 < data.length && section6End > section6
        ? parseAdtTable(data, section6, section6End, strings)
        : [];
    if (adtTable.length > 0) {
      process.stdout.write('; ADT table:\n');
      for (let i = 0; i < adtTable.length; i++) {
        process.stdout.write(`;   ADT ${i}: ${adtTable[i]!.name}\n`);
        for (let j = 0; j < adtTable[i]!.constructors.length; j++) {
          const ctor = adtTable[i]!.constructors[j]!;
          const payload = ctor.payloadTypeIndex === 0xFFFF_FFFF ? 'none' : `type ${ctor.payloadTypeIndex}`;
          process.stdout.write(`;     ${j}: ${ctor.name} (${payload})\n`);
        }
      }
      process.stdout.write('\n');
    }
  }

  if (!codeOnly) {
    const lines = disasm(data, section3, codeEnd, constantComments, debugByOffset, section2Data.functions, verbose);
    process.stdout.write(`; Code section (offset ${section3}, ${codeEnd - section3} bytes)\n`);
    for (const line of lines) {
      process.stdout.write(line + '\n');
    }
  } else {
    // Code-only mode: just the raw instruction lines
    const lines = disasm(data, section3, codeEnd, constantComments, debugByOffset, section2Data.functions, verbose);
    for (const line of lines) {
      if (!line.startsWith(';')) {
        process.stdout.write(line + '\n');
      }
    }
  }
}

main();
