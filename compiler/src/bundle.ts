/**
 * Bundle multiple CodegenResults into one (for multi-module scenarios).
 * Patches dep's bytecode to remap indices into the merged tables.
 */
import type { CodegenResult } from './codegen/codegen.js';
import type { ConstantEntry } from './bytecode/constants.js';
import { ConstTag } from './bytecode/constants.js';

const Op = {
  LOAD_CONST: 0x01,
  CALL: 0x10,
  CONSTRUCT: 0x14,
  ALLOC_RECORD: 0x16,
  GET_FIELD: 0x17,
  SET_FIELD: 0x18,
  SPREAD: 0x19,
} as const;

function patchDepCode(
  code: Uint8Array,
  offsets: { constOffset: number; funcOffset: number; shapeOffset: number; adtOffset: number }
): Uint8Array {
  const out = new Uint8Array(code);
  let pc = 0;
  while (pc < out.length) {
    const op = out[pc]!;
    pc += 1;
    switch (op) {
      case Op.LOAD_CONST:
        if (pc + 4 <= out.length) {
          const idx = (out[pc]! | (out[pc + 1]! << 8) | (out[pc + 2]! << 16) | (out[pc + 3]! << 24)) >>> 0;
          const n = (idx + offsets.constOffset) >>> 0;
          out[pc] = n & 0xff;
          out[pc + 1] = (n >> 8) & 0xff;
          out[pc + 2] = (n >> 16) & 0xff;
          out[pc + 3] = (n >> 24) & 0xff;
        }
        pc += 4;
        break;
      case Op.CALL:
        if (pc + 8 <= out.length) {
          const fnId = (out[pc]! | (out[pc + 1]! << 8) | (out[pc + 2]! << 16) | (out[pc + 3]! << 24)) >>> 0;
          if (fnId !== 0xffffff00 && fnId !== 0xffffff01) {
            const n = (fnId + offsets.funcOffset) >>> 0;
            out[pc] = n & 0xff;
            out[pc + 1] = (n >> 8) & 0xff;
            out[pc + 2] = (n >> 16) & 0xff;
            out[pc + 3] = (n >> 24) & 0xff;
          }
        }
        pc += 8;
        break;
      case Op.CONSTRUCT:
        if (pc + 12 <= out.length) {
          const adtId = (out[pc]! | (out[pc + 1]! << 8) | (out[pc + 2]! << 16) | (out[pc + 3]! << 24)) >>> 0;
          const n = (adtId + offsets.adtOffset) >>> 0;
          out[pc] = n & 0xff;
          out[pc + 1] = (n >> 8) & 0xff;
          out[pc + 2] = (n >> 16) & 0xff;
          out[pc + 3] = (n >> 24) & 0xff;
        }
        pc += 12;
        break;
      case Op.ALLOC_RECORD:
      case Op.GET_FIELD:
      case Op.SET_FIELD:
      case Op.SPREAD:
        if (pc + 4 <= out.length) {
          const idx = (out[pc]! | (out[pc + 1]! << 8) | (out[pc + 2]! << 16) | (out[pc + 3]! << 24)) >>> 0;
          const n = (idx + offsets.shapeOffset) >>> 0;
          out[pc] = n & 0xff;
          out[pc + 1] = (n >> 8) & 0xff;
          out[pc + 2] = (n >> 16) & 0xff;
          out[pc + 3] = (n >> 24) & 0xff;
        }
        pc += 4;
        break;
      case 0x02: // LOAD_LOCAL
      case 0x03: // STORE_LOCAL
        pc += 4;
        break;
      case 0x04:
      case 0x05:
      case 0x06:
      case 0x07:
      case 0x08:
      case 0x09:
      case 0x0a:
      case 0x0b:
      case 0x0c:
      case 0x0d:
      case 0x0e:
      case 0x0f:
      case 0x11: // RET
        break;
      case 0x12: // JUMP
      case 0x13: // JUMP_IF_FALSE
      case 0x1b: // TRY
        pc += 4;
        break;
      case 0x15: // MATCH
        {
          const count = (out[pc]! | (out[pc + 1]! << 8) | (out[pc + 2]! << 16) | (out[pc + 3]! << 24)) >>> 0;
          pc += 4 + count * 4;
        }
        break;
      case 0x1a: // THROW
      case 0x1c: // END_TRY
      case 0x1d: // AWAIT
        break;
      default:
        pc = out.length;
        break;
    }
  }
  return out;
}

function remapConstants(constants: ConstantEntry[], stringOffset: number): ConstantEntry[] {
  return constants.map((c) => {
    if (c.tag === ConstTag.String) {
      return { ...c, stringIndex: c.stringIndex + stringOffset };
    }
    return c;
  });
}

function remapShapes(shapes: { nameIndices: number[] }[], stringOffset: number): { nameIndices: number[] }[] {
  return shapes.map((s) => ({
    nameIndices: s.nameIndices.map((n) => n + stringOffset),
  }));
}

function remapAdts(adts: { nameIndex: number; constructors: { nameIndex: number; payloadTypeIndex: number }[] }[], stringOffset: number) {
  return adts.map((a) => ({
    nameIndex: a.nameIndex + stringOffset,
    constructors: a.constructors.map((c) => ({
      nameIndex: c.nameIndex + stringOffset,
      payloadTypeIndex: c.payloadTypeIndex, // type index, not string — leave unchanged
    })),
  }));
}

/** Merge main + deps into a single CodegenResult. Main comes first. */
export function bundleCodegenResults(main: CodegenResult, deps: CodegenResult[]): CodegenResult {
  let stringTable = [...main.stringTable];
  let constantPool = [...main.constantPool];
  let functionTable = [...main.functionTable];
  let code = new Uint8Array(main.code);
  let shapes = [...main.shapes];
  let adts = [...main.adts];

  for (const dep of deps) {
    const strOff = stringTable.length;
    const poolOff = constantPool.length;
    const funcOff = functionTable.length;
    const shapeOff = shapes.length;
    const adtOff = adts.length;

    stringTable = stringTable.concat(dep.stringTable);
    constantPool = constantPool.concat(remapConstants(dep.constantPool, strOff));
    shapes = shapes.concat(remapShapes(dep.shapes, strOff));
    adts = adts.concat(remapAdts(dep.adts, strOff));

    const codeOff = code.length;
    for (const fn of dep.functionTable) {
      functionTable.push({
        nameIndex: fn.nameIndex + strOff,
        arity: fn.arity,
        codeOffset: fn.codeOffset + codeOff,
      });
    }

    const patched = patchDepCode(dep.code, {
      constOffset: poolOff,
      funcOffset: funcOff,
      shapeOffset: shapeOff,
      adtOffset: adtOff,
    });
    const merged = new Uint8Array(code.length + patched.length);
    merged.set(code);
    merged.set(patched, code.length);
    code = merged;
  }

  return {
    stringTable,
    constantPool,
    code,
    functionTable,
    importSpecifierIndices: main.importSpecifierIndices,
    shapes,
    adts,
  };
}
