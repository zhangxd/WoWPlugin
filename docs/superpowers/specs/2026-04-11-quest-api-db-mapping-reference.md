# 任务 API 与 DB 字段映射离线参考

- 日期：2026-04-11
- 状态：研究结论（离线查找用）
- 适用范围：`WoWPlugin` 任务页签 / `WoWTools` 任务相关导出
- 关联模块：`encounter_journal`

---

## 1. 目的

本文件用于沉淀以下问题的离线结论，后续做导出契约、运行时 inflate、UI 字段取值时可直接查阅：

1. 当前插件实际使用了哪些 quest 相关 API。
2. 这些 API 的语义分别更接近“运行时状态”还是“静态 DB 字段”。
3. 当前 `wow.db` 中哪些表、哪些字段能和这些 API 概念建立稳定对应。
4. 当前 `Toolbox/Data/InstanceQuestlines.lua` 的结构，哪些字段已经能从数据库稳定关联，哪些还不能。

---

## 2. 当前插件实际使用的 quest 相关 API

当前本地代码中与任务页签直接相关的 API 主要位于：

- [QuestlineProgress.lua](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/Toolbox/Core/API/QuestlineProgress.lua)

当前实际已使用：

1. `C_QuestLog.GetTitleForQuestID`
2. `QuestUtils_GetQuestName`
3. `C_Map.GetMapInfo`
4. `C_QuestLog.GetLogIndexForQuestID`
5. `C_QuestLog.IsQuestFlaggedCompleted`

设计稿计划使用但当前领域 API 尚未接入：

1. `C_QuestLog.ReadyForTurnIn`

补充说明：

- [MinimapButton.lua](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/Toolbox/Modules/MinimapButton.lua) 里还用到了 `C_Map.GetBestMapForUnit` 与 `C_Map.GetPlayerMapPosition`，但它们属于玩家当前位置能力，不是任务静态数据能力。

---

## 3. API 语义与 DB 对应结论

| API / 字段语义 | 更偏向什么 | DB 候选字段 | 结论 |
|---|---|---|---|
| `C_QuestLog.GetTitleForQuestID(questID)` 任务名 | 运行时 quest data | `QuestV2CliTask.QuestTitle_lang` | 当前 `wow.db` 不能稳定全量对应 |
| `QuestUtils_GetQuestName(questID)` | 运行时任务名兜底 | 无稳定全量表 | 当前 `wow.db` 不能稳定全量对应 |
| `C_Map.GetMapInfo(uiMapID).name` 地图名 | 静态地图元数据 | `UiMap.Name_lang` | 可以稳定对应 |
| `C_QuestLog.IsQuestFlaggedCompleted(questID)` | 角色运行时状态 | 无 | 不能从静态 DB 导出 |
| `C_QuestLog.GetLogIndexForQuestID(questID)` | 角色任务日志状态 | 无 | 不能从静态 DB 导出 |
| `C_QuestLog.ReadyForTurnIn(questID)` | 角色运行时交付状态 | 无 | 不能从静态 DB 导出 |
| `C_QuestLog.GetInfo(questLogIndex)` | 运行时 quest log 视图对象 | 只能概念映射到 quest / poi / tag 等表 | 不适合直接当导出字段来源 |
| `C_QuestLog.GetQuestObjectives(questID)` | 运行时 objective 视图对象 | `QuestObjective.*` | 只能部分概念对应，不能直接等同 |
| `C_QuestLog.GetQuestType(questID)` | API 自己的 quest type 枚举 | 候选仅 `QuestInfo.Type` | 目前不能证明是同一概念 |

关键结论：

1. **任务名、完成状态、日志状态、可交付状态**都更偏运行时，不适合直接要求当前 `wow.db` 静态导出全量覆盖。
2. **地图名、地图 ID、POI 点位**属于静态 client DB 能力，和当前数据链路相容。
3. **`QuestInfo.Type` 不能在没有覆盖率核对前，直接当作 API quest type 或设计里的“任务类型”**。

