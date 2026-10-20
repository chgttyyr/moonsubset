///|
/// Binary reader utilities for parsing sfnt and OpenType tables.

///|
/// Read unsigned 8-bit integer from Bytes
pub fn read_u8(data : Bytes, offset : Int) -> Int {
  data[offset].to_int()
}

///|
/// Read signed 8-bit integer from Bytes
pub fn read_i8(data : Bytes, offset : Int) -> Int {
  let v = data[offset].to_int()
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
/// Read big-endian unsigned 16-bit integer from Bytes
pub fn read_u16(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 8) | data[offset + 1].to_int()
}

///|
/// Read big-endian signed 16-bit integer from Bytes
pub fn read_i16(data : Bytes, offset : Int) -> Int {
  let v = read_u16(data, offset)
  if v >= 32768 {
    v - 65536
  } else {
    v
  }
}

///|
/// Read big-endian 32-bit integer from Bytes
pub fn read_u32(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
/// Read 4-character ASCII tag
pub fn read_tag(data : Bytes, offset : Int) -> String {
  let b0 = data[offset].to_int()
  let b1 = data[offset + 1].to_int()
  let b2 = data[offset + 2].to_int()
  let b3 = data[offset + 3].to_int()
  let chars : Array[Char] = [
    b0.unsafe_to_char(),
    b1.unsafe_to_char(),
    b2.unsafe_to_char(),
    b3.unsafe_to_char(),
  ]
  String::from_array(chars)
}

///|
/// Slice a subrange of bytes
pub fn bytes_slice(data : Bytes, offset : Int, length : Int) -> Bytes {
  Bytes::makei(length, fn(i) { data[offset + i] })
}
