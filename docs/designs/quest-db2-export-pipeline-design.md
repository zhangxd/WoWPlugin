# 任务数据 DB2 导出管道设计

- 文档类型：设计
- 状态：草稿
- 主题：quest-db2-export-pipeline
- 适用范围：`WoWTools/scripts/export/**`
- 关联模块：无
- 关联文档：
  - `docs/designs/instance-questlines-questcompletist-design.md`
- 最后更新：2026-04-14

## 1. 背景

需要一张稳定的离线映射表，描述"任务 → 地图 → 资料片"的归属关系，以便每次版本更新时一键重新生成最新数据，供插件侧静态表使用。

WoW 客户端本身包含所需的 DB2 文件（`QuestPOI.db2`、`UiMap.db2`、`Map.db2`），本设计基于本地已有 wow.tools.local 实例进行导出与联表。

## 2. 设计目标

- 每次 WoW 版本更新后，执行一条命令即可输出最新的 `quest_expansion_map.csv`。
- 映射关系完全来源于客户端 DB2 文件，不依赖服务器端缓存或手工维护。
- 输出格式稳定，列名不随工具版本变动。

## 3. 非目标

- 不覆盖无地图 POI 的任务（对话任务、纯剧情任务）——这类任务不在 `QuestPOI.db2` 中。
- 不实现插件运行时查询；输出结果仅作静态数据源。
- 不处理经典服或怀旧服数据。

## 4. 方案对比

### 4.1 方案 A：客户端 DB2 联表（本方案）

- **做法**：从 WoW 客户端直接提取 `QuestPOI.db2`、`UiMap.db2`、`Map.db2`，用 DBC2CSV 导出 CSV，Python 脚本联表生成映射。
- **优点**：完全离线、可重复执行、数据来源权威（Blizzard 客户端）、热修复可通过 `DBCache.bin` 一并应用。
- **风险 / 缺点**：`QuestPOI.db2` 不覆盖所有任务；联表关键字段（`UiMap.MapID` 是否外键到 `Map.db2`）**⚠️ 待验证**。

### 4.2 方案 B：游戏内插件 dump

- **做法**：编写 Lua 插件，登录游戏后遍历任务 ID 调用 `GetQuestExpansion(questID)`，将结果保存到 SavedVariables，再离线处理。
- **优点**：数据最完整，覆盖所有任务。
- **风险 / 缺点**：需要人工登录游戏触发、无法完全自动化、任务 ID 枚举范围难以确定上限。

### 4.3 选型结论

- **选定方案**：方案 A（客户端 DB2 联表）
- **选择原因**：可完全脚本化、无需登录游戏、对工具依赖少；POI 覆盖不全的缺口可在后续版本以方案 B 的 dump 数据作补充源叠加。

## 5. 选定方案

### 5.1 联表链路

```
QuestPOI.db2
  QuestID ──→ 输出字段
  UiMapID ──┐
            ↓
        UiMap.db2
          ID (= UiMapID)
          Name_lang ──→ ZoneName
          MapID     ──┐   ⚠️ 待验证：MapID 是否外键到 Map.db2.ID
          Type      ──→ 仅保留 Zone(3) / Dungeon(4)
                    ↓
                Map.db2
                  ID (= MapID)
                  MapName_lang ──→ MapName
                  ExpansionID  ──→ 资料片枚举值
```

> **⚠️ 待验证**：在 wow.tools.local 中打开 `UiMap.db2`，确认是否存在 `MapID` 字段且其值域与 `Map.db2.ID` 对应。若不存在，需调研替代连接键。

### 5.2 工具链

