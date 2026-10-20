///|
/// MoonSubset CLI: Production-grade TrueType font subsetting command-line tool.

fn print_usage() -> Unit {
  println("MoonSubset: Production TrueType font subsetting toolchain in pure MoonBit")
  println("")
  println("Usage:")
  println("  moonsubset subset --font <in.ttf> --chars <chars> --out <out.ttf>")
  println("  moonsubset subset -f <in.ttf> --text-file <text.txt> -o <out.ttf>")
  println("  moonsubset subset -f <in.ttf> --preset <ascii|chinese|digits> -o <out.ttf>")
  println("  moonsubset subset -f <in.ttf> --unicodes <U+4E00,U+4E8C> -o <out.ttf>")
  println("")
  println("Options:")
  println("  -f, --font <path>         Path to input TrueType font (.ttf)")
  println("  -c, --chars <string>      Characters to retain in subset")
  println("  -t, --text-file <path>    Text file containing characters to retain")
  println("  -u, --unicodes <list>     Comma-separated hex codepoints (e.g. U+4E00,0x4E8C)")
  println("  -p, --preset <name>       Preset character set (ascii, digits, alphanumeric, chinese)")
  println("  -o, --out <path>          Output path for subset font (.ttf)")
  println("  --css <family_name>       Also generate a CSS @font-face declaration file")
  println("  -v, --verbose             Print detailed inspection information")
  println("  -h, --help                Show this help message")
}

