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
- 最后更新：2026-04-27

## 1. 目标

- 将 `encounter_journal` 的文档边界重新对齐到当前代码，只保留副本列表、详情页和锁定摘要增强。
- 新增副本列表条目右下角图钉按钮：点击后打开目标地图，创建系统用户 waypoint，并启用系统导航追踪。
- 在现有图钉导航基础上补齐副本列表焦点态、双击进入、图钉高亮版与“定位图标常驻显示”设置。

## 2. 输入文档

- 需求：
  `docs/specs/encounter-journal-spec.md`
- 设计：
  `docs/designs/encounter-journal-design.md`
- 其他约束：
  当前代码实现是唯一事实来源；任务能力已拆到 `quest` 模块；导航入口已由用户在 2026-04-27 回复“开动”确认，并在后续反馈中修正为副本列表条目右下角图钉；同日又确认未勾选常驻显示时按“焦点或悬停显示”规则，双击进入副本。

## 3. 影响文件

- 新增：
  无。
- 修改：
  - `Toolbox/Core/API/EncounterJournal.lua`
  - `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua`
  - `Toolbox/Modules/EncounterJournal/Shared.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/FEATURES.md`
  - `docs/Toolbox-addon-design.md`
  - `tests/validate_settings_subcategories.py`
  - `tests/logic/spec/encounter_journal_navigation_spec.lua`
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
- [ ] 步骤 10：先为列表焦点 / 双击 / 图钉显隐规则写失败中的逻辑测试，并确认失败原因正确。
- [ ] 步骤 11：实现 `encounter_journal` 列表焦点态、双击进入与图钉显示状态管理。
- [ ] 步骤 12：新增 `listPinAlwaysVisible` 默认值、迁移与设置页复选框。
- [ ] 步骤 13：核对 Blizzard 高亮图钉资源名后替换列表图钉图标，并完成自动化验证。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py`
- 命令 / 检查点 2：
  搜索 `docs/**` 中 `encounter_journal` 与“任务页签 / Quest Inspector / rootTab”组合的残留错位表述。
- 游戏内验证点：
  副本列表“仅坐骑”、单击焦点、双击进入、副本列表图钉焦点 / 悬停 / 常驻显示、CD 叠加、详情页增强、小地图与 `EJMicroButton` 锁定摘要。

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
- 2026-04-27 已把“焦点 / 悬停显示”“双击进入”“定位图标常驻显示”确认规则写入 spec / design / plan；接下来先补失败中的逻辑测试，再改业务代码。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 的现状基线与后续演进计划 |
| 2026-04-15 | 对齐当前实现：计划完成，`encounter_journal` 文档边界收敛为副本列表、详情页与锁定摘要能力 |
| 2026-04-27 | 用户确认“开动”：计划进入执行中，新增副本入口导航实施步骤 |
| 2026-04-27 | 用户反馈修正：导航入口落点改为副本列表条目右下角图钉 |
| 2026-04-27 | 用户确认列表交互增强：追加焦点 / 双击 / 常驻显示设置的实现步骤 |
