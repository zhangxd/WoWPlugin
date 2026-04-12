# instance_questlines 接入 QuestCompletist 补充源设计

- 文档类型：设计
- 状态：已落地
- 主题：instance-questlines-questcompletist
- 适用范围：`../WoWTools/scripts/export/**`、`DataContracts/instance_questlines.json`
- 关联模块：encounter_journal
- 关联文档：
  - `docs/specs/instance-questlines-questcompletist-spec.md`
  - `docs/plans/instance-questlines-questcompletist-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-13

## 1. 背景

- `instance_questlines` 当前完全依赖 SQLite 查询结果，缺少一个可插拔的补充源合并层。
- QuestCompletist 在 `qcQuest.lua` 内维护了任务线名称表和任务记录表，其中任务记录包含任务线 id 与前置任务 id，可用于重建任务线链路。

## 2. 设计目标

- 在不改变插件运行时数据消费方式的前提下，把 QuestCompletist 作为 `instance_questlines` 的可选补充源接入导出流程。
- 保持导出脚本的契约驱动结构，避免为单一契约写死仓库本地路径。
- 让补充源缺席时保留现有导出行为，降低工具链回归风险。

## 3. 非目标

- 不把 QuestCompletist 解析逻辑带入 WoW 插件 Lua 运行时。
- 不为所有契约建立通用多源合并 DSL；本次只做当前导出工具可承载的最小扩展。
- 不调整 `Toolbox.Data.InstanceQuestlines` 的 Lua 结构或字段命名。

## 4. 方案对比

### 方案 A：插件运行时直接兼容 QuestCompletist

- 优点：不需要改导出工具。
- 缺点：违反当前静态数据契约驱动方向，运行时增加外部依赖，且用户未要求新增运行时入口。

### 方案 B：在导出工具增加 QuestCompletist 解析与合并层

- 优点：符合现有“工具生成 Data 文件”的规则，插件侧无感知，便于测试和复用。
- 缺点：需要在 `WoWTools` 中增加 Lua 大表解析逻辑。

### 方案 C：先手工抽取 QuestCompletist 数据为中间文件，再让导出脚本消费

- 优点：导出脚本实现简单。
- 缺点：多出一层人工产物治理，后续同步成本高，也不满足“使用工具来做”的要求。

### 结论

- 选定方案 B。它与现有契约驱动导出最一致，且能够把 QuestCompletist 限制在工具链边界内。

## 5. 选定方案

- 在 `toolbox_db_export.py` 中为 document 型契约增加一个可选补充源入口，仅在 `instance_questlines` 契约声明了 QuestCompletist 配置时启用。
- 新增 QuestCompletist 解析器，从 `qcQuest.lua` 中提取：
  - `qcQuestLines`：任务线 id 到任务线名称。
  - `qcQuestDatabase`：任务 id、任务线 id、前置任务 id。
- 合并策略：
  - 先执行现有 `wow.db` datasets 查询。
  - 再根据 QuestCompletist 生成补充的 `core_links` 行。
  - 同一任务若在 QuestCompletist 中声明了任务线 id，则该关系覆盖 `wow.db` 原关系。
  - 同一任务线内的顺序优先按 QuestCompletist 的前置链推导，无法推导时退回稳定排序。
  - `quest_ui_map_id`、`quest_line_ui_map_id`、`quest_line_expansion_id` 优先复用现有 `wow.db` 已能得到的映射；对新增任务线则基于其成员任务的最佳地图投票结果回填。
- 路径配置：
  - 优先命令行参数传入 QuestCompletist 目录。
  - 可选环境变量兜底。
  - 未配置时跳过补充源，不报硬错误。

## 6. 影响面

- 数据：
  - `instance_questlines` 导出结果可能新增任务线或变更现有任务线成员顺序。
- API：
  - 插件侧公共 API 不变。
  - 导出脚本 CLI 可能新增 QuestCompletist 路径参数。
- 目录 / 文件：
  - 主要修改 `../WoWTools/scripts/export/toolbox_db_export.py` 及其测试。
  - 可能需要在 `DataContracts/instance_questlines.json` 中声明补充源配置。
- 文档回写：
  - 落地后需要回写 [Toolbox-addon-design.md](D:\WoWProject\WoWPlugin\docs\Toolbox-addon-design.md) 的数据导出说明与修订记录。

## 7. 风险与回退

- 风险：QuestCompletist 的 Lua 数据格式不是标准序列化格式，解析器若写得过于宽松，容易把异常记录吞掉。
- 风险：基于前置任务推导顺序时，可能遇到循环、断链或多前置分支。
- 风险：QuestCompletist 的分类 / 区域 id 不一定能直接映射到当前 `UiMapID`。
- 回退方式：保留“未提供 QuestCompletist 路径即按原 SQL 导出”的路径；若补充源解析失败，可禁用其配置并重新导出。

## 8. 验证策略

- 先为 QuestCompletist 解析与合并写离线测试，用最小样本证明：
  - 能解析任务线名称、任务线 id、前置任务 id。
  - 同任务冲突时采用 QuestCompletist。
  - 新任务线可从任务级地图推导 `quest_line_ui_map_id`。
- 再执行 `export_toolbox_one.py instance_questlines` 做端到端验证。
- 最后检查生成文件头、契约快照和输出结构未变。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：确定 QuestCompletist 作为 `instance_questlines` 的导出补充源接入方案 |
