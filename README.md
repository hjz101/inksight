# 墨见 InkSight

> iOS 26+ · Liquid Glass 液态玻璃 · 中文小说阅读 App
> **研究形态：本仓库不对外发行，不构成任何可分发的产品版本。**

---

## 一、本仓库是什么

「墨见 InkSight」是一个 iOS 26+ 原生小说阅读 App 的完整交付基线，包含三部分：

| 层 | 内容 | 路径 |
|---|---|---|
| 文档层 | PRD / 液态玻璃设计系统 / 技术约束清单 / 交付决策台账 / 原型验收记录 / POC 实测安排 | `deliverables/*.md` |
| 原型层 | 可点击高保真 HTML 原型 | `deliverables/prototype/index.html` |
| 原生层 | 两个 Swift Package（引擎核心 + App），可编译可测 | `deliverables/native/` |

## 二、原生层结构

### `InkSightCore`（引擎核心 · 契约冻结）

跨源零位移排版引擎，只读消费、不可静默修改：

- `ChapterScanner` — 分章扫描（`Data` → 章节锚点，不驻留正文）
- `Kinsoku` — 中日文禁则表（**版本号必须入排版签名**）
- `StyleStripper` — 样式剥离（去 HTML / 内联样式，残留须为 0）
- `Typesetter` — 自绘断行排版，逐字 advance 累加产出 `TypesetLine`
- `PageAnchor` — 定位锚点 ＋ `PageAnchorCache`（LRU 10 章，O(1) 世代号全作废）＋ `CTFrameCache`（LRU 7 页，仅内存）
- `TypographySignature` — 排版签名（哈希含禁则表版本号）

### `InkSightApp`（App 层）

- `InkSightAppKit` — 数据层与逻辑层：`BookShelfStore` / `ReadingProgressStore` / `SQLiteCache` / `ReaderEngine` / `CoreTextLineCompositor` / `PaginationCoordinator` / `TypographyPresetStore` / `AgeGate` / `MotionRegistry`
- `InkSightAppUI` — SwiftUI 界面：`ReaderSurface` / `PlaceholderScreens` / `GlassSurface` / `AgeGateViews`
- `InkSightAppMain` — 应用入口

## 三、三条不可让步的工程铁律

这三条写进了类型层与测试，不靠"约定遵守"：

1. **定位铁律** — 持久化只存 `charOffset + fingerprint`。
   `PageAnchor` 与 `ReadingProgress` 的类型里**没有 `pageIndex` 字段**，Codable 输出也不可能出现该键。
   页码是派生量，会漂移，落盘即埋雷。

2. **合规四禁令** — `CTFrame` 只在内存：不写任何磁盘路径、不进崩溃快照（含 MetricKit diagnostic）、不进内存转储、切书或会话结束即释放。
   判据是"是否形成稳定可再现的副本"——glyph ＋ 字体可经反向 cmap 还原为 Unicode，故视同正文。
   **尤其"序列化到磁盘加速二次打开"＝正文落盘＝违规。**

3. **正文区 0 玻璃** — 由类型层保证：`ReaderSurfaceView` 不引用 `GlassSurface`。
   全 App 唯一玻璃入口是 `GlassSurface`（三档 L1/L2/L3），一屏最多 1–2 处玻璃浮层。

另有一条变更纪律：**InkSightCore 契约冻结**——7 个源文件的 MD5 基线逐字节锁定，任何改动都要走台账新编号。

## 四、验证状态

| 验证项 | 结果 |
|---|---|
| `InkSightApp` 单元测试 | **64 / 0**（退出码 0） |
| `InkSightCore` 单元测试 | **22 / 0**（退出码 0） |
| iOS 26.5 Simulator SDK 真实编译 | **Build complete**（退出码 0） |
| FR-031 跨源零位移 | 逐行最差 delta **0.0 pt**（判据 ≤0.5 pt） |
| 跨文档一致性检查器 | **PASS 67 / FAIL 0** |
| 正文/设置链玻璃引用 | **NONE**（去注释后扫描） |

构建命令（本机需绕过宿主沙箱，禁用 `xcodebuild`）：

```bash
cd deliverables/native/InkSightApp
swift test --disable-sandbox
swift build --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk \
            --triple arm64-apple-ios26.0-simulator --disable-sandbox
```

## 五、尚待真机验证（不与本机逻辑证据混装）

本机只判**逻辑正确性**。以下必须在真机判，仓库内不伪造：

- **POC-2** — 液态玻璃观感与 `containerSpacing` 校准（模拟器截图不得终审）
- **POC-3** — 真机性能子项：release 分章 ≤100 ms、首屏分页 ≤8 ms、后台批量重分页调度
- **POC-4** — 连续阅读 30 分钟温控与功耗（外壳升温 ≤5 ℃、掉电 ≤8%）
- **POC-5** — ProMotion 120 Hz 真机帧率（59 fps+ / 118 fps+）与 PingFangSC 真机字形／FR-031 复核
- DeclaredAgeRange 真机接入、SQLite 8 MB 真实落盘体积观测

## 六、合规声明

- 内容形态为「聚合书源 ＋ 用户导入」，**仅作产品研究与技术预研，不用于实际发行**；仓库内所有书源示例域名一律 `example.com`。
- 三态年龄门（`minorConfirmed` / `ageUnresolved` / `unverified`）由 `AgeGateMatrix` 按 `(state, variant)` **派生**界面能力；release 变体下相关入口结构上不生成（沉默，非隐藏）。
- 界面中不存在任何"切换年龄 / 完善年龄"控件——那是合规反向路径。
- 投诉邮箱在台账中为 `[TBD-CONTACT]` 占位，发行前必须替换。

---

**交付决策台账**：`deliverables/交付决策台账-墨见InkSight.md`（D-01～D-54），记录每一次裁定、每一次随附交付登记与每一处主理人独立复核。
