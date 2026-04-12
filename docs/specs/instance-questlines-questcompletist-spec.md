# instance_questlines 接入 QuestCompletist 补充源需求

- 文档类型：需求
- 状态：已完成
- 主题：instance-questlines-questcompletist
- 适用范围：`DataContracts/instance_questlines.json`、`../WoWTools/scripts/export/**`、`Toolbox/Data/InstanceQuestlines.lua`
- 关联模块：encounter_journal
- 关联文档：
  - `docs/Toolbox-addon-design.md`
  - `docs/designs/instance-questlines-questcompletist-design.md`
  - `docs/plans/instance-questlines-questcompletist-plan.md`
- 最后更新：2026-04-13

## 1. 背景

- 现有 `instance_questlines` 导出仅依赖 `wow.db` 中的 `questline`、`questlinexquest` 与 `questpoi*` 表。
- 用户要求将本地安装的 QuestCompletist 插件数据补充进现有任务线导出链路，以弥补 `wow.db` 中缺失或不完整的任务线成员关系。
- 由于数据量大，必须通过契约驱动导出工具处理，不能手工覆盖生成文件。

## 2. 目标

- 在不新增运行时入口和模块的前提下，让 `instance_questlines` 导出支持读取 QuestCompletist 数据，并将其合并到最终生成的 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua) 中。

## 3. 范围

### 3.1 In Scope

- 为 `instance_questlines` 导出增加 QuestCompletist 补充源解析与合并逻辑。
- 保持生成产物的 Lua 文档结构不变，继续由契约驱动脚本输出。
- 允许 QuestCompletist 覆盖现有任务线成员关系与顺序。
- 为补充源路径提供非硬编码配置方式。
- 为新导出链路补测试与验证命令。

### 3.2 Out of Scope

- 不新增 `RegisterModule`、菜单、按钮、slash 命令或运行时兜底读取。
- 不把 QuestCompletist 整体数据模型引入插件运行时。
- 不为其他契约同时接入 QuestCompletist。
- 不手工修改 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua) 内容。

## 4. 已确认决策

- 数据归属：继续归属现有 `instance_questlines` 契约，不新增独立 Data 契约。
- 主方案：在 `WoWTools` 导出脚本中读取 QuestCompletist 数据，与 `wow.db` 结果合并后再输出。
- 冲突策略：QuestCompletist 优先，允许覆盖现有任务线关系和排序。
- 运行时边界：`Toolbox.Questlines` 与 `encounter_journal` 只消费统一导出结果，不直接感知 QuestCompletist。
- 数据来源：当前已确认 QuestCompletist 主数据位于 `qcQuest.lua`，任务线名称位于 `qcQuestLines`，任务记录位于 `qcQuestDatabase`。
- 环境隔离：QuestCompletist 路径必须通过命令行参数或环境变量传入，不得在仓库中硬编码 `E:` 盘路径。

## 5. 待确认项

- 无。用户已确认“开动”，且主方案、边界与冲突规则均已落地为可执行决策。

## 6. 验收标准

1. 导出脚本在提供 QuestCompletist 路径时，能读取 `qcQuest.lua` 并产出补充后的 `instance_questlines` 数据。
2. 当同一任务线关系同时存在于 `wow.db` 与 QuestCompletist 时，最终导出结果以 QuestCompletist 的任务线归属和排序为准。
3. 未提供 QuestCompletist 路径时，导出脚本仍可按原有纯 `wow.db` 路径工作，且不会报本地路径相关错误。
4. `export_toolbox_one.py instance_questlines` 可成功生成带契约头的 [InstanceQuestlines.lua](D:\WoWProject\WoWPlugin\Toolbox\Data\InstanceQuestlines.lua)，并保存契约快照。
5. 插件侧现有消费代码无需新增入口即可使用更新后的静态数据结构。

## 7. 实施状态

- 当前状态：已完成
- 下一步：如后续需要继续扩展补充源过滤规则或映射规则，再单独立新需求。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：记录 QuestCompletist 接入 `instance_questlines` 的确认决策与验收标准 |
