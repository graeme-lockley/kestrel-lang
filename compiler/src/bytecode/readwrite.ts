/**
 * Little-endian u32 read/write for bytecode manipulation.
 */

export function readU32(data: Uint8Array, offset: number): number {
  return (
    (data[offset]! | (data[offset + 1]! << 8) | (data[offset + 2]! << 16) | (data[offset + 3]! << 24)) >>>
    0
  );
}

/** Write u32 in-place at offset (little-endian). */
export function patchU32At(data: Uint8Array, offset: number, value: number): void {
  const n = value >>> 0;
  data[offset] = n & 0xff;
  data[offset + 1] = (n >> 8) & 0xff;
  data[offset + 2] = (n >> 16) & 0xff;
  data[offset + 3] = (n >> 24) & 0xff;
}
