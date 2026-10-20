# MoonSubset 命令行工具完整操作手册 (CLI Guide)

`moonsubset` 是用纯 MoonBit 实现的工业级 TrueType 字体子集化 CLI 工具。

---

## 1. 命令概览

```bash
# 查看帮助信息
moon run cmd/main -- --help

# 子集化裁剪命令 (subset)
moon run cmd/main -- subset [OPTIONS]

# 字体元数据与表结构诊断命令 (info)
moon run cmd/main -- info -f <in.ttf>
```

---

## 2. 常用操作场景与命令示例

### 场景 1：直接输入文字裁剪
适合单页宣传页、活动标题或网页导航栏文字提取：
```bash
moon run cmd/main -- subset -f ./my-font.ttf -c "你好世界" -o ./out.ttf --css "MySubset"
```
**输出结果**：
- `./out.ttf`：裁剪后的精简字体二进制（保留仅 5 个字形：`.notdef` + 4 个汉字）
- `./out.ttf.css`：自动配对生成的 `@font-face` 声明文件

### 场景 2：从长篇文本或文章中全自动提取
适合电子书、技术文档站（SSG / Astro / VitePress）或博客文章：
```bash
moon run cmd/main -- subset -f ./SourceHanSans.ttf -t ./article.md -o ./article-font.ttf
```
CLI 会自动读取整个文本文件，去重提取所有出现过的文字码点并完成重映射。

### 场景 3：按标准高频汉字预设裁剪（CJK 常用 3500 字）
开发通用中文 Web 网站时，内置的常用字表覆盖绝大多数日常交互：
```bash
moon run cmd/main -- subset -f ./simhei.ttf --preset chinese -o ./chinese-common.ttf
```
支持的预设值：
- `chinese` / `sc` / `cjk`：常用规范汉字（覆盖 99.8% 现代书面中文）
- `ascii`：ASCII 可打印字符集（32..126，含标点与英文字母）
- `digits` / `numbers`：纯数字字符集（0..9）
- `alphanumeric` / `alnum`：字母与数字组合（0-9, a-z, A-Z）

### 场景 4：按十六进制 Unicode 码点列表指定
适用于国际化本地化工程、脚本构建工具链：
```bash
moon run cmd/main -- subset -f ./my-font.ttf -u "U+4E00,U+4E8C,0x4E09,U+56DB" -o ./digits-zh.ttf
```

### 场景 5：字体结构与表目录诊断分析 (`info`)
快速分析任意 TrueType 字体的总字形数、表目录、长短 Loca 格式与校验和校准值：
```bash
moon run cmd/main -- info -f ./fixtures/test-font.ttf
```
终端将输出结构化诊断报告：
```text
==================================================
  MoonSubset: Font Inspection Report              
==================================================
File: fixtures/test-font.ttf (66156 bytes)
Tables Count: 17
Total Glyphs: 470
Units Per Em: 1000
Loca Format : Short (16-bit)
Checksum Adj: 0xafd287fc
--------------------------------------------------
Table Directory:
  - GDEF (offset=284, length=786, checksum=0x1806263411)
  - cmap (offset=13656, length=1410, checksum=0x838e1ca3)
  - glyf (offset=15068, length=39374, checksum=0x2f3e8f86)
  - head (offset=54444, length=54, checksum=0x214e21a2)
  ...
==================================================
```

---

## 3. 命令行参数完整对照表

| 参数名 | 简写 | 类型 | 必填 | 说明 |
| :--- | :---: | :---: | :---: | :--- |
| `--font` | `-f` | 路径 | 是 | 输入 TrueType 原始字体文件路径（`.ttf`） |
| `--out` | `-o` | 路径 | subset 必填 | 裁剪生成的输出字体路径（`.ttf`） |
| `--chars` | `-c` | 字符串 | 否 | 直接在命令行指定需要保留的字符文本 |
| `--text-file` | `-t` | 路径 | 否 | 指定包含目标字符的文本文件（自动去重提取） |
| `--unicodes` | `-u` | 字符串 | 否 | 逗号分隔的 Unicode 码点（如 `U+4E00,0x4E8C`） |
| `--preset` | `-p` | 名称 | 否 | 内置预设集（`chinese`, `ascii`, `digits`, `alnum`） |
| `--css` | - | 字体族名称 | 否 | 同步输出同名 `.ttf.css` 的 `@font-face` 声明代码 |
| `--verbose` | `-v` | 布尔 | 否 | 打印调试与处理中间详情 |
| `--help` | `-h` | - | 否 | 显示帮助手册 |
