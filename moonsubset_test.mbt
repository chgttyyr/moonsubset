///|
/// Comprehensive end-to-end blackbox test suite for MoonSubset.
/// Validates all 9 test groups specified in section 6 of the task specification.

///|
/// Test Group 1: sfnt container parsing
test "test_1/sfnt_parsing" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let tables = @moonsubset.parse_sfnt(font_bytes).unwrap()

  // Assert essential tables exist
  inspect(tables.get("head") is Some(_), content="true")
  inspect(tables.get("maxp") is Some(_), content="true")
  inspect(tables.get("hhea") is Some(_), content="true")
  inspect(tables.get("hmtx") is Some(_), content="true")
  inspect(tables.get("cmap") is Some(_), content="true")
  inspect(tables.get("glyf") is Some(_), content="true")
  inspect(tables.get("loca") is Some(_), content="true")

  // Assert numGlyphs in maxp
  let maxp = tables.get("maxp").unwrap()
  let num_glyphs = @moonsubset.read_u16(maxp, 4)
  inspect(num_glyphs, content="470")
}

///|
/// Test Group 2: cmap parsing
test "test_2/cmap_parsing" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let tables = @moonsubset.parse_sfnt(font_bytes).unwrap()
  let cmap = tables.get("cmap").unwrap()
  let cp_to_gid = @moonsubset.parse_cmap(cmap).unwrap()

  // Codepoints 'A' (65), 'B' (66), 'C' (67) should have valid positive GIDs
  inspect(cp_to_gid.get(65) is Some(_), content="true")
  inspect(cp_to_gid.get(66) is Some(_), content="true")
  inspect(cp_to_gid.get(67) is Some(_), content="true")
}

///|
/// Test Group 3: Subsetting validity and glyph count
test "test_3/subset_validity_and_glyph_count" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let res = @moonsubset.subset(font_bytes, [65, 66, 67]).unwrap()

  // Output must parse back into sfnt
  let sub_tables = @moonsubset.parse_sfnt(res.bytes()).unwrap()
  let sub_maxp = sub_tables.get("maxp").unwrap()
  let sub_num_glyphs = @moonsubset.read_u16(sub_maxp, 4)

  // .notdef (gid 0) + 'A' + 'B' + 'C' = 4 glyphs
  inspect(sub_num_glyphs, content="4")
  inspect(res.subset_num_glyphs, content="4")
}

///|
/// Test Group 4: Character coverage and isolation
test "test_4/character_coverage_and_isolation" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let res = @moonsubset.subset(font_bytes, [65, 66]).unwrap() // Only A and B

  let sub_tables = @moonsubset.parse_sfnt(res.bytes()).unwrap()
  let sub_cmap = sub_tables.get("cmap").unwrap()
  let sub_cp_to_gid = @moonsubset.parse_cmap(sub_cmap).unwrap()

  // Requested characters must have non-zero GIDs
  let gid_a = sub_cp_to_gid.get(65).unwrap()
  let gid_b = sub_cp_to_gid.get(66).unwrap()
  inspect(gid_a > 0, content="true")
  inspect(gid_b > 0, content="true")

  // Unrequested characters must NOT be present
  inspect(sub_cp_to_gid.get(67) is None, content="true") // 'C'
  inspect(sub_cp_to_gid.get(68) is None, content="true") // 'D'
}

///|
/// Test Group 5: Composite glyph dependency resolution
test "test_5/composite_glyph_dependencies" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  // Codepoint 0xC0 (192) is 'À' (A with grave accent), a composite glyph
  let res = @moonsubset.subset(font_bytes, [192]).unwrap()

  // If composite recursion works, the subset must include:
  // gid 0 (.notdef) + composite glyph (À) + component glyphs (base letter 'A' + grave accent)
  // Therefore, total glyphs must be >= 3!
  inspect(res.subset_num_glyphs >= 3, content="true")

  let sub_tables = @moonsubset.parse_sfnt(res.bytes()).unwrap()
  let sub_cmap = sub_tables.get("cmap").unwrap()
  let sub_cp_to_gid = @moonsubset.parse_cmap(sub_cmap).unwrap()
  inspect(sub_cp_to_gid.get(192) is Some(_), content="true")
}

///|
/// Test Group 6: Loca format switching and consistency
test "test_6/loca_format_consistency" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let res = @moonsubset.subset(font_bytes, [65, 66]).unwrap()

  let sub_tables = @moonsubset.parse_sfnt(res.bytes()).unwrap()
  let head = sub_tables.get("head").unwrap()
  let loca = sub_tables.get("loca").unwrap()

  let index_to_loc = @moonsubset.read_i16(head, 50)
  // Must be long format (1)
  inspect(index_to_loc, content="1")

  // Number of loca entries must be (num_glyphs + 1) * 4 bytes
  let expected_loca_len = (res.subset_num_glyphs + 1) * 4
  inspect(loca.length(), content=expected_loca_len.to_string())
}

