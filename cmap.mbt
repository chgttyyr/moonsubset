///|
/// OpenType cmap table parser and builder.
/// Supports Format 4 (Unicode BMP) and Format 12 (Unicode Full / Non-BMP).

///|
/// Parse cmap table and return codepoint -> old glyph ID mapping.
pub fn parse_cmap(data : Bytes) -> Result[Map[Int, Int], FontError] {
  if data.length() < 4 {
    return Err(InvalidCmap("cmap table too short"))
  }
  let num_tables = read_u16(data, 2)
  if data.length() < 4 + num_tables * 8 {
    return Err(InvalidCmap("cmap encoding records truncated"))
  }

  // Find candidate subtables (Format 12 preferred, Format 4 fallback)
  let mut fmt12_offset = -1
  let mut fmt4_offset = -1

  for i = 0; i < num_tables; i = i + 1 {
    let rec = 4 + i * 8
    let platform_id = read_u16(data, rec)
    let encoding_id = read_u16(data, rec + 2)
    let sub_offset = read_u32(data, rec + 4)

    if sub_offset < 0 || sub_offset + 2 > data.length() {
      continue
    }

    let format = read_u16(data, sub_offset)

    if format == 12 {
      // Platform 3 / Encoding 10 or Platform 0 / Encoding 4
      if (platform_id == 3 && encoding_id == 10) || platform_id == 0 {
        fmt12_offset = sub_offset
      } else if fmt12_offset < 0 {
        fmt12_offset = sub_offset
      }
    } else if format == 4 {
      // Platform 3 / Encoding 1 or Platform 0 / Encoding 3
      if (platform_id == 3 && encoding_id == 1) || platform_id == 0 {
        fmt4_offset = sub_offset
      } else if fmt4_offset < 0 {
        fmt4_offset = sub_offset
      }
    }
  }

  if fmt12_offset >= 0 {
    parse_cmap_format12(data, fmt12_offset)
  } else if fmt4_offset >= 0 {
    parse_cmap_format4(data, fmt4_offset)
  } else {
    Err(UnsupportedFormat("No supported cmap subtable found (requires format 4 or 12)"))
  }
}

///|
/// Parse cmap format 12 subtable (32-bit full Unicode)
fn parse_cmap_format12(data : Bytes, offset : Int) -> Result[Map[Int, Int], FontError] {
  if offset + 16 > data.length() {
    return Err(InvalidCmap("Format 12 subtable header truncated"))
  }
  let length = read_u32(data, offset + 4)
  let n_groups = read_u32(data, offset + 12)
  if offset + length > data.length() || offset + 16 + n_groups * 12 > data.length() {
    return Err(InvalidCmap("Format 12 subtable groups truncated"))
  }

  let map : Map[Int, Int] = Map([])
  for i = 0; i < n_groups; i = i + 1 {
    let g_off = offset + 16 + i * 12
    let start_cp = read_u32(data, g_off)
    let end_cp = read_u32(data, g_off + 4)
    let start_gid = read_u32(data, g_off + 8)

    for cp = start_cp; cp <= end_cp; cp = cp + 1 {
      let gid = start_gid + (cp - start_cp)
      if gid > 0 {
        map[cp] = gid
      }
    }
  }
  Ok(map)
}

