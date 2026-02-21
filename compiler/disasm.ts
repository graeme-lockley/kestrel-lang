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
};

function readU32(data: Uint8Array, offset: number): number {
  return data[offset]! | (data[offset + 1]! << 8) | (data[offset + 2]! << 16) | (data[offset + 3]! << 24);
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

function disasm(
  data: Uint8Array,
  codeStart: number,
  codeEnd: number,
  constantComments: string[] = []
): string[] {
  const lines: string[] = [];
  let pc = codeStart;

  while (pc < codeEnd) {
    const base = pc;
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

    lines.push(`  ${String(base).padStart(6)}  ${name}${operands}${constComment}`);
  }

  return lines;
}

function main(): void {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    process.stderr.write('Usage: disasm <file.kbc>\n');
    process.exit(1);
  }

  const path = args[0]!;
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
  const codeEnd = Math.min(section4, data.length);

  const strings =
    section0 < data.length && section1 > section0
      ? parseStringTable(data, section0, section1)
      : [];
  const constantComments =
    section1 < data.length && section2 > section1
      ? parseConstantPool(data, section1, section2, strings)
      : [];

  const lines = disasm(data, section3, codeEnd, constantComments);
  process.stdout.write(`; Code section (offset ${section3}, ${codeEnd - section3} bytes)\n`);
  for (const line of lines) {
    process.stdout.write(line + '\n');
  }
}

main();
