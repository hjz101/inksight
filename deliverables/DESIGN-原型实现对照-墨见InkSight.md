# 墨见 InkSight · 原型实现 ↔ 设计规范对照

> 定位：这是 DESIGN v1.9 与 `prototype/index.html` 之间的**映射文档**。
> DESIGN 是抽象规则（token／玻璃／动效／页面规格），原型是 3405 行 HTML 的具象实现。
> 本文件回答两个问题：**「原型里这个元素对应哪条规范」**（实现侧反查）与
> **「这条规范在原型里落在哪」**（规范侧定位）。不重复持有规范字面，只做索引与差异说明。
>
> 快照：`prototype/index.html` MD5 `6e98c93cba533845414c7da68b35665a`（与《原型验收记录》锁定快照一致）。
> 若原型快照变更，本文件与《原型验收记录》同时失效，须在新快照上复核。

---

## 一、屏 ↔ 页面规格映射

原型共 9 个屏（`<section class="screen">`），对应 DESIGN §5「12 个页面视觉规范」的 11 项。
原型未独立成屏的规范页（首启分龄 / 书籍详情）由「调试坞 + 弹层」承载，见 §四。

| 原型屏 | `id` | 行范围 | DESIGN §5 对应 | 说明 |
|---|---|---|---|---|
| 发现 | `screen-discover` | 994–1031 | ① | 继续阅读卡 L2（`rec-card glass glass-reg`）；3 条横滑书单 |
| 淘书 | `screen-browse` | 1032–1056 | ② | 搜索胶囊 + 分段 L1（`seg glass glass-l1`）；2 列网格 |
| 架上 | `screen-shelf` | 1057–1100 | ③ | 视图切换条 L1；`grid-books` 3 列 gap 16 |
| 压力测试 | `screen-stress` | 1101–1144 | — | 演示屏（`prototype-only` 豁免区，见验收记录 16 项） |
| 阅读器 | `screen-reader` | 1145–1184 | ④ | 阅读态玻璃 **0**；`readerTools` 工具条；`readerMore` 齿轮 |
| 规范页⑥（实验入口）| `screen-sources` | 1185–1270 | ⑥ | 「我 → 高级」内二级页，可如实命名（页名见 DESIGN §5 ⑥，属 D-05 实验入口例外）|
| 墨量 | `screen-ink` | 1271–1320 | ⑦ | `data-motion="T6"` 墨量错峰生长；成就卡 L2 |
| 主题 | `screen-themes` | 1321–1336 | ⑧ | 横滑卡 2:3.4；选中 2pt accent 环 |
| 我 | `screen-me` | 1337–1475 | ⑩ | 分组行；排版 / 换一个版本 / 年龄状态 / 版权入口 |

**与 DESIGN §5 的已知差异（如实登记，不粉饰）**：
- 原型「架上」屏（`screen-shelf`）顶部标题是「架上」，同时含 `offlineStrip` 离线提示条（13px，D-48 snap 后）。
- 「书城」在原型中命名为「淘书」（`page-title` 淘书）；DESIGN §5 用「书城」。命名差异属原型侧 UI 文案口径，规范侧以 PRD 术语红线为准（内部词不进 UI）。

---

## 二、Design Token ↔ CSS 变量映射

DESIGN §1.7 规定「规范名 `--ink-*` 为语义源，实现名作别名」。原型实际引用统计（与验收记录 17 项一致）：

| 规范名 | 原型引用次数 | 主要用途 |
|---|---|---|
| `--ink-surface` | 见验收记录 | 页面底 / 卡片底 |
| `--ink-line` | 同上 | 分隔线 |
| `--ink-text` / `--ink-text-2` / `--ink-text-3` | 同上 | 主 / 次 / 弱文字 |
| `--ink-bg` | 同上 | 背景 |
| `--ink-raised` | 同上 | 浮起层 |
| `--ink-accent` | 同上 | 强调（选中环、主按钮）|
| `--ink-scrim` | 同上 | 遮罩 |

**对照规则**（DESIGN §1.7 原文口径）：原型内 `var(--tint/--surface/--hair/--sub/--text/--accent)` 是实现别名，一一对应规范名；**新增 token 必须先入 DESIGN §1.7 对照表**，不得只在原型里出现。

---

## 三、玻璃 ↔ DESIGN §2 材质映射

DESIGN §2 定义：全 App 玻璃**唯一入口** `GlassSurface`（L1/L2/L3 仅 tint 0.14/0.20/0.28）；白名单 5 类容器；单块 ≤ 屏面积 30%（仅屏内卡片类）；底部 sheet ≤ 屏高 75%＋内部滚动。

原型玻璃元素实测（与验收记录 4/10/13/14 项一致）：

| 元素 | class | 档位 | 对应规范 |
|---|---|---|---|
| `#setSheet` / `#srcSheet` / `#ageSheet` / `#contactSheet` | `sheet glass glass-l3` | L3 | 白名单 4 类底部 sheet；高度 639pt＝75% 屏高＋内部滚动（D-29/D-38）|
| `#quoteModal` | `quote-modal glass-solid` | **纯色，无 backdrop-filter** | D-28：书摘卡移出白名单改实体卡（压在正文正中）|
| `.rec-card`（继续阅读卡） | `glass glass-reg` | L2 | 白名单「继续阅读卡」；屏内卡片 ≤30% |
| `.seg`（分段控件） | `glass glass-l1` | L1 | 书城 / 书架视图切换条 |
| `#tabbar` | `glass glass-l1` | L1 | **不计入**一屏浮层配额（常驻导航，D-19/D-30）|

