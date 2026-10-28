# 埋点需求表 · 墨见 InkSight

v1.3｜需求侧口径｜配合 PRD v1.8。**内部文件，不得外发。**
采集能力仅用于**内部研究验证**，不上传正文、不默认联网。

## 0. 五条采集红线（先于一切事件生效）

1. **不采正文文本、不采书名/作者字符串**。属性只允许 ID、枚举、数值。
2. **不记录对象标识**：不得包含第三方域名、站点名称、书源标识、规则文件指纹——**哈希、缩写、序号都不行**。可记事件类型与计数，不可记指向具体第三方的标识。
3. **本地存储同样受约束**：电子数据鉴定会直接镜像设备、解析本地库，"不上传"不构成保护（闵行"×读"案的电子数据即从设备内提取）。服务端日志同适用；出网组件只记或不记，复用 `Redactor`，但**凭据（值）与站点标识（对象）分开管**。
4. **判断标准是输入熵，不是"是否哈希"**：域名是低熵输入、彩虹表可反查，哈希等于明文；段落指纹的输入是数百字高熵文本，可存哈希。书源在日志里只允许 `sourceSlotIndex`（本地序号）或不记。
5. **不默认上报**：先落本地，导出由用户手动触发；每事件可单关，关闭后只留聚合计数。`book_id` 用**随机 UUID**，不得用书名哈希（内容哈希仍可被比对确认是哪本书）。

## 1. 上报纪律与口径

- **高频事件节流合并**：≥60s 或每 10 页一次，退出补报一次，禁止逐 tick——观测行为不得抬高功耗，否则先打破 NFR-06（≤5%）。

| 口径 | 定义 |
|---|---|
| 阅读时长 | 前台且处于阅读器；连续 120 秒无翻页/滚动暂停计时；单次会话上限 4h。**封顶只停累加，不锁功能、不弹拦截** |
| 位置对齐成功率 | `align_result = fingerprint` 或 `percent` 的次数 ÷ 全部切换次数 |
| 弃读（手动） | 用户点「我弃了」（FR-035）。**不做算法判弃读** |
| 停滞 `stalled` | 进度 > 0 且 7 天无记录，且为「已完结」或「本地导入」书；连载不计 |
| 停滞软区 `stalled_soft` | 进度 > 0 且 3 天无记录；仅墨量轨迹浅灰区，不进分母 |
| 首启到第一本书 | 首次启动 → 首次进入阅读器耗时（分路径：本地文件 / 规则文件导入） |

## 2. 事件表

