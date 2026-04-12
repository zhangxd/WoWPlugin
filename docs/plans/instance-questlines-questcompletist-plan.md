# instance_questlines 接入 QuestCompletist 补充源实施计划

- 文档类型：计划
- 状态：已完成
- 主题：instance-questlines-questcompletist
- 适用范围：`../WoWTools/scripts/export/**`、`DataContracts/instance_questlines.json`、`Toolbox/Data/InstanceQuestlines.lua`
- 关联模块：encounter_journal
- 关联文档：
  - `docs/specs/instance-questlines-questcompletist-spec.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
- 最后更新：2026-04-13

## 1. 目标

- 为 `instance_questlines` 导出增加 QuestCompletist 补充源解析与合并，并完成测试和一次契约驱动导出验证。

## 2. 输入文档

- 需求：`docs/specs/instance-questlines-questcompletist-spec.md`
- 设计：`docs/designs/instance-questlines-questcompletist-design.md`
- 其他约束：
  - `AGENTS.md` 中的 WoWDB 静态数据导出规则。
  - 不得在仓库中硬编码本地 QuestCompletist 路径。

## 3. 影响文件

- 新增：
  - 视实现需要新增 `../WoWTools/scripts/export/tests/*` 测试文件或测试用例。
- 修改：
  - `../WoWTools/scripts/export/toolbox_db_export.py`
  - `DataContracts/instance_questlines.json`
  - `Toolbox/Data/InstanceQuestlines.lua`
  - `docs/Toolbox-addon-design.md`
- 验证：
  - `../WoWTools/scripts/export/tests/test_contract_export.py`
  - 相关新增测试文件

## 4. 执行步骤

- [x] 步骤 1：将“开动”后的确认决策写入需求/设计/计划文档，并把需求状态置为“可执行”。
- [x] 步骤 2：梳理 `toolbox_db_export.py` 与 `qcQuest.lua` 的最小字段映射，形成可测试的解析规则。
- [x] 步骤 3：先写 QuestCompletist 解析与合并的失败测试，覆盖冲突覆盖、顺序重建与缺省路径。
- [x] 步骤 4：实现 QuestCompletist 路径配置、Lua 表解析和 `core_links` 合并逻辑。
- [x] 步骤 5：运行测试修正实现，保证导出工具在有/无 QuestCompletist 路径时都能工作。
- [x] 步骤 6：执行 `export_toolbox_one.py instance_questlines` 生成最新 Data 文件并检查契约头与快照。
- [x] 步骤 7：根据落地结果回写总设计文档，并记录实际验证结果。

## 5. 验证

- 命令 / 检查点 1：运行 `python -m unittest scripts.export.tests.test_contract_export`。
- 命令 / 检查点 2：运行补充的 QuestCompletist 解析/合并测试。
- 命令 / 检查点 3：运行 `python scripts/export/export_toolbox_one.py instance_questlines --contract-dir ../WoWPlugin/DataContracts --data-dir ../WoWPlugin/Toolbox/Data`，必要时附带 QuestCompletist 路径参数或环境变量。
- 游戏内验证点：当前回合以离线导出与静态数据结构验证为主，不直接要求游戏内 UI 点验。

## 6. 风险与回滚

- 风险：QuestCompletist 数据格式解析失败导致导出中断。
- 风险：顺序推导规则与现有消费者预期不一致。
- 回滚方式：撤回导出工具与契约配置改动，重新按纯 `wow.db` 路径导出 `instance_questlines`。

## 7. 执行记录

- 2026-04-13：已确认用户选择“QuestCompletist 作为 `instance_questlines` 的补充输入源”，且冲突策略为“QuestCompletist 优先”。
- 2026-04-13：已核实 QuestCompletist 主数据位于 `qcQuest.lua`，其中 `qcQuestLines` 与 `qcQuestDatabase` 可作为补充源解析入口。
- 2026-04-13：已在 `WoWTools/scripts/export/toolbox_db_export.py` 中增加 QuestCompletist 解析、路径参数与 `core_links` 合并逻辑。
- 2026-04-13：已新增 `scripts/export/tests/test_questcompletist_export.py`，并通过离线测试验证“QuestCompletist 覆盖现有任务线关系与顺序”。
- 2026-04-13：已执行单项导出命令生成最新 `Toolbox/Data/InstanceQuestlines.lua`，并抽查到 `5459`、`5578/5579`、`5934` 等补充任务线写入结果。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：记录 QuestCompletist 补充源接入的执行步骤与验证口径 |
