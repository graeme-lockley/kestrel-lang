/**
 * Constant pool (spec 03 §5). Tags and payload encoding.
 */
export const enum ConstTag {
  Int = 0,
  Float = 1,
  False = 2,
  True = 3,
  Unit = 4,
  Char = 5,
  String = 6,
}

export type ConstantEntry =
  | { tag: ConstTag.Int; value: number }
  | { tag: ConstTag.Float; value: number }
  | { tag: ConstTag.False }
  | { tag: ConstTag.True }
  | { tag: ConstTag.Unit }
  | { tag: ConstTag.Char; value: number }
  | { tag: ConstTag.String; stringIndex: number };

/** Encode one constant entry into buffer at offset; returns bytes written (4-aligned). */
export function encodeConstant(buf: DataView, offset: number, c: ConstantEntry): number {
  buf.setUint8(offset, c.tag);
  // 3 bytes padding
  buf.setUint8(offset + 1, 0);
  buf.setUint8(offset + 2, 0);
  buf.setUint8(offset + 3, 0);
  const payloadStart = offset + 4;
  let payloadLen = 0;
  switch (c.tag) {
    case ConstTag.Int: {
      const v = BigInt(Math.trunc(c.value));
      buf.setBigInt64(payloadStart, v, true);
      payloadLen = 8;
      break;
    }
    case ConstTag.Float:
      buf.setFloat64(payloadStart, c.value, true);
      payloadLen = 8;
      break;
    case ConstTag.False:
    case ConstTag.True:
    case ConstTag.Unit:
      payloadLen = 0;
      break;
    case ConstTag.Char:
      buf.setUint32(payloadStart, c.value >>> 0, true);
      payloadLen = 4;
      break;
    case ConstTag.String:
      buf.setUint32(payloadStart, c.stringIndex >>> 0, true);
      payloadLen = 4;
      break;
  }
  const total = 4 + payloadLen;
  return (total + 3) & ~3; // align to 4
}
