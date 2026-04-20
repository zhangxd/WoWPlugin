# instance_questlines 运行时扩展实施计划

- 文档类型：计划
- 状态：待执行
- 主题：instance-questlines-runtime-extension
- 适用范围：`scripts/export/**`、`Toolbox/Data/InstanceQuestlines.lua`、`Toolbox/Core/API/QuestlineProgress.lua`
- 关联模块：quest
- 关联文档：
  - `docs/designs/quest-db2-export-pipeline-design.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
- 最后更新：2026-04-15

> 使用说明：本计划用于把任务级/任务线级扩展字段接回现有 `instance_questlines`，保持 `schema v6` 主骨架兼容，不直接切换到全新数据模型。

## 1. 目标

- 在不破坏现有 `InstanceQuestlines` 视图逻辑的前提下，为任务线静态数据增加多地图、任务资料片、阵营/种族/职业限制字段，并让运行时按当前角色过滤不可做任务。

## 2. 输入文档

- 设计：
  - `docs/designs/quest-db2-export-pipeline-design.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
- 其他约束：
  - 仓库根 `AGENTS.md`
  - `docs/AI-ONBOARDING.md`
  - `instance_questlines` 正式导出走专门脚本，不再依赖 `DataContracts/instance_questlines.json`

## 3. 影响文件

- 新增：
  - `scripts/export/tests/test_instance_questlines_runtime_extension.py`
  - `scripts/export/export_instance_questlines_runtime.py`
- 修改：
  - `Toolbox/Data/InstanceQuestlines.lua`（工具生成）
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `tests/logic/fixtures/InstanceQuestlines_Mock.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
  - `docs/designs/quest-db2-export-pipeline-design.md`
- 验证：
  - `scripts/export/tests/*`
  - `tests/logic/spec/questline_progress_spec.lua`

## 4. 执行步骤

- [ ] 步骤 1：在导出工具测试里先写失败用例，锁定 `schema v6` 扩展版的字段集合。
- [ ] 步骤 2：新增 `export_instance_questlines_runtime.py`，从 `quest_expansion_map.csv` 聚合正式 `InstanceQuestlines.lua`。
- [ ] 步骤 3：在该脚本里让 `quests[*]` 新增 `QuestLineIDs`、`UiMapIDs`、`FactionTags`、`FactionConditions`、`RaceMaskValues`、`ClassMaskValues`、`ContentExpansionID`。
- [ ] 步骤 4：在该脚本里扩展 `questLines[*]`，新增 `UiMapIDs`、`PrimaryUiMapID`、`PrimaryMapCount`、`PrimaryMapShare`、`FactionTags`、`RaceMaskValues`、`ClassMaskValues`、`ContentExpansionID`，并保持旧字段 `UiMapID` 与 `QuestIDs` 不变。
- [ ] 步骤 5：在该脚本里按 `questLines[*].ContentExpansionID` 生成顶层 `expansions`。
- [ ] 步骤 6：生成新的 `Toolbox/Data/InstanceQuestlines.lua`，确认文件头、字段顺序和注释输出符合当前文档定义。
- [ ] 步骤 7：更新 `tests/logic/fixtures/InstanceQuestlines_Mock.lua`，补入最小扩展字段样例。
- [ ] 步骤 8：在 `Toolbox/Core/API/QuestlineProgress.lua` 的 strict 校验里允许新字段存在，但继续要求 `questLines[*].UiMapID`、`questLines[*].QuestIDs`、顶层 `expansions`。
- [ ] 步骤 9：在运行时新增任务过滤函数，按 `FactionTags`、`RaceMaskValues`、`ClassMaskValues` 判断当前角色是否能做任务。
- [ ] 步骤 10：把任务过滤接入任务线列表与任务详情构建流程；无可见任务的任务线在导航中隐藏。
- [ ] 步骤 11：把资料片导航改读 `ContentExpansionID` / 顶层 `expansions`，保留默认主地图导航继续读 `UiMapID`。
- [ ] 步骤 12：补充逻辑测试，覆盖联盟/部落共享主干、种族限制任务隐藏、多地图主地图稳定显示、任务资料片改为 `ContentExpansionID` 四类场景。
- [ ] 步骤 13：回写设计文档的正式落地状态，并记录与临时 `runtime_preview` 结构相比保留了哪些兼容字段。

## 5. 验证

- 命令 / 检查点 1：
  - `python -m unittest scripts.export.tests.test_instance_questlines_runtime_extension -v`
- 命令 / 检查点 2：
  - `python -m unittest scripts.export.tests.test_quest_db2_export_pipeline scripts.export.tests.test_questline_runtime_preview_export -v`
- 命令 / 检查点 3：
  - `python scripts/export/export_instance_questlines_runtime.py`
- 命令 / 检查点 4：
  - 运行 `tests/logic/spec/questline_progress_spec.lua`
- 游戏内验证点：
  - `quest` 模块仍能按主地图显示任务线
  - `收复吉尔尼斯` 归到 `Dragonflight`
  - 当前角色不满足阵营/种族/职业条件时，相关任务线或任务被隐藏

## 6. 风险与回滚

- 风险：
  - `QuestlineProgress.lua` 仍隐式假设一条任务线只有一个 `UiMapID`，扩展后若误用 `UiMapIDs` 可能导致导航重复显示。
  - 把 `expansions` 改为按 `ContentExpansionID` 聚合后，现有基于地图资料片的调试预期会变化。
  - 任务过滤如果直接作用于任务线视图，可能让部分共享主干线在不同阵营角色上“空线”消失。
- 回滚方式：
  - 保留 `UiMapID` 与旧 `expansions` 生成路径的 git 历史，出现回归时先回退专门脚本和生成文件。
  - 若运行时过滤引发误伤，先保留新字段但移除过滤调用，仅用于详情/调试视图。

## 7. 执行记录

- 2026-04-15：完成方案对齐，已先生成 `InstanceQuestlines.runtime_preview.lua` 作为轻量结构预览，不影响正式导出规则。
- 2026-04-15：确认 `instance_questlines` 正式导出跳过 `DataContracts`，改由专门脚本从 CSV 聚合生成。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：规划在兼容 `schema v6` 的前提下接入多地图、任务资料片与阵营/种族/职业限制字段 |
| 2026-04-15 | 调整实施路径：`instance_questlines` 改走专门脚本直出正式 Lua，不再依赖 `DataContracts` |

