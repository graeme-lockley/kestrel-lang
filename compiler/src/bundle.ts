/**
 * Bundle multiple CodegenResults into one (for multi-module scenarios).
 * Patches dep's bytecode to remap indices into the merged tables.
 */
import type { CodegenResult } from './codegen/codegen.js';
import type { ConstantEntry } from './bytecode/constants.js';
import { ConstTag } from './bytecode/constants.js';
import { Op } from './bytecode/instructions.js';
import { readU32, patchU32At } from './bytecode/readwrite.js';

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
          const idx = readU32(out, pc);
          patchU32At(out, pc, idx + offsets.constOffset);
        }
        pc += 4;
        break;
      case Op.CALL:
        if (pc + 8 <= out.length) {
          const fnId = readU32(out, pc);
          if (fnId !== 0xffffff00 && fnId !== 0xffffff01) {
            patchU32At(out, pc, fnId + offsets.funcOffset);
          }
        }
        pc += 8;
        break;
      case Op.CONSTRUCT:
        if (pc + 12 <= out.length) {
          const adtId = readU32(out, pc);
          patchU32At(out, pc, adtId + offsets.adtOffset);
        }
        pc += 12;
        break;
      case Op.CONSTRUCT_IMPORT:
        // import_index is stable; adt_id is relative to the dependency module (not merged ADT table).
        pc += 16;
        break;
      case Op.ALLOC_RECORD:
      case Op.GET_FIELD:
      case Op.SET_FIELD:
      case Op.SPREAD:
        if (pc + 4 <= out.length) {
          const idx = readU32(out, pc);
          patchU32At(out, pc, idx + offsets.shapeOffset);
        }
        pc += 4;
        break;
      case Op.LOAD_LOCAL:
      case Op.STORE_LOCAL:
        pc += 4;
        break;
      case Op.ADD:
      case Op.SUB:
      case Op.MUL:
      case Op.DIV:
      case Op.MOD:
      case Op.POW:
      case Op.EQ:
      case Op.NE:
      case Op.LT:
      case Op.LE:
      case Op.GT:
      case Op.GE:
      case Op.RET:
        break;
      case Op.JUMP:
      case Op.JUMP_IF_FALSE:
      case Op.TRY:
        pc += 4;
        break;
      case Op.MATCH:
        {
          const count = readU32(out, pc);
          pc += 4 + count * 4;
        }
        break;
      case Op.THROW:
      case Op.END_TRY:
      case Op.AWAIT:
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
