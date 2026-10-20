///|
/// TrueType / OpenType Format 0 Horizontal Kerning Subsetting.
///
/// Filters and remaps kerning pairs when both left and right glyphs
/// are preserved in the subset font.

///|
/// A kerning pair with left GID, right GID, and value in FUnits.
pub(all) struct KernPair {
  left : Int
  right : Int
  value : Int
} derive(Debug, Eq)

///|
/// Parse Format 0 horizontal kerning pairs from a TrueType kern table.
/// Returns an empty array if table is malformed or not Format 0.
pub fn parse_kern_table(data : Bytes) -> Array[KernPair] {
  let pairs : Array[KernPair] = []
  if data.length() < 4 {
    return pairs
  }

  // Microsoft OpenType version 0 header
  let version = read_u16(data, 0)
  if version != 0 {
    return pairs
  }

  let n_tables = read_u16(data, 2)
  let mut offset = 4

  for _t = 0; _t < n_tables; _t = _t + 1 {
    if offset + 6 > data.length() {
      break
    }
    let _sub_version = read_u16(data, offset)
    let length = read_u16(data, offset + 2)
    let coverage = read_u16(data, offset + 4)

    let format = coverage >> 8
    let is_horizontal = (coverage & 1) != 0
    let is_cross_stream = (coverage & 4) != 0

    // Format 0 horizontal, non-cross-stream
    if format == 0 && is_horizontal && !is_cross_stream {
      if offset + 14 <= data.length() {
        let n_pairs = read_u16(data, offset + 6)
        let mut p_off = offset + 14
        for _p = 0; _p < n_pairs; _p = _p + 1 {
          if p_off + 6 > data.length() || p_off + 6 > offset + length {
            break
          }
          let left = read_u16(data, p_off)
          let right = read_u16(data, p_off + 2)
          let value = read_i16(data, p_off + 4)
          pairs.push({ left, right, value, })
          p_off += 6
        }
      }
    }

    if length < 6 {
      break
    }
    offset += length
  }

  pairs
}

///|
/// Subset and rebuild a Format 0 kern table using old_to_new_gid mapping.
/// Returns Some(rebuilt_bytes) if any pairs remain, or None if no pairs were kept.
pub fn rebuild_kern_table(
  orig_kern : Bytes,
  old_to_new_gid : Map[Int, Int],
) -> Bytes? {
  let orig_pairs = parse_kern_table(orig_kern)
  if orig_pairs.is_empty() {
    return None
  }

  let kept_pairs : Array[KernPair] = []
  for p in orig_pairs {
    match (old_to_new_gid.get(p.left), old_to_new_gid.get(p.right)) {
      (Some(new_left), Some(new_right)) =>
        kept_pairs.push({ left: new_left, right: new_right, value: p.value, })
      _ => ()
    }
  }

  if kept_pairs.is_empty() {
    return None
  }

  // Sort pairs by (left << 16) | right as required by OpenType specification
  kept_pairs.sort_by(fn(a, b) {
    if a.left != b.left {
      a.left.compare(b.left)
    } else {
      a.right.compare(b.right)
    }
  })

  // Deduplicate consecutive identical (left, right) pairs if any
  let unique_pairs : Array[KernPair] = []
  let mut last_key = -1
  for p in kept_pairs {
    let key = (p.left << 16) | (p.right & 0xFFFF)
    if key != last_key {
      unique_pairs.push(p)
      last_key = key
    }
  }

  let n_pairs = unique_pairs.length()
  if n_pairs == 0 {
    return None
  }

  // Defensively cap at max uint16 entries
  let actual_n_pairs = if n_pairs > 10920 { 10920 } else { n_pairs }

  let subtable_len = 14 + actual_n_pairs * 6
  let total_len = 4 + subtable_len

  let entry_selector = log2_floor(actual_n_pairs)
  let search_range = (1 << entry_selector) * 6
  let range_shift = actual_n_pairs * 6 - search_range

  let out : Array[Byte] = Array::make(total_len, b'\x00')

  // Kern table header (Microsoft OpenType version 0)
  write_be16(out, 0, 0) // version = 0
  write_be16(out, 2, 1) // nTables = 1

  // Format 0 subtable header
  write_be16(out, 4, 0) // sub_version = 0
  write_be16(out, 6, subtable_len) // length
  write_be16(out, 8, 1) // coverage = 1 (horizontal kerning, format 0)
  write_be16(out, 10, actual_n_pairs)
  write_be16(out, 12, search_range)
  write_be16(out, 14, entry_selector)
  write_be16(out, 16, range_shift)

  let mut p_off = 18
  for i = 0; i < actual_n_pairs; i = i + 1 {
    let p = unique_pairs[i]
    write_be16(out, p_off, p.left)
    write_be16(out, p_off + 2, p.right)
    write_be16(out, p_off + 4, p.value & 0xFFFF)
    p_off += 6
  }

  Some(Bytes::from_array(out[:]))
}
