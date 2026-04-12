# 冒险指南现状基线与演进计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前能力基线整理与后续增量演进入口
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
- 最后更新：2026-04-13

## 1. 目标

- 把 `encounter_journal` 当前已实现能力整理成可持续维护的文档基线，并明确后续新增功能时应沿用的更新路径。

## 2. 输入文档

- 功能：`docs/features/encounter-journal-features.md`
- 需求：`docs/specs/encounter-journal-spec.md`
- 设计：`docs/designs/encounter-journal-design.md`
- 测试：`docs/tests/encounter-journal-test.md`
- 其他约束：当前代码实现是唯一事实来源；历史阶段文档仅保留追溯作用。

## 3. 影响文件

- 当前实现主文件：
  - `Toolbox/Modules/EncounterJournal.lua`
  - `Toolbox/Modules/MinimapButton.lua`
  - `Toolbox/Core/API/EncounterJournal.lua`
  - `Toolbox/Core/API/QuestlineProgress.lua`
- 当前文档基线：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
- 历史并回项：
  - 任务页签导航重构
  - 任务线运行时名称
  - 任务类型运行时名称

## 4. 执行步骤

- [x] 梳理当前代码中已经落地的冒险指南能力。
- [x] 建立模块级功能文档，记录用户视角的当前能力。
- [x] 建立需求基线文档，记录现阶段范围与验收口径。
- [x] 建立设计文档，统一模块归属、数据来源与边界。
- [x] 建立测试基线文档，记录现有自动化验证与手工检查清单。
- [x] 覆盖旧的阶段性文档，使其只作为历史入口，不再作为并行事实来源。
- [x] 将 `encounter-journal-*` 子专题中的仍有效内容并回主文档，仅保留 `encounter-journal` 五份主文档。

## 5. 验证

- 目录验证：
  `encounter_journal` 已具备 `features / spec / design / plan / test` 五类配套文档，且不再保留继续维护的 `encounter-journal-*` 子专题平行文档。
- 一致性验证：
  文档中的模块归属、数据来源、入口说明必须与当前代码一致。
- 自动化验证：
  运行 `python tests/run_all.py --ci`，确认当前逻辑与静态校验仍然通过。

## 6. 风险与回滚

- 风险：
  若未来只改代码而不回写本套文档，会再次出现“功能存在但说明分散”的漂移。
- 风险：
  若跨模块联动只写在单模块文档中，容易让边界再次混乱。
- 回滚方式：
  若本计划中的整理结论需要调整，应优先修改 `spec / design / features / test` 四类文档，再回写 `Toolbox-addon-design.md` 与 `FEATURES.md`。

## 7. 执行记录

- 本计划记录的不是“待开发任务”，而是“当前实现的整理与未来演进入口”。
- 后续新增冒险手册 / 冒险指南能力时，以 `encounter-journal-features / spec / design / plan / test` 这一组文档为统一基线：
  - 先更新 `encounter-journal-spec.md`
  - 再更新 `encounter-journal-design.md`
  - 若功能已对外可见，同步更新 `encounter-journal-features.md`
  - 补充或更新 `encounter-journal-test.md`
  - 最后回写 `FEATURES.md` 与 `Toolbox-addon-design.md`
- 同一功能下的导航重构、名称来源调整、验证补充等子专题，也统一落在这五份主文档中，不再单独新建 `encounter-journal-xxx-plan.md` 等文件。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 的现状基线与后续演进计划 |
| 2026-04-13 | 文档收口：明确仅保留 `encounter-journal` 五份主文档，子专题执行记录统一并回主计划 |
