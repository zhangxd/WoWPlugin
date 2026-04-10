# 2026-04-10 冒险手册任务页签多视图实现计划（合规版）

- 日期：2026-04-10
- 关联模块：`encounter_journal`
- 状态：可执行

## 0. 前置确认（已完成）

本计划基于以下已确认结论执行，不再二次分叉：

1. 需求方已明确回复「开动」。
2. `InstanceQuestlines` 保持 `schemaVersion = 3`（不升级到 4）。
3. `InstanceQuestlines` 当前已是 `DataContracts/instance_questlines.json -> Toolbox/Data/InstanceQuestlines.lua` 的契约导出链路；本次在该链路内扩字段，不再以“未自动导出”为前提。
4. 对应确认结果已写入需求文档：  
   `docs/superpowers/specs/2026-04-10-ej-quest-ui-alignment-design.md`

---

## 1. 合规边界（执行时强制）

1. 仅在已有模块 `encounter_journal` 范围内实现，不新增 `RegisterModule`。
2. 业务代码改动前，先确保需求文档确认结果已落地（本计划已满足）。
3. 玩家可见字符串统一走 `Toolbox/Core/Foundation/Locales.lua`，业务逻辑不硬编码文案。
4. 持久化只写 `ToolboxDB.modules.encounter_journal`，并在 `Core/Config.lua` 声明默认值与迁移。
5. UI 挂接仅使用 `OnShow` / `hooksecurefunc` / 正式事件路径，不以固定延迟作为主路径。
6. 未实际用过或不确定的 WoW API，先查证再实现（暴雪文档 / FrameXML / Warcraft Wiki）。
7. 本次不改变导出入口形态；若扩展 `InstanceQuestlines` 字段，必须改契约并重新导出，禁止手改生成文件。

---

## 2. 目标与范围

### 2.1 目标

在冒险手册任务页签实现三视图：

1. 状态视图（默认）
2. 类型视图（树形/列表）
3. 地图视图

并实现：

1. 统一选择状态（跨视图保持、无法落点时降级）
2. 类型索引与类型展示名映射
3. 视图/选择状态持久化
4. 三视图共享详情区行为一致

### 2.2 非目标

1. 不在本次实现地图导航 / NPC 导航 / 高亮能力（仅占位）。
2. 不改变 `InstanceQuestlines` 当前“契约驱动 + wow.db 导出”的链路形态，只在该链路内补字段。
3. 不新增外部插件联动。

---

## 3. 文件改动清单

### 3.1 新增

1. `Toolbox/Data/QuestTypeNames.lua`

### 3.2 修改