fn main {
  let raw_args = @env.args()

  // Subcommands: subset, info
  let mut is_info_cmd = false
  let mut start_idx = 1
  if raw_args.length() > 1 {
    if raw_args[1] == "info" {
      is_info_cmd = true
      start_idx = 2
    } else if raw_args[1] == "subset" {
      start_idx = 2
    }
  }

  if raw_args.length() <= start_idx {
    print_usage()
    return
  }

  let mut font_path = ""
  let mut chars_arg = ""
  let mut text_file_path = ""
  let mut unicodes_arg = ""
  let mut preset_arg = ""
  let mut out_path = ""
  let mut css_family = ""
  let mut verbose = false

  let mut i = start_idx
  while i < raw_args.length() {
    let arg = raw_args[i]
    if arg == "-h" || arg == "--help" {
      print_usage()
      return
    } else if (arg == "-f" || arg == "--font") && i + 1 < raw_args.length() {
      font_path = raw_args[i + 1]
      i += 2
    } else if (arg == "-c" || arg == "--chars") && i + 1 < raw_args.length() {
      chars_arg = raw_args[i + 1]
      i += 2
    } else if (arg == "-t" || arg == "--text-file") && i + 1 < raw_args.length() {
      text_file_path = raw_args[i + 1]
      i += 2
    } else if (arg == "-u" || arg == "--unicodes") && i + 1 < raw_args.length() {
      unicodes_arg = raw_args[i + 1]
      i += 2
    } else if (arg == "-p" || arg == "--preset") && i + 1 < raw_args.length() {
      preset_arg = raw_args[i + 1]
      i += 2
    } else if (arg == "-o" || arg == "--out") && i + 1 < raw_args.length() {
      out_path = raw_args[i + 1]
      i += 2
    } else if arg == "--css" && i + 1 < raw_args.length() {
      css_family = raw_args[i + 1]
      i += 2
    } else if arg == "-v" || arg == "--verbose" {
      verbose = true
      i += 1
    } else {
      println("Unknown argument: \{arg}")
      print_usage()
      return
    }
  }

  if font_path.is_empty() {
    println("Error: Missing required argument: --font <path>")
    return
  }

  // Handle 'info' command
  if is_info_cmd {
    let font_bytes = try {
      @fs.read_file_to_bytes(font_path)
    } catch {
      _ => {
        println("Error: Failed to read font file: \{font_path}")
        return
      }
    }
    match @moonsubset.inspect_font(font_bytes) {
      Ok(info) => {
        println("==================================================")
        println("  MoonSubset: Font Inspection Report              ")
        println("==================================================")
        println("File: \{font_path} (\{font_bytes.length()} bytes)")
        println("Tables Count: \{info.num_tables}")
        println("Total Glyphs: \{info.num_glyphs}")
        println("Units Per Em: \{info.units_per_em}")
        println("Loca Format : " + (if info.is_long_loca { "Long (32-bit)" } else { "Short (16-bit)" }))
        println("Checksum Adj: 0x\{info.checksum_adjustment}")
        println("--------------------------------------------------")
        println("Table Directory:")
        for t in info.tables {
          println("  - \{t.tag} (offset=\{t.offset}, length=\{t.length}, checksum=0x\{t.checksum})")
        }
        println("==================================================")
      }
      Err(e) => println("Error: Failed to inspect font: \{e}")
    }
    return
  }

  if out_path.is_empty() {
    println("Error: Missing required argument: --out <path>")
    return
  }

  // Collect target codepoints from all sources
  let target_codepoints : Array[Int] = []

  // 1. From direct string
  if !chars_arg.is_empty() {
    for c in chars_arg {
      target_codepoints.push(c.to_int())
    }
  }

  // 2. From text file
  if !text_file_path.is_empty() {
    try {
      let file_content = @fs.read_file_to_string(text_file_path)
      for c in file_content {
        target_codepoints.push(c.to_int())
      }
    } catch {
      _ => {
        println("Error: Failed to read text file: \{text_file_path}")
        return
      }
    }
  }

  // 3. From unicodes list
  if !unicodes_arg.is_empty() {
    let parsed_cps = @moonsubset.parse_unicode_string(unicodes_arg)
    for cp in parsed_cps {
      target_codepoints.push(cp)
    }
  }

  // 4. From preset
  if !preset_arg.is_empty() {
    match @moonsubset.get_preset_by_name(preset_arg) {
      Some(preset_cps) => {
        for cp in preset_cps {
          target_codepoints.push(cp)
        }
      }
      None => {
        println("Error: Unknown preset: '\{preset_arg}'. Supported presets: ascii, digits, alphanumeric, chinese")
        return
      }
    }
  }

  if verbose {
    println("[Info] Reading font from: \{font_path}")
    println("[Info] Requested codepoints count: \{target_codepoints.length()}")
  }

  // Read input font bytes
  let font_bytes = try {
    @fs.read_file_to_bytes(font_path)
  } catch {
    _ => {
      println("Error: Failed to read input font file: \{font_path}")
      return
    }
  }

  // Run pure subsetting engine
  let result = match @moonsubset.subset(font_bytes, target_codepoints) {
    Ok(r) => r
    Err(e) => {
      println("Error: Subsetting failed: \{e}")
      return
    }
  }

  // Write subset font bytes
  try {
    @fs.write_bytes_to_file(out_path, result.bytes())
  } catch {
    _ => {
      println("Error: Failed to write output font to: \{out_path}")
      return
    }
  }

  // Generate CSS if requested
  if !css_family.is_empty() {
    let css_file_path = out_path + ".css"
    let css_content = @moonsubset.generate_font_face_css(css_family, out_path)
    try {
      @fs.write_string_to_file(css_file_path, css_content)
      println("[CSS] Generated @font-face stylesheet: \{css_file_path}")
    } catch {
      _ => println("Warning: Failed to write CSS file: \{css_file_path}")
    }
  }

  // Print volume report
  let savings = result.savings_percent()
  println("==================================================")
  println("  MoonSubset: Subsetting Completed Successfully!  ")
  println("==================================================")
  println("Original Size : \{result.orig_size} bytes (\{result.orig_num_glyphs} glyphs)")
  println("Subset Size   : \{result.subset_size} bytes (\{result.subset_num_glyphs} glyphs)")
  println("Compression   : \{savings}% reduction")
  println("Retained Chars: \{result.retained_codepoints.length()} unique characters (plus .notdef)")
  println("Output File   : \{out_path}")
  println("==================================================")
}
