# instance_questlines 接入 QuestCompletist 补充源需求

- 文档类型：需求
- 状态：可执行
- 主题：instance-questlines-questcompletist
- 适用范围：`DataContracts/instance_questlines.json`、`scripts/export/**`、`Toolbox/Data/InstanceQuestlines.lua`
- 关联模块：quest
- 关联文档：
  - `docs/Toolbox-addon-design.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
  - `docs/plans/instance-questlines-questcompletist-plan.md`
- 最后更新：2026-04-13

## 1. 背景

- 现有 `instance_questlines` 导出仍保留偏 DB 中间态结构，包含 `questLineXQuest`、`questPOIBlobs`、`questPOIPoints` 等插件运行时并不稳定依赖的块。
- 用户本轮要求把任务线链路进一步收敛为“任务线为中心”的消费结构，并把地图 / 资料片归属规则改为明确、可复现的导出规则。
- QuestCompletist 仍作为补充源保留在导出链路内，但本轮重点不再是“是否接入补充源”，而是“最终导出结构与使用规则”。

## 2. 目标

- 在不新增运行时入口和模块的前提下，把 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua) 收敛为只保留 `quests`、`questLines`、`expansions` 三块的 schema v6 文档结构。
- 明确任务线地图归属、资料片归属和过滤规则，使插件侧只消费稳定的任务线级静态数据。
- 当前导出范围改为全量资料片数据，但仍只保留链路完整的任务线。

## 3. 范围

### 3.1 In Scope

- 调整 `instance_questlines` 契约与生成结果为 schema v6。
- 保留 QuestCompletist 补充源能力，但允许其结果进入新的任务线聚合结构。
- 将 `questLineXQuest` 合并进 `questLines[questLineID].QuestIDs`，并保证导出顺序稳定。
- 移除 `questPOIBlobs`、`questPOIPoints` 以及 `quests[*].UiMapID`。
- 新增顶层 `expansions[expansionID] = { questLineID... }` 分组索引。
- 更新插件侧 `Toolbox.Questlines` 与 `quest` 模块消费逻辑。
- 重新导出经典旧世数据并完成静态 / 逻辑验证。

### 3.2 Out of Scope

- 不新增 `RegisterModule`、菜单、按钮、slash 命令。
- 不把 QuestCompletist 整体数据模型引入插件运行时。
- 不为其他契约同时重构结构。
- 不手工修改 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua) 内容。
- 不再让任务详情通过静态 `quests[*].UiMapID` 回推地图。

## 4. 已确认决策

- 数据归属：继续归属现有 `instance_questlines` 契约，不新增独立 Data 契约。
- 主方案：在 `WoWTools` 导出脚本中读取 `wow.db` 与 QuestCompletist 数据，聚合后输出 schema v6。
- 冲突策略：QuestCompletist 优先，允许覆盖现有任务线成员关系与顺序。
- 结构形状：
  - 顶层保留 `quests`
  - 顶层保留 `questLines`
  - 顶层新增 `expansions`
  - 顶层移除 `questLineXQuest`
  - 顶层移除 `questPOIBlobs`
  - 顶层移除 `questPOIPoints`
- `quests[questID]`：
  - 仅保留 `ID`
- `questLines[questLineID]`：
  - 保留 `ID`
  - 保留 `UiMapID`
  - 保留有序 `QuestIDs`
  - 不再保留 `ExpansionID`
- `expansions[expansionID]`：
  - 维护该资料片下的有序 `questLineID` 数组
- 任务线任务列表来源：
  - 取 `questlinexquest where QuestLineID = questline.id`
  - 先按 `OrderIndex ASC` 排序
  - 同序再按 `QuestID ASC` 排序
  - 导出时只保留排好序的 `QuestIDs`
- 任务线地图归属：
  - 取排序后第一个任务
  - 由该任务关联的 `QuestPOIBlob -> UiMap`
  - 沿当前节点及父链寻找第一个 `type == 3` 的 `UiMapID`
- 过滤规则：
  - 若任务线没有可用 `UiMapID`，则不导出
  - 若 `UiMap` 父链不存在 `type == 3`，则不导出
  - 若最终 `UiMapID` 查不到 `ExpansionID`，则不导出
- 不再按 `ExpansionID` 过滤资料片范围；只要链路完整就导出
- 插件侧边界：
  - `Toolbox.Questlines` 与 `quest` 模块只消费统一导出结果
  - 任务详情不再依赖静态 `quests[*].UiMapID`
  - 地图信息改为运行时 API 获取，或由调用路径显式传入上下文
- 数据来源：QuestCompletist 主数据位于 `qcQuest.lua`，任务线名称位于 `qcQuestLines`，任务记录位于 `qcQuestDatabase`。
- 环境隔离：QuestCompletist 路径必须通过命令行参数或环境变量传入，不得在仓库中硬编码本地路径。

## 5. 待确认项

- 无。用户已于 2026-04-13 明确回复“开动”，且新增结构、过滤规则与插件消费边界已确认。

## 6. 验收标准

1. 导出脚本在提供 QuestCompletist 路径时，能读取 `qcQuest.lua` 并产出 schema v6 的 `instance_questlines` 数据。
2. 当同一任务线关系同时存在于 `wow.db` 与 QuestCompletist 时，最终导出结果以 QuestCompletist 的任务线归属和排序为准。
3. 生成结果只包含 `quests`、`questLines`、`expansions` 三个主块，不再输出 `questLineXQuest`、`questPOIBlobs`、`questPOIPoints`。
4. `questLines[*].QuestIDs` 已按 `OrderIndex ASC, QuestID ASC` 稳定排序，且导出结果不再保留 `OrderIndex`。
5. 只有链路完整且能解析出 `ExpansionID` 的任务线会出现在最终导出结果中。
6. 未提供 QuestCompletist 路径时，导出脚本仍可按纯 `wow.db` 路径工作，且不会报本地路径相关错误。
7. `export_toolbox_one.py instance_questlines` 可成功生成带契约头的 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua)，并保存契约快照。
8. 插件侧现有消费代码无需新增额外数据入口即可使用更新后的静态数据结构；任务详情地图信息改为运行时 API 或显式上下文传入。

## 7. 实施状态

- 当前状态：已确认为可执行，待完成代码修改、导出与验证。
- 下一步：按计划完成 schema v6 适配、全量导出和插件侧消费收敛。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：记录 QuestCompletist 接入 `instance_questlines` 的确认决策与验收标准 |
| 2026-04-13 | 更新：按用户确认调整为 schema v6，移除中间块并只导出经典旧世且链路完整的任务线 |
| 2026-04-13 | 更新：按用户追加要求改为导出全量资料片数据，不再限制 `ExpansionID == 0` |