///|
/// Parse cmap format 4 subtable (16-bit BMP)
fn parse_cmap_format4(data : Bytes, offset : Int) -> Result[Map[Int, Int], FontError] {
  if offset + 14 > data.length() {
    return Err(InvalidCmap("Format 4 subtable header truncated"))
  }
  let length = read_u16(data, offset + 2)
  let seg_count_x2 = read_u16(data, offset + 6)
  let seg_count = seg_count_x2 / 2
  if offset + length > data.length() || offset + 14 + seg_count * 8 > data.length() {
    return Err(InvalidCmap("Format 4 subtable segments truncated"))
  }

  let end_codes_offset = offset + 14
  let start_codes_offset = end_codes_offset + seg_count * 2 + 2 // skip reservedPad
  let id_deltas_offset = start_codes_offset + seg_count * 2
  let id_range_offsets_offset = id_deltas_offset + seg_count * 2

  let map : Map[Int, Int] = Map([])

  for i = 0; i < seg_count; i = i + 1 {
    let end_cp = read_u16(data, end_codes_offset + i * 2)
    let start_cp = read_u16(data, start_codes_offset + i * 2)
    let id_delta = read_i16(data, id_deltas_offset + i * 2)
    let id_range_ro_pos = id_range_offsets_offset + i * 2
    let id_range_offset = read_u16(data, id_range_ro_pos)

    if start_cp == 0xFFFF {
      break
    }

    for cp = start_cp; cp <= end_cp; cp = cp + 1 {
      let mut gid = 0
      if id_range_offset == 0 {
        gid = (cp + id_delta) & 0xFFFF
      } else {
        let glyph_addr = id_range_ro_pos + id_range_offset + (cp - start_cp) * 2
        if glyph_addr + 2 <= data.length() {
          let val = read_u16(data, glyph_addr)
          if val != 0 {
            gid = (val + id_delta) & 0xFFFF
          }
        }
      }
      if gid > 0 {
        map[cp] = gid
      }
    }
  }

  Ok(map)
}

///|
/// Build a format 4 subtable from sorted (codepoint, new_gid) pairs.
/// All codepoints must be <= 0xFFFF.
pub fn build_cmap_format4_subtable(pairs : Array[(Int, Int)]) -> Bytes {
  // Construct contiguous segments with constant (gid - cp)
  let segments : Array[(Int, Int, Int)] = [] // (start_cp, end_cp, id_delta)

  for pair in pairs {
    let (cp, gid) = pair
    if cp > 0xFFFF {
      continue
    }
    let delta = (gid - cp) & 0xFFFF
    let can_extend = if segments.length() > 0 {
      let (_, end_c, d) = segments[segments.length() - 1]
      cp == end_c + 1 && delta == d
    } else {
      false
    }

    if can_extend {
      let idx = segments.length() - 1
      let (start_c, _, d) = segments[idx]
      segments[idx] = (start_c, cp, d)
    } else {
      segments.push((cp, cp, delta))
    }
  }

  // Always append the final 0xFFFF termination segment per spec
  segments.push((0xFFFF, 0xFFFF, 1))

  let seg_count = segments.length()
  let seg_count_x2 = seg_count * 2
  let entry_selector = log2_floor(seg_count)
  let search_range = (1 << entry_selector) * 2
  let range_shift = seg_count_x2 - search_range

  // subtable header (14) + endCode (segCount*2) + reservedPad (2) + startCode (segCount*2) + idDelta (segCount*2) + idRangeOffset (segCount*2)
  let subtable_len = 16 + seg_count * 8
  let out : Array[Byte] = Array::make(subtable_len, b'\x00')

  write_be16(out, 0, 4) // format 4
  write_be16(out, 2, subtable_len) // length
  write_be16(out, 4, 0) // language = 0
  write_be16(out, 6, seg_count_x2)
  write_be16(out, 8, search_range)
  write_be16(out, 10, entry_selector)
  write_be16(out, 12, range_shift)

  let end_codes_pos = 14
  let start_codes_pos = end_codes_pos + seg_count * 2 + 2
  let id_deltas_pos = start_codes_pos + seg_count * 2
  let id_range_offsets_pos = id_deltas_pos + seg_count * 2

  for i, seg in segments {
    let (start_c, end_c, delta) = seg
    write_be16(out, end_codes_pos + i * 2, end_c)
    write_be16(out, start_codes_pos + i * 2, start_c)
    write_be16(out, id_deltas_pos + i * 2, delta)
    write_be16(out, id_range_offsets_pos + i * 2, 0)
  }

  Bytes::from_array(out[:])
}

