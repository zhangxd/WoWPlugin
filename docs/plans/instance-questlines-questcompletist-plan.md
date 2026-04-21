# instance_questlines 接入 QuestCompletist 补充源实施计划

- 文档类型：计划
- 状态：执行中
- 主题：instance-questlines-questcompletist
- 适用范围：`scripts/export/**`、`DataContracts/instance_questlines.json`、`Toolbox/Data/InstanceQuestlines.lua`
- 关联模块：quest
- 关联文档：
  - `docs/specs/instance-questlines-questcompletist-spec.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
- 最后更新：2026-04-13

## 1. 目标

- 将 `instance_questlines` 调整为 schema v6：导出结果只保留 `quests`、`questLines`、`expansions`，并完成插件侧消费适配、测试与全量数据导出验证。

## 2. 输入文档

- 需求：`docs/specs/instance-questlines-questcompletist-spec.md`
- 设计：`docs/designs/instance-questlines-questcompletist-design.md`
- 其他约束：
  - `AGENTS.md` 中的 WoWDB 静态数据导出规则。
  - 不得在仓库中硬编码本地 QuestCompletist 路径。
  - 用户已确认：
    - `questLineXQuest` 合并进 `questLines[*].QuestIDs`
    - `QuestIDs` 导出时保证有序但不保留 `OrderIndex`
    - `questPOIBlobs`、`questPOIPoints` 移除
    - `quests[*].UiMapID` 移除
    - 顶层新增 `expansions[expansionID] = { questLineID... }`
    - 缺失 `ExpansionID`、缺失有效 `UiMapID`、父链不存在 `type == 3`、或 `ExpansionID ~= 0` 时不导出
    - 任务详情地图信息改为运行时 API 获取或显式上下文传入

## 3. 影响文件

- 修改：
  - `scripts/export/toolbox_db_export.py`
  - `DataContracts/instance_questlines.json`
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Data/InstanceQuestlines.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
  - `tests/logic/spec/questline_progress_live_data_spec.lua`
  - `tests/validate_settings_subcategories.py`
  - `docs/Toolbox-addon-design.md`
  - 本需求 / 设计 / 计划文档
- 新增：
  - 视导出器现状，按需新增 `scripts/export/tests/*` 测试文件或测试用例

## 4. 执行步骤

- [x] 步骤 1：将“开动”后的确认决策写入需求/设计/计划文档，并把需求状态置为“可执行”。
- [ ] 步骤 2：先修改 `questline_progress_spec.lua`、`questline_progress_live_data_spec.lua` 与 `tests/validate_settings_subcategories.py`，写出针对 schema v6 的失败测试 / 校验。
- [ ] 步骤 3：运行逻辑测试与静态校验，确认它们先因旧结构失败。
- [ ] 步骤 4：修改 `DataContracts/instance_questlines.json` 与导出脚本，生成 schema v6 所需聚合结构和过滤规则。
- [ ] 步骤 5：修改 `Toolbox/Core/API/QuestlineProgress.lua`，适配 `questLines[*].QuestIDs` 和顶层 `expansions`，移除对 `questPOIBlobs`、`questPOIPoints`、`quests[*].UiMapID` 的依赖。
- [ ] 步骤 6：重新运行测试并修正实现，保证逻辑测试和静态校验通过。
- [ ] 步骤 7：执行 `python scripts/export/export_quest_achievement_merged_from_db.py` 重导全量数据，检查 tagged header 与结构。
- [ ] 步骤 8：根据最终落地结果回写总设计文档，并补记执行记录。

## 5. 验证

- 命令 / 检查点 1：运行 `python tests/run_all.py` 或当前仓库用于逻辑测试的最小命令，至少覆盖 `questline_progress_spec.lua` 与 `questline_progress_live_data_spec.lua`。
- 命令 / 检查点 2：运行 `python tests/validate_settings_subcategories.py`，确认静态结构校验通过。
- 命令 / 检查点 3：运行 `python -m unittest scripts.export.tests.test_contract_export` 以及相关 QuestCompletist / 导出测试。
- 命令 / 检查点 4：运行 `python scripts/export/export_quest_achievement_merged_from_db.py --output-lua Toolbox/Data/InstanceQuestlines.lua`，必要时附带 `--db` 路径参数。
- 检查点 5：抽查生成的 `InstanceQuestlines.lua` 是否只保留 `quests`、`questLines`、`expansions`，且存在多个资料片分组。
- 游戏内验证点：本回合以离线导出与静态数据结构验证为主，不直接要求游戏内 UI 点验。

## 6. 风险与回滚

- 风险：QuestCompletist 数据格式解析失败导致导出中断。
- 风险：`UiMap` 父链 `type == 3` 过滤后，导出结果比预期少。
- 风险：插件侧仍残留旧结构依赖，导致逻辑测试或任务详情回归。
- 回滚方式：撤回导出工具、契约与插件消费改动，重新按旧 schema 导出 `instance_questlines`。

## 7. 执行记录

- 2026-04-13：已确认用户选择“QuestCompletist 作为 `instance_questlines` 的补充输入源”，且冲突策略为“QuestCompletist 优先”。
- 2026-04-13：已确认本轮目标调整为 schema v6，并收敛为 `quests`、`questLines`、`expansions` 三块。
- 2026-04-13：已确认导出范围改为全量资料片；缺失 `UiMapID`、缺失 `type == 3`、缺失 `ExpansionID` 的记录一律过滤。
- 2026-04-13：已确认任务详情不再依赖静态 `quests[*].UiMapID`，改为运行时 API 或调用链上下文。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：记录 QuestCompletist 补充源接入的执行步骤与验证口径 |
| 2026-04-13 | 更新：计划扩展为 schema v6 收敛、插件侧消费适配与经典旧世过滤导出 |
| 2026-04-13 | 更新：导出范围改为全量资料片，验证口径同步调整 |

