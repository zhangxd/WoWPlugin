# 冒险指南任务类型运行时名称计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal-quest-type-runtime-name
- 适用范围：`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Modules/EncounterJournal.lua`、相关逻辑测试
- 关联模块：
  - `encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-quest-type-runtime-name-spec.md`
  - `docs/designs/encounter-journal-design.md`
- 最后更新：2026-04-12

## 1. 目标

- 让任务类型索引在构建时保存运行时类型名称，并让冒险指南类型视图直接消费该名称。

## 2. 输入文档

- 需求：`docs/specs/encounter-journal-quest-type-runtime-name-spec.md`
- 设计：`docs/designs/encounter-journal-design.md`
- 其他约束：`AGENTS.md` 的三关门禁、API 查证规则、TDD 要求与 `docs/DOCS-STANDARD.md`

## 3. 影响文件

- 新增：
  - `docs/specs/encounter-journal-quest-type-runtime-name-spec.md`
  - `docs/plans/encounter-journal-quest-type-runtime-name-plan.md`
- 修改：
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
  - `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
  - `docs/designs/encounter-journal-design.md`
- 验证：
  - `python tests/run_all.py --ci`
  - 相关单测选择性运行

## 4. 执行步骤

- [x] 步骤 1：在 `tests/logic/spec/questline_progress_spec.lua` 为 `GetQuestTypeIndex()` 新增失败测试，先断言 `typeList` 包含运行时名称对象与 `Unknown Type (%s)` 兜底。
- [x] 步骤 2：运行受影响单测，确认新增断言在现状下失败，且失败原因是类型索引结构/名称来源不符合预期。
- [x] 步骤 3：在 `Toolbox/Core/API/QuestlineProgress.lua` 最小化实现运行时任务类型名称查询，并在类型索引构建时写入 `{ id, name }` 对象。
- [x] 步骤 4：在 `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua` 为类型视图列表与标题新增失败测试，断言其直接显示类型索引中的运行时名称。
- [x] 步骤 5：运行受影响单测，确认 UI 侧断言在现状下失败，且失败原因是消费层仍按旧的数字数组处理。
- [x] 步骤 6：在 `Toolbox/Modules/EncounterJournal.lua` 最小化修改类型视图消费逻辑，保持 `selectedTypeID` 仍为数字型。
- [x] 步骤 7：运行相关逻辑测试并更新 `docs/designs/encounter-journal-design.md` 的任务类型名称来源说明。
- [x] 步骤 8：汇总验证结果，确认无新增存档迁移与无新增入口后收尾。

## 5. 验证

- 命令 / 检查点 1：`python tests/run_all.py --ci`
- 命令 / 检查点 2：按需运行 `python tests/run_all.py --pattern questline_progress_spec`
- 命令 / 检查点 3：按需运行 `python tests/run_all.py --pattern encounter_journal_event_lifecycle_spec`
- 游戏内验证点：冒险指南任务类型视图的列表项名称、右侧标题与类型筛选行为正常

## 6. 风险与回滚

- 风险：`GetQuestTagInfo` 在部分任务上可能返回空名称，导致更多类型显示为 `Unknown Type (%s)`。
- 风险：`typeList` 结构变化会影响现有消费方与测试桩，若有遗漏会直接导致类型视图渲染异常。
- 回滚方式：回退本次对 `QuestlineProgress.lua`、`EncounterJournal.lua` 与相关测试、文档的修改，恢复 `typeList` 数字数组与静态映射显示路径。

## 7. 执行记录

- 2026-04-12：已记录用户确认决策，并先将 spec 状态落为“可执行”。
- 2026-04-12：已按 TDD 先补失败测试，再实现类型索引运行时名称与类型视图新结构消费。
- 2026-04-12：已运行 `python tests/run_all.py --ci`，结果为 35 successes / 0 failures / 0 errors。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：记录运行时类型名称改造的执行步骤与验证路径 |
| 2026-04-12 | 完成：步骤全勾选，计划状态改为已完成 |
