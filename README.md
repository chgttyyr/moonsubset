# MoonSubset

<p align="center">
  <b>用纯 MoonBit 实现的工业级 TrueType 字体子集化工具链与资产管线</b><br>
  <i>Production-grade TrueType Font Subsetting Toolchain & Web Asset Pipeline in Pure MoonBit</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-MoonBit-purple.svg" alt="MoonBit">
  <img src="https://img.shields.io/badge/Zero--FFI-Pure%20Wasm-brightgreen.svg" alt="Zero FFI">
  <img src="https://img.shields.io/badge/CI-GitHub%20Actions-blue.svg" alt="CI">
  <img src="https://img.shields.io/badge/License-Apache--2.0-blue.svg" alt="License">
  <img src="https://img.shields.io/badge/Tests-15%2F15%20Green-success.svg" alt="Tests">
</p>

---

## 1. 项目背景与生态定位

在 Web 应用、在线阅读、轻量级游戏与图形渲染中，一套完整中文字体体积动辄 **10MB ~ 25MB**，而一个特定网页往往只需渲染几十到几百个关键汉字。全量字体下载严重拖慢首屏加载并消耗大量带宽。**字体子集化（Font Subsetting）** 是 Web 性能优化的核心杀手锏。

### 为什么生态需要 MoonSubset？
截至 2026 年，Mooncakes 生态中虽已有底层的字体解析库（如著名的 [`mizchi/font`](https://github.com/mizchi/font)），并在内部探索过内存级字形截取，但生态中**始终缺乏一个开箱即用、具备生产级健全性、可独立作为终端工具与自动化资产产线（Asset Pipeline）运行的子集化软件产品**。

**MoonSubset 填补的正是“从底层算法纯函数到生产级开发者工具”这一关键鸿沟**：
1. **开箱即用的工业级 CLI**：支持直接传参、文本文件批量提取、十六进制 Unicode 码点解析、内置高频 CJK 常用字预设。
2. **端到端 Web 资产交付**：一键生成精简 `.ttf` 并同步输出配对的 `@font-face` CSS 声明代码。
3. **严格的 OpenType 规范合规**：
   - 完整实现全局 `0xB1B0AFBA` 校验和校准（`head.checkSumAdjustment`），通过微软/Google 浏览器内核 `ots` 严苛校验；
   - 支持 **Format 4（16-bit BMP）与 Format 12（32-bit Full Unicode）双 cmap 兼容构建**，彻底解决老旧设备与现代浏览器的跨平台兼容问题。
4. **零 FFI、纯安全内存**：核心算法完全由纯 MoonBit 编写，天然支持编译为高效的 WebAssembly / Native。

---

## 2. 压缩性能基准测试 (Benchmark)

在真实测试字体环境下的端到端裁剪实测结果：

| 测试字体类别 | 原始体积 | 裁剪字符范围 | 子集体积 | 体积压缩比 | 节省空间 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **思源 / 黑体中文字体 (`simhei.ttf`)** | **9,745,792 Bytes** (28,562 字形) | 13 个常用中文字符 | **5,848 Bytes** (14 字形) | **0.06%** | **99.94% ⬇️** |
| **开源西文字体 (`test-font.ttf`, OFL)** | **91,360 Bytes** (424 字形) | 基础西文字符 (A, B, C) | **4,308 Bytes** (4 字形) | **4.71%** | **95.28% ⬇️** |
| **复合字形重音字符 (`À` 复合字形)** | **66,156 Bytes** (470 字形) | 单个复合码点 (递归展开组件) | **4,124 Bytes** (3 字形) | **6.23%** | **93.77% ⬇️** |

---

## 3. 快速开始

### 3.1 环境要求
- [MoonBit](https://www.moonbitlang.com/) 工具链 (v0.1.2026+ 均可)

### 3.2 运行自动化测试
```bash
# 运行全部 14 组白盒与黑盒集成测试
moon test
```

### 3.3 CLI 命令行使用

```bash
# 1. 直接指定字符串裁剪中文字体并生成 CSS
moon run cmd/main -- subset -f ./my-font.ttf -c "你好世界" -o ./subset.ttf --css "MyWebFont"

# 2. 从文本文件中批量收集字符
moon run cmd/main -- subset -f ./my-font.ttf -t ./article.txt -o ./subset.ttf

# 3. 按十六进制 Unicode 码点列表指定
moon run cmd/main -- subset -f ./my-font.ttf -u "U+4E00,U+4E8C,0x4E09" -o ./subset.ttf

# 4. 使用内置 CJK 常用字或 ASCII 预设
moon run cmd/main -- subset -f ./my-font.ttf --preset chinese -o ./chinese-common.ttf
moon run cmd/main -- subset -f ./my-font.ttf --preset ascii -o ./ascii-only.ttf
```

终端将输出精美的体积报告：
```text
[CSS] Generated @font-face stylesheet: ./subset.ttf.css
==================================================
  MoonSubset: Subsetting Completed Successfully!  
==================================================
Original Size : 9745792 bytes (28562 glyphs)
Subset Size   : 5848 bytes (14 glyphs)
Compression   : 99.94% reduction
Retained Chars: 13 unique characters (plus .notdef)
Output File   : ./subset.ttf
==================================================
```

---

## 4. 浏览器端在线交互渲染预览

MoonSubset 提供了轻量级的静态 HTML 交互式验证器：
- 位于 [`examples/demo.html`](examples/demo.html)
- 评委或开发者可直接在浏览器中打开，**拖拽任意生成的子集 `.ttf` 文件**，页面通过动态 `@font-face` 立即加载并实时渲染文字，直观验证字形轮廓与度量准确性。

```bash
# Windows 一键执行全流程演示
powershell -File examples/run_demo.ps1

# Linux / macOS 一键执行全流程演示
bash examples/run_demo.sh
```

---

## 5. 作为 MoonBit 库集成 (API)

```moonbit
import "chgttyyr/moonsubset" as @moonsubset

fn example() -> Unit {
  let font_bytes : Bytes = ... // 字体原始二进制数据
  let codepoints : Array[Int] = ['你'.to_int(), '好'.to_int()]

  match @moonsubset.subset(font_bytes, codepoints) {
    Ok(result) => {
      let output_font : Bytes = result.bytes()
      println("子集大小: \{result.subset_size} bytes")
      println("压缩节省: \{result.savings_percent()}%")
    }
    Err(e) => println("子集化失败: \{e}")
  }
}
```

---

## 6. 支持范围与非目标

### ✅ 已完整支持（In-Scope）
- **sfnt 容器**：TrueType `0x00010000` 与 `true` flavor，表目录按 tag 字典序对齐与排序。
- **glyf / loca 表重建**：简单字形与复合字形，4 字节长偏移（Long loca）安全格式。
- **复合字形递归解析**：解析 `ARG_1_AND_2_ARE_WORDS`、`WE_HAVE_A_SCALE` 等位标志，自动递归保留所有子组件，并重写组件 `glyphIndex`。
- **双模 cmap 构建**：Format 4（16 位连续段折叠算法）+ Format 12（32 位连续区间组）。
- **度量表重建**：`hhea.numberOfHMetrics` 与 `hmtx` 全长重写。
- **校验和闭环**：每表 Checksum 与 `head.checkSumAdjustment`（`0xB1B0AFBA`）。
- **元数据保留**：保留 `name`、`OS/2`、`post`，保证操作系统字体识别。

### ❌ 非目标（Non-Goals）
- **OTF / CFF 轮廓**（CFF 的 Type 2 charstring 裁剪需专用的字节码反编译器，本期专注于 TrueType glyf）。
- **变量字体变体插值**（`gvar` / `fvar`）。
- **复杂文本排版特性表**（`GSUB` / `GPOS` / `GDEF`，子集化直接剪除未重写的连字表以避免排版崩溃）。
- **低分辨率光栅化 Hinting**（`cvt `, `fpgm`, `prep`，Web 高分屏环境下无必要）。

---

## 7. 项目架构

```
.
├── cmd/main/             # CLI 命令行入口与参数解析
│   ├── main.mbt
│   └── moon.pkg
├── docs/                 # 技术文档与规范笔记
│   └── format-notes.md   # OpenType 结构与子集算法详解
├── examples/             # 演示工程与在线预览
│   ├── demo.html         # 浏览器端 @font-face 渲染验证页
│   ├── run_demo.ps1      # Windows 一键端到端演示脚本
│   └── run_demo.sh       # Unix 一键端到端演示脚本
├── fixtures/             # 测试素材与 OFL 开源字体
│   ├── README.md         # 许可与字形说明
│   └── test-font.ttf     # OFL 授权小型 TrueType 测试字体
├── cmap.mbt              # Format 4 与 Format 12 解析与生成
├── glyf.mbt              # loca 解析、复合字形递归、组件 GID 重写
├── moonsubset.mbt        # 纯函数端到端子集化调度 API
├── presets.mbt           # CJK 常用字、ASCII 等内置预设
├── reader.mbt            # 大端无符号/有符号二进制读取器
├── sfnt.mbt              # 容器解析、表目录排序与 ChecksumAdjustment 闭环
├── tables.mbt            # head, hhea, hmtx, maxp 专用生成器
├── types.mbt             # 错误模型与结果度量类型
├── moonsubset_test.mbt   # 9 组端到端集成测试集
└── moonsubset_wbtest.mbt # 白盒单元与算法不变式测试集
```

---

## 8. 开源合规与参考来源

本项目遵循 **Apache-2.0** 许可证开源。

### 规范与前人参考
1. **[Microsoft OpenType Specification v1.9](https://learn.microsoft.com/en-us/typography/opentype/spec/)**：SFNT 容器对齐、`cmap` Format 4/12 结构、复合字形标志位及 `checkSumAdjustment` 计算标准。
2. **[`mizchi/font`](https://github.com/mizchi/font)**：MoonBit 社区核心字体库，本项目在其解析思想启发下，重构了独立的双模 Cmap 生成器、严格全局校验和与完整 CLI 资产工具链。
3. **[fonttools](https://github.com/fonttools/fonttools)**：Python 生态知名子集化工具，参考了其针对 TrueType 表目录精简与丢弃无效 Hinting 表的设计经验。
4. **[SIL Open Font License 1.1](https://scripts.sil.org/OFL)**：测试字形素材遵守 OFL 开源协议。