///|
/// Test Group 7: Global checksum compliance (0xB1B0AFBA)
test "test_7/global_checksum_compliance" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let res = @moonsubset.subset(font_bytes, [65, 66, 67]).unwrap()
  let out = res.bytes()

  // Calculate sum of all 32-bit words in the entire font file
  let total_words = @moonsubset.pad4(out.length())
  let mut total_checksum = 0
  for i = 0; i < total_words; i = i + 4 {
    let b0 = if i < out.length() { out[i].to_int() } else { 0 }
    let b1 = if i + 1 < out.length() { out[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < out.length() { out[i + 2].to_int() } else { 0 }
    let b3 = if i + 3 < out.length() { out[i + 3].to_int() } else { 0 }
    total_checksum = total_checksum + ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
  }

  // Per OpenType specification, sum of entire font must equal 0xB1B0AFBA (-1313820742 in signed int32)
  inspect(total_checksum, content="-1313820742")
}

///|
/// Test Group 8: Volume and size reduction report
test "test_8/volume_reduction_report" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let res = @moonsubset.subset(font_bytes, [65, 66, 67]).unwrap()

  // Original size ~66KB -> Subset size ~4KB
  inspect(res.subset_size < res.orig_size, content="true")
  inspect(res.savings_percent() > 80.0, content="true")
  inspect(res.compression_ratio() < 0.20, content="true")
}

///|
/// Test Group 9: Edge cases (empty set, missing chars, duplicates, malformed)
test "test_9/edge_cases" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")

  // Case 9.1: Empty codepoints produces valid font with only .notdef
  let empty_res = @moonsubset.subset(font_bytes, []).unwrap()
  inspect(empty_res.subset_num_glyphs, content="1") // Only .notdef

  // Case 9.2: Codepoints not present in font (e.g. random emoji/unsupported)
  let missing_res = @moonsubset.subset(font_bytes, [0x1FFFF]).unwrap()
  inspect(missing_res.subset_num_glyphs, content="1") // Only .notdef

  // Case 9.3: Duplicate codepoints are deduplicated gracefully
  let dup_res = @moonsubset.subset(font_bytes, [65, 65, 65, 66, 66]).unwrap()
  inspect(dup_res.subset_num_glyphs, content="3") // .notdef + A + B

  // Case 9.4: Malformed font data returns error instead of crashing
  let bad_data = Bytes::make(5, b'\x00')
  inspect(@moonsubset.subset(bad_data, [65]) is Err(_), content="true")

  // Case 9.5: Inspect font diagnostics
  let insp = @moonsubset.inspect_font(font_bytes).unwrap()
  inspect(insp.num_glyphs, content="470")
  inspect(insp.num_tables, content="17")
}

///|
/// Test Group 10: Kerning table (kern) preservation and filtering (Bonus 3.2 #3)
test "test_10/kern_preservation" {
  let font_bytes = @fs.read_file_to_bytes("fixtures/test-font.ttf")
  let orig_tables = @moonsubset.parse_sfnt(font_bytes).unwrap()

  // Find old GIDs for 'A' (65) and 'B' (66)
  let cmap = orig_tables.get("cmap").unwrap()
  let cp_to_gid = @moonsubset.parse_cmap(cmap).unwrap()
  let gid_a = cp_to_gid.get(65).unwrap()
  let gid_b = cp_to_gid.get(66).unwrap()

  // Construct a synthetic kern table containing pair (gid_a, gid_b, -40) and an unselected pair (gid_a, 999, -20)
  let kern_raw : Array[Byte] = Array::make(30, b'\x00')
  @moonsubset.write_be16(kern_raw, 0, 0) // version = 0
  @moonsubset.write_be16(kern_raw, 2, 1) // nTables = 1
  @moonsubset.write_be16(kern_raw, 4, 0) // sub_version = 0
  @moonsubset.write_be16(kern_raw, 6, 26) // length = 14 + 2 * 6 = 26
  @moonsubset.write_be16(kern_raw, 8, 1) // coverage = 1 (horizontal format 0)
  @moonsubset.write_be16(kern_raw, 10, 2) // nPairs = 2
  @moonsubset.write_be16(kern_raw, 12, 12) // searchRange
  @moonsubset.write_be16(kern_raw, 14, 1) // entrySelector
  @moonsubset.write_be16(kern_raw, 16, 0) // rangeShift

  // Pair 1: (gid_a, gid_b, -40)
  @moonsubset.write_be16(kern_raw, 18, gid_a)
  @moonsubset.write_be16(kern_raw, 20, gid_b)
  @moonsubset.write_be16(kern_raw, 22, -40 & 0xFFFF)

  // Pair 2: (gid_a, 999, -20) -- 999 will NOT be in subset
  @moonsubset.write_be16(kern_raw, 24, gid_a)
  @moonsubset.write_be16(kern_raw, 26, 999)
  @moonsubset.write_be16(kern_raw, 28, -20 & 0xFFFF)

  let table_list : Array[(String, Bytes)] = []
  orig_tables.each(fn(tag, data) { table_list.push((tag, data)) })
  table_list.push(("kern", Bytes::from_array(kern_raw[:])))

  let font_with_kern = @moonsubset.rebuild_sfnt(table_list)

  // 1. Subset with keep_kern = true
  let res_kept = @moonsubset.subset(font_with_kern, [65, 66], keep_kern=true).unwrap()
  let subset_tables = @moonsubset.parse_sfnt(res_kept.output_bytes).unwrap()
  inspect(subset_tables.get("kern") is Some(_), content="true")

  let new_kern = subset_tables.get("kern").unwrap()
  let pairs = @moonsubset.parse_kern_table(new_kern)
  inspect(pairs.length(), content="1") // Only (A, B) retained, (A, 999) dropped!
  inspect(pairs[0].value, content="-40")

  // 2. Subset with keep_kern = false
  let res_dropped = @moonsubset.subset(
    font_with_kern,
    [65, 66],
    keep_kern=false,
  ).unwrap()
  let dropped_tables = @moonsubset.parse_sfnt(res_dropped.output_bytes).unwrap()
  inspect(dropped_tables.get("kern") is None, content="true")
}