---

## 4. 当前相关 DB 表与关系

本轮核对中最关键的表如下：

### 4.1 任务线与任务关系

- `QuestLine`
  - `ID`
  - `Name_lang`
- `QuestLineXQuest`
  - `QuestLineID`
  - `QuestID`
  - `OrderIndex`

用途：

- 提供 `questLineID -> questID` 的稳定关系
- 提供任务在线中的顺序信息

### 4.2 地图与任务 POI

- `QuestPOIBlob`
  - `ID`
  - `QuestID`
  - `UiMapID`
  - `ObjectiveID`
- `QuestPOIPoint`
  - `QuestPOIBlobID`
  - `X`
  - `Y`
  - `Z`
- `UiMap`
  - `ID`
  - `Name_lang`
  - `ParentUiMapID`
  - `Type`

用途：

- `QuestPOIBlob.QuestID -> QuestPOIPoint.QuestPOIBlobID` 可以稳定推导 quest 的 POI 点位。
- `QuestPOIBlob.UiMapID -> UiMap.ID` 可以稳定推导地图名称与地图层级。

### 4.3 Objective 与候选 NPC

- `QuestObjective`
  - `ID`
  - `QuestID`
  - `Type`
  - `ObjectID`
  - `Description_lang`

`wowdbd` 对 `QuestObjective.ObjectID` 的注释非常关键：

- `Type in {0, 3, 11}` 时，`ObjectID` 语义为 `CreatureID`
- `Type = 1` 时，`ObjectID` 为 `ItemID`
- `Type = 2` 时，`ObjectID` 为 `GameObjectID`
- 其它类型依赖具体枚举，不应默认当 NPC

这意味着：

- `NpcIDs` 只能在 `QuestObjective.Type in {0, 3, 11}` 时由 `ObjectID` 推导。
- 不能看到 `ObjectID > 0` 就一律当 NPC。

### 4.4 QuestInfo 候选链

- `QuestV2CliTask`
  - `ID`
  - `QuestTitle_lang`
  - `QuestInfoID`
- `QuestInfo`
  - `ID`
  - `InfoName_lang`
  - `Type`

表结构上的关系成立：

- `QuestV2CliTask.ID = questID`
- `QuestV2CliTask.QuestInfoID -> QuestInfo.ID`

但覆盖率很差，不能据此认定它是当前任务线导出范围的稳定主来源。

---

## 5. 当前 `InstanceQuestlines.lua` 是否已能从 DB 关上

当前 live 数据定义位于：

- [InstanceQuestlines.lua](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/Toolbox/Data/InstanceQuestlines.lua)
- [instance_questlines.json](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/DataContracts/instance_questlines.json)

当前 `schemaVersion = 3` 的根结构：

1. `quests[questID].ID`
2. `quests[questID].UiMapID`
3. `questLines[questLineID].ID`
4. `questLines[questLineID].Name_lang`
5. `questLines[questLineID].UiMapID`
6. `questLineQuestIDs[questLineID] = { questID... }`

这些字段与当前 `wow.db` 的闭环关系是清楚的：

- `questLines[*].ID` <- `QuestLine.ID`
- `questLines[*].Name_lang` <- `QuestLine.Name_lang`
- `questLineQuestIDs` <- `QuestLineXQuest.QuestLineID / QuestID / OrderIndex`
- `quests[*].ID` <- `QuestLineXQuest.QuestID`
- `quests[*].UiMapID` <- `QuestPOIBlob.UiMapID` 的投票/聚合结果
- `questLines[*].UiMapID` <- 同一任务线下 quest 的 `QuestPOIBlob.UiMapID` 投票结果

结论：

- **当前 live v3 结构与当前 `wow.db` 是能稳定闭环的。**

---

## 6. 设计稿新增字段的可关联性矩阵

以下统计基于当前任务线导出范围：

- 基准任务数：`17661`
- 其中带有效 `QuestPOIBlob.UiMapID` 的任务：`16986`，约 `96.18%`