1. `DataContracts/instance_questlines.json`
2. `Toolbox/Data/InstanceQuestlines.lua`（通过导出脚本生成）
3. `Toolbox/Toolbox.toc`
4. `Toolbox/Core/API/QuestlineProgress.lua`
5. `Toolbox/Core/Foundation/Locales.lua`
6. `Toolbox/Core/Foundation/Config.lua`
7. `Toolbox/Modules/EncounterJournal.lua`
8. `tests/logic/fixtures/InstanceQuestlines_Mock.lua`
9. `tests/logic/spec/questline_progress_spec.lua`
10. `tests/logic/spec/questline_progress_live_data_spec.lua`
11. `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
12. `docs/Toolbox-addon-design.md`

---

## 4. 分阶段执行（TDD）

## 阶段 A：数据契约与领域 API（Questlines）

### 任务 A1：先补失败测试（扩展字段 + 类型索引）

- [ ] 在 `questline_progress_spec.lua` 增加以下断言并先跑失败：
1. `ValidateInstanceQuestlinesData()` 允许 `schemaVersion = 3` 下出现 `Type/MapPos/NpcIDs/NpcPos` 可选字段。
2. `GetQuestTypeLabel(typeId)`：有映射返回本地化文案；无映射返回 `EJ_QUEST_TYPE_UNKNOWN_FMT`。
3. `GetQuestTabModel()`：包含 `typeList`、`typeToQuestIDs`、`typeToQuestLineIDs`、`typeToMapIDs`。
4. `typeList` 按数值升序。

- [ ] 运行：  
`busted tests/logic/spec/questline_progress_spec.lua`  
期望：先失败（红灯）。

### 任务 A2：对齐 `instance_questlines` 契约与导出产物

- [ ] 修改 `DataContracts/instance_questlines.json`：
1. 保持 Lua 运行时 `schemaVersion = 3`。
2. 为 `quests` block 增加 `Type/MapPos/NpcIDs/NpcPos` 的结构定义。
3. 明确导出字段变化对应 `contract.schema_version` 递增，而不是升级运行时 `schemaVersion`。

- [ ] 使用现有导出入口重新生成 `Toolbox/Data/InstanceQuestlines.lua`，不手改生成文件。

- [ ] 运行：  
`python ..\\WoWTools\\scripts\\export\\export_toolbox_one.py instance_questlines --db ..\\WoWTools\\data\\sqlite\\wow.db --contract-dir .\\DataContracts --data-dir .\\Toolbox\\Data`  
期望：成功生成更新后的 `Toolbox/Data/InstanceQuestlines.lua`。

### 任务 A3：落地类型映射表与本地化键

- [ ] 新增 `Toolbox/Data/QuestTypeNames.lua`（使用 Data 模板 B 头注释，`manual` 来源）。
- [ ] 在 `Locales.lua` 增加：
1. `EJ_QUEST_TYPE_UNKNOWN_FMT`
2. 类型映射相关键（`enUS`/`zhCN` 同步）
- [ ] 在 `Toolbox.toc` 注册 `Data/QuestTypeNames.lua`（保证加载顺序正确）。

### 任务 A4：实现 QuestlineProgress 类型能力（保持 v3 兼容）

- [ ] 在 `QuestlineProgress.lua` 实现：
1. `GetQuestTypeLabel(typeId)`（映射 -> `Toolbox.L` -> 兜底格式化）。
2. 构建 `typeList/typeToQuestIDs/typeToQuestLineIDs/typeToMapIDs`。
3. `schemaVersion = 3` 下将 `Type/MapPos/NpcIDs/NpcPos` 作为可选字段透传到运行时 `QuestEntry`。
4. `Type` 缺失时跳过类型桶，不造伪类型；地图解析失败时交给 UI 落到“其他”分组。

- [ ] 为新增对外函数补 `---`/`@param`/`@return` 注释。

- [ ] 运行：
1. `busted tests/logic/spec/questline_progress_spec.lua`
2. `busted tests/logic/spec/questline_progress_live_data_spec.lua`
期望：通过（绿灯）。

## 阶段 B：存档键与迁移

### 任务 B1：配置默认值与迁移

- [ ] 在 `Core/Config.lua` 的 `encounter_journal` defaults 增加：
1. `questViewMode`
2. `questViewSelectedMapID`
3. `questViewSelectedTypeID`
4. `questViewSelectedQuestLineID`
5. `questViewSelectedQuestID`

- [ ] 补幂等迁移逻辑（重复执行不改变结果）。

- [ ] 运行：  
`busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`  
期望：通过。

## 阶段 C：任务页签多视图 UI

### 任务 C1：统一选择状态与视图切换器

- [ ] 在 `Modules/EncounterJournal.lua` 增加统一 `SelectionState`：
1. `selectedView`
2. `selectedKind`
3. `selectedTypeID/selectedMapID/selectedQuestLineID/selectedQuestID`

- [ ] 视图切换写回 `questViewMode`，并在进入任务页签时恢复状态。
- [ ] 不可落点时执行降级：回退目标视图默认节点。

### 任务 C2：状态视图

- [ ] 默认进入状态视图。
- [ ] 左侧保留地图树过滤（地图 -> 任务线 -> 任务）。
- [ ] 主区渲染三列泳道：`可交付 / 进行中 / 待解锁`。
- [ ] 默认选中当前地图；点击卡片同步详情区。

### 任务 C3：类型视图（树形/列表）

- [ ] 顶层按 `typeList` 构建类型桶，按原始数值排序。
- [ ] 树形层级：
1. 有地图：`类型 -> 地图 -> 任务线 -> 任务`
2. 无地图：`类型 -> 任务线 -> 任务`（归入“其他”分组）
- [ ] 列表模式复用当前地图过滤；若为“其他”分组，仅展示该分组任务。

### 任务 C4：地图视图

- [ ] 左侧地图树与主区联动。
- [ ] 默认选中上次记忆地图；无则首个可用地图。

### 任务 C5：共享详情区

- [ ] 三视图统一详情区行为：
1. 任务详情
2. 任务线详情
3. 地图详情

- [ ] 操作区保留导航/高亮占位，不实现真实跳转。

### 任务 C6：UI 生命周期与安全约束

- [ ] 创建与刷新时机绑定 `OnShow` / `hooksecurefunc`，避免固定秒延迟。
- [ ] 与受保护框体交互路径遵守战斗锁定约束（必要时排队到 `PLAYER_REGEN_ENABLED`）。

---

## 5. 验收映射（与需求稿对齐）

- [ ] 默认进入状态视图，默认当前地图。
- [ ] 三视图切换保持同一选择状态，无法落点时正确降级。
- [ ] 类型桶覆盖数据中全部类型，排序正确。
- [ ] 类型视图无地图分组跳层正确。
- [ ] 详情区在三视图行为一致。
- [ ] 状态视图左树过滤能正确限制泳道内容。
- [ ] 不引入固定延迟等待布局。
- [ ] 类型列表模式按“当前地图/其他分组”过滤正确。

---

## 6. 验证命令（完成前必须实跑）

1. `busted tests/logic/spec/questline_progress_spec.lua`
2. `busted tests/logic/spec/questline_progress_live_data_spec.lua`
3. `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
4. `python tests/validate_settings_subcategories.py`
5. `python tests/run_all.py`

若某命令在本地环境不可执行，需在交付说明中明确未执行项与原因。

---

## 7. 提交策略（中文）

建议按“测试先行 -> 实现 -> 收口文档”提交：

1. `测试:` 扩展字段与类型索引失败用例
2. `数据:` InstanceQuestlines 契约与导出产物对齐
3. `数据:` QuestTypeNames 与 Locales/TOC 接入
4. `功能:` QuestlineProgress 类型索引与扩展字段透传
5. `配置:` encounter_journal 新持久化键与迁移
6. `功能:` EncounterJournal 三视图与统一选择状态
7. `文档:` 总设计映射与说明更新

---

## 8. 完成定义（DoD）

1. 第 6 节验证命令通过（或明确未执行原因）。
2. 与 `2026-04-10-ej-quest-ui-alignment-design.md` 的确认项一致，无“待确认项”残留。
3. 代码改动遵守 AGENTS 三关、UI 挂接时机、存档边界与本地化规则。
