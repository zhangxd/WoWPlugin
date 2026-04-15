# instance_questlines 接入 QuestCompletist 补充源设计

- 文档类型：设计
- 状态：已确认
- 主题：instance-questlines-questcompletist
- 适用范围：`../WoWTools/scripts/export/**`、`DataContracts/instance_questlines.json`
- 关联模块：quest
- 关联文档：
  - `docs/specs/instance-questlines-questcompletist-spec.md`
  - `docs/plans/instance-questlines-questcompletist-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-13

## 1. 背景

- `instance_questlines` 当前完全依赖 SQLite 查询结果，缺少一个可插拔的补充源合并层。
- QuestCompletist 在 `qcQuest.lua` 内维护了任务线名称表和任务记录表，其中任务记录包含任务线 id 与前置任务 id，可用于重建任务线链路。

## 2. 设计目标

- 保留 QuestCompletist 作为 `instance_questlines` 的可选补充源。
- 将导出结果收敛为以任务线为中心的 schema v6，减少 DB 中间态结构直接暴露给插件运行时。
- 让插件侧只依赖稳定的任务线级静态数据，并把任务详情地图信息交还给运行时 API 或调用链上下文。

## 3. 非目标

- 不把 QuestCompletist 解析逻辑带入 WoW 插件 Lua 运行时。
- 不为所有契约建立通用多源合并 DSL；本次只做当前导出工具可承载的最小扩展。
- 不新增模块、入口或专门的运行时兼容层。

## 4. 方案对比

### 方案 A：保持现有 schema，仅补 QuestCompletist 数据

- 优点：改动范围最小。
- 缺点：继续保留 `questLineXQuest`、`questPOIBlobs`、`questPOIPoints` 等中间块，结构仍然偏 DB 形状，不符合本轮目标。

### 方案 B：在导出工具中完成补充源合并，并同时收敛为 schema v6

- 优点：符合现有“工具生成 Data 文件”的规则，插件侧只消费最终形状，能够把静态结构与运行时职责重新切清。
- 缺点：需要同时修改契约、导出器、插件消费代码和测试。

### 方案 C：运行时放弃静态聚合，改由 API 动态推导任务线地图和资料片

- 优点：静态数据结构更薄。
- 缺点：运行时要承担更多查表和容错逻辑，且无法替代导出时对链路完整性的过滤要求。

### 结论

- 选定方案 B。它与现有契约驱动导出最一致，也能把 QuestCompletist 限制在工具链边界内，同时满足用户对 schema v6 与全量导出的要求。

## 5. 选定方案

- 在 `toolbox_db_export.py` 中继续使用 QuestCompletist 作为 `instance_questlines` 的可选补充源。
- `core_links` 的语义改为“任务线最终成员关系源”，输出用于聚合 `questLines[*].QuestIDs`。
- 任务线成员排序：
  - 优先按 QuestCompletist 推导出的链路顺序
  - 否则回退到 `questlinexquest.OrderIndex ASC, QuestID ASC`
  - 最终导出只保留有序 `QuestIDs` 数组
- 任务线地图归属：
  - 取排好序后的第一个任务
  - 查询该任务关联的 `QuestPOIBlob -> UiMap`
  - 沿当前节点及父链向上找到第一个 `type == 3` 的 `UiMapID`
- 资料片分组：
  - 由最终 `UiMapID -> map.ExpansionID` 得到 `expansionID`
  - 反向聚合为顶层 `expansions[expansionID] = { questLineID... }`
- 过滤规则：
  - 没有有效 `UiMapID` 的任务线不导出
  - 父链找不到 `type == 3` 的任务线不导出
  - 查不到 `ExpansionID` 的任务线不导出
- 不按 `ExpansionID` 过滤导出范围；所有可解析资料片都会保留
- 运行时消费：
  - `Toolbox.Questlines` 改为读取 `questLines[*].QuestIDs` 与顶层 `expansions`
  - 不再读取 `questLineXQuest`、`questPOIBlobs`、`questPOIPoints`
  - 任务详情地图信息由运行时 API 获取，或由调用链显式传入上下文
- 路径配置：
  - QuestCompletist 目录优先命令行参数传入
  - 可选环境变量兜底
  - 未配置时跳过补充源，不报硬错误

## 6. 影响面

- 数据：
  - `instance_questlines` 导出结构升级为 schema v6
  - `questLines[*]` 新增内嵌 `QuestIDs`
  - 新增顶层 `expansions`
  - 删除顶层 `questLineXQuest`
  - 删除顶层 `questPOIBlobs`
  - 删除顶层 `questPOIPoints`
  - 删除 `quests[*].UiMapID`
- API：
  - 插件侧公共入口名保持不变
  - `Toolbox.Questlines` 内部校验和建模逻辑需适配 schema v6
  - 任务详情不再依赖静态任务地图字段
- 目录 / 文件：
  - 主要修改 `../WoWTools/scripts/export/toolbox_db_export.py` 及其测试
  - 需要更新 `DataContracts/instance_questlines.json`
  - 需要更新 `Toolbox/Core/API/QuestlineProgress.lua`
  - 需要更新逻辑测试与静态校验脚本
- 文档回写：
  - 落地后需要回写 [Toolbox-addon-design.md](D:\WoWProject\WoWPlugin\docs\Toolbox-addon-design.md) 的导出结构与消费说明

## 7. 风险与回退

- 风险：QuestCompletist 的 Lua 数据格式不是标准序列化格式，解析器若写得过于宽松，容易把异常记录吞掉。
- 风险：基于前置任务推导顺序时，可能遇到循环、断链或多前置分支。
- 风险：首任务沿 `UiMap` 父链查 `type == 3` 的规则，可能让部分原先可见任务线被过滤掉。
- 风险：移除静态 `quests[*].UiMapID` 后，若插件侧仍有旧依赖会直接回归。
- 回退方式：
  - 保留“未提供 QuestCompletist 路径即按原 SQL 导出”的路径
  - 如 schema v6 消费侧出现回归，可回退契约和消费代码并重新导出旧版本数据

## 8. 验证策略

- 先为 `QuestlineProgress.lua` 新 schema 适配写失败测试，覆盖：
  - schema v6 strict 校验
  - `questLines[*].QuestIDs` 建模
  - `expansions` 分组消费
  - 任务详情不再依赖静态 `quests[*].UiMapID`
- 再为导出工具补离线测试，覆盖：
  - `QuestIDs` 排序
  - `UiMap` 父链 `type == 3` 过滤
- 全量资料片导出
- 再执行 `export_toolbox_one.py instance_questlines` 做端到端验证。
- 最后检查生成文件头、契约快照以及 schema v6 结构符合预期。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-13 | 初稿：确定 QuestCompletist 作为 `instance_questlines` 的导出补充源接入方案 |
| 2026-04-13 | 更新：方案扩展为 schema v6 收敛，移除中间块并只保留经典旧世且链路完整的任务线 |
| 2026-04-13 | 更新：取消经典旧世限定，schema v6 改为导出全量资料片且链路完整的任务线 |
