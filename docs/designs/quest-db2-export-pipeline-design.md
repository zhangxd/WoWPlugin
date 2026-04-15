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

### 5.1.1 当前 CSV 字段语义

当前 `quest_expansion_map.csv` 已从单纯的"任务 → 地图 → 资料片"映射扩展为"地图归属 + 任务条件摘要"联合导出。字段按语义分为四类：

1. 地图 / 资料片归属：
   - `QuestID`
   - `QuestLineID`
   - `UiMapID`
   - `UiMapType`
   - `ZoneName`
   - `MapID`
   - `MapName`
   - `MapExpansionID`
   - `MapExpansionName`
   - `ContentExpansionID`
   - `ContentExpansionName`
2. 主链前置关系：
   - `PrevQuestIDs`
   - `PrevQuestLogic`
   - `PrevQuestLogicRaw`
   - `NextQuestIDs`
3. 可接 / 状态 / 引导条件：
   - `ExclusiveToQuestIDs`
   - `BreadcrumbQuestID`
   - `StoryCondition`
   - `StoryLogicRaw`
   - `ModifierTreeID`
   - `ConditionFlags`
4. 阵营 / 职业限制：
   - `FactionTag`
   - `FactionCondition`
   - `FactionMaskRaw`
   - `ClassCondition`
   - `ClassMaskRaw`

### 5.1.2 字段消费约定

为避免插件或离线分析脚本把弱条件误当成真实任务树，约定如下：

| 字段 | 含义 | 是否适合直接建任务树 |
|------|------|----------------------|
| `PrevQuestIDs` | `PlayerCondition.PrevQuestID_*` 提供的前置任务候选 | **是**，但仅表示 DB2 暴露出的前置关系 |
| `PrevQuestLogic` / `PrevQuestLogicRaw` | 前置任务逻辑值 | **是**，用于解释多前置的 AND / OR 关系 |
| `NextQuestIDs` | 基于当前导出集合内 `PrevQuestIDs` 反推的后继任务 | **是**，但不是服务端完整后继全集 |
| `ExclusiveToQuestIDs` | `QuestV2CliTask.FiltCompletedQuest_*` 的完成条件候选 | **否**，只能视为"可能互斥/完成门槛"摘要 |
| `BreadcrumbQuestID` | 引导任务关系 | **否**，仅适合画弱边或作为入口提示 |
| `StoryCondition` | `completed + active + non_active` 的可读摘要 | **否**，适合显示和筛选，不替代主链前置 |
| `ModifierTreeID` | 更复杂条件树入口 | **否**，需后续脚本二次解释 |
| `MapExpansionID` / `MapExpansionName` | 当前这条地图归属记录对应的地图资料片 | **否**，只用于地图层分析 |
| `ContentExpansionID` / `ContentExpansionName` | 以“同任务线内最大地图资料片值”回填的任务资料片 | **否**，用于内容版本归属，不等同于单行地图资料片 |
| `FactionTag` | 对 `FactionCondition` 的稳定归一化标记 | **否**，适合过滤与分组，不替代原始掩码 |

### 5.1.3 摘要字段编码规则

- 多值 ID 列统一使用 `=` 连接，保持与 `QuestLineID` 一致。
- 无值统一输出空字符串，避免用 `0` 混淆"无条件"与"原始值就是 0"。
- 资料片字段拆分为两组：
  - `MapExpansion*`：当前地图归属行自己的 `map.ExpansionID`
  - `ContentExpansion*`：对该任务所属所有任务线，收集线内全部任务的地图资料片，取最大值作为任务资料片
  - 目的：显式区分“任务出现在旧世界地图上”与“任务属于新版本内容”
- `ClassCondition`：
  - 由 `ClassMask` 解析为职业 token 列表，如 `rogue`、`warrior=paladin`
  - 若出现未覆盖位，回退输出原始数值字符串
- `FactionCondition`：
  - 基于 `chrraces.PlayableRaceBit + Alliance` 动态归并
  - 当前可输出 `alliance`、`horde`、`alliance=horde`、`neutral`
  - 若掩码包含未知位，回退输出原始数值字符串
- `FactionTag`：
  - 仅在 `FactionCondition` 可稳定归并时输出
  - 当前有效值：`alliance`、`horde`、`neutral`、`shared`
  - `FactionCondition = alliance=horde` 时，`FactionTag = shared`
  - 若无法稳定归并则留空，不猜测阵营
- `StoryCondition`：
  - 当前只汇总 `completed:<ids>`、`active:<questID>`、`non_active:<questID>`
  - 不纳入 `PrevQuestIDs`，避免与主链前置重复
- `ConditionFlags`：
  - 目前用于标记是否存在已提取的剧情状态条件
  - 后续若引入 `ModifierTree` 细分解析，可继续向该列追加稳定标记

