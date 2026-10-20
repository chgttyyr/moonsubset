# OpenType / TrueType 字体子集化技术规范与结构笔记 (Format Notes)

本文档整理了 `MoonSubset` 在基于 MoonBit 实现 TrueType 字体裁剪（Subsetting）过程中的关键结构定义、位偏移、对齐规范及核心算法决策。

---

## 1. sfnt 容器模型

TrueType 字体采用 `sfnt` 二进制容器封装，核心由 **Offset Table**、**Table Directory** 和 **Table Data** 三部分构成：

```
+-------------------------------------------------------+
| sfnt Header (Offset Table, 12 Bytes)                  |
| - sfntVersion: uint32 (0x00010000 for TrueType 1.0)   |
| - numTables: uint16                                   |
| - searchRange: uint16   = (1 << floor(log2(n))) * 16  |
| - entrySelector: uint16 = floor(log2(n))              |
| - rangeShift: uint16    = numTables * 16 - searchRange|
+-------------------------------------------------------+
| Table Directory (16 Bytes * numTables)                |
| - tag: uint32 (e.g. 'cmap', 'glyf', 'head'...)        |
| - checkSum: uint32                                    |
| - offset: uint32                                      |
| - length: uint32                                      |
+-------------------------------------------------------+
| Table Data (4-Byte Aligned, 0-padded)                 |
+-------------------------------------------------------+
```

### 1.1 表目录排序规则
OpenType 规范要求表目录必须按 Tag 的 ASCII 字典序严格升序排列（例如 `'OS/2' < 'cmap' < 'glyf' < 'head' < 'hhea' < 'hmtx' < 'loca' < 'maxp' < 'name' < 'post'`）。不符合排序的字体会在某些严格系统（如 macOS 或 OTS 检查器）中加载失败。

### 1.2 Checksum 与全局校准（CheckSumAdjustment）
- **单表校验和**：以 32 位大端无符号整数累加整表字节（若表长非 4 的倍数，末尾补 0 补足 4 字节）。
- **全局校验和 (`head.checkSumAdjustment`)**：
  1. 将 `head` 表偏移 8 处的 `checkSumAdjustment` 预置为 0。
  2. 计算各表 Checksum 写入表目录。
  3. 遍历计算整份字体文件（包含目录与所有表）的 32 位无符号整数总和 `total_sum`。
  4. 写入 `0xB1B0AFBA - total_sum` 至 `head.checkSumAdjustment`。
  5. 校验器验证时，对整文件累加的和必等于常量 `0xB1B0AFBA`（在 32 位有符号整型中对应 `-1313820742`）。

---

## 2. glyf 与 loca 映射机制

TrueType 字形数据存放在 `glyf` 表中，每个字形在 `glyf` 中的字节偏移由 `loca`（Index to Location）表索引。

### 2.1 loca 格式类型 (`head.indexToLocFormat`)
- **Format 0 (Short)**: 偏移以 `uint16` 存储，实际字节偏移为存储值乘以 2。最大可寻址长度为 $65535 \times 2 = 131070$ 字节（~128 KB）。
- **Format 1 (Long)**: 偏移以 `uint32` 存储，直接代表字节偏移。
- **MoonSubset 架构决策**：子集字体一律采用 **Format 1 (Long)**，将 `head.indexToLocFormat` 设为 1。由于中文字体或复杂字形裁剪后即使总长极小，使用 Long loca 也能消除任何溢出风险，具备最佳通用性。
- `loca` 条目总数为 `numGlyphs + 1`，最后一项代表最后一个字形的结束偏移。如果 `loca[i] == loca[i+1]`，表示 GID `i` 为空白字形（如空格字符）。

### 2.2 复合字形（Composite Glyph）依赖解构
当字形首部 `numberOfContours < 0` 时，该字形为复合字形（由多个简单字形拼合而成，例如带重音的字母 `À` 或带有偏旁部首的汉字）。
复合字形组件记录格式：
```
flags: uint16
glyphIndex: uint16
argument1, argument2: (int8/int16, 取决于 flags & 0x0001)
transform: (取决于 flags & 0x0008, 0x0040, 0x0080)
```
- **关键位掩码**：
  - `0x0001 (ARG_1_AND_2_ARE_WORDS)`: 参数占 4 字节（两组 int16）；否则占 2 字节（两组 int8）。
  - `0x0008 (WE_HAVE_A_SCALE)`: 后续带 2 字节标量缩放值。
  - `0x0040 (WE_HAVE_AN_X_AND_Y_SCALE)`: 后续带 4 字节独立 X/Y 缩放值。
  - `0x0080 (WE_HAVE_A_TWO_BY_TWO)`: 后续带 8 字节 $2 \times 2$ 仿射变换矩阵。
  - `0x0020 (MORE_COMPONENTS)`: 为 1 表示后续还有下一个组件记录；为 0 表示最后一个组件。
- **子集化要求**：
  1. 必须递归收集所有引用的 `glyphIndex`（加入保留 GID 集合）。
  2. 重建 `glyf` 时，必须将组件记录中的旧 `glyphIndex` 重写为映射后的新 GID。

---

## 3. cmap 字符编码映射表

`cmap` 表负责将 Unicode 码点（Codepoints）转换为字形编号（Glyph ID）。

### 3.1 Format 4 (16-bit BMP)
针对 BMP 区间（`U+0000` ~ `U+FFFF`）的分段连续映射。
MoonSubset 创新性地采用“恒定 delta 分段算法”：
- 将连续且 `gid - cp` 恒定的区间折叠为一个 Segment。
- 使得所有 Segment 的 `idRangeOffset` 恒为 0，直接利用 `gid = (cp + idDelta) & 0xFFFF` 瞬时寻址。
- 尾部强制补全终止段 `[0xFFFF, 0xFFFF, idDelta=1, idRangeOffset=0]`，完全兼容 OpenType 规范。

### 3.2 Format 12 (32-bit Full Unicode)
针对含有非 BMP 字符（如 Emoji、CJK 扩展区、大字符集）的连续区间映射：
- 结构：`SequentialMapGroup { startCharCode, endCharCode, startGlyphID }`。
- 将连续分配的码点按区间压缩，存储紧凑且解析开销极低。

### 3.3 双格式输出策略（Dual-Table Architecture）
- **纯 BMP 字符集**：生成 `(0, 3)` 与 `(3, 1)` 两组记录指向同一 Format 4 子表。
- **混合非 BMP 字符集**：生成 `(3, 1)` Format 4（过滤 BMP 部分）与 `(3, 10)` Format 12（全量映射），确保老旧嵌入式渲染器与现代浏览器同时具备最高兼容性。

---

## 4. 水平度量与头信息调整

### 4.1 hhea 与 hmtx
- 原字体中为了精简体积，后半部分等宽字形可能省略 `advanceWidth`，只保留 `lsb`。
- 子集化重建时，为简化排版开销并保证合法性，将 `hhea.numberOfHMetrics` 直接置为 `subset_num_glyphs`，为每个保留的字形输出完整的 `(advanceWidth, lsb)` 4 字节度量，计算简明且绝对健壮。

### 4.2 非目标表的剪除决策
子集字体明确剪除：
- Hinting 表：`cvt `, `fpgm`, `prep`（现代 Web / 矢量高分屏无需低分辨率栅格化指令）。
- 复杂高级排版表：`GSUB`, `GPOS`, `GDEF`（裁剪后字形已重新紧凑排布，移除旧的特性表避免连字断链崩溃）。
- 数字签名表：`DSIG`（子集字体哈希已变更，剪除无效签名）。
