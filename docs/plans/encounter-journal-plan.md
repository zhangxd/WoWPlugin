# 冒险指南现状基线与演进计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前副本列表、详情页、锁定摘要与副本列表入口导航能力
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/plans/quest-plan.md`
- 最后更新：2026-04-29

## 1. 目标

- 将 `encounter_journal` 的文档边界重新对齐到当前代码，只保留副本列表、详情页和锁定摘要增强。
- 新增副本列表条目右下角图钉按钮：点击后打开目标地图，创建系统用户 waypoint，并启用系统导航追踪。
- 在现有图钉导航基础上补齐副本列表悬停显钉、图钉高亮版与“定位图标常驻显示”设置，并确保不破坏 Blizzard 原生单击进入详情页。
- 新增 DB 导出的静态副本入口表，补足运行时入口 API 对旧副本分翼的精确入口缺口。
- 收口 `encounter_journal` 设置页与相关持久化：删除 3 个已确认废弃的设置项，保留并记忆列表“仅坐骑”，固定开启列表 CD 叠加，并删除详情页“仅坐骑”功能。

## 2. 输入文档

- 需求：
  `docs/specs/encounter-journal-spec.md`
- 设计：
  `docs/designs/encounter-journal-design.md`
- 其他约束：
  当前代码实现是唯一事实来源；任务能力已拆到 `quest` 模块；导航入口已由用户在 2026-04-27 回复“开动”确认，并在后续反馈中修正为副本列表条目右下角图钉；同日又确认图钉需要高亮版与常驻显示设置。2026-04-27 用户再次确认 DB 静态入口方案：从 `wow.db` 导出精确入口，选中 / 点击冒险指南条目时按 `journalInstanceID` 直接读取静态表；2026-04-27 修正为精确 `areapoi` 优先，缺失时再使用 `journalinstanceentrance`。2026-04-29 用户确认设置精简口径：删除 3 个设置项；保留并记忆列表“仅坐骑”；列表 CD 叠加固定开启；详情页“仅坐骑”删除。2026-04-29 点击回归修正口径：副本列表必须继续沿用 Blizzard 原生单击进入详情页，插件不再依赖自定义双击 / 单击焦点逻辑。

## 3. 影响文件

- 新增：
  - `DataContracts/instance_entrances.json`
  - `Toolbox/Data/InstanceEntrances.lua`（由正式导出脚本生成）
- 修改：
  - `Toolbox/Core/API/EncounterJournal.lua`
  - `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua`
  - `Toolbox/Modules/EncounterJournal/Shared.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `Toolbox/Toolbox.toc`
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/FEATURES.md`
  - `docs/Toolbox-addon-design.md`
  - `tests/validate_settings_subcategories.py`
  - `tests/logic/spec/encounter_journal_mount_filter_spec.lua`
  - `tests/validate_data_contracts.py`（如校验需要识别新结构）
  - `tests/logic/spec/encounter_journal_navigation_spec.lua`
  - `scripts/export/tests/test_contract_export.py`（如新增契约路径测试需要覆盖）
- 验证：
  - `python tests/run_all.py --ci`
  - 相关文档交叉引用与模块边界搜索

## 4. 执行步骤

- [x] 步骤 1：核对 `Toolbox/Modules/EncounterJournal*.lua`、`Toolbox/Core/API/EncounterJournal.lua` 与 `Toolbox/Modules/MinimapButton.lua` 的当前实现边界。
- [x] 步骤 2：重写 `encounter-journal` 对应的 feature/spec/design/test 文档，移除已迁移到 `quest` 的任务描述。
- [x] 步骤 3：同步回写 `docs/FEATURES.md` 与 `docs/Toolbox-addon-design.md`。
- [x] 步骤 4：通过自动化命令验证仓库当前状态。
- [x] 步骤 5：在需求 / 设计 / 计划文档中落地 2026-04-27 “导航入口”确认规则，状态推进为可执行 / 执行中。
- [x] 步骤 6：为 `Toolbox.EJ` 增加入口查找与 waypoint 设置回归测试。
- [x] 步骤 7：实现 `Toolbox.EJ.FindDungeonEntranceForJournalInstance` 与导航触发 API。
- [x] 步骤 8：将导航入口从详情页按钮修正为副本列表条目右下角图钉，跟随模块开关和列表刷新状态刷新。
- [x] 步骤 9：更新本地化文案、功能 / 总设计 / 测试文档，并运行自动化验证。
- [x] 步骤 10：先为列表点击兼容 / 图钉显隐规则写失败中的逻辑测试，并确认失败原因正确。
- [x] 步骤 11：实现 `encounter_journal` 列表点击兼容与图钉显示状态管理。
- [x] 步骤 12：新增 `listPinAlwaysVisible` 默认值、迁移与设置页复选框。
- [x] 步骤 13：核对 Blizzard 高亮图钉资源名后替换列表图钉图标，并完成自动化验证。
- [x] 步骤 14：为 `instance_entrances` 契约写失败中的导出 / 结构校验测试，覆盖 `1277 厄运之槌 - 戈多克议会` 能从 DB 导出精确入口。
- [x] 步骤 15：新增 `DataContracts/instance_entrances.json`，精确 `areapoi` 优先，缺失时使用 `journalinstanceentrance`，关联 `journalinstance`、`areatable`、`uimapassignment`、`uimap` 输出世界坐标、区域信息、`HintUiMapID` 与来源字段。
- [x] 步骤 16：通过 `python scripts/export/export_toolbox_one.py instance_entrances --contract-dir DataContracts --data-dir Toolbox/Data` 生成 `Toolbox/Data/InstanceEntrances.lua` 与契约快照。
- [x] 步骤 17：在 `Toolbox/Toolbox.toc` Data 区加入 `Data/InstanceEntrances.lua`，加载顺序位于 `Core/API/EncounterJournal.lua` 之后、`Modules/EncounterJournal*.lua` 之前。
- [x] 步骤 18：为 `Toolbox.EJ` 写失败中的逻辑测试：运行时入口 API 无 `1277` 精确记录时，静态入口表可命中 `1277` 并调用 `C_Map.GetMapPosFromWorldPos` / waypoint API。
- [x] 步骤 19：实现 `Toolbox.EJ` 静态入口读取：静态 `Toolbox.Data.InstanceEntrances[journalInstanceID]` 优先，运行时入口 API 仅作静态缺失兜底；不使用同 mapID / 同名 / 同组猜测。
- [x] 步骤 20：更新功能、测试与总设计文档，记录静态入口数据来源、覆盖口径、已知限制和验证结果。
- [x] 步骤 21：先修改自动化测试，锁定“设置页删除 3 项、列表仅坐骑保留并记忆、列表 CD 叠加固定开启、详情页仅坐骑删除”的新口径。
- [x] 步骤 22：运行最小相关测试，确认旧代码按预期失败。
- [x] 步骤 23：删除 `lockoutOverlayEnabled`、`detailMountOnlyEnabled` 的默认值、迁移、文案和业务分支；设置页删除对应 3 个选项。
- [x] 步骤 24：保留 `mountFilterEnabled` 作为副本列表“仅坐骑”按钮记忆状态，并清理不再需要的设置页文案 / 判断逻辑。
- [x] 步骤 25：删除详情页“仅坐骑”按钮与过滤逻辑，同时保留详情页重置标签。
- [x] 步骤 26：更新功能 / 设计 / 测试 / 总设计文档并跑全量验证。
## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`：已通过，逻辑测试 129 successes / 0 failures / 0 errors。
- 命令 / 检查点 2：
  搜索 `docs/**` 中 `encounter_journal` 与“任务页签 / Quest Inspector / rootTab”组合的残留错位表述。
