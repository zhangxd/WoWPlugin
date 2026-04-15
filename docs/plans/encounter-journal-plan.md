# 冒险指南现状基线与演进计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前副本列表、详情页与锁定摘要能力的文档基线
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/plans/quest-plan.md`
- 最后更新：2026-04-15

## 1. 目标

- 将 `encounter_journal` 的文档边界重新对齐到当前代码，只保留副本列表、详情页和锁定摘要增强。

## 2. 输入文档

- 需求：
  `docs/specs/encounter-journal-spec.md`
- 设计：
  `docs/designs/encounter-journal-design.md`
- 其他约束：
  当前代码实现是唯一事实来源；任务能力已拆到 `quest` 模块。

## 3. 影响文件

- 新增：
  无。
- 修改：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/FEATURES.md`
  - `docs/Toolbox-addon-design.md`
- 验证：
  - `python tests/run_all.py --ci`
  - 相关文档交叉引用与模块边界搜索

## 4. 执行步骤

- [x] 步骤 1：核对 `Toolbox/Modules/EncounterJournal*.lua`、`Toolbox/Core/API/EncounterJournal.lua` 与 `Toolbox/Modules/MinimapButton.lua` 的当前实现边界。
- [x] 步骤 2：重写 `encounter-journal` 对应的 feature/spec/design/test 文档，移除已迁移到 `quest` 的任务描述。
- [x] 步骤 3：同步回写 `docs/FEATURES.md` 与 `docs/Toolbox-addon-design.md`。
- [x] 步骤 4：通过自动化命令验证仓库当前状态。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`
- 命令 / 检查点 2：
  搜索 `docs/**` 中 `encounter_journal` 与“任务页签 / Quest Inspector / rootTab”组合的残留错位表述。
- 游戏内验证点：
  副本列表“仅坐骑”、CD 叠加、详情页增强、小地图与 `EJMicroButton` 锁定摘要。

## 6. 风险与回滚

- 风险：
  若只改 `encounter_journal` 文档而不同时建立 `quest` 文档，任务能力会在总览层丢失落点。
- 回滚方式：
  若对齐结果有误，应以当前代码为准重新修正文档，不回退到旧的“任务仍属于 `encounter_journal`”表述。

## 7. 执行记录

- 本轮已按当前代码现状把 `encounter_journal` 文档收敛为副本列表、详情页与锁定摘要增强。
- 任务能力改由 `quest` 文档链承接。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 的现状基线与后续演进计划 |
| 2026-04-15 | 对齐当前实现：计划完成，`encounter_journal` 文档边界收敛为副本列表、详情页与锁定摘要能力 |
