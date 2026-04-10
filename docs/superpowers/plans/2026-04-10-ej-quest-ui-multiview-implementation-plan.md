# 2026-04-10 冒险手册任务页签多视图实现计划（合规版）

- 日期：2026-04-10
- 关联模块：`encounter_journal`
- 状态：可执行

## 0. 前置确认（已完成）

本计划基于以下已确认结论执行，不再二次分叉：

1. 需求方已明确回复「开动」。
2. `InstanceQuestlines` 当前已是 `DataContracts/instance_questlines.json -> Toolbox/Data/InstanceQuestlines.lua` 的契约导出链路。
3. 静态 Lua 结构优先贴近 DB 关系结构；动态字段由 `Toolbox.Questlines` 在运行时补齐并组装为统一 UI 模型。
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
7. 允许在现有导出链路内扩展导出器能力，但必须保持其为**通用嵌套文档渲染器**，禁止写领域特判。
8. `Type` 属于运行时字段，必须通过 `C_QuestLog.GetQuestType(questID)` 获取，禁止写入静态导出结构。
9. `静态数据 + 动态数据 -> UI 数据` 的组装职责固定放在 `Toolbox.Questlines`，UI 模块禁止自行拼装底层 quest 数据。
10. 凡当前无法稳定静态导出的字段，一律转入运行时字段层，不得以“弱静态字段”名义继续进入主导出结构。

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

### 2.1.1 硬规则

1. 任何依赖运行时 API 才能稳定获取的字段，都不得进入 `Toolbox.Data.InstanceQuestlines` 静态导出结构。
2. `Type` 是本次明确的运行时字段，只能在内存中获取与缓存。
3. `NpcIDs / NpcPos` 在当前阶段也视为运行时字段，直到出现稳定静态来源前不得进入主导出结构。
4. UI 统一消费 `Toolbox.Questlines` 组装好的模型，禁止在 `EncounterJournal.lua` 内自行把静态数据和动态数据再拼一遍。

### 2.2 非目标

1. 不在本次实现地图导航 / NPC 导航 / 高亮能力（仅占位）。
2. 不把导出器改造成 EJ 专用拼装器；新增能力必须可复用到其他 DB 导出。
3. 不新增外部插件联动。

---

## 3. 文件改动清单

### 3.1 新增

1. `Toolbox/Data/QuestTypeNames.lua`

### 3.2 修改

