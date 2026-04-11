# 冒险指南任务类型运行时名称需求

- 文档类型：需求
- 状态：已完成
- 主题：encounter-journal-quest-type-runtime-name
- 适用范围：`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Modules/EncounterJournal.lua` 的任务类型索引与类型视图显示
- 关联模块：
  - `encounter_journal`
- 关联文档：
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-quest-type-runtime-name-plan.md`
- 最后更新：2026-04-12

## 1. 背景

- 当前任务类型索引只保存数值型 `typeID`，类型名称展示依赖 `Toolbox.Data.QuestTypeNames` 与 `Toolbox.Questlines.GetQuestTypeLabel(typeID)` 的静态映射。
- 用户已确认将任务类型名称切换为运行时来源，希望在构建类型索引时就把名称一起带上，减少类型视图再次反查时对静态映射的依赖。
- 本次需求只调整已有 `encounter_journal` 类型视图与 `Toolbox.Questlines` 内部索引结构，不新增模块、入口或存档键。

## 2. 目标

- 让任务类型索引在构建时同时保存 `typeID` 与运行时类型名称，并让冒险指南类型视图直接消费该名称。

## 3. 范围

### 3.1 In Scope

- 调整 `GetQuestTypeIndex()` 的 `typeList` 返回结构，使其由数字数组改为对象数组。
- 在构建类型索引时，通过 `GetQuestTagInfo(questID)` 获取类型名称，并写入 `typeList`。
- 更新 `encounter_journal` 类型视图与标题逻辑，改为优先读取类型索引中的名称。
- 补充/更新相关自动化测试，覆盖运行时名称与兜底行为。

### 3.2 Out of Scope

- 不修改 `ToolboxDB.modules.encounter_journal` 的现有字段结构。
- 不为其它视图或其它模块新增新的任务类型 API。
- 不回填或维护 `Toolbox/Data/QuestTypeNames.lua` 的静态映射内容。
- 不处理静态任务线模型未覆盖的任务类型漏项问题。

## 4. 已确认决策

- `GetQuestTypeIndex()` 的 `typeList` 改为对象数组，元素结构为 `{ id = typeID, name = displayName }`。
- 任务类型名称只使用 `GetQuestTagInfo(questID)` 作为运行时来源。
- 当 `GetQuestTagInfo(questID)` 取不到可用名称时，类型名称直接回退到现有 `Unknown Type (%s)` 兜底格式。
- `typeToQuestIDs`、`typeToQuestLineIDs`、`typeToMapIDs` 继续以数字型 `typeID` 作为键，不改索引主键。
- 本次改动边界只限于 `Toolbox.Questlines` 类型索引与 `encounter_journal` 类型视图显示。

## 5. 待确认项

- 无。

## 6. 验收标准

1. `Toolbox.Questlines.GetQuestTypeIndex()` 返回的 `typeList` 为对象数组，且每个对象至少包含 `id` 与 `name`。
2. 类型视图列表与右侧标题显示的类型名称来自运行时 `GetQuestTagInfo(questID)` 结果，而不是静态映射表。
3. 当运行时取不到类型名称时，类型视图仍显示 `Unknown Type (%s)` 兜底文本，且不报错。
4. 类型视图下按类型筛选任务、地图与任务线的行为保持不变，`selectedTypeID` 仍使用数字型 `typeID`。

## 7. 实施状态

- 当前状态：已完成
- 下一步：无；实现、文档回写与测试验证已完成

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：记录运行时类型名称来源、索引结构与显示边界 |
| 2026-04-12 | 完成：按确认决策落地代码与测试，需求状态改为已完成 |
