// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "chgttyyr/moonsubset"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/chgttyyr/moonsubset"

license = "Apache-2.0"

keywords = ["font", "subset", "truetype", "ttf", "cli", "wasm", "typography"]

preferred_target = "wasm"

description = "Production-grade TrueType font subsetting toolchain and asset pipeline in pure MoonBit"

import {
  "moonbitlang/x@0.5.5",
}
