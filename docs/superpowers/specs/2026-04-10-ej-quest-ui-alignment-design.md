# 冒险手册任务页签多视图 UI 设计稿（状态 / 类型 / 地图）

- 日期：2026-04-10
- 状态：已按当前仓库数据链路复核（待实现）
- 关联模块：`encounter_journal`
- 范围：`Toolbox`（Retail）

---

## 1. 背景与目标

为冒险手册任务页签引入**多视图切换**（状态 / 类型 / 地图），并在后续扩展（地图导航 / NPC 导航 / 位置高亮）前，先对齐 UI 信息架构与数据契约。

本设计的目标是：

1. 单一数据模型，多视图渲染，避免能力重复开发。
2. 默认以**状态视图**进入，聚焦“当前要做什么”。
3. 引入任务类型维度（WoWDB 导出），支持“按类型”组织。
4. 先定义结构与契约，数据稍后导出填充。

---

## 2. 已确认的关键决策

1. 视图切换：`状态 / 类型 / 地图`
2. 默认进入：状态视图
3. 类型标签：WoWDB 全量导出
4. 类型枚举：使用 WoWDB 原字段原值（不做归一化）
5. 类型桶：自动列出 WoWDB 出现过的所有类型（不做聚合）
6. 类型桶排序：按 WoWDB 原始类型值排序
7. 类型视图层级：有地图则 `类型→地图→任务线→任务`，无地图则 `类型→任务线→任务`
8. 状态视图左侧保留“地图树”过滤
9. 状态视图默认选中“当前角色所在地图”

---

## 3. 静态数据结构（契约导出 + 运行时载荷）

> 当前仓库已存在 `instance_questlines` 契约导出链路；本节先对齐“真实数据来源”和“后续扩展字段边界”。

### 3.0 数据来源与版本语义（已对齐）

当前权威链路为：

`wow.db` -> `DataContracts/instance_questlines.json` -> `Toolbox/Data/InstanceQuestlines.lua` -> `Toolbox.Questlines`

这里存在两个版本号，语义必须分开：

- `DataContracts/instance_questlines.json` 中的 `contract.schema_version`：表示导出契约版本；只要导出字段或文件结构变化，就应升级。
- `Toolbox.Data.InstanceQuestlines.schemaVersion`：表示 Lua 运行时载荷版本；当前继续保持 `3`，只要 `quests/questLines/questLineQuestIDs` 基线不破坏即可不升级。

因此，本次对齐的原则是：

- 保持运行时 `schemaVersion = 3`。
- 在 `schemaVersion = 3` 下允许增加**可选扩展字段**。
- 若导出契约新增字段，升级 **contract schema**，但不以此强制升级运行时 `schemaVersion`。

### 3.1 Lua 载荷结构（目标形态）

```lua
Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 3,
  sourceMode = "live",
  generatedAt = "2026-..",

  quests = {
    [questID] = {
      ID = questID,
      UiMapID = 123,
      Type = 12,
      MapPos = { x = 0.52, y = 0.31, UiMapID = 123 },
      NpcIDs = { 1001, 2002 },
      NpcPos = {
        [1001] = { x = 0.41, y = 0.63, UiMapID = 123 },
        [2002] = { x = 0.55, y = 0.22 },
      },
    },
  },

  questLines = {
    [questLineID] = {
      ID = questLineID,
      Name_lang = "Questline Name",
      UiMapID = 123,
    },
  },

  questLineQuestIDs = {
    [questLineID] = { questID1, questID2, ... },
  },
}
```

说明：

- `UiMapID` 表示任务在任务页签中的**归属地图**；它是分组字段，不等于精确导航点。
- `Type` 直接使用 WoWDB 原始枚举值（number），不做归一化。
- `MapPos/NpcPos` 的 `UiMapID` 可省略；省略时默认继承 `quests[questID].UiMapID`。
- `NpcPos` 允许只给部分 NPC 坐标；不要求和 `NpcIDs` 一一完整对应。

### 3.2 必要字段基线（v3 兼容基线）

当前运行时 strict 校验和 live 数据已依赖的**最小必填**仍是：

- `quests[questID]`：`ID`、`UiMapID`
- `questLines[questLineID]`：`ID`、`Name_lang`、`UiMapID`
- `questLineQuestIDs`

在这条基线下：

- 现有 `QuestlineProgress.ValidateInstanceQuestlinesData()` 无需因新增 UI 需求而升级到 `schemaVersion = 4`。
- 新增视图相关字段一律按**可选扩展字段**处理。
- live 数据未补齐扩展字段前，现有地图树视图仍可继续工作。

### 3.3 可选扩展字段（多视图实现所需）

多视图实现阶段新增但保持可选的字段如下：

- `quests[questID].Type`
  作用：类型视图的唯一权威来源；缺失时该任务不进入任何类型桶。
- `quests[questID].MapPos`
  作用：地图导航/位置高亮的任务点位；缺失时仅保留地图分组，不显示精确位置。
