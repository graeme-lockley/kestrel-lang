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

function disasm(data: Uint8Array, codeStart: number, codeEnd: number): string[] {
  const lines: string[] = [];
  let pc = codeStart;

  while (pc < codeEnd) {
    const base = pc;
    const op = data[pc];
    pc += 1;

    const name = OP_NAMES[op];
    if (name === undefined) {
      lines.push(`  ${String(base).padStart(6)}  ??? 0x${op.toString(16).padStart(2, '0')}`);
      continue;
    }

    let operands = '';
    switch (op) {
      case 0x01: // LOAD_CONST
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

    lines.push(`  ${String(base).padStart(6)}  ${name}${operands}`);
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

  const section3 = readU32(data, 20);
  const section4 = readU32(data, 24);
  const codeEnd = Math.min(section4, data.length);

  const lines = disasm(data, section3, codeEnd);
  process.stdout.write(`; Code section (offset ${section3}, ${codeEnd - section3} bytes)\n`);
  for (const line of lines) {
    process.stdout.write(line + '\n');
  }
}

main();
