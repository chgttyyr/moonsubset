///|
/// MoonSubset: Production-grade TrueType font subsetting toolchain in pure MoonBit.
///
/// Takes a TrueType font (.ttf) and an array of character codepoints,
/// and produces an optimized, standalone subset font containing only the required glyphs.

///|
/// Subset a TrueType font binary to retain only the specified codepoints.
/// Returns a SubsetResult containing the new font bytes and compression metrics.
pub fn subset(
  font_data : Bytes,
  codepoints : Array[Int]
) -> Result[SubsetResult, FontError] {
  // Step 1: Parse sfnt container into tables
  let tables = match parse_sfnt(font_data) {
    Ok(t) => t
    Err(e) => return Err(e)
  }

  // Step 2: Validate mandatory TrueType tables
  let head = match tables.get("head") {
    Some(t) => t
    None => return Err(TableNotFound("head"))
  }
  let maxp = match tables.get("maxp") {
    Some(t) => t
    None => return Err(TableNotFound("maxp"))
  }
  let hhea = match tables.get("hhea") {
    Some(t) => t
    None => return Err(TableNotFound("hhea"))
  }
  let hmtx = match tables.get("hmtx") {
    Some(t) => t
    None => return Err(TableNotFound("hmtx"))
  }
  let cmap = match tables.get("cmap") {
    Some(t) => t
    None => return Err(TableNotFound("cmap"))
  }
  let glyf = match tables.get("glyf") {
    Some(t) => t
    None => return Err(TableNotFound("glyf"))
  }
  let loca = match tables.get("loca") {
    Some(t) => t
    None => return Err(TableNotFound("loca"))
  }

  // Step 3: Extract font metadata
  let orig_num_glyphs = read_u16(maxp, 4)
  let orig_is_long_loca = read_i16(head, 50) == 1
  let orig_num_h_metrics = read_u16(hhea, 34)

  // Step 4: Parse loca and cmap tables
  let orig_loca = match parse_loca(loca, orig_num_glyphs, orig_is_long_loca) {
    Ok(l) => l
    Err(e) => return Err(e)
  }
  let cp_to_old_gid = match parse_cmap(cmap) {
    Ok(c) => c
    Err(e) => return Err(e)
  }

  // Step 5: Build initial glyph set (always include .notdef gid 0)
  let glyph_set : Map[Int, Bool] = Map([])
  glyph_set[0] = true

  let retained_cps : Array[Int] = []
  let seen_cps : Map[Int, Bool] = Map([])

  for cp in codepoints {
    if seen_cps.get(cp) is None {
      seen_cps[cp] = true
      match cp_to_old_gid.get(cp) {
        Some(gid) => {
          if gid > 0 {
            glyph_set[gid] = true
            retained_cps.push(cp)
          }
        }
        None => ()
      }
    }
  }

  // Step 6: Recursively resolve composite glyph dependencies
  scan_compound_refs(glyf, orig_loca, glyph_set)

  // Step 7: Build sorted array of retained old glyph IDs
  let old_gids : Array[Int] = []
  glyph_set.each(fn(gid, _) { old_gids.push(gid) })
  old_gids.sort()

  let subset_num_glyphs = old_gids.length()

  // Step 8: Build old GID -> new GID mapping
  let old_to_new_gid : Map[Int, Int] = Map([])
  for i, old_gid in old_gids {
    old_to_new_gid[old_gid] = i
  }

  // Step 9: Rebuild glyf and loca tables with rewritten component references
  let (new_glyf, new_loca, new_is_long) = rebuild_glyf_and_loca(
    glyf,
    orig_loca,
    old_gids,
    old_to_new_gid
  )

  // Step 10: Rebuild cmap with new GID mapping
  let cmap_pairs : Array[(Int, Int)] = []
  for cp in retained_cps {
    match cp_to_old_gid.get(cp) {
      Some(old_gid) => {
        match old_to_new_gid.get(old_gid) {
          Some(new_gid) => cmap_pairs.push((cp, new_gid))
          None => ()
        }
      }
      None => ()
    }
  }
  let new_cmap = build_cmap_table(cmap_pairs)

  // Step 11: Rebuild maxp, head, hhea, hmtx
  let new_maxp = rebuild_maxp(maxp, subset_num_glyphs)
  let new_head = rebuild_head(head, new_is_long)
  let new_hhea = rebuild_hhea(hhea, subset_num_glyphs)
  let new_hmtx = rebuild_hmtx(hmtx, old_gids, orig_num_h_metrics)

  // Step 12: Collect all tables for rebuilt sfnt container
  let rebuilt_tables : Array[(String, Bytes)] = [
    ("cmap", new_cmap),
    ("glyf", new_glyf),
    ("head", new_head),
    ("hhea", new_hhea),
    ("hmtx", new_hmtx),
    ("loca", new_loca),
    ("maxp", new_maxp),
  ]

  // Preserve metadata tables if present in original font
  let meta_tags = ["name", "OS/2", "post"]
  for tag in meta_tags {
    match tables.get(tag) {
      Some(tbytes) => rebuilt_tables.push((tag, tbytes))
      None => ()
    }
  }

  // Step 13: Rebuild final sfnt binary with checksums and alignment
  let output_bytes = rebuild_sfnt(rebuilt_tables)

  Ok({
    output_bytes,
    orig_size: font_data.length(),
    subset_size: output_bytes.length(),
    orig_num_glyphs,
    subset_num_glyphs,
    retained_codepoints: retained_cps,
  })
}