- `quests[questID].NpcIDs`
  作用：NPC 导航候选集合；允许为空或缺失。
- `quests[questID].NpcPos`
  作用：按 `NpcID` 提供 NPC 点位；允许稀疏。

补充约束：

- 类型视图的上线门槛是导出至少补齐 `Type`。
- `questLines` 继续保持最小元数据，不额外复制 `Type`、`NpcIDs` 等任务级字段，避免双重权威源。
- “其他”分组属于 UI 运行时合成节点，不写回静态数据。

类型名称通过**本地映射表**展示，不直接显示数字。
映射表位置：`Toolbox/Data/QuestTypeNames.lua`（手工维护，独立于数据库生成文件）。
映射表建议存 `TypeID -> LocaleKey`，实际显示通过 `Toolbox.L[LocaleKey]` 获取；缺失映射时使用 `Toolbox.L.EJ_QUEST_TYPE_UNKNOWN_FMT` 兜底并显示原始数值。

### 3.4 导出实现约束

- `Toolbox/Data/InstanceQuestlines.lua` 是**生成产物**，不作为手工长期维护文件。
- 对齐字段时，应修改 `DataContracts/instance_questlines.json` 并通过导出脚本重新生成数据文件，而不是直接手改生成文件。
- 若仅新增 `Type/MapPos/NpcIDs/NpcPos` 这类可选字段，运行时 `schemaVersion` 继续保持 `3`；但 `contract.schema_version` 应按契约治理递增。

### 3.5 UI 字段来源与兜底（实现前需按 AGENTS 查证 API）

| UI 字段 | 主要来源 | 兜底 |
|---|---|---|
| 任务名 | `C_QuestLog.GetTitleForQuestID` | `QuestUtils_GetQuestName` |
| 地图名 | `C_Map.GetMapInfo(UiMapID).name` | `Map #<id>` |
| 任务状态 | `IsQuestFlaggedCompleted` + `GetLogIndexForQuestID` | 无 |
| 可交付 | `C_QuestLog.ReadyForTurnIn` | 无 |

> 注：以上 API 需在实现前按权威资料查证并核对参数/返回值。

---

## 4. 运行时模型（Questlines Model）

在 `Toolbox.Questlines.GetQuestTabModel()` 现有结构上，运行时统一归一到以下对象层级：

```lua
QuestEntry = {
  id = questID,
  name = "Quest Name",
  status = "completed" | "active" | "pending",
  UiMapID = 123,
  typeID = 12,
  mapPos = { x = 0.52, y = 0.31, UiMapID = 123 },
  npcIDs = { 1001, 2002 },
  npcPos = { [1001] = { x = 0.41, y = 0.63, UiMapID = 123 } },
  quest = questRecord,
}

QuestLineEntry = {
  id = questLineID,
  name = "Questline Name",
  UiMapID = 123,
  quests = { questEntry1, questEntry2, ... },
  progress = { completed, total, hasActive, nextQuestID, nextQuestName, isCompleted },
  typeIDs = { 12, 34, ... },
}

QuestTabModel = {
  maps = { { id, name, questLines, progress }, ... },
  mapByID = { [mapID] = mapEntry },

  questLineByID = { [questLineID] = questLineEntry },
  questToQuestLineID = { [questID] = questLineID },

  typeList = { 12, 34, ... },
  typeToQuestIDs = { [typeId] = { questID1, questID2, ... } },
 typeToQuestLineIDs = { [typeId] = { questLineID1, questLineID2, ... } },
  typeToMapIDs = { [typeId] = { mapID1, mapID2, ... } },
}
```

规则：

- `QuestEntry.quest` 保留原始静态记录，新增运行时便利字段走扁平属性（`typeID/mapPos/npcIDs/npcPos`）。
- `typeList` 仅从 `Type` 为 number 的任务中去重生成，并按数值升序。
- 同一任务线可因子任务分布而出现在多个类型桶，`QuestLineEntry.typeIDs` 由子任务聚合得到。
- `typeToMapIDs` 取自任务或任务线最终可解析出的地图集合；解析失败时由 UI 放入“其他”分组，不在静态数据中造假地图。
- 运行时索引统一由领域 API 构建与缓存（`Toolbox.Questlines`），UI 只消费模型，不直接拼索引。

---

## 5. 视图协议与选择状态

### 5.1 统一选择状态

```lua
SelectionState = {
  selectedView = "status" | "type" | "map",
  selectedKind = "type" | "map" | "questline" | "quest",
  selectedTypeID = 12,
  selectedMapID = 123,
  selectedQuestLineID = 456,
  selectedQuestID = 789,
}
```

不变量与降级规则：

- `selectedKind = "type"` 时仅要求 `selectedTypeID` 有效，其它选中字段可空。
- `selectedKind = "map"` 时要求 `selectedMapID` 有效。
- 切换视图时，若当前 `selectedKind` 在目标视图不可落点，则降级到目标视图默认节点。
- 目标视图无法解析 `selectedMapID` 时，回退到“默认地图”。

### 5.2 视图协议