| 步骤 | 工具 | 说明 |
|------|------|------|
| 提取 DB2 | wow.export 或 wow.tools.local | 从 CASC 存储导出原始 `.db2` 文件 |
| 转换 CSV | [DBC2CSV](https://github.com/Marlamin/DBC2CSV) | 支持 CLI 批量转换，同时应用 `DBCache.bin` 热修复 |
| 联表生成 | Python（pandas） | 见 5.3 节 |

### 5.3 导出命令

```bash
# 1. 转换三张表（DBCache.bin 应用热修复）
DBC2CSV.exe QuestPOI.db2 UiMap.db2 Map.db2 DBCache.bin
# DBCache.bin 位于: <WoW>/_retail_/Cache/ADB/enUS/DBCache.bin

# 2. 生成映射表
python build_quest_table.py

# 输出: quest_expansion_map.csv
```

### 5.4 联表脚本（`build_quest_table.py`）

```python
import pandas as pd

EXPANSION_NAMES = {
    0: "Classic",
    1: "The Burning Crusade",
    2: "Wrath of the Lich King",
    3: "Cataclysm",
    4: "Mists of Pandaria",
    5: "Warlords of Draenor",
    6: "Legion",
    7: "Battle for Azeroth",
    8: "Shadowlands",
    9: "Dragonflight",
    10: "The War Within",
    # ⚠️ 待确认：11/12 对应资料片名称
}

quest_poi = pd.read_csv("QuestPOI.csv")
ui_map    = pd.read_csv("UiMap.csv")
map_db2   = pd.read_csv("Map.csv")

# Quest → UiMap
# ⚠️ 待确认：QuestPOI.csv 中 UiMapID 的实际列名
df = quest_poi[["QuestID", "UiMapID"]].drop_duplicates("QuestID")

# UiMap → Map
# ⚠️ 待确认：UiMap.csv 中是否有 MapID 列，以及其与 Map.csv.ID 的对应关系
df = df.merge(
    ui_map[["ID", "Name_lang", "MapID"]].rename(
        columns={"ID": "UiMapID", "Name_lang": "ZoneName"}
    ),
    on="UiMapID", how="left"
)

# Map → ExpansionID
df = df.merge(
    map_db2[["ID", "ExpansionID", "MapName_lang"]].rename(
        columns={"ID": "MapID", "MapName_lang": "MapName"}
    ),
    on="MapID", how="left"
)

df["ExpansionName"] = df["ExpansionID"].map(EXPANSION_NAMES)
df = df[["QuestID", "UiMapID", "ZoneName", "MapID", "MapName", "ExpansionID", "ExpansionName"]]
df = df.sort_values(["ExpansionID", "ZoneName", "QuestID"])
df.to_csv("quest_expansion_map.csv", index=False)
print(f"导出 {len(df)} 条，缺失区域: {df['ZoneName'].isna().sum()} 条")
```

### 5.5 一键脚本（`update_quest_table.sh`）

```bash
#!/bin/bash
# 每次 WoW 版本更新后执行此脚本

WOW_DIR="C:/Program Files/World of Warcraft/_retail_"
DB2_DIR="$WOW_DIR/DBFilesClient"
HOTFIX="$WOW_DIR/Cache/ADB/enUS/DBCache.bin"

DBC2CSV.exe \
  "$DB2_DIR/QuestPOI.db2" \
  "$DB2_DIR/UiMap.db2" \
  "$DB2_DIR/Map.db2" \
  "$HOTFIX"

python build_quest_table.py
```

> **⚠️ 待确认**：`DB2_DIR` 路径是否正确；部分版本下 `.db2` 文件可能不在 `DBFilesClient/` 目录，需以 wow.export 实际导出路径为准。

## 6. 影响面

- **数据与存档**：输出 `quest_expansion_map.csv`，作为 `DataContracts/` 下静态数据源候选。
- **API 与模块边界**：不涉及插件运行时 API；仅影响导出工具层。
- **文件与目录**：新增 `WoWTools/scripts/export/build_quest_table.py`、`update_quest_table.sh`。
- **文档回写**：若落地为正式数据源，需更新 `docs/Toolbox-addon-design.md` 中的数据来源说明。

## 7. 风险与回退

| 风险 | 缓解方式 |
|------|----------|
| `UiMap.MapID` 不直接外键到 `Map.db2` | 调研 `AreaTable.db2` 或其他中间表作为连接键 |
| `QuestPOI.db2` 覆盖率不足 | 后续叠加方案 B（插件 dump）作补充源 |
| DBC2CSV 定义文件落后于新 build | 从 WoWDBDefs 仓库手动更新 `definitions/` 目录 |
| 列名随 build 变动 | 脚本中统一做列名断言，版本更新时快速定位 |

## 8. 验证策略

1. 导出后检查 `quest_expansion_map.csv` 行数与资料片分布是否合理（不应出现大量 ExpansionID 为空）。
2. 抽取已知任务（如魔兽世界原始暗夜要塞任务）验证 ExpansionID = 0 映射正确。
3. 与 Wowhead 任务页面的区域标注交叉比对 10 条以上样本。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-14 | 初稿，基于 wow.tools.local + DBC2CSV 方案，标记待验证项 |