1. `DataContracts/instance_questlines.json`
2. `../WoWTools/scripts/export/contract_model.py`
3. `../WoWTools/scripts/export/toolbox_db_export.py`
4. `../WoWTools/scripts/export/lua_contract_writer.py`
5. `../WoWTools/scripts/export/tests/test_lua_contract_writer.py`
6. `Toolbox/Data/InstanceQuestlines.lua`（通过导出脚本生成）
7. `Toolbox/Toolbox.toc`
8. `Toolbox/Core/API/QuestlineProgress.lua`
9. `Toolbox/Core/Foundation/Locales.lua`
10. `Toolbox/Core/Foundation/Config.lua`
11. `Toolbox/Modules/EncounterJournal.lua`
12. `tests/logic/fixtures/InstanceQuestlines_Mock.lua`
13. `tests/logic/spec/questline_progress_spec.lua`
14. `tests/logic/spec/questline_progress_live_data_spec.lua`
15. `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
16. `docs/Toolbox-addon-design.md`

---

## 4. 分阶段执行（TDD）

## 阶段 A：数据契约与领域 API（Questlines）

### 任务 A1：先补失败测试（扩展字段 + 类型索引）

- [ ] 在 `questline_progress_spec.lua` 增加以下断言并先跑失败：
1. `ValidateInstanceQuestlinesData()` 不要求静态结构包含 `Type`，且仍接受 DB-shape 的静态字段。
2. `GetQuestRuntimeState(questID)` 或等价运行时接口能够返回 `typeID`。
3. `GetQuestTypeLabel(typeId)`：有映射返回本地化文案；无映射返回 `EJ_QUEST_TYPE_UNKNOWN_FMT`。
4. `GetQuestTabModel()`：在“静态记录 + 动态 type”合并后包含 `typeList`、`typeToQuestIDs`、`typeToQuestLineIDs`、`typeToMapIDs`。
5. `typeList` 按数值升序。

- [ ] 运行：  
`busted tests/logic/spec/questline_progress_spec.lua`  
期望：先失败（红灯）。

### 任务 A2：先补导出器能力（通用嵌套文档，不写领域特判）

- [ ] 在 `WoWTools/scripts/export/**` 扩展以下通用能力：
1. `source` 支持多 dataset，而不是仅单条 SQL。
2. `structure` 支持递归 `children` 与 `match_on`。
3. block 类型最小增量支持 `object_optional` / 嵌套 `map_object` / 嵌套 `array_objects`。
4. 校验拆为 dataset 字段校验 + 结构装配校验。

- [ ] 为导出器新增针对 document nesting 的单元测试，先红后绿。

- [ ] 运行：
1. `python ..\\WoWTools\\scripts\\export\\tests\\test_lua_contract_writer.py`
2. `python tests/run_all.py`
期望：导出器测试通过，现有契约导出不回归。

### 任务 A3：对齐 `instance_questlines` 契约与导出产物

- [ ] 修改 `DataContracts/instance_questlines.json`：
1. 将契约改为多 dataset 驱动，而不是单 SQL 大拼表。
2. 静态导出层优先贴近 DB 关系结构，只输出 `questLineXQuest`、`questPOIBlobs`、`questPOIPoints` 等稳定关系块。
3. `Type` 不进入静态导出结构。
4. `NpcIDs/NpcPos` 不进入静态导出结构。
5. 导出字段变化对应 `contract.schema_version` 递增。

- [ ] 使用现有导出入口重新生成 `Toolbox/Data/InstanceQuestlines.lua`，不手改生成文件。

- [ ] 运行：  
`python ..\\WoWTools\\scripts\\export\\export_toolbox_one.py instance_questlines --db ..\\WoWTools\\data\\sqlite\\wow.db --contract-dir .\\DataContracts --data-dir .\\Toolbox\\Data`  
期望：成功生成更新后的 `Toolbox/Data/InstanceQuestlines.lua`。

### 任务 A4：落地类型映射表与本地化键

- [ ] 新增 `Toolbox/Data/QuestTypeNames.lua`（使用 Data 模板 B 头注释，`manual` 来源）。
- [ ] 在 `Locales.lua` 增加：
1. `EJ_QUEST_TYPE_UNKNOWN_FMT`
2. 类型映射相关键（`enUS`/`zhCN` 同步）
- [ ] 在 `Toolbox.toc` 注册 `Data/QuestTypeNames.lua`（保证加载顺序正确）。

### 任务 A5：实现 QuestlineProgress 运行时 inflate 与类型能力

- [ ] 在 `QuestlineProgress.lua` 实现：
1. `GetQuestTypeLabel(typeId)`（映射 -> `Toolbox.L` -> 兜底格式化）。
2. 底层领域层统一提供“静态记录读取”“动态字段获取”“统一模型组装”三段职责。
3. `Type` 通过 `C_QuestLog.GetQuestType(questID)` 在运行时获取，并合并进统一 `QuestEntry`。
4. 从 DB-shape 静态块 inflate 出 `quest.MapPos` 等稳定 UI convenience 字段。
5. `NpcIDs / NpcPos` 作为运行时字段挂入统一模型；在暂无稳定来源时允许缺失。
6. 构建 `typeList/typeToQuestIDs/typeToQuestLineIDs/typeToMapIDs`。
7. `Type` 缺失时跳过类型桶，不造伪类型；地图解析失败时交给 UI 落到“其他”分组。

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
2. `工具:` 导出器嵌套文档能力与测试
3. `数据:` InstanceQuestlines 契约与导出产物对齐
4. `数据:` QuestTypeNames 与 Locales/TOC 接入
5. `功能:` QuestlineProgress inflate 与类型索引
6. `配置:` encounter_journal 新持久化键与迁移
7. `功能:` EncounterJournal 三视图与统一选择状态
8. `文档:` 总设计映射与说明更新

---

## 8. 完成定义（DoD）

1. 第 6 节验证命令通过（或明确未执行原因）。
2. 与 `2026-04-10-ej-quest-ui-alignment-design.md` 的确认项一致，无“待确认项”残留。
3. 代码改动遵守 AGENTS 三关、UI 挂接时机、存档边界与本地化规则。