**宵禁页与书摘卡禁遮罩（D-26 补盲区判据）**：`#curtain` `backdrop='none'`、`transition='0.001s'`、`bg=rgba(14,13,12,.94)`；`#quoteModal` `backdrop='none'`。这两处是「减弱动效后无玻璃」穷举证明必须单独取值的维度。

---

## 四、动效 ↔ DESIGN §4 映射

DESIGN §4.1 冻结 13 条权威表（T1–T6 / EGG1–EGG5 / UIT1–UIT2），§2.9（PRD）定义开关语义。原型 `MotionRegistry.dump()` 实测 13/13 已挂载（验收记录 1 项），挂载点：

| ID | 挂载元素 | 触发 |
|---|---|---|
| T1 bookOpen | `data-motion="T1"` | 书架翻开转场 |
| T2 versionSwap | `data-motion="T2"` | 换一个版本层翻片 |
| T3 themeWipe | `data-motion="T3"` ×2 | 主题色带漫延 |
| T4 restoreSettle | `data-motion="T4"` | 位置记忆回弹（无单独开关）|
| T5 switchRipple | `data-motion="T5"` | 切换涟漪（无单独开关，关态降 0ms 静态态）|
| T6 inkGrow | `screen-ink data-motion="T6"` | 墨量错峰生长（25ms 错峰）|
| EGG1 coverLiquid | —（书脊视图） | 封面液体流动 / 书脊抽出（同 ID 双表现）|
| EGG2 pinchSpine | —（书脊视图） | 捏合书脊 |
| EGG3 paperPull | —（书架/发现页共用） | 纸质下拉回弹 |
| EGG4 dogEar | `data-motion="EGG4"` | 页角折角（绑书签）|
| EGG5 shakePanel | `data-motion="EGG5"` + `#eggPanel` | 摇一摇唤出随机书摘卡（原型以连点标题模拟）|
| UIT1 chromeToggle | `data-motion="UIT1"` | 阅读工具条显隐（唯一入口＝点击正文中央）|
| UIT2 edgeBack | `data-motion="UIT2"` | 边缘单指侧滑退出（仅滚动/直切模式）|

**减弱动效实测**（验收记录 2/3/4 项）：`#rmSwitch` 开启 → `document.body.classList` 加 `reduce`；扫描 1,546 元素、时长 >1ms 违规 **0**；宵禁页 `transition=0.001s`。**穷举维度必须写全**：时长维度之外，`backdrop-filter` 是独立维度（D-26）。

---

## 五、分龄四态 ↔ AGE_MATRIX 派生

DESIGN §7 与 AGE_MATRIX 字段定义要求：**状态条与拦截页文案必须从矩阵派生，视图层不得 `if state == .xxx` 拼文案**。

原型实现（验收记录 5/6/7 项）：

| 调试坞元素 | 作用 | 实测 |
|---|---|---|
| `#stateSw` | 四态切换（`.adultConfirmed` 子项见排除项 E-3）| `minorConfirmed`=2 预览按钮、`ageUnresolved`=1、`unverified`=0 |
| `#variantSw` | buildVariant 切换（research / release）| release 在线源列全 `∅`；research 全 `✗` |
| `#ageMatrix` | 行为矩阵（5 行 × 3 列 = 15 格，连表头 18 格）| 三值符号单模式统计：`∅`=8 / `✗`=8 / `✓`=11 |
| `#curtainBtns` | 拦截页预览按钮（**调试面板**，非产品 UI）| 真机拦截页 `#curtain` 内 `<button>` 数 0（三态均 0）|

**关键纪律**（D-02 / D-09 / E-1）：`#curtainBtns` 的 2/1/0 是**调试面板的预览触发按钮**，不是产品拦截页的控件；产品拦截页无任何可点元素。文档与探针若混用这两个计数对象，会误判红线。

---

## 六、空态与异常态 ↔ DESIGN §6

| 原型元素 | 对应规范 | 实测 |
|---|---|---|
| `#offlineStrip` | 离线提示条（13px，D-48 snap）| 书架页顶部 |
| `packAllFail` / `packBigFile` / `packOffline` | 源三态（加载/失败/空）| 压力测试屏 |
| `HonestPlaceholder`（原生层）| 「不伪装有内容」纪律 | 原生骨架页空态 |

---

## 七、已知缺口（如实登记，供下一轮补）

1. **EGG1 / EGG2 / EGG3 的原型挂载点未显式标注 `data-motion`**（依赖书脊视图与手势上下文）；`MotionRegistry.dump()` 判定「已挂载」基于注册表而非 DOM 属性扫描——两者口径需在验收记录中写明，避免「探针数 13/13」与「DOM 属性 10 处」被当成矛盾。
2. **`screen-stress` 压力测试屏**是演示屏，`prototype-only` 豁免区；新增演示内容必须带该标注（D-48 口径）。
3. **书籍详情页（DESIGN §5 ⑨）未在原型独立成屏**，由弹层承载；后续若补，须回到 §5 ⑨ 规格。

---

## 八、维护规则

1. 本文件随原型快照变更而失效，须与《原型验收记录》同轮复核。
2. 只做索引与差异说明，**不复制 DESIGN 字面**（与台账 §4 规则 3 同源）。
3. 新增原型元素时，先确认它在 DESIGN 有对应条目；没有的，先补 DESIGN 再进原型。
