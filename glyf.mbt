///|
/// OpenType glyf and loca table parser, dependency resolver, and builder.

///|
/// Parse the loca table into an array of glyph offsets in the glyf table.
pub fn parse_loca(
  loca_data : Bytes,
  num_glyphs : Int,
  is_long : Bool
) -> Result[Array[Int], FontError] {
  let expected_entries = num_glyphs + 1
  if is_long {
    if loca_data.length() < expected_entries * 4 {
      return Err(InvalidLoca("Long loca table truncated"))
    }
    let offsets : Array[Int] = Array::make(expected_entries, 0)
    for i = 0; i < expected_entries; i = i + 1 {
      offsets[i] = read_u32(loca_data, i * 4)
    }
    Ok(offsets)
  } else {
    if loca_data.length() < expected_entries * 2 {
      return Err(InvalidLoca("Short loca table truncated"))
    }
    let offsets : Array[Int] = Array::make(expected_entries, 0)
    for i = 0; i < expected_entries; i = i + 1 {
      offsets[i] = read_u16(loca_data, i * 2) * 2
    }
    Ok(offsets)
  }
}

///|
/// Scan composite glyphs recursively and add referenced component glyph IDs.
pub fn scan_compound_refs(
  glyf_data : Bytes,
  loca : Array[Int],
  glyph_set : Map[Int, Bool]
) -> Unit {
  let mut changed = true
  while changed {
    changed = false
    let current_gids : Array[Int] = []
    glyph_set.each(fn(gid, _) { current_gids.push(gid) })

    for gid in current_gids {
      if gid >= loca.length() - 1 {
        continue
      }
      let start_off = loca[gid]
      let end_off = loca[gid + 1]
      if start_off == end_off || start_off + 10 > glyf_data.length() {
        continue // empty or invalid glyph
      }

      let num_contours = read_i16(glyf_data, start_off)
      if num_contours >= 0 {
        continue // simple glyph
      }

      // Compound glyph: skip numberOfContours (2) + bbox (8) = 10 bytes
      let mut pos = start_off + 10
      let mut has_more = true

      while has_more && pos + 4 <= glyf_data.length() {
        let flags = read_u16(glyf_data, pos)
        let component_gid = read_u16(glyf_data, pos + 2)

        if glyph_set.get(component_gid) is None {
          glyph_set[component_gid] = true
          changed = true
        }

        pos += 4 // flags(2) + glyphIndex(2)

        // Skip argument 1 and 2
        let arg1_and_2_are_words = (flags & 0x0001) != 0
        if arg1_and_2_are_words {
          pos += 4
        } else {
          pos += 2
        }

        // Skip transformation records
        let we_have_a_scale = (flags & 0x0008) != 0
        let we_have_xy_scale = (flags & 0x0040) != 0
        let we_have_2x2 = (flags & 0x0080) != 0

        if we_have_a_scale {
          pos += 2
        } else if we_have_xy_scale {
          pos += 4
        } else if we_have_2x2 {
          pos += 8
        }

        has_more = (flags & 0x0020) != 0
      }
    }
  }
}

///|
/// Rewrite compound glyph component indices to new glyph IDs.
fn rewrite_compound_glyph(
  glyph_data : Bytes,
  old_to_new_gid : Map[Int, Int]
) -> Bytes {
  let out : Array[Byte] = Array::make(glyph_data.length(), b'\x00')
  for i = 0; i < glyph_data.length(); i = i + 1 {
    out[i] = glyph_data[i]
  }

  // Skip numContours(2) + bbox(8) = 10 bytes
  let mut pos = 10
  let mut has_more = true

  while has_more && pos + 4 <= glyph_data.length() {
    let flags = read_u16(glyph_data, pos)
    let old_gid = read_u16(glyph_data, pos + 2)
    let new_gid = old_to_new_gid.get(old_gid).unwrap_or(0)

    // Rewrite new glyph ID in big-endian
    out[pos + 2] = ((new_gid >> 8) & 0xFF).to_byte()
    out[pos + 3] = (new_gid & 0xFF).to_byte()

    pos += 4

    let arg1_and_2_are_words = (flags & 0x0001) != 0
    if arg1_and_2_are_words {
      pos += 4
    } else {
      pos += 2
    }

    let we_have_a_scale = (flags & 0x0008) != 0
    let we_have_xy_scale = (flags & 0x0040) != 0
    let we_have_2x2 = (flags & 0x0080) != 0

    if we_have_a_scale {
      pos += 2
    } else if we_have_xy_scale {
      pos += 4
    } else if we_have_2x2 {
      pos += 8
    }

    has_more = (flags & 0x0020) != 0
  }

  Bytes::from_array(out[:])
}

///|
/// Rebuild glyf and loca tables for subset glyphs.
/// Returns (new_glyf, new_loca, is_long_loca).
pub fn rebuild_glyf_and_loca(
  glyf_data : Bytes,
  orig_loca : Array[Int],
  old_gids : Array[Int],
  old_to_new_gid : Map[Int, Int]
) -> (Bytes, Bytes, Bool) {
  let glyf_parts : Array[Bytes] = []
  let loca_offsets : Array[Int] = []
  let mut current_offset = 0

  for old_gid in old_gids {
    loca_offsets.push(current_offset)
    if old_gid >= orig_loca.length() - 1 {
      // Empty glyph beyond bounds
      continue
    }

    let start_off = orig_loca[old_gid]
    let end_off = orig_loca[old_gid + 1]

    if start_off >= end_off || start_off >= glyf_data.length() {
      // Empty glyph (e.g. whitespace)
      continue
    }

    let glyph_len = end_off - start_off
    let actual_len = if start_off + glyph_len > glyf_data.length() {
      glyf_data.length() - start_off
    } else {
      glyph_len
    }

    let raw_glyph = bytes_slice(glyf_data, start_off, actual_len)
    let num_contours = if raw_glyph.length() >= 2 {
      read_i16(raw_glyph, 0)
    } else {
      0
    }

    let final_glyph = if num_contours < 0 {
      rewrite_compound_glyph(raw_glyph, old_to_new_gid)
    } else {
      raw_glyph
    }

    glyf_parts.push(final_glyph)
    // Align each glyph record to 4 bytes in glyf table
    current_offset += pad4(final_glyph.length())
  }

  // Final loca offset marking end of last glyph
  loca_offsets.push(current_offset)

  // Assemble new glyf bytes
  let glyf_out : Array[Byte] = Array::make(current_offset, b'\x00')
  let mut write_pos = 0
  for part in glyf_parts {
    for j = 0; j < part.length(); j = j + 1 {
      glyf_out[write_pos + j] = part[j]
    }
    write_pos += pad4(part.length())
  }

  // Assemble new loca bytes (Long format 32-bit offsets)
  let loca_len = loca_offsets.length() * 4
  let loca_out : Array[Byte] = Array::make(loca_len, b'\x00')
  for i, off in loca_offsets {
    write_be32(loca_out, i * 4, off)
  }

  (Bytes::from_array(glyf_out[:]), Bytes::from_array(loca_out[:]), true)
}