- 游戏内验证点：
  副本列表“仅坐骑”、单击进入详情页、副本列表图钉悬停 / 常驻显示、CD 叠加、详情页增强、小地图与 `EJMicroButton` 锁定摘要。
- 数据验证点：
  `Toolbox/Data/InstanceEntrances.lua` 文件头符合数据库生成文件规范；`Toolbox.Data.InstanceEntrances.entrances[230]` 使用 `areapoi` / `AreaPoiID=6501`，不再混入分翼门候选；`Toolbox.Data.InstanceEntrances.entrances[1277]` 包含来源为 `journalinstanceentrance` 的精确入口记录。
- 游戏内新增验证点：
  `厄运之槌 - 戈多克议会` 在运行时入口 API 未返回 `1277` 精确入口时，仍能通过静态入口数据设置导航；若坐标转换失败，插件给出不可用提示且不报错。
- 行为新增验证点：
  设置页不再出现“在冒险指南中筛选坐骑”“在冒险指南中显示副本CD”“仅坐骑”；副本列表“仅坐骑”按钮仍可切换并在重开后记忆；详情页不再出现“仅坐骑”按钮。

## 6. 风险与回滚

- 风险：
  若只改 `encounter_journal` 文档而不同时建立 `quest` 文档，任务能力会在总览层丢失落点。