### 5.1.4 原始列保留原则

为兼顾人工可读性与后续脚本二次解释，以下列保留原始值：

- `FactionMaskRaw`
- `ClassMaskRaw`
- `StoryLogicRaw`
- `PrevQuestLogicRaw`
- `ModifierTreeID`

原则：

- 摘要列负责"看得懂"
- 原始列负责"不丢信息"
- 后续若要进一步细化逻辑，以原始列为准，不反向解析摘要列

### 5.1.4.1 `收复吉尔尼斯` 资料片归属示例

`收复吉尔尼斯` 任务线存在“地图资料片”和“任务资料片”分离的典型情况：

- `78178 前往吉尔尼斯`
  - `MapExpansionName = Classic`
  - `ContentExpansionName = Dragonflight`
- `78597`
  - 当 `UiMapID = 21 / 85` 时，`MapExpansionName = Classic`
  - 当 `UiMapID = 2112` 时，`MapExpansionName = Dragonflight`
  - 但三行统一回填 `ContentExpansionName = Dragonflight`

这类案例说明：

- 地图所在资料片不能直接当作任务内容版本
- 同一任务可同时出现在旧地图与新版本地图
- 因此导出必须显式区分 `MapExpansion*` 与 `ContentExpansion*`

### 5.1.5 任务线建模约定（共享前置集合分组）

当导出结果用于离线任务图或任务树分析时，采用以下建模规则：

1. 若多个后续任务拥有**相同的前置任务集合**，则不直接把这些后续任务彼此串联，而是先抽象出一个“前置组节点”。
2. 该前置组节点从上游前置任务汇入，再向下**居中分叉**到这组后续任务。
3. 若下一层任务又依赖上一层分叉任务的共同集合，则继续抽象新的前置组节点，而不是强行还原成单链。
4. 该建模是**依赖分组图**，不等同于游戏内实际接取 UI 的逐步时序图。

适用边界：

- `PrevQuestIDs` 与 `PrevQuestLogic*` 仍然是“硬前置”优先来源。
- 当 `PrevQuestIDs` 缺失，但 `QuestV2CliTask.FiltCompletedQuest_*` 能提供稳定的共同前置集合时，可用于构建“共享前置集合分组”。
- `BreadcrumbQuestID` 不参与该分组建模，只作为弱引导关系保留。

### 5.1.6 `78180` 示例：收复吉尔尼斯

基于当前 `wow.db`，`78180` 与 `78181` 都关联相同的完成条件候选 `78177 / 78178`，因此在共享前置集合建模下，不把 `78180 -> 78181` 直接视作单链，而是先从共同前置组分叉，再在下一层收束。

示意图：

```text
[78596]
  |
  v
[78177 前往吉尔尼斯]
  \
   \
    +-----------------------------+
                                  |
[78178 前往吉尔尼斯]               |
  /                               |
 /                                v
+------------------------> [前置组 A: 78177 / 78178]
                                   |
                    +--------------+--------------+
                    |                             |
                    v                             v
             [78180 血溅十字军]            [78181 埃德里奇的回击]
                    \                             /
                     \                           /
                      +-----------+-------------+
                                  |
                                  v
                      [前置组 B: 78180 / 78181]
                                  |
                                  v
                           [78182 膝行而前]
                                  |
                                  v
                           [78183 血染大地]
                                  |
                                  v
                            [78184 未命名]
                                  |
                                  v
                            [78185 未命名]
                                  |
                                  v
                            [78186 未命名]
                                  |
                                  v
                            [78187 未命名]
                                  |
                                  v
                            [78188 未命名]
                                  |
                                  v
                            [78189 未命名]
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             [78190 未命名]              [78597 未命名]
                                                |
                                                v
                                          [79137 未命名]
```

解释：

- `78177` 与 `78178` 视为共同入口条件组 `A`
- `78180` 与 `78181` 视为从组 `A` 分叉出的同层任务
- `78182` 视为依赖上一层任务组 `B = {78180, 78181}` 的后续任务
- `78189` 之后再次分叉为两个终点支路：
  - `78190`
  - `78597 -> 79137`

### 5.1.7 任务线串联语义约定

当导出结果或官方资料使用 `A -> B -> C` 这类任务线串联表达时，默认按以下语义理解：

1. 首先表示**故事线中的编排顺序**，即玩家在剧情阅读或官方说明中的推荐推进顺序。
2. 通常也表示**推荐的任务推进顺序**，但不自动等同于底层唯一的硬前置依赖链。
3. 在复杂任务线中，串联可能覆盖：
   - 双入口汇入同一主干
   - 中段公共节点
   - 尾部分流
   - 被多条任务线复用的章节锚点
