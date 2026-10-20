///|
/// Error types for font parsing and subsetting operations.
pub(all) enum FontError {
  InvalidSfnt(String)
  TableNotFound(String)
  InvalidCmap(String)
  InvalidGlyf(String)
  InvalidLoca(String)
  InvalidMetrics(String)
  UnsupportedFormat(String)
} derive(Debug, Eq)

///|
pub impl Show for FontError with fn output(self : FontError, logger : &Logger) -> Unit {
  match self {
    InvalidSfnt(s) => logger.write_string("InvalidSfnt(" + s + ")")
    TableNotFound(s) => logger.write_string("TableNotFound(" + s + ")")
    InvalidCmap(s) => logger.write_string("InvalidCmap(" + s + ")")
    InvalidGlyf(s) => logger.write_string("InvalidGlyf(" + s + ")")
    InvalidLoca(s) => logger.write_string("InvalidLoca(" + s + ")")
    InvalidMetrics(s) => logger.write_string("InvalidMetrics(" + s + ")")
    UnsupportedFormat(s) => logger.write_string("UnsupportedFormat(" + s + ")")
  }
}

///|
/// Result of a subsetting operation containing metadata and output bytes.
pub(all) struct SubsetResult {
  output_bytes : Bytes
  orig_size : Int
  subset_size : Int
  orig_num_glyphs : Int
  subset_num_glyphs : Int
  retained_codepoints : Array[Int]
} derive(Debug)

///|
/// Calculate compression ratio (subset_size / orig_size)
pub fn SubsetResult::compression_ratio(self : SubsetResult) -> Double {
  if self.orig_size == 0 {
    1.0
  } else {
    self.subset_size.to_double() / self.orig_size.to_double()
  }
}

///|
/// Calculate savings percentage ((1 - subset_size / orig_size) * 100%)
pub fn SubsetResult::savings_percent(self : SubsetResult) -> Double {
  (1.0 - self.compression_ratio()) * 100.0
}

///|
/// Get the output font bytes
pub fn SubsetResult::bytes(self : SubsetResult) -> Bytes {
  self.output_bytes
}

///|
/// Internal record of an sfnt table directory entry.
pub(all) struct TableEntry {
  tag : String
  checksum : Int
  offset : Int
  length : Int
} derive(Debug, Eq)
