///|
/// SFNT container parsing, validation, and serialization.

///|
/// Parse an sfnt font binary into a map of table tag to raw table bytes.
pub fn parse_sfnt(data : Bytes) -> Result[Map[String, Bytes], FontError] {
  if data.length() < 12 {
    return Err(InvalidSfnt("Font data too short: < 12 bytes"))
  }
  let sfnt_version = read_u32(data, 0)
  if sfnt_version == 0x4F54544F {
    return Err(UnsupportedFormat("OTTO (CFF/OpenType) not supported in TrueType subsetter"))
  }
  if sfnt_version == 0x774F4646 || sfnt_version == 0x774F4632 {
    return Err(UnsupportedFormat("WOFF/WOFF2 container must be decompressed to TTF first"))
  }
  if sfnt_version != 0x00010000 && sfnt_version != 0x74727565 {
    return Err(InvalidSfnt("Unknown sfnt version: 0x\{sfnt_version}"))
  }
  let num_tables = read_u16(data, 4)
  let expected_dir_len = 12 + num_tables * 16
  if data.length() < expected_dir_len {
    return Err(InvalidSfnt("Font directory truncated"))
  }
  let tables : Map[String, Bytes] = Map([])
  for i = 0; i < num_tables; i = i + 1 {
    let rec_offset = 12 + i * 16
    let tag = read_tag(data, rec_offset)
    let offset = read_u32(data, rec_offset + 8)
    let length = read_u32(data, rec_offset + 12)
    if offset < 0 || length < 0 || offset + length > data.length() {
      return Err(InvalidSfnt("Table '\{tag}' offset/length exceeds file size"))
    }
    let tbytes = bytes_slice(data, offset, length)
    tables[tag] = tbytes
  }
  Ok(tables)
}

///|
/// Rebuild an sfnt TrueType font binary from individual tables.
/// Computes searchRange, table checksums, 4-byte padding alignment,
/// and correctly sets the global head.checkSumAdjustment (0xB1B0AFBA).
pub fn rebuild_sfnt(
  tables : Array[(String, Bytes)],
  flavor? : Int = 0x00010000
) -> Bytes {
  // Sort tables alphabetically by tag per OpenType spec
  tables.sort_by(fn(a, b) { a.0.compare(b.0) })

  let num_tables = tables.length()
  let entry_selector = log2_floor(num_tables)
  let search_range = (1 << entry_selector) * 16
  let range_shift = num_tables * 16 - search_range
  let header_size = 12 + num_tables * 16

  let mut total_size = header_size
  for i = 0; i < num_tables; i = i + 1 {
    let (_, tdata) = tables[i]
    total_size += pad4(tdata.length())
  }

  let out : Array[Byte] = Array::make(total_size, b'\x00')

  // Write Offset Table (12 bytes)
  write_be32(out, 0, flavor)
  write_be16(out, 4, num_tables)
  write_be16(out, 6, search_range)
  write_be16(out, 8, entry_selector)
  write_be16(out, 10, range_shift)

  let mut data_offset = header_size
  let mut head_table_offset = -1

  for i = 0; i < num_tables; i = i + 1 {
    let (tag, tdata) = tables[i]
    let rec_offset = 12 + i * 16

    // Tag (4 ASCII bytes)
    for j = 0; j < 4; j = j + 1 {
      out[rec_offset + j] = tag[j].to_int().to_byte()
    }

    // Checksum
    let checksum = calc_table_checksum(tdata)
    write_be32(out, rec_offset + 4, checksum)
    write_be32(out, rec_offset + 8, data_offset)
    write_be32(out, rec_offset + 12, tdata.length())

    // Copy table data
    for j = 0; j < tdata.length(); j = j + 1 {
      out[data_offset + j] = tdata[j]
    }

    if tag == "head" {
      head_table_offset = data_offset
    }

    data_offset += pad4(tdata.length())
  }

  // If head table exists, calculate head.checkSumAdjustment per spec
  if head_table_offset >= 0 && head_table_offset + 12 <= total_size {
    // 1. Ensure checkSumAdjustment is 0
    write_be32(out, head_table_offset + 8, 0)

    // 2. Compute checksum of the entire file
    let mut total_checksum = 0
    let total_words = pad4(total_size)
    for i = 0; i < total_words; i = i + 4 {
      let b0 = if i < total_size { out[i].to_int() } else { 0 }
      let b1 = if i + 1 < total_size { out[i + 1].to_int() } else { 0 }
      let b2 = if i + 2 < total_size { out[i + 2].to_int() } else { 0 }
      let b3 = if i + 3 < total_size { out[i + 3].to_int() } else { 0 }
      total_checksum = total_checksum + ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    }

    // 3. checkSumAdjustment = 0xB1B0AFBA - total_checksum
    // Note: 0xB1B0AFBA as signed 32-bit int is -1313796166
    let adjustment = 0xB1B0AFBA - total_checksum
    write_be32(out, head_table_offset + 8, adjustment)
  }

  Bytes::from_array(out[:])
}