- 回滚方式：
  若对齐结果有误，应以当前代码为准重新修正文档，不回退到旧的“任务仍属于 `encounter_journal`”表述。

## 7. 执行记录

- 本轮已按当前代码现状把 `encounter_journal` 文档收敛为副本列表、详情页与锁定摘要增强。
- 任务能力改由 `quest` 文档链承接。
- 2026-04-27 已将“导航入口”确认规则写入需求和设计，开始实现阶段；业务代码须在文档落地后修改。
- 2026-04-27 已完成第一版 `Toolbox.EJ` 入口查找 / waypoint API；用户反馈按钮落点应从详情页改为副本列表条目右下角图钉，正在修正。
- 2026-04-27 已把“图钉高亮版”“定位图标常驻显示”确认规则写入 spec / design / plan；接下来先补失败中的逻辑测试，再改业务代码。
- 2026-04-29 已把点击回归修正口径写回 spec / design / plan：副本列表恢复 Blizzard 原生单击进入详情页，插件不再接管自定义双击 / 单击焦点逻辑。
- 2026-04-27 已把 DB 静态入口确认规则写入 spec / design / plan：新增 `instance_entrances` 契约，从 `journalinstanceentrance` 导出精确入口，业务代码须在本记录落地后再修改。
- 2026-04-27 已完成 `instance_entrances` 契约导出、TOC 接入、`Toolbox.EJ` 静态入口 fallback、文档回写与全量自动化验证。
- 2026-04-27 已修正 `厄运之槌 - 中心花园` 静态数据来源：`instance_entrances` 升级到 schema v2，精确 `areapoi` 优先，`230` 命中 `AreaPoiID=6501`。
- 2026-04-28 已修正 `Toolbox.EJ` 入口读取优先级：静态 `InstanceEntrances` 为主，运行时入口 API 不再抢占静态数据。
- 2026-04-28 已修正静态入口目标区域地图：`instance_entrances` 升级到 schema v3，从实例地图父 UiMap 推导 `HintUiMapID`；`230 厄运之槌 - 中心花园` 现在导出 `HintUiMapID=69`。
- 2026-04-29 已将新确认规则写回需求 / 设计 / 计划：删除 3 个设置项；保留并记忆列表“仅坐骑”；固定开启列表 CD 叠加；删除详情页“仅坐骑”按钮与功能。
- 2026-04-29 已按 TDD 落地本轮业务代码，并通过 `python tests/validate_settings_subcategories.py` 与 `busted tests/logic/spec/encounter_journal_mount_filter_spec.lua` 定向验证。
- 2026-04-29 已完成文档回写与全量自动化验证：`python tests/run_all.py --ci` 通过，计划收口为已完成。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 的现状基线与后续演进计划 |
| 2026-04-15 | 对齐当前实现：计划完成，`encounter_journal` 文档边界收敛为副本列表、详情页与锁定摘要能力 |
| 2026-04-27 | 用户确认“开动”：计划进入执行中，新增副本入口导航实施步骤 |
| 2026-04-27 | 用户反馈修正：导航入口落点改为副本列表条目右下角图钉 |
| 2026-04-27 | 用户确认列表图钉增强：追加悬停显钉 / 常驻显示设置的实现步骤 |
| 2026-04-27 | 用户确认 DB 静态入口方案：追加 `instance_entrances` 契约导出、TOC 加载与 `Toolbox.EJ` 静态入口兜底步骤 |
| 2026-04-29 | 用户确认设置精简方案：计划重开，追加删除 3 个设置项与对应存档/详情页功能收口步骤 |
| 2026-04-29 | 本轮执行完成：设置收口、详情页过滤移除与全量自动化验证已落地 |
