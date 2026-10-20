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
  inspect(cps[2], content="101") // '65' parsed as hex 0x65 = 101

  // Range parsing with hyphen
  let range_cps = parse_unicode_string("U+0041-U+0045")
  inspect(range_cps.length(), content="5") // A, B, C, D, E
  inspect(range_cps[0], content="65")
  inspect(range_cps[4], content="69")

  // Range parsing with dot-dot
  let dots_cps = parse_unicode_string("0x30..0x32")
  inspect(dots_cps.length(), content="3") // '0', '1', '2'
  inspect(dots_cps[0], content="48")
  inspect(dots_cps[2], content="50")

  // Wildcard parsing
  let wild_cps = parse_unicode_string("U+004?")
  inspect(wild_cps.length(), content="16") // 0x40..0x4F
  inspect(wild_cps[0], content="64")
  inspect(wild_cps[15], content="79")

  // Mixed delimiters (semicolon, newline, comma)
  let mixed = parse_unicode_string("U+0041; U+0042\nU+0043, 0x0044")
  inspect(mixed.length(), content="4")
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

///|
test "wb/kern_table_subsetting" {
  // Build a synthetic kern table:
  // 3 pairs: (10, 20, -50), (10, 30, -30), (25, 40, -20)
  let kern_raw : Array[Byte] = Array::make(36, b'\x00')
  write_be16(kern_raw, 0, 0) // version = 0
  write_be16(kern_raw, 2, 1) // nTables = 1

  // Subtable 0 header (offset 4)
  write_be16(kern_raw, 4, 0) // sub_version = 0
  write_be16(kern_raw, 6, 32) // length = 14 + 3 * 6 = 32
  write_be16(kern_raw, 8, 1) // coverage = 1 (horizontal, format 0)
  write_be16(kern_raw, 10, 3) // nPairs = 3
  write_be16(kern_raw, 12, 12) // searchRange = 2 * 6
  write_be16(kern_raw, 14, 1) // entrySelector = 1
  write_be16(kern_raw, 16, 6) // rangeShift = 3*6 - 12 = 6

  // Pair 1: (10, 20, -50)
  write_be16(kern_raw, 18, 10)
  write_be16(kern_raw, 20, 20)
  write_be16(kern_raw, 22, -50 & 0xFFFF)

  // Pair 2: (10, 30, -30)
  write_be16(kern_raw, 24, 10)
  write_be16(kern_raw, 26, 30)
  write_be16(kern_raw, 28, -30 & 0xFFFF)

  // Pair 3: (25, 40, -20)
  write_be16(kern_raw, 30, 25)
  write_be16(kern_raw, 32, 40)
  write_be16(kern_raw, 34, -20 & 0xFFFF)

  let kern_bytes = Bytes::from_array(kern_raw[:])

  // Test parse_kern_table
  let parsed = parse_kern_table(kern_bytes)
  inspect(parsed.length(), content="3")
  inspect(parsed[0].left, content="10")
  inspect(parsed[0].right, content="20")
  inspect(parsed[0].value, content="-50")

  // Test rebuild_kern_table: retain only glyphs 10 and 20 (mapped to new GID 1 and 2)
  let old_to_new_gid : Map[Int, Int] = Map([])
  old_to_new_gid[10] = 1
  old_to_new_gid[20] = 2
  // 30, 25, 40 are not retained

  let rebuilt_opt = rebuild_kern_table(kern_bytes, old_to_new_gid)
  inspect(rebuilt_opt is Some(_), content="true")

  let new_kern = rebuilt_opt.unwrap()
  let new_pairs = parse_kern_table(new_kern)
  inspect(new_pairs.length(), content="1")
  inspect(new_pairs[0].left, content="1")
  inspect(new_pairs[0].right, content="2")
  inspect(new_pairs[0].value, content="-50")

  // Test with no matching pairs -> None
  let empty_gid_map : Map[Int, Int] = Map([])
  empty_gid_map[1] = 1
  let none_opt = rebuild_kern_table(kern_bytes, empty_gid_map)
  inspect(none_opt is None, content="true")
}
