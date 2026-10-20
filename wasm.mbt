///|
/// WebAssembly and foreign interface bindings for MoonSubset.
/// Enables client-side font subsetting directly in the browser or JS runtimes.

///|
/// Subset font using a string of target characters.
/// Returns the new font bytes directly, or empty Bytes on failure.
pub fn subset_string_wasm(font_data : Bytes, text : String) -> Bytes {
  match subset_from_string(font_data, text) {
    Ok(result) => result.bytes()
    Err(_) => Bytes::make(0, b'\x00')
  }
}

///|
/// Inspect font and return lightweight diagnostic JSON summary for Web frontend.
pub fn inspect_font_wasm(font_data : Bytes) -> String {
  match inspect_font(font_data) {
    Ok(info) => {
      let sb = StringBuilder()
      sb.write_string("{\"num_tables\":\{info.num_tables},\"num_glyphs\":\{info.num_glyphs},\"units_per_em\":\{info.units_per_em},\"is_long_loca\":\{info.is_long_loca}}")
      sb.to_string()
    }
    Err(_) => "{}"
  }
}
