///|
/// Whitebox unit tests for internal algorithm validation and invariants.

///|
test "wb/binary_reader_and_writer" {
  let arr : Array[Byte] = Array::make(16, b'\x00')
  write_be16(arr, 0, 0x1234)
  write_be32(arr, 2, 0x56789ABC)
  let bytes = Bytes::from_array(arr[:])

  inspect(read_u16(bytes, 0), content="4660") // 0x1234
  inspect(read_u32(bytes, 2), content="1450744508") // 0x56789ABC
  inspect(pad4(1), content="4")
  inspect(pad4(4), content="4")
  inspect(pad4(5), content="8")
}

///|
test "wb/cmap_format4_builder" {
  // Map 'A' (65) -> 1, 'B' (66) -> 2, 'C' (67) -> 3
  let pairs : Array[(Int, Int)] = [(65, 1), (66, 2), (67, 3)]
  let subtable = build_cmap_format4_subtable(pairs)

  inspect(read_u16(subtable, 0), content="4") // format 4
  inspect(subtable.length() > 16, content="true")
}

///|
test "wb/cmap_format12_builder" {
  let pairs : Array[(Int, Int)] = [(65, 1), (66, 2), (0x1F600, 3)]
  let subtable = build_cmap_format12_subtable(pairs)

  inspect(read_u16(subtable, 0), content="12") // format 12
  inspect(read_u32(subtable, 12), content="2") // 2 groups: 65..66 and 0x1F600
}

///|
test "wb/unicode_parser" {
  let cps = parse_unicode_string("U+4E00, 0x4E01, 65")
  inspect(cps.length(), content="3")
  inspect(cps[0], content="19968") // 0x4E00
  inspect(cps[1], content="19969") // 0x4E01
  inspect(cps[2], content="101")   // '65' parsed as hex 0x65 = 101
}

///|
test "wb/presets" {
  let ascii = get_ascii_preset()
  inspect(ascii.length(), content="95") // 32..126
  let digits = get_digits_preset()
  inspect(digits.length(), content="10")
  inspect(get_preset_by_name("ascii") is Some(_), content="true")
  inspect(get_preset_by_name("digits") is Some(_), content="true")
  inspect(get_preset_by_name("chinese") is Some(_), content="true")
  inspect(get_preset_by_name("unknown") is None, content="true")
}

///|
test "wb/wasm_exports" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let sub_bytes = subset_string_wasm(font_bytes, "ABC")
  inspect(sub_bytes.length() > 0, content="true")
  inspect(sub_bytes.length() < font_bytes.length(), content="true")

  let json = inspect_font_wasm(font_bytes)
  inspect(json.contains("num_glyphs"), content="true")
}
