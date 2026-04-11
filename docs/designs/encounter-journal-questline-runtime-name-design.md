# 冒险指南任务线运行时名称设计

- 文档类型：设计
- 状态：已落地
- 主题：encounter-journal-questline-runtime-name
- 适用范围：`encounter_journal` 任务页签与 `Toolbox.Questlines` 的任务线名称显示链路
- 关联模块：`encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-questline-runtime-name-spec.md`
  - `docs/designs/encounter-journal-design.md`
- 最后更新：2026-04-12

## 1. 背景

- 当前任务线显示已经优先使用运行时 API，但 `InstanceQuestlines.questLines[*].Name_lang` 仍作为结构化字段导出。
- 官方 API 能从任务上下文拿到任务线名称，但入口依赖 `questID` 或 `uiMapID`，而不是直接接收 `questLineID`。
- 因此本次设计的关键不在“是否能全量运行时化”，而在“如何移除结构化 `Name_lang` 字段，同时保留人工可读注释和运行时回退能力”。

## 2. 设计目标

- 为任务线名称提供统一显示名访问器，避免 UI 多处自行拼接逻辑。
- 把运行时 API 引入限制在 `Toolbox.Questlines`，保持模块边界清晰。
- 在运行时数据不足时稳定回退到 `QuestLine #<id>`。
- 让导出文件中的任务线名称仅以 Lua 尾注释形式保留，不再成为运行时结构化字段。

## 3. 非目标

- 不替换 `InstanceQuestlines` 的主结构块划分。
- 不把 Lua 尾注释重新解析回运行时字段。
- 不新增数据库迁移、模块设置或用户可见开关。

## 4. 方案对比

### 4.1 方案 A：保留结构化 `Name_lang` 字段

- 做法：继续在 `questLines[*]` 中导出 `Name_lang`，UI 失败时回退到该字段。
- 优点：实现简单，兼容现有静态模型。
- 风险 / 缺点：导出数据冗余，任务线名称继续占用运行时结构字段，与“仅保留稳定关系数据”的方向不一致。

### 4.2 方案 B：去掉字段，改为 Lua 尾注释，UI 回退 `QuestLine #<id>`

- 做法：契约把 `questLines[*].Name_lang` 从 `value_template` 挪到尾注释模板；运行时名称只走 API，失败时显示 `QuestLine #<id>`。
- 优点：数据结构更瘦，保留人工可读性，不需要在运行时消费注释。
- 风险 / 缺点：失去结构化静态名称字段；少数无运行时名称的任务线会显示 ID 兜底文本。

### 4.3 方案 C：去掉字段也不保留注释

- 做法：直接移除 `Name_lang`，不在生成文件中保留任何任务线名称痕迹。
- 优点：导出最精简。
- 风险 / 缺点：人工排查静态数据时可读性明显下降，不利于维护。

### 4.4 选型结论

- 选定方案：方案 B。
- 选择原因：它满足用户提出的“字段删除但注释保留”要求，同时保持运行时显示链路简单。

## 5. 选定方案

- 在 `Toolbox/Core/API/QuestlineProgress.lua` 中保留任务线显示名解析函数 `Toolbox.Questlines.GetQuestLineDisplayName(questLineID)`。
- 解析顺序如下：
  - 先读取静态模型中的任务线对象，确认 `questLineID`、`UiMapID` 和 `questIDs`。
  - 再读取该任务线的 `questIDs`，优先选择当前任务日志中仍存在的任务作为代表任务；若没有，则退回数组中的第一个任务。
  - 若客户端存在 `C_QuestLine.GetQuestLineInfo`，则使用代表任务尝试获取运行时 `questLineName`。
  - 若运行时结果为非空字符串，则返回运行时名称；否则回退 `QuestLine #<id>`。
- 对显示名结果做轻量运行时缓存，缓存键使用 `questLineID` 并跟随当前运行时秒级缓存键失效，避免在 UI 渲染循环中重复调 API。
- 在 `DataContracts/instance_questlines.json` 中，把 `questLines` 块的 `Name_lang` 从 `value_template` 移到 `comment_template`，并提升契约 `schema_version`。
- 在 `WoWTools` 导出器里，为 `document` 的 `map_object` 块增加尾注释模板输出能力，生成形如 `-- Name_lang = "..."` 的行尾注释。
- `EncounterJournal` 中所有直接消费 `questLineEntry.name` 的显示位置，改为调用统一访问器或先由模型层提供 `displayName`。

## 6. 影响面

- 数据与存档：
  不新增 `ToolboxDB` 键；`InstanceQuestlines.questLines[*]` 去掉 `Name_lang` 结构化字段。
- API 与模块边界：
  `Toolbox.Questlines` 新增任务线显示名访问器；`EncounterJournal` 只消费结果，不直接碰 `C_QuestLine`。
- 文件与目录：
  主要修改 `DataContracts/instance_questlines.json`、`../WoWTools/scripts/export/lua_contract_writer.py`、`../WoWTools/scripts/export/toolbox_db_export.py`、`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Modules/EncounterJournal.lua` 和相关测试。
- 文档回写：
  落地后需要补充 `docs/designs/encounter-journal-design.md` 与 `docs/Toolbox-addon-design.md` 中“任务线名称来源”的说明。

## 7. 风险与回退

- 风险：
  某些任务线无法通过代表任务稳定拿到运行时名称，导致部分任务线显示 `QuestLine #<id>`。
- 风险：
  若导出器尾注释模板实现不完整，可能影响其它 document 契约块的写出格式。
- 回退或缓解方式：
  运行时 API 封装在统一访问器里；若发现兼容性问题，可在访问器内继续回退到 `QuestLine #<id>`。若导出格式需要回滚，可恢复 `Name_lang` 到 `value_template`。

## 8. 验证策略

- 自动化：
  补充导出器单测与逻辑测试，分别验证“尾注释输出”和“`QuestLine #<id>` 回退”路径。
- 游戏内：
  打开冒险指南任务页签，确认地图树、状态视图右侧标题等显示一致，且无空名称。
- 代码边界：
  确认 `EncounterJournal` 中不新增对 `C_QuestLine` 的直接调用。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：确认采用运行时 API 优先、静态名称兜底的任务线显示方案 |
| 2026-04-12 | 设计落地：`Toolbox.Questlines` 新增任务线显示名访问器，任务页签显示点切到统一访问器 |
| 2026-04-12 | 调整：`questLines[*].Name_lang` 改为 Lua 尾注释，运行时回退改为 `QuestLine #<id>` |