每个视图必须实现：

- `buildLeftFilter()`：左侧过滤区（状态/地图视图为地图树，类型视图为空）
- `buildMainList()`：主区列表或泳道
- `defaultSelection()`：默认选中节点
- `onSelectionChange()`：更新主区与详情区

---

## 6. 三视图 UI 结构

### 6.1 状态视图（默认）

- 左侧：地图树过滤（地图→任务线→任务）
- 默认选中：当前角色所在地图
- 主区：三列泳道 `可交付 / 进行中 / 待解锁`
- 任务卡片：任务名 / 任务线名 / 地图名 / 状态标记
- 点击卡片：选中 `quest`，同步详情区

### 6.2 类型视图

顶层类型桶来自 `typeList`，主区层级：

- 有地图：`类型→地图→任务线→任务`
- 无地图：`类型→任务线→任务`

无地图分组规则：

- 任务与任务线无法解析地图时，归入“其他”分组。

列表模式（已确认）：

- 类型视图提供“树形 / 列表”切换。
- 列表模式**保留地图层级过滤**：仅列出当前选中地图下的任务。
- 列表模式复用树形模式的“当前选中地图”作为过滤来源。
- 若当前类型不存在地图层级（或选中“其他”分组），列表仅展示该分组下任务。

### 6.3 地图视图

- 左侧：地图树（地图→任务线→任务）
- 主区：随左树选中显示任务线列表或任务列表
- 默认选中：上次记忆的地图节点；无则第一个可用地图

---

## 7. 详情区与操作区

三视图共享统一详情区：

- 任务详情：名称 / 状态 / 任务线 / 地图
- 任务线详情：名称 / 进度摘要 / 任务列表
- 地图详情：名称 / 进度摘要 / 任务线列表
- 操作区：地图导航 / NPC 导航 / 高亮入口（本次仅占位）

---

## 8. 状态口径（默认）

本设计采用以下默认口径：

- 可交付：`ReadyForTurnIn == true`
- 进行中：`Active` 且不可交付
- 待解锁：`pending`（未完成且不在任务日志）

若后续需调整口径，可在实现前最终确认。

> 说明：`pending` 不区分“前置未达成/等级不足/剧情未解锁”等细分原因，属于粗口径；若需精确分类需补充数据源。

---

## 9. 持久化与存档

新增视图与选择记忆需在 `ToolboxDB.modules.encounter_journal` 中持久化，建议键：

- `questViewMode`（`status` / `type` / `map`）
- `questViewSelectedMapID`
- `questViewSelectedTypeID`
- `questViewSelectedQuestLineID`
- `questViewSelectedQuestID`

落库前需在 `Core/Config.lua` defaults 中声明，并提供迁移逻辑。

---

## 10. 内存与体量评估（基于当前导出规模）

当前导出规模：约 16,984 任务 / 1,563 任务线。

在“平均 2 个 NPC/任务”的假设下：

- 数据文件体积估计约 **3.7 MB**
- 运行时内存预计为文件体积的 **2–4 倍**（约 **7–15 MB**）
- “按类型列表/索引”额外开销约 **0.5–1.0 MB**

---

## 11. 新入口门禁与 UI 挂接约束

1. 视图切换属于新玩家可见入口，实现阶段触发 AGENTS 关 3，需先完成方案评估并获得“开动”确认。
2. UI 挂接必须遵循 `OnShow`/`hooksecurefunc` 等正式路径，禁止以固定延迟作为唯一时机（见 AGENTS.md「暴雪 UI 挂接时机」）。

---

## 12. 非目标

1. 不在本次设计中落实实际 UI 代码。
2. 不在本次设计中实现导航/高亮能力。
3. 不包含外部任务插件联动。

---

## 13. 验收要点

1. 进入任务页签默认进入**状态视图**，并默认选中当前地图。
2. 三视图切换保持同一选择状态，无法落点时降级到默认节点。
3. 类型桶自动列出 WoWDB 出现过的所有类型。
4. 类型视图在“无地图”时正确跳过地图层级。
5. 详情区在三视图中行为一致。
6. 类型展示名通过本地映射表展示，类型桶按 WoWDB 原始类型值排序。
7. 左侧地图树过滤能正确限制状态视图泳道内容。
8. 视图切换不引入固定延迟等待布局。
9. 类型视图列表模式能正确按“选中地图/其他分组”过滤任务。

---

## 14. 实现前确认结果（2026-04-11，按当前仓库复核）

1. `schemaVersion`：保持 `3`（不升级到 `4`）。
2. `InstanceQuestlines`：当前已纳入 `DataContracts/instance_questlines.json` 契约驱动导出；后续字段扩展以现有导出链路为准，不再以“手工维护/未自动导出”为前提。
3. `Type/MapPos/NpcIDs/NpcPos`：作为 `schemaVersion = 3` 下的可选扩展字段接入；导出契约变更时升级 `contract.schema_version`，但不强制升级运行时 `schemaVersion`。
4. 状态口径：不做进一步细化，维持三态。