### 6.1 `QuestTitle`

候选来源：

- `QuestV2CliTask.QuestTitle_lang`

覆盖率：

- `644 / 16986`，约 `3.79%`

结论：

- **不能**作为当前任务线静态导出的稳定任务名来源。
- 继续走 `C_QuestLog.GetTitleForQuestID` / `QuestUtils_GetQuestName` 作为运行时任务名，更合理。

### 6.2 `Type`

候选来源：

- `QuestV2CliTask.QuestInfoID -> QuestInfo.Type`

覆盖率：

- `333 / 16986`，约 `1.96%`

补充观察：

- `QuestInfo.Type` 的值域为 `0..19`
- 对应 `InfoName_lang` 出现“世界任务 / 大使任务 / 地下城世界任务 / 世界首领”等分类
- 这更像 `QuestInfo` 自己的分类系统，不应直接假定与 `C_QuestLog.GetQuestType()` 等同

结论：

- **不能**把 `QuestInfo.Type` 直接当作当前任务线导出范围的稳定全量 `Type` 字段。
- 如果后续仍要引入“任务类型”，需要先确认新的权威来源，或接受“当前 DB 只覆盖极小子集”的事实。

### 6.3 `MapPos`

来源链：

- `QuestPOIBlob.QuestID`
- `QuestPOIBlob.ID`
- `QuestPOIBlob.UiMapID`
- `QuestPOIPoint.QuestPOIBlobID`
- `QuestPOIPoint.X / Y / Z`

覆盖率：

- `16986 / 17661`，约 `96.18%`

结论：

- **可以**作为当前 `wow.db` 下最稳定的新字段来源。

### 6.4 `NpcIDs`

候选来源：

- `QuestObjective.Type in {0, 3, 11}`
- 此时 `QuestObjective.ObjectID` 语义可视为 `CreatureID`

覆盖率：

- `313 / 17661`，约 `1.77%`

类型分布：

- `Type = 0`：`306` 个 quest
- `Type = 3`：`13` 个 quest
- `Type = 11`：`5` 个 quest

重要说明：

- 这个结论来自 `wowdbd` 对 `QuestObjective.ObjectID` 的**语义注释**
- 不依赖 `ObjectID -> Creature.ID` 一定能 join 成功
- 前期如果直接拿 `Creature` 表去验证，会低估覆盖率，因为 client DB 的 `Creature` 行并不是完整 NPC 索引

结论：

- `NpcIDs` **可以做候选字段**，但覆盖率很低，只能覆盖当前任务线导出中的极小子集。

### 6.5 `NpcPos`

当前直接来源：

- **未找到** `QuestID + CreatureID/NPCID + UiMapID + X/Y` 的稳定静态 client DB 表

可做的近似：

- `QuestPOIBlob.ObjectiveID -> QuestObjective.ID`
- 若该 objective 满足 `Type in {0, 3, 11}`
- 则可用同 objective 对应的 `QuestPOIPoint` 近似成该 NPC 的导航点

近似覆盖率：

- 带 creature 语义 objective 的任务：`313`
- 其中还能和 `QuestPOIBlob.ObjectiveID` 对上的任务：`274`

结论：

- 当前 `wow.db` **不能直接稳定导出真实 `NpcPos`**
- 只能做“objective-linked quest poi”的近似导航点
- 如果设计要求的是“真实 NPC 坐标”，当前 DB 不满足

---

## 7. 当前最稳的设计解释

基于以上核对，当前最稳的判断是：

1. **静态 DB 层**
   - 稳定可导：`questLine/quest relation`、`UiMapID`、`MapPos`
   - 可弱导：`NpcIDs`
   - 不能稳定导：`QuestTitle`、`Type`、`NpcPos`

2. **运行时 API 层**
   - 继续承担 `QuestTitle`、完成状态、进行中状态、可交付状态等动态能力
   - 若未来需要 `Type` 或 `NpcPos`，应先补新的权威数据源，再落导出

