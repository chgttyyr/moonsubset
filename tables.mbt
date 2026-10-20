///|
/// Builders and rewriters for head, hhea, hmtx, and maxp tables.

///|
/// Rebuild the maxp table with updated numGlyphs.
pub fn rebuild_maxp(orig_maxp : Bytes, new_num_glyphs : Int) -> Bytes {
  if orig_maxp.length() >= 6 {
    let out : Array[Byte] = Array::make(orig_maxp.length(), b'\x00')
    for i = 0; i < orig_maxp.length(); i = i + 1 {
      out[i] = orig_maxp[i]
    }
    write_be16(out, 4, new_num_glyphs)
    Bytes::from_array(out[:])
  } else {
    // Standard minimal TrueType maxp v1.0 (32 bytes)
    let out : Array[Byte] = Array::make(32, b'\x00')
    write_be32(out, 0, 0x00010000) // version 1.0
    write_be16(out, 4, new_num_glyphs)
    Bytes::from_array(out[:])
  }
}

///|
/// Rebuild the head table with indexToLocFormat set to long (1) and checksum reset.
pub fn rebuild_head(orig_head : Bytes, is_long_loca : Bool) -> Bytes {
  let len = if orig_head.length() >= 54 { orig_head.length() } else { 54 }
  let out : Array[Byte] = Array::make(len, b'\x00')

  for i = 0; i < orig_head.length() && i < len; i = i + 1 {
    out[i] = orig_head[i]
  }

  // Set checkSumAdjustment to 0 (will be recalculated globally in rebuild_sfnt)
  write_be32(out, 8, 0)

  // Set indexToLocFormat: 1 = long, 0 = short
  write_be16(out, 50, if is_long_loca { 1 } else { 0 })

  Bytes::from_array(out[:])
}

///|
/// Rebuild the hhea table with numberOfHMetrics updated to new_num_glyphs.
pub fn rebuild_hhea(orig_hhea : Bytes, new_num_glyphs : Int) -> Bytes {
  let len = if orig_hhea.length() >= 36 { orig_hhea.length() } else { 36 }
  let out : Array[Byte] = Array::make(len, b'\x00')

  for i = 0; i < orig_hhea.length() && i < len; i = i + 1 {
    out[i] = orig_hhea[i]
  }

  // Offset 34: numberOfHMetrics (all glyphs have long horizontal metrics)
  write_be16(out, 34, new_num_glyphs)

  Bytes::from_array(out[:])
}

///|
/// Rebuild the hmtx table containing horizontal metrics for all subset glyphs.
pub fn rebuild_hmtx(
  orig_hmtx : Bytes,
  old_gids : Array[Int],
  orig_num_h_metrics : Int,
) -> Bytes {
  let num_glyphs = old_gids.length()
  let out_len = num_glyphs * 4
  let out : Array[Byte] = Array::make(out_len, b'\x00')

  for i, old_gid in old_gids {
    let mut advance_width = 0
    let mut lsb = 0

    if old_gid < orig_num_h_metrics {
      let off = old_gid * 4
      if off + 4 <= orig_hmtx.length() {
        advance_width = read_u16(orig_hmtx, off)
        lsb = read_i16(orig_hmtx, off + 2)
      }
    } else {
      // Monospace / trailing glyphs share last advance_width
      if orig_num_h_metrics > 0 {
        let last_long_off = (orig_num_h_metrics - 1) * 4
        if last_long_off + 2 <= orig_hmtx.length() {
          advance_width = read_u16(orig_hmtx, last_long_off)
        }
      }
      let extra_idx = old_gid - orig_num_h_metrics
      let lsb_off = orig_num_h_metrics * 4 + extra_idx * 2
      if lsb_off + 2 <= orig_hmtx.length() {
        lsb = read_i16(orig_hmtx, lsb_off)
      }
    }

    write_be16(out, i * 4, advance_width)
    write_be16(out, i * 4 + 2, lsb & 0xFFFF)
  }

  Bytes::from_array(out[:])
}
