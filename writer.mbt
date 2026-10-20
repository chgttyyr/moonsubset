///|
/// Binary writer utilities for rebuilding sfnt containers and OpenType tables.

///|
/// Round up to the next multiple of 4
pub fn pad4(n : Int) -> Int {
  (n + 3) & -4
}

///|
/// Write big-endian 16-bit integer into Array[Byte]
pub fn write_be16(out : Array[Byte], offset : Int, value : Int) -> Unit {
  out[offset] = ((value >> 8) & 0xFF).to_byte()
  out[offset + 1] = (value & 0xFF).to_byte()
}

///|
/// Write big-endian 32-bit integer into Array[Byte]
pub fn write_be32(out : Array[Byte], offset : Int, value : Int) -> Unit {
  out[offset] = ((value >> 24) & 0xFF).to_byte()
  out[offset + 1] = ((value >> 16) & 0xFF).to_byte()
  out[offset + 2] = ((value >> 8) & 0xFF).to_byte()
  out[offset + 3] = (value & 0xFF).to_byte()
}

///|
/// Calculate OpenType table checksum per spec:
/// Sum of all uint32 words in big-endian, padding with 0s for trailing bytes.
pub fn calc_table_checksum(data : Bytes) -> Int {
  let len = pad4(data.length())
  let mut sum = 0
  for i = 0; i < len; i = i + 4 {
    let b0 = if i < data.length() { data[i].to_int() } else { 0 }
    let b1 = if i + 1 < data.length() { data[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < data.length() { data[i + 2].to_int() } else { 0 }
    let b3 = if i + 3 < data.length() { data[i + 3].to_int() } else { 0 }
    sum = sum + ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
  }
  sum
}

///|
/// Calculate floor of log2(n) for sfnt directory search parameters
pub fn log2_floor(n : Int) -> Int {
  let mut result = 0
  let mut val = n
  while val > 1 {
    val = val >> 1
    result += 1
  }
  result
}