3. **对设计稿的含义**
   - `MapPos` 是可以优先推进的
   - `NpcIDs/NpcPos` 不能按“当前 DB 已有稳定源”来描述，应明确为“候选 / 近似 / 待新源”
   - `Type` 不能继续默认写成“WoWDB 全量导出已可行”，当前证据不支持

---

## 8. 当前建议的数据分层

如果后续继续做任务页签与导航能力，建议按下面的心智模型理解：

1. **运行时字段**
   - `quest.name`
   - `quest.status`
   - `quest.readyForTurnIn`

2. **静态 DB 字段**
   - `quest.UiMapID`
   - `quest.MapPos`
   - `questLine.Name_lang`
   - `questLineXQuest.OrderIndex`

3. **条件成立时可导的弱字段**
   - `quest.NpcIDs`

4. **当前不能直接落地的字段**
   - `quest.Type`
   - `quest.NpcPos`

---

## 9. 本地核对文件

本轮研究直接核对过的本地文件：

- [QuestlineProgress.lua](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/Toolbox/Core/API/QuestlineProgress.lua)
- [InstanceQuestlines.lua](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/Toolbox/Data/InstanceQuestlines.lua)
- [instance_questlines.json](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/DataContracts/instance_questlines.json)
- [2026-04-10-ej-quest-ui-alignment-design.md](C:/Users/zhangxd/.config/superpowers/worktrees/WoWPlugin/codex/ej-quest-ui-multiview/docs/superpowers/specs/2026-04-10-ej-quest-ui-alignment-design.md)

---

## 10. 在线参考来源

API 文档：

- [C_QuestLog.GetTitleForQuestID](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetTitleForQuestID)
- [C_QuestLog.RequestLoadQuestByID](https://warcraft.wiki.gg/wiki/API_C_QuestLog.RequestLoadQuestByID)
- [C_QuestLog.GetInfo](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetInfo)
- [C_QuestLog.GetQuestObjectives](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetQuestObjectives)
- [C_QuestLog.GetQuestType](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetQuestType)
- [C_QuestLog.GetLogIndexForQuestID](https://warcraft.wiki.gg/wiki/API_C_QuestLog.GetLogIndexForQuestID)
- [C_QuestLog.IsQuestFlaggedCompleted](https://warcraft.wiki.gg/wiki/API_C_QuestLog.IsQuestFlaggedCompleted)
- [C_QuestLog.ReadyForTurnIn](https://warcraft.wiki.gg/wiki/API_C_QuestLog.ReadyForTurnIn)
- [C_Map.GetMapInfo](https://warcraft.wiki.gg/wiki/API_C_Map.GetMapInfo)

DB 表结构：

- [QuestV2CliTask](https://www.lupine.org/~alinsa/wowdbd/tables/QuestV2CliTask.html)
- [QuestInfo](https://www.lupine.org/~alinsa/wowdbd/tables/QuestInfo.html)
- [QuestObjective](https://www.lupine.org/~alinsa/wowdbd/tables/QuestObjective.html)
- [QuestPOIBlob](https://www.lupine.org/~alinsa/wowdbd/tables/QuestPOIBlob.html)
- [QuestPOIPoint](https://www.lupine.org/~alinsa/wowdbd/tables/QuestPOIPoint.html)
- [UiMap](https://www.lupine.org/~alinsa/wowdbd/tables/UiMap.html)

---

## 11. 后续使用建议

后续如果有人再问“某个任务字段能不能从 DB 导出来”，建议先按这个顺序检查：

1. 它是运行时状态，还是静态元数据？
2. 在 `wowdbd` 里是否能找到**明确表字段和关系说明**？
3. 在当前 `wow.db` 导入范围里，覆盖率是不是足够高？
4. 如果只是低覆盖或近似关系，不要直接写进正式契约，先在设计稿里标成“弱字段”或“近似字段”。

这个顺序能避免把“表结构上看起来能连”误判成“当前项目里已经能稳定导”。
