# 冒险指南任务线运行时名称需求规格

- 文档类型：需求
- 状态：已完成
- 主题：encounter-journal-questline-runtime-name
- 适用范围：`encounter_journal` 任务页签中的任务线名称显示
- 关联模块：`encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-questline-runtime-name-design.md`
  - `docs/plans/encounter-journal-questline-runtime-name-plan.md`
  - `docs/designs/encounter-journal-design.md`
- 最后更新：2026-04-12

## 1. 背景

- 当前任务页签中的任务线名称已经改为优先使用运行时 API，但 `InstanceQuestlines` 仍把 `questLines[*].Name_lang` 作为结构化字段导出。
- 用户要求进一步收紧导出结构：生成文件中不再保留 `Name_lang` 字段，只保留同名 Lua 尾注释供人工查看。
- 现有官方 API 可以通过任务上下文拿到任务线名称，但并不存在稳定的“仅凭 `questLineID` 直接取名称”的单一入口，因此需要确定主方案与回退边界。

## 2. 目标

- 让任务页签中的任务线名称优先使用运行时 API 结果显示。
- 在运行时 API 不可用或无法解析时，稳定回退到 `QuestLine #<id>`，不影响现有功能可用性。
- 让 `InstanceQuestlines.lua` 的 `questLines` 块只保留 `ID` / `UiMapID` 字段，并把 `Name_lang` 改为 Lua 尾注释。
- 保持当前模块边界不变，由 `Toolbox.Questlines` 负责名称解析，`EncounterJournal` 只消费显示结果。

## 3. 范围

### 3.1 In Scope

- 为任务线名称增加运行时显示名解析逻辑。
- 调整 `instance_questlines` 契约与导出器，让 `questLines` 块输出尾注释而不是 `Name_lang` 字段。
- 在任务页签左侧树、右侧标题和相关列表中改为统一使用任务线显示名访问器。
- 为新行为补充逻辑测试，覆盖 API 成功与 `QuestLine #<id>` 回退两条路径。

### 3.2 Out of Scope

- 不把运行时解析结果写回静态数据文件、`SavedVariables` 或其它持久化缓存。
- 不顺带改动任务名、地图名、阵营或职业限制等其它字段来源。

## 4. 已确认决策

- 主方案采用“运行时 API 优先、`QuestLine #<id>` 兜底”的显示模式。
- `instance_questlines` 契约中的 `questLines` 块不再导出 `Name_lang` 字段，只保留同名 Lua 尾注释。
- 运行时任务线名称解析放在 `Toolbox.Questlines`，不在 `EncounterJournal` 模块内直接调用 `C_QuestLine`。
- 运行时名称只用于 UI 显示，不回写 `Toolbox.Data.InstanceQuestlines`、不新增存档键。
- 任务线名称解析允许通过任务线下的代表任务推导，不要求存在“`questLineID -> 名称`”的直接 API。
- 当运行时 API 缺失、返回空值、或当前任务线上没有可用代表任务时，UI 必须回退为 `QuestLine #<id>`，不能出现空文本。

## 5. 待确认项

- 无。用户已明确“开动”，并按推荐方案进入实现。

## 6. 验收标准

1. 当运行时 API 能返回任务线名称时，任务页签中的任务线显示文本使用运行时名称。
2. 当运行时 API 不可用、返回空值或当前任务线没有可用代表任务时，任务页签回退显示 `QuestLine #<id>`，界面不报错。
3. `Toolbox/Data/InstanceQuestlines.lua` 的 `questLines` 块中不再存在 `Name_lang` 字段，只保留 `-- Name_lang = "..."` 尾注释。
4. 左侧树中的地图下任务线行、状态视图右侧标题、以及其它复用任务线名称的任务页签区域，显示结果保持一致。
5. 新逻辑不新增 `ToolboxDB` 键，并通过契约驱动脚本实跑导出。

## 7. 实施状态

- 当前状态：已完成
- 下一步：后续若扩展到更多任务线名称来源或更多客户端分支，在对应需求文档中继续增量记录。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：确认采用运行时 API 优先、静态名称兜底的任务线显示方案，并进入可执行状态 |
| 2026-04-12 | 实现完成：任务页签任务线名称改为运行时 API 优先、静态名称兜底 |
| 2026-04-12 | 调整：`questLines[*].Name_lang` 改为 Lua 尾注释，运行时回退改为 `QuestLine #<id>` |