4. 因此，任务线串联的解释优先级固定为：
   - 官方任务线说明 / 权威资料
   - `questlinexquest.OrderIndex`
   - `PrevQuestID_*`
   - `FiltCompletedQuest_*` 等条件字段

定版原则：

- 官方任务线说明优先用于定义“真实剧情流程”。
- `questlinexquest.OrderIndex` 主要用于补齐 DB2 结构顺序和未命名节点位置。
- `PrevQuestID_*` 用于识别硬前置依赖。
- `FiltCompletedQuest_*`、`RaceMask`、`ClassMask`、`ModifierTreeID` 用于解释可接条件或分组条件，不直接定义任务线串联。

一句话约定：

> 任务线串联表示任务在故事线中的编排顺序与推荐推进顺序；它通常反映剧情流程，但不必然等同于底层唯一的硬前置依赖链。

### 5.2 工具链

| 步骤 | 工具 | 说明 |
|------|------|------|
| 提取 DB2 | wow.export 或 wow.tools.local | 从 CASC 存储导出原始 `.db2` 文件 |
| 转换 CSV | [DBC2CSV](https://github.com/Marlamin/DBC2CSV) | 支持 CLI 批量转换，同时应用 `DBCache.bin` 热修复 |
| 联表生成 | Python（pandas） | 见 5.3 节 |

### 5.2.1 导出分层原则（固定规则）

正式固定导出链路为三层：

1. **DB 原始层**
   - 来源：`wow.db` 与其对应的 DB2 导入表
   - 职责：保存原始事实关系，不直接为插件视图负责
2. **CSV 分析中间层**
   - 文件：`quest_expansion_map.csv`
   - 职责：以“任务 × 地图归属”粒度摊平关系，用于分析、统计、排错、规则验证
   - 说明：CSV 明确不是插件运行时正式数据格式
3. **Lua 运行时层**
   - 文件：`Toolbox/Data/InstanceQuestlines.lua`
   - 职责：按 `Toolbox.Questlines` / `quest` 模块的消费需求做聚合收敛，仅保留运行时真正需要的核心字段

固定约定：

- 正式 Lua 不直接由 DB 表投影生成，而是由 CSV 中间层聚合生成。
- CSV 允许保留分析字段、冗余字段和调试字段；Lua 层只保留稳定运行时字段。
- 当导出规则仍在迭代时，优先修改 CSV 分析层；只有在规则收敛后，才回写 Lua 运行时层。

### 5.2.2 脚本、目录、文件职责

#### `WoWTools/scripts/export/`

- `quest_db2_export_pipeline.py`
  - 职责：从 `wow.db` 生成 `quest_expansion_map.csv`
  - 输出粒度：`任务 × 地图归属`
  - 允许包含分析辅助字段，如条件摘要、原始掩码、地图资料片、任务资料片
- `questline_runtime_preview_export.py`
  - 职责：从 `quest_expansion_map.csv` 生成轻量临时 Lua 预览
  - 用途：验证运行时最小模型是否可行
  - 说明：不是正式契约导出器
- `toolbox_db_export.py`
  - 职责：正式契约驱动导出器
  - 用途：生成 `Toolbox/Data/*.lua`
  - 说明：只有规则定版后才应把 CSV 聚合逻辑接回这里

#### `WoWTools/outputs/toolbox/`

- `quest_expansion_map.csv`
  - 角色：分析中间层
  - 生命周期：允许频繁重生成
- `InstanceQuestlines.runtime_preview.lua`
  - 角色：临时运行时结构预览
  - 生命周期：仅用于方案验证，不作为正式插件数据
- `contract_snapshots/`
  - 角色：正式契约快照归档

#### `WoWPlugin/Toolbox/Data/`

- `InstanceQuestlines.lua`
  - 角色：插件运行时正式静态表
  - 说明：保持 `schema v6` 主骨架兼容，扩展字段以 `Toolbox.Questlines` / `quest` 模块的消费需求为准

### 5.2.3 `instance_questlines` 正式导出策略（快速迭代版）

针对 `instance_questlines`，正式固定以下特例：

1. **不再要求通过 `DataContracts/instance_questlines.json` 驱动正式导出。**
2. 由专门脚本直接读取 `quest_expansion_map.csv`，聚合并输出 `Toolbox/Data/InstanceQuestlines.lua`。
3. 该脚本的职责是：
   - 把 CSV 分析层收敛为 `quest` / `Toolbox.Questlines` 所需的运行时静态结构
   - 保持现有 `schema v6` 主骨架兼容
   - 支持快速迭代字段和聚合规则，而不必同步维护契约 DSL
4. `DataContracts/instance_questlines.json` 在后续迭代中不再作为 `instance_questlines` 的正式事实源；如历史文件仍保留，仅作参考，不参与当前正式导出链路。

选择原因：

- `instance_questlines` 当前仍在快速迭代字段与聚合规则。
- 其运行时结构已明显偏离通用“SQL 直出 -> 契约写 Lua”的模式，更适合由专门脚本从 CSV 中间层二次聚合。
- 先去掉契约耦合，可以更快验证 `Toolbox.Questlines` / `quest` 模块的消费模型；待结构稳定后，再评估是否需要回归统一契约治理。

约束：

- 虽然跳过契约文件，但脚本输出结构仍须在文档中明确说明，并由测试锁定。
- `InstanceQuestlines.lua` 的字段变更必须同步更新：
  - 设计文档
  - 计划文档
  - 运行时 strict 校验
  - 逻辑测试 fixture

### 5.2.4 `quest` 导航规则（资料片优先）

`quest` 模块当前的任务导航固定采用：

```text
资料片 -> 混合列表项 -> 任务线 -> 任务
```

其中“混合列表项”有两种：

1. `map`
   - 当任务线可以稳定识别主地图时，先按地图聚合，再在地图下列出任务线。
2. `questline`
   - 当任务线无法稳定归图，或按地图表达会明显误导时，直接显示任务线名称。

固定原则：

- 顶层仍然以 `ContentExpansionID` 作为资料片归属，不因地图复用而改变。
- 不再把“地图”视为任务线的天然唯一归属，只把它作为导航入口维度之一。
- 同一资料片下的列表项排序：
  - 先显示 `map`
  - 再显示 `questline`
  - 各自内部按名称排序

地图项适用条件：

- `PrimaryUiMapID` 存在
- `PrimaryMapShare >= 0.60`
- 该任务线不是明显的主题导览线 / 复用型任务线

直接显示任务线名的适用条件：

- `PrimaryMapShare < 0.60`
- 关联地图过多
- 主题导览、强复用、跨资料片旧内容重组等场景

例子：

- `收复吉尔尼斯`
  - 允许挂在 `吉尔尼斯废墟` 地图项下
- `游学探奇：萨拉塔斯`
  - 不应强行归到某张地图，应直接作为任务线项出现在 `The War Within` 下

### 5.2.5 运行时数据结构建议

为支持上述导航规则，`Toolbox.Questlines.GetQuestNavigationModel()` 建议在资料片节点下统一产出“混合列表项”，而不是只产出地图模式或类型模式。

建议结构：

```lua
navigationModel = {
  expansionList = {
    { id = 9, name = "Dragonflight" },
  },
  expansionByID = {
    [9] = {
      id = 9,
      name = "Dragonflight",
      entries = {
        {
          kind = "map",
          id = 217,
          name = "吉尔尼斯废墟",
          questLines = { ... },
        },
        {
          kind = "questline",
          id = 5673,
          name = "游学探奇：萨拉塔斯",
          questLine = { ... },
        },
      },
    },
  },
}
```

运行时建议：

- `questLine` 模型继续保留：
  - `id`
  - `UiMapID`
  - `questIDs`
  - `ExpansionID`
- 在此基础上继续保留扩展字段：
  - `ContentExpansionID`
  - `UiMapIDs`
  - `PrimaryUiMapID`
  - `PrimaryMapShare`
  - `FactionTags`
- 运行时过滤顺序：
  1. 先过滤当前角色不可见的任务
  2. 再过滤空任务线
  3. 再根据 `PrimaryMapShare` 决定该任务线进入 `map` 项还是 `questline` 项

特殊注意：

- 地图模式主区若按 `selectedMapID` 取任务线，必须同时带上 `selectedExpansionID`，避免同图跨资料片串线。
- 共享任务不应只记录单一 `questToQuestLineID` 语义；详情、面包屑和跳转需以当前上下文任务线优先。

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
| 2026-04-14 | 补充 `quest_expansion_map.csv` 扩展字段语义、消费约定、摘要编码规则与原始列保留原则 |
| 2026-04-15 | 补充“共享前置集合分组”建模约定，并加入 `78180` / `78181` 的 ASCII 图示示例 |
| 2026-04-15 | 补充 `MapExpansion* / ContentExpansion* / FactionTag` 数据模型，以及 `收复吉尔尼斯` 的资料片归属示例 |
| 2026-04-15 | 补充“任务线串联语义约定”，明确官方流程、OrderIndex 与条件字段的解释优先级 |
| 2026-04-15 | 固定 `DB -> CSV -> Lua` 三层导出原则，并补充脚本、目录、文件职责边界 |
| 2026-04-15 | 为 `instance_questlines` 固定快速迭代特例：跳过 `DataContracts`，改由专门脚本直接从 CSV 聚合正式 Lua |
| 2026-04-15 | 补充 `quest` 模块的资料片优先导航规则，以及“地图或任务线混合列表项”的运行时结构建议 |
