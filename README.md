# MoonSubset

<p align="center">
  <b>用纯 MoonBit 实现的 TrueType 字体子集化工具</b><br>
  <i>A TrueType Font Subsetting Tool Written in Pure MoonBit</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-MoonBit-purple.svg" alt="MoonBit">
  <img src="https://img.shields.io/badge/Zero--FFI-Pure%20MoonBit-brightgreen.svg" alt="Zero FFI">
  <img src="https://img.shields.io/badge/CI-GitHub%20Actions-blue.svg" alt="CI">
  <img src="https://img.shields.io/badge/License-Apache--2.0-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/Tests-15%20Passed-success.svg" alt="Tests">
</p>

---

## 1. 项目简介

**MoonSubset** 是一个用 MoonBit 编写的 TrueType (`.ttf`) 字体子集化（Subsetting）命令行工具与基础库。

给定一个 TrueType 字体文件与一组目标字符，该工具会解析字体表结构，仅提取目标字符所依赖的字形数据，重新计算偏移、映射与校验和，输出一个只包含所需字符的精简字体文件，以减少 Web 加载时的字体体积。

### 生态背景与现状说明
- MoonBit 社区已有著名的字体解析库 [`mizchi/font`](https://github.com/mizchi/font)，其内部包含一个约 360 行的 `subset_font` 内存函数（支持 Format 12 cmap 与复合字形收集）。
- **MoonSubset 的实际工作**：
  1. 提供独立的命令行工具（CLI），支持直接传参、文本文件读取、Unicode 码点解析与常用字符预设；
  2. 实现 `cmap` Format 4（16位 BMP 格式）与 Format 12（32位全量格式）的双模生成，提升跨平台兼容性；
  3. 补全了整字体的 `head.checkSumAdjustment` 计算（`0xB1B0AFBA - total_sum`）；
  4. 支持伴生生成 `@font-face` CSS 片段，并提供 `info` 命令用于诊断字体表目录结构；
  5. 全部逻辑用 MoonBit 实现，无外部 C/Rust 库依赖（零 FFI）。

---

## 2. 实测数据 (Test Benchmark)

字体子集化的原理是“**剔除未使用的字形**”，因此裁剪后体积取决于保留的字符数量，而非特定的数据压缩算法。以下为真实字体测试数据：

| 测试字体 | 原始大小 | 原始字形数 | 提取字符范围 | 提取后大小 | 提取后字形数 | 备注 |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **中文字体 (simhei.ttf)** | 9,745,792 字节 | 28,562 | 13 个汉字 ("你好世界欢迎来到开源黑客松") | 5,848 字节 | 14 | 保留 .notdef + 13 字形 |
| **西文字体 (fixtures/test-font.ttf)** | 66,156 字节 | 470 | 3 个字母 ("ABC") | 4,308 字节 | 4 | 保留 .notdef + 3 字形 |
| **复合字形字符 (U+00C0 `À`)** | 66,156 字节 | 470 | 1 个复合字符 (`À`) | 4,124 字节 | 3 | 递归保留基础字形与重音符号 |

---

## 3. 功能特性与局限性 (Scope & Limitations)

### 支持的功能
- **sfnt 容器读写**：支持 TrueType 1.0 (`0x00010000`) 与 `true` 标识，表按 4 字节对齐并按 tag 字典序排序。
- **TrueType `glyf` 轮廓**：支持简单字形与复合字形（解析 `flags` 并递归收集子组件，重写组件 GID）。
- **`loca` 表重构**：统一使用 Long loca（32 位偏移），避免短偏移越界。
- **`cmap` 表重构**：支持 Format 4 与 Format 12 子表生成。
- **度量表更新**：更新 `maxp.numGlyphs`、`hhea.numberOfHMetrics`，为保留字形重建 `hmtx`。
- **校验和计算**：计算各表 checksum 及 `head.checkSumAdjustment`。
- **元数据保留**：保留原字体中的 `name`、`OS/2`、`post` 表。
- **命令行工具**：
  - `moonsubset subset`：子集化裁剪；
  - `moonsubset info`：查看字体表目录与基础元数据；
  - `--css`：生成 `@font-face` 声明。

### 明确不支持的范围（非目标）
- **不支持 OTF / CFF 字体**（包含 PostScript `OTTO` 轮廓的字体无法裁剪，仅支持 TrueType `glyf`）。
- **不支持 WOFF / WOFF2 压缩**（输出仅为标准 `.ttf` 文件，不包含 Brotli 压缩）。
- **不保留高级排版表**：子集化后会主动丢弃 `GSUB`、`GPOS`、`GDEF`，因此不适用于依赖复杂连字（Ligatures）或阿拉伯语等上下文塑形的排版。
- **不保留低分辨率 Hinting**：丢弃 `cvt `、`fpgm`、`prep`。
- **不支持变量字体**（`gvar` / `fvar`）。

---

## 4. 快速上手

### 4.1 环境要求
- [MoonBit](https://www.moonbitlang.com/) 工具链 (v0.1.2026+)

### 4.2 运行测试
```bash
# 运行 15 组单元与集成测试
moon test
```

### 4.3 命令行用法

```bash
# 查看帮助
moon run cmd/main -- --help

# 1. 指定字符串裁剪，并生成 @font-face CSS
moon run cmd/main -- subset -f ./font.ttf -c "你好世界" -o ./out.ttf --css "MyFont"

# 2. 从文本文件中读取字符
moon run cmd/main -- subset -f ./font.ttf -t ./text.txt -o ./out.ttf

# 3. 按 Unicode 码点列表指定
moon run cmd/main -- subset -f ./font.ttf -u "U+4E00,U+4E8C,0x4E09" -o ./out.ttf

# 4. 使用内置常用字符预设 (chinese / ascii / digits / alphanumeric)
moon run cmd/main -- subset -f ./font.ttf --preset chinese -o ./chinese-common.ttf

# 5. 查看字体表目录信息
moon run cmd/main -- info -f ./font.ttf
```

---

## 5. 浏览器端渲染验证

项目包含一个本地静态 HTML 验证页面：
- 位于 [`examples/demo.html`](examples/demo.html)
- 在浏览器中打开后，拖入生成的子集 `.ttf` 文件，页面会使用浏览器原生的 `FontFace` API 加载字体并渲染文字，直观验证裁剪后的字体轮廓是否显示正常。

---

## 6. 代码组织

```
├── cmd/main/             # CLI 命令行入口
│   ├── main.mbt
│   └── moon.pkg
├── docs/                 # 技术文档
│   ├── cli-guide.md      # 命令行详细参数说明
│   └── format-notes.md   # OpenType 表结构与算法笔记
├── examples/             # 示例与验证
│   ├── demo.html         # 本地字体渲染验证网页
│   ├── run_demo.ps1      # Windows 演示脚本
│   └── run_demo.sh       # Shell 演示脚本
├── fixtures/             # 测试素材
│   ├── README.md
│   └── test-font.ttf     # NotoSansHebrew (SIL OFL 许可, 约 66KB)
├── cmap.mbt              # Format 4 与 Format 12 cmap 解析与生成
├── glyf.mbt              # loca 解析、复合字形递归与组件重写
├── moonsubset.mbt        # 端到端纯函数 API 与 info 诊断
├── presets.mbt           # 字符预设集
├── reader.mbt            # 大端二进制流读取辅助
├── sfnt.mbt              # sfnt 容器读写与校验和计算
├── tables.mbt            # head, hhea, hmtx, maxp 重写
├── types.mbt             # 错误与数据结构定义
├── wasm.mbt              # Wasm 导出接口
├── moonsubset_test.mbt   # 黑盒集成测试
└── moonsubset_wbtest.mbt # 白盒单元测试
```

---

## 7. 参考与致谢

- **OpenType 规范 1.9**：[Microsoft OpenType Specification](https://learn.microsoft.com/en-us/typography/opentype/spec/)
- **mizchi/font**：参考了其字形读取与复合字形 flags 的位处理思路。
- **fonttools**：参考了其表丢弃与 TrueType 目录构建的工程实践。
- **测试字体**：`fixtures/test-font.ttf` 采用 Google Noto Sans 字体，基于 [SIL Open Font License 1.1](https://scripts.sil.org/OFL) 许可。

---

## 8. 许可证

本项目采用 [Apache-2.0](LICENSE) 许可证。