///|
/// Build a format 12 subtable from sorted (codepoint, new_gid) pairs.
pub fn build_cmap_format12_subtable(pairs : Array[(Int, Int)]) -> Bytes {
  let groups : Array[(Int, Int, Int)] = [] // (start_cp, end_cp, start_gid)

  for pair in pairs {
    let (cp, gid) = pair
    let can_extend = if groups.length() > 0 {
      let (_, end_cp, start_gid) = groups[groups.length() - 1]
      cp == end_cp + 1 && gid == start_gid + (cp - groups[groups.length() - 1].0)
    } else {
      false
    }

    if can_extend {
      let idx = groups.length() - 1
      let (start_cp, _, start_gid) = groups[idx]
      groups[idx] = (start_cp, cp, start_gid)
    } else {
      groups.push((cp, cp, gid))
    }
  }

  let num_groups = groups.length()
  let subtable_len = 16 + num_groups * 12
  let out : Array[Byte] = Array::make(subtable_len, b'\x00')

  write_be16(out, 0, 12) // format 12
  write_be16(out, 2, 0)  // reserved
  write_be32(out, 4, subtable_len) // length
  write_be32(out, 8, 0)  // language
  write_be32(out, 12, num_groups)

  for i, group in groups {
    let (start_cp, end_cp, start_gid) = group
    let off = 16 + i * 12
    write_be32(out, off, start_cp)
    write_be32(out, off + 4, end_cp)
    write_be32(out, off + 8, start_gid)
  }

  Bytes::from_array(out[:])
}

///|
/// Build a complete, highly-compatible cmap table.
/// Emits Format 4 (Platform 3/Encoding 1) and Format 12 (Platform 3/Encoding 10).
pub fn build_cmap_table(pairs : Array[(Int, Int)]) -> Bytes {
  pairs.sort_by(fn(a, b) { a.0.compare(b.0) })

  let has_non_bmp = pairs.any(fn(p) { p.0 > 0xFFFF })

  if !has_non_bmp {
    // BMP only: Format 4 is sufficient and universal
    let fmt4 = build_cmap_format4_subtable(pairs)
    // 2 encoding records: (3, 1) Windows Unicode BMP and (0, 3) Unicode 2.0+ BMP
    let header_len = 4 + 2 * 8
    let total_len = header_len + fmt4.length()
    let out : Array[Byte] = Array::make(total_len, b'\x00')

    write_be16(out, 0, 0) // version 0
    write_be16(out, 2, 2) // numTables = 2

    // Record 0: Platform 0 (Unicode), Encoding 3 (Unicode 2.0+ BMP)
    write_be16(out, 4, 0)
    write_be16(out, 6, 3)
    write_be32(out, 8, header_len)

    // Record 1: Platform 3 (Windows), Encoding 1 (Unicode BMP)
    write_be16(out, 12, 3)
    write_be16(out, 14, 1)
    write_be32(out, 16, header_len)

    for j = 0; j < fmt4.length(); j = j + 1 {
      out[header_len + j] = fmt4[j]
    }

    Bytes::from_array(out[:])
  } else {
    // Contains non-BMP: Generate dual format (Format 4 for BMP + Format 12 for Full)
    let fmt4 = build_cmap_format4_subtable(pairs)
    let fmt12 = build_cmap_format12_subtable(pairs)

    let header_len = 4 + 2 * 8 // 2 records: (3, 1) and (3, 10)
    let fmt4_offset = header_len
    let fmt12_offset = fmt4_offset + fmt4.length()
    let total_len = fmt12_offset + fmt12.length()

    let out : Array[Byte] = Array::make(total_len, b'\x00')

    write_be16(out, 0, 0) // version 0
    write_be16(out, 2, 2) // numTables = 2

    // Record 0: Platform 3 (Windows), Encoding 1 (Unicode BMP) -> Format 4
    write_be16(out, 4, 3)
    write_be16(out, 6, 1)
    write_be32(out, 8, fmt4_offset)

    // Record 1: Platform 3 (Windows), Encoding 10 (Unicode Full) -> Format 12
    write_be16(out, 12, 3)
    write_be16(out, 14, 10)
    write_be32(out, 16, fmt12_offset)

    for j = 0; j < fmt4.length(); j = j + 1 {
      out[fmt4_offset + j] = fmt4[j]
    }
    for j = 0; j < fmt12.length(); j = j + 1 {
      out[fmt12_offset + j] = fmt12[j]
    }

    Bytes::from_array(out[:])
  }
}
