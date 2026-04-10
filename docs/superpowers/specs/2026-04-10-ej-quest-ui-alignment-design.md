# 冒险手册任务页签多视图 UI 设计稿（状态 / 类型 / 地图）

- 日期：2026-04-10
- 状态：已对齐（未开动实现）
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
6. 类型视图层级：有地图则 `类型→地图→任务线→任务`，无地图则 `类型→任务线→任务`
7. 状态视图左侧保留“地图树”过滤
8. 状态视图默认选中“当前角色所在地图”

---

## 3. 静态数据结构（WoWDB 导出，Live）

> 先定义结构，数据稍后导出填充。

```lua
Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 4,
  sourceMode = "live",
  generatedAt = "2026-..",

  quests = {
    [questID] = {
      ID = questID,
      UiMapID = 123,
      Type = "RAW_DB_TYPE",
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

- `Type` 直接使用 WoWDB 原始枚举值。
- `MapPos/NpcPos` 的 `UiMapID` 可省略，默认等于 `quests[questID].UiMapID`。
- 若需保持 `schemaVersion = 3`，新增字段必须视为可选；本设计推荐升至 `v4` 以保证 strict 校验一致。

---

## 4. 运行时模型（Questlines Model）

在 `Toolbox.Questlines.GetQuestTabModel()` 现有结构上，补齐类型索引：

```lua
QuestTabModel = {
  maps = { { id, name, questLines, progress }, ... },
  mapByID = { [mapID] = mapEntry },

  questLineByID = { [questLineID] = questLineEntry },
  questToQuestLineID = { [questID] = questLineID },

  typeList = { "RAW_DB_TYPE_A", "RAW_DB_TYPE_B", ... },
  typeToQuestIDs = { [typeKey] = { questID1, questID2, ... } },
  typeToQuestLineIDs = { [typeKey] = { questLineID1, questLineID2, ... } },
  typeToMapIDs = { [typeKey] = { mapID1, mapID2, ... } },
}
```

规则：

- `typeList` 为去重后的类型列表（即类型桶）。
- 同一任务线可出现在多个类型桶。
- 若任务/任务线缺少地图，则类型视图跳过地图层。

---

## 5. 视图协议与选择状态

### 5.1 统一选择状态

```lua
SelectionState = {
  selectedView = "status" | "type" | "map",
  selectedKind = "type" | "map" | "questline" | "quest",
  selectedTypeKey = "RAW_DB_TYPE",
  selectedMapID = 123,
  selectedQuestLineID = 456,
  selectedQuestID = 789,
}
```

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

---

## 9. 内存与体量评估（基于当前导出规模）

当前导出规模：约 16,984 任务 / 1,563 任务线。

在“平均 2 个 NPC/任务”的假设下：

- 数据文件体积估计约 **3.7 MB**
- 运行时内存预计为文件体积的 **2–4 倍**（约 **7–15 MB**）
- “按类型列表/索引”额外开销约 **0.5–1.0 MB**

---

## 10. 非目标

1. 不在本次设计中落实实际 UI 代码。
2. 不在本次设计中实现导航/高亮能力。
3. 不包含外部任务插件联动。

---

## 11. 验收要点

1. 进入任务页签默认进入**状态视图**，并默认选中当前地图。
2. 三视图切换保持同一选择状态，无法落点时降级到默认节点。
3. 类型桶自动列出 WoWDB 出现过的所有类型。
4. 类型视图在“无地图”时正确跳过地图层级。
5. 详情区在三视图中行为一致。

---

## 12. 待确认项（实现前）

1. `schemaVersion` 是否升级到 4。
2. 类型视图是否需要“列表模式”或“纯任务列表”。
3. 状态口径是否需要进一步细化（例如活动/世界任务的特殊状态）。