///|
/// Subset a font by a string of characters.
pub fn subset_from_string(
  font_data : Bytes,
  text : String
) -> Result[SubsetResult, FontError] {
  let codepoints : Array[Int] = []
  for c in text {
    codepoints.push(c.to_int())
  }
  subset(font_data, codepoints)
}

///|
/// Parse unicode hex strings like "U+4E00,U+4E8C" or "0x4E00,0x4E8C" into codepoints.
pub fn parse_unicode_string(input : String) -> Array[Int] {
  let codepoints : Array[Int] = []
  let parts = input.split(",")
  for part in parts {
    let mut s = part.trim().to_upper()
    if s.is_empty() {
      continue
    }
    if s.has_prefix("U+") {
      s = s[2:].to_owned()
    } else if s.has_prefix("0X") {
      s = s[2:].to_owned()
    }

    let mut cp = 0
    let mut valid = true
    for c in s {
      let code = c.to_int()
      let digit = if code >= '0'.to_int() && code <= '9'.to_int() {
        code - '0'.to_int()
      } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
        code - 'A'.to_int() + 10
      } else {
        valid = false
        0
      }
      cp = (cp << 4) | digit
    }
    if valid && cp > 0 {
      codepoints.push(cp)
    }
  }
  codepoints
}

///|
/// Font inspection summary for diagnostics and CLI info command.
pub(all) struct FontInspection {
  sfnt_version : Int
  num_tables : Int
  num_glyphs : Int
  is_long_loca : Bool
  units_per_em : Int
  checksum_adjustment : Int
  tables : Array[TableEntry]
} derive(Debug)

///|
/// Inspect a font binary and extract diagnostic information without modifying it.
pub fn inspect_font(font_data : Bytes) -> Result[FontInspection, FontError] {
  if font_data.length() < 12 {
    return Err(InvalidSfnt("Font data too short"))
  }
  let sfnt_version = read_u32(font_data, 0)
  let num_tables = read_u16(font_data, 4)
  let tables_map = match parse_sfnt(font_data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }

  let table_entries : Array[TableEntry] = []
  for i = 0; i < num_tables; i = i + 1 {
    let rec_offset = 12 + i * 16
    let tag = read_tag(font_data, rec_offset)
    let checksum = read_u32(font_data, rec_offset + 4)
    let offset = read_u32(font_data, rec_offset + 8)
    let length = read_u32(font_data, rec_offset + 12)
    table_entries.push({ tag, checksum, offset, length })
  }

  let num_glyphs = match tables_map.get("maxp") {
    Some(maxp) => if maxp.length() >= 6 { read_u16(maxp, 4) } else { 0 }
    None => 0
  }

  let (is_long_loca, units_per_em, checksum_adjustment) = match tables_map.get("head") {
    Some(head) => {
      let is_long = if head.length() >= 52 { read_i16(head, 50) == 1 } else { false }
      let upem = if head.length() >= 20 { read_u16(head, 18) } else { 1000 }
      let csum_adj = if head.length() >= 12 { read_u32(head, 8) } else { 0 }
      (is_long, upem, csum_adj)
    }
    None => (false, 1000, 0)
  }

  Ok({
    sfnt_version,
    num_tables,
    num_glyphs,
    is_long_loca,
    units_per_em,
    checksum_adjustment,
    tables: table_entries,
  })
}

///|
/// Generate standard CSS @font-face declaration for the subset font.
pub fn generate_font_face_css(
  family_name : String,
  font_url_or_path : String
) -> String {
  let sb = StringBuilder()
  sb.write_string("@font-face {\n")
  sb.write_string("  font-family: '\{family_name}';\n")
  sb.write_string("  src: url('\{font_url_or_path}') format('truetype');\n")
  sb.write_string("  font-display: swap;\n")
  sb.write_string("}\n")
  sb.to_string()
}