| 编号 | 事件名 | 触发时机 | 关键属性（仅 ID/枚举/数值） | 服务的口径 | P |
|---|---|---|---|---|---|
| EV-01 | `app_launch` | 首帧 / 首屏可交互 | `first_frame_ms`、`tti_ms`、`launch_type`、`book_count` | NFR-01 双指标真实分布 | P0 |
| EV-02 | `tab_switch` | 切换底部 Tab | `from_tab`、`to_tab`、`dwell_ms` | 架上/淘书谁是入口 | P0 |
| EV-03 | `read_session` | 进入/退出阅读器 | `book_id`、`origin_type`(local/remote)、`chapter_index`、`duration_sec`、`page_turns`、`page_mode`、`font_pt` | 阅读时长、翻页模式偏好 | P0 |
| EV-04 | `position_align` | 切换文件/副本完成 | `switch_type`(replace/coexist)、`origin_type`(**local/online**，禁写 `online_source`——"source"是身份词)、`chapter_index`、`char_offset`、`align_result`(fingerprint/percent/failed)、`trigger`(manual/file_missing)、`elapsed_ms`。**禁止任何对象标识** | 位置对齐成功率——价值主张是否成立 | P0 |
| EV-05 | `chapter_gap` | 检出断章/错序 | `book_id`、`missing_count`、`dup_count`、`resolve_type`(realign/placeholder/abandon) | 断章的真实严重度 | P0 |
| EV-06 | `stall_point` | 每日离线批算 | `book_id`、`chapter_index`、`progress_pct`、`state`(stalled/stalled_soft/读完)、`serial` | 停滞章节分布 | P1 |
| EV-06b | `manual_drop` | 点「我弃了」/撤销 | `book_id`、`chapter_index`、`progress_pct`、`action`(drop/undo) | 自述弃读与算法停滞的偏差 | P1 |
| EV-07 | `theme_change` | 主题/夜间切换 | `from`、`to`、`mode`(manual/auto/schedule)、`hour` | 夜间是否真被用 | P0 |
| EV-08 | `motion_toggle` | 动效开关变更 | `scope`(global/single)、`target_id`（13 个枚举：T1–T6/EGG1–5/UIT1–2）、`value` | 动效关闭率与最想关的那条 | P0 |
| EV-09 | `import_result` | 导入结束 | `type`(**rule_file/txt/epub**)、`result`、`fail_reason`、`duration_ms`、`encoding` | 首启到第一本书耗时、失败类型排序 | P0 |
| EV-10 | `search_result` | 搜索返回 | `query_type`(书名/作者)、`scope`(local/online)、`result_group_count`、`dedup_count`、`first_result_ms`、`hit` | 搜不到率、多源是否真有增益 | P0 |
| EV-11 | `state_shown` | 展示 loading/failed/empty | `page`、`state`、`reason` | 反模式监控：空态是否被伪装 | P0 |
| EV-12 | `note_create` | 划线/想法/标签保存 | `type`、`tag`、`chapter_index`、`char_len_bucket` | 笔记标签化是否被用 | P1 |
| EV-13 | `age_gate` | 分龄请求结果/模式进出 | `branch`(sharing_under18/sharing_over18/declined/unsupported)、`action`(enter/exit/blocked_by_time) | 分龄三支是否被真实走到、是否误判 | P0 |

## 3. 用途说明

- 墨量页只展示本地聚合（时长、本数、连续天数、时段分布），**不外传**。
- **EV-04 是最关键观测点**：若 `align_result=failed` 长期偏高，说明「换一个版本后仍停在同一段」不成立，要改产品而非改文案。
- **EV-08 反证需求真伪**：关闭率 <5% 且无人关单条，单条开关可降级。
- **EV-13 验证合规路径**：`declined` 分支占比高说明"未验证档"是常见路径，onboarding 文案与提示必须做好；`unsupported` 高说明原型 fallback 必须做。

## 4. 版本对照（主动留痕，证明持续合规）

| 版本 | 变更 | 原因 |
|---|---|---|
| v1.0 | 初版，含 `src_id`/`from_src`/`to_src`/`opened_src`/`source_count` | — |
| v1.2 | 删除全部源标识字段；EV-04 改 `align_event`；`book_id` 改随机 UUID | 站点清单构成"明知"的直接证据；本地库会被镜像提取 |
| v1.3 | EV-04 定名 `position_align`；新增红线第 3–5 条（本地同样受约束、输入熵判据、不默认上报）；`origin_type` 限定 local/online | 名实对齐结果；"online"描述性质、"source"是身份 |

**v1.0 已作废，被 v1.3 取代；本表不再存在含源标识字段的现行版本。** 历史版本可能残留于 git 历史，如被检索到，以本对照表说明为准——主动解释比让人翻 diff 更有利。

## 5. 已关闭的待确认项

ID 与枚举已冻结（`T1 bookOpen / T2 versionSwap / T3 themeWipe / T4 restoreSettle / T5 switchRipple / T6 inkGrow / EGG1 coverLiquid+spineLift / EGG2 pinchSpine / EGG3 paperPull / EGG4 dogEar / EGG5 shakePanel / UIT1 focusPull / UIT2 edgeBack`）；弃读三态；墨量周报卡片留 P1。
