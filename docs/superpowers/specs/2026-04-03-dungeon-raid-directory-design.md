# 地下城 / 团队副本目录（DungeonRaidDirectory）— 设计规格

**状态**：已进入实现；代码位于 `Toolbox/Core/DungeonRaidDirectory.lua`，待游戏内验证与细节收尾。  
**日期**：2026-04-03  
**范围**：新增 `Core` 领域 API `Toolbox.DungeonRaidDirectory`，统一提供冒险手册中的地下城 / 团队副本基础目录、全部支持难度、掉落摘要、角色锁定映射、异步构建状态，以及设置页中的缓存重建与进度展示。  
**不依赖**：现有 `Modules/EJMountFilter.lua` 的实现细节；后续实现不得以其为设计前提。

---

## 1. 目标与验收

| 项 | 说明 |
|----|------|
| **统一目录层** | 提供一个 `Core` 领域 API，作为以后所有「冒险手册增强」的统一副本目录数据源。 |
| **数据事实源** | 以 **Encounter Journal（冒险手册）** 为准；仅收录手册中的地下城 / 团队副本。 |
| **难度模型** | 每个副本条目必须显式包含其 **全部支持的难度**，而非仅当前角色有 CD 的难度。 |
| **掉落能力** | 首版仅提供 **掉落摘要**（如 `hasMountLoot`），**不**暴露完整 loot 明细列表。 |
| **角色锁定** | 每个难度条目可挂接当前角色的 `lockout`；未锁定时为 `nil`。 |
| **异步构建** | 目录与摘要扫描必须支持分帧后台构建，避免长时间阻塞主线程。 |
| **持久化缓存** | 扫描结果写入 `SavedVariables`，支持补丁/结构版本失效，以及设置页中手动重建。 |
| **设置页能力** | 在 Settings 中提供缓存状态、进度条、进度文本、「重建缓存」按钮，以及调试信息输出到聊天框的开关。 |
| **后续复用** | `ej_mount_filter`、未来的副本详情增强、CD 展示与独立面板等功能，均应消费该目录层，而不是各自复制一套 EJ 扫描逻辑。 |

**首版验收建议**

1. 插件启动后，不打开可见的冒险手册窗口，也能开始后台构建目录缓存。  
2. 缓存构建期间不出现明显长帧卡顿；进度条与进度文本持续更新。  
3. 目录可枚举出冒险手册中的全部地下城 / 团队副本，并为每个副本写出全部支持难度。  
4. 对已完成扫描的副本，`hasMountLoot` 摘要可读；未完成的难度摘要为 `nil`，不得伪造为 `false`。  
5. 角色锁定可映射到对应副本与难度；无锁定的难度 `lockout = nil`。  
6. 点击设置页「重建缓存」后，旧缓存清空，任务从头异步重建，并重新展示进度。  

---

## 2. 术语与主方案

### 2.1 命名

- **DungeonRaidDirectory**：共享目录层 / 领域 API，不是业务模块。  
- **DungeonRaidRecord**：单个副本条目。  
- **difficulty record**：某一副本下某个 `difficultyID` 的难度记录。  

### 2.2 已确认决策

| 议题 | 已选方案 |
|------|----------|
| **领域入口名** | `Toolbox.DungeonRaidDirectory` |
| **目录事实源** | 以 **冒险手册目录** 为准，不做「冒险手册 + 锁定并集」 |
| **主键** | `journalInstanceID` |
| **掉落范围** | 首版仅做 **摘要能力**，如 `hasMountLoot` |
| **角色锁定** | 纳入目录模型，挂在难度记录上 |
| **难度集合** | 记录 **全部支持难度**，不是仅有 CD 的难度 |
| **构建方式** | 后台 **异步分帧**，避免卡主线程 |
| **缓存策略** | **持久化到 SavedVariables** |
| **重建入口** | Settings 中提供「重建缓存」按钮与进度条 |

### 2.3 非目标

- 首版 **不**提供完整 loot 条目树（首领 → 物品列表）。  
- 首版 **不**把目录层直接做成最终 UI 面板。  
- 首版 **不**以现有 `ej_mount_filter` 的会话缓存或同步扫描逻辑作为兼容约束。  

---

## 3. 架构与边界

### 3.1 分层

新增 `Core/DungeonRaidDirectory.lua`，作为地下城 / 团队副本领域的共享目录 API；它应与现有领域 API 并列，而不是作为 `Modules/` 下的业务模块存在。

建议内部采用“两层实现，对外一层接口”的方式：

- **对外公开层**：`Toolbox.DungeonRaidDirectory`
  - 暴露目录查询、构建状态、缓存重建等稳定接口。
- **内部状态助手**：仅供 `DungeonRaidDirectory` 文件内使用
  - 负责维护 Encounter Journal 的选中状态、切换 tier / instance / difficulty / encounter，并在扫描后恢复原状态。

### 3.2 与现有领域 API 的关系

| 领域 API | 关系 |
|------|------|
| `Toolbox.EJ` | **已存在**的冒险手册底层薄门面；负责枚举、状态切换与掉落读取。`DungeonRaidDirectory` 建立在它之上，而不是替代它。 |
| `Toolbox.Lockouts` | 作为角色锁定列表数据源 |
| `Toolbox.MountJournal` | 负责 `itemID -> mountID` 判断 |
| `Toolbox.Chat` | 若需向用户输出重建状态或错误提示，经此输出 |

### 3.3 业务模块边界

后续业务模块不得再各自维护一套副本目录与掉落扫描逻辑：

- `ej_mount_filter` 只消费目录层提供的 `hasMountLoot` 摘要。
- 冒险手册详情增强只消费目录层中的难度与 `lockout` 结果。
- 新模块若需要额外摘要，应优先扩展 `DungeonRaidDirectory`，而不是在模块内直扫 `EJ_*`。

---

## 4. 数据模型

### 4.1 SavedVariables 位置

目录缓存属于跨模块共享的领域数据，不宜放入单个 `modules.<id>`。建议放在：

```lua
ToolboxDB.global.dungeonRaidDirectory = {
  schemaVersion = 1,
  interfaceBuild = 0,
  lastBuildAt = 0,
  tierNames = { ... },         -- [tierIndex] = tierName
  difficultyMeta = { ... },    -- [difficultyID] = { name = "英雄" }
  records = { ... },
}
```

**角色锁定不得写入该持久化缓存。**

原因：当前仓库的 `ToolboxDB` 是账号级 `SavedVariables`；若把 `lockout` 持久化进 `global.dungeonRaidDirectory`，会在多角色间串数据。

### 4.2 单个副本条目

```lua
records[journalInstanceID] = {
  base = {
    journalInstanceID = 1190,
    name = "奈幽巴宫殿",
    kind = "raid",              -- "dungeon" | "raid"
    tierIndex = 10,
    mapID = 2215,
    worldInstanceID = 2648,     -- 能映射时填；首轮构建后可补齐
  },
  difficultyOrder = { 14, 15, 16 },
  difficulties = {              -- 键存在即表示支持该难度
    [14] = {
      hasMountLoot = false,     -- true | false | nil（尚未扫描）
    },
    [15] = {
      hasMountLoot = true,
    },
  },
  summary = {
    hasAnyMountLoot = true,     -- true | false | nil（尚有未扫描难度）
    mountDifficultyIDs = { 15, 16 },
  },
}
```

### 4.3 字段语义

- `base`：稳定基础目录信息；不带角色态。  
- `difficultyOrder`：难度显示顺序；避免依赖 Lua table 的无序遍历。  
- `difficulties`：该副本支持的全部难度集合；**键存在**即表示目录中存在该难度。  
- `hasMountLoot`：
  - `true`：该难度已确认有坐骑掉落
  - `false`：该难度已扫描且无坐骑掉落
  - `nil`：该难度尚未完成摘要扫描
- `summary`：加速读取层，不是事实源；变更时可由 `difficulties` 重算

### 4.4 运行时覆盖层

角色锁定、构建进度与后台任务游标放在运行时层，不写入账号级缓存。建议：

```lua
Toolbox.DungeonRaidDirectory._runtime = {
  state = "idle",              -- idle | building | completed | failed | cancelled
  currentStage = nil,
  totalUnits = 0,
  completedUnits = 0,
  currentLabel = nil,
  isManualRebuild = false,
  token = 0,
  driverFrame = nil,
  recordOrder = {},
  cursor = {},
  lockoutsByJournalInstanceID = {
    [1190] = {
      [15] = {
        instanceId = 2648,
        difficultyId = 15,
        reset = 123456,
        locked = true,
        extended = false,
        encounterProgress = 6,
        numEncounters = 8,
      },
    },
  },
}
```

查询接口若需要返回 `lockout`，应在读取时把运行时覆盖层合并到返回结果中，而不是把角色态回写到持久化缓存里。

### 4.5 内存预算（建议）

按“数百个副本 * 每副本数个难度”的规模，首版应主动压缩存储：

- `tierName` 放入共享 `tierNames` 字典，不在每条记录重复存
- `difficultyName` 放入共享 `difficultyMeta` 字典，不在每个难度条目重复存
- `supported=true` 省略；键存在即表示支持
- `lockout` 不持久化
- 不存完整 loot 明细，只存摘要

**目标预算**

- `SavedVariables` 文本体积：尽量控制在 **500 KB** 以内
- 目录层运行时常驻内存：尽量控制在 **2 MB** 左右

---

## 5. 目录构建与映射策略

### 5.1 基础目录构建

基础目录以 Encounter Journal 为事实源，流程建议如下：

1. 初始化 EJ 运行上下文。  
2. 遍历 `Toolbox.EJ.GetNumTiers()`。  
3. 对每个 `tierIndex` 调 `Toolbox.EJ.SelectTier(tierIndex)`。  
4. 分别对 `isRaid = false` 与 `isRaid = true` 调 `Toolbox.EJ.GetInstanceByIndexFlat(index, isRaid)`，直到返回 `nil`。  
5. 为每条返回值生成 `base` 记录，并写入 `records[journalInstanceID]`。  

### 5.2 支持难度集合

首版不依赖“现成难度列表 API”一次性返回，而采用探测式构建：

1. 选中副本 `SelectInstance(journalInstanceID)`。  
2. 对候选 `difficultyID` 集合逐个判断：
   - `Toolbox.EJ.IsValidInstanceDifficulty(difficultyID)`  
   - `GetDifficultyInfo(difficultyID)` 取难度名称  
3. 判定支持时，建立 `difficulties[difficultyID]` 记录。  

候选难度集合应按 **地下城** / **团队副本** 分组集中在 `DungeonRaidDirectory` 内维护，不允许模块自行复制不同的难度枚举表。

### 5.3 世界副本 ID 与手册 ID 映射

后续锁定映射依赖 `worldInstanceID`，而目录主键为 `journalInstanceID`。两者不得混用。

建议采用“目录先建、映射后补”的策略：

1. 目录骨架构建时，优先从 EJ 可获得的信息中提取 `mapID`、可能的 `instanceID`。  
2. 若首轮无法直接取得 `worldInstanceID`，允许先记为 `nil`。  
3. 在锁定映射阶段，利用已知字段补齐：
   - `worldInstanceID`
   - 名称规范化兜底（仅在必要时）

实现阶段应以单独的小型验证实验确认：

- 在当前 Retail 版本中，`EJ` 哪个接口最稳定地提供世界副本 `instanceID`  
- 若无法稳定取得，名称匹配需要哪些正则化规则  

### 5.4 角色锁定映射

遍历 `Toolbox.Lockouts.GetNumSavedInstances()` 与 `Toolbox.Lockouts.GetSavedInstanceInfo(index)`：

1. 读取 `instanceId`、`difficultyId`、`reset`、`locked`、`extended`、`numEncounters`、`encounterProgress`。  
2. 通过 `worldInstanceID -> journalInstanceID` 映射定位目录条目。  
3. 若目录条目存在，且对应 `difficultyID` 已在 `difficulties` 中声明支持，则写入运行时层 `lockoutsByJournalInstanceID[journalInstanceID][difficultyID]`。  
4. 若目录条目存在但该难度尚未出现在 `difficulties` 中，记录为异常映射并留日志 / debug 入口，避免静默吞掉。  

锁定刷新不属于“昂贵摘要缓存”的一部分；建议在以下时机轻量刷新：

- 登录后
- 目录构建完成后
- `UPDATE_INSTANCE_INFO`
- 玩家手动请求刷新锁定信息时

---

## 6. 掉落摘要与 EJ 状态维护

### 6.1 掉落摘要范围

首版仅维护以下摘要：

- `hasMountLoot`
- `summary.hasAnyMountLoot`
- `summary.mountDifficultyIDs`

首版不缓存完整 loot 条目明细，不存每个首领掉什么物品列表。

### 6.2 扫描原则

掉落摘要扫描基于 Encounter Journal 的“全局选中状态”工作，不以“可见 UI 已打开”作为前提。实现时需显式维护并恢复以下状态：

- 当前 selected tier
- 当前 selected instance
- 当前 selected difficulty
- 当前 selected encounter
- 可能影响战利品视图的过滤状态

扫描单个副本难度的建议流程：

1. 保存当前 EJ 状态。  
2. `SelectTier` → `SelectInstance` → `SetDifficulty`。  
3. 读取 `GetNumEncounters()`、`GetNumLoot()`、`GetLootInfoByIndex()`。  
4. 用 `Toolbox.MountJournal.GetMountFromItem(itemID)` 判断是否为坐骑。  
5. 写回该难度的 `hasMountLoot`。  
6. 恢复之前保存的 EJ 状态。  

### 6.3 EJ 状态助手（内部）

建议在 `DungeonRaidDirectory.lua` 文件内维护一个私有助手，例如 `EJStateDriver`，集中收口以下能力：

- `Initialize()`：确保 `Blizzard_EncounterJournal` 已加载，并初始化 Journal 运行上下文
- `Capture()`：保存当前 tier / instance / difficulty / encounter 等必要状态
- `Restore(snapshot)`：按固定顺序恢复之前状态
- `WithSnapshot(workFn)`：执行一个最小工作单元，并在结束后无条件恢复状态

推荐恢复顺序：

1. `SelectTier`
2. `SelectInstance`
3. `SetDifficulty`
4. `SelectEncounter`

后续所有重任务（难度探测、mount 摘要扫描）均应包在 `WithSnapshot(workFn)` 中，避免分支漏恢复。

### 6.4 对旧实现的约束

后续实现不得假设：

- 必须依赖 `EncounterJournal_ListInstances` 的可见列表  
- 必须依赖 `instanceSelect` 当前显示  
- 必须依赖现有 `EJMountFilter.lua` 的同步扫描与行隐藏逻辑  

该目录层是新的事实源；现有筛选模块后续应改为消费其结果。

---

## 7. 异步分帧构建

### 7.1 总体策略

目录构建必须拆成阶段，并按帧预算推进，避免单帧全量扫完：

1. **目录骨架阶段**：遍历 tier 与实例，写入 `base`  
2. **难度探测阶段**：为每个副本写出全部支持难度  
3. **掉落摘要阶段**：逐副本逐难度构建 `hasMountLoot`  

角色锁定刷新不放进重建主流水线；其成本较低，应在缓存载入或重建完成后单独刷新到运行时层。

### 7.2 构建状态机

建议状态：

- `idle`
- `building`
- `completed`
- `failed`
- `cancelled`

建议额外记录：

- `currentStage`
- `totalUnits`
- `completedUnits`
- `currentLabel`（当前副本名 / 阶段说明）
- `isManualRebuild`
- `token`（取消旧任务 / 防止过期回调继续写入）

### 7.3 调度方式

按仓库约束，禁止以固定秒级 `C_Timer.After(正数秒, …)` 作为“等布局”的主路径；但这里的后台构建并非“等 UI”，而是任务分帧，允许采用：

- `C_Timer.After(0, nextStep)`  
- 或 `OnUpdate` 驱动的帧预算执行器

**推荐** 使用隐藏 `Frame` 的 `OnUpdate` 驱动器，并以 `debugprofilestop()` 控制每帧预算。实现时应在注释中明确其用途是“任务分帧”，而不是“等待手册布局”。

### 7.4 未完成状态语义

异步构建期间，不得把“尚未扫描”误写为“确定没有”：

- `hasMountLoot = nil` 表示未知
- `summary.hasAnyMountLoot = nil` 表示存在未完成难度，当前无法下结论

业务模块必须能区分 `nil` 与 `false`。

### 7.5 具体实现建议

推荐采用“**游标式状态机**”而不是预展开的超大任务队列，以减少额外内存：

```lua
_runtime.cursor = {
  phase = "skeleton",
  tierIndex = 1,
  kindIndex = 1,          -- 1 = dungeon, 2 = raid
  instanceIndex = 1,
  recordIndex = 1,
  difficultyIndex = 1,
}
```

每帧只处理少量“最小工作单元”：

- `ProcessSkeletonUnit()`：枚举一个副本并写入 `base`
- `ProcessDifficultyUnit()`：探测一个 `(journalInstanceID, difficultyID)` 是否支持
- `ProcessMountSummaryUnit()`：扫描一个 `(journalInstanceID, difficultyID)` 的 `hasMountLoot`

推荐的 `OnUpdate` 驱动伪代码：

```lua
local BUILD_BUDGET_MS = 4

driver:SetScript("OnUpdate", function()
  local startMs = debugprofilestop()
  while _runtime.state == "building" do
    local done, err = AdvanceOneUnit()
    if err then
      FailBuild(err)
      break
    end
    if done then
      FinishBuild()
      break
    end
    if debugprofilestop() - startMs >= BUILD_BUDGET_MS then
      break
    end
  end
end)
```

其中：

- `AdvanceOneUnit()` 根据 `currentStage` 分派到对应的 `Process*Unit`
- 每个 `Process*Unit` 最多只处理一个实例或一个难度
- 涉及 EJ 状态切换的工作单元，应包在 `EJStateDriver.WithSnapshot(workFn)` 内

### 7.6 进度条与设置页

Settings 不直接感知构建细节，只读取：

```lua
Toolbox.DungeonRaidDirectory.GetBuildProgress()
```

建议返回：

```lua
{
  state = "building",
  currentStage = "mount_summary",
  totalUnits = 1800,
  completedUnits = 945,
  percent = 0.525,
  currentLabel = "奈幽巴宫殿 / 英雄",
  isManualRebuild = false,
}
```

设置页按固定频率（如 `0.1s`）刷新：

- 状态文本
- 进度条百分比
- 当前阶段
- 当前副本 / 难度标签

---

## 8. 缓存持久化与重建

### 8.1 SavedVariables 结构

建议：

```lua
ToolboxDB.global.dungeonRaidDirectory = {
  schemaVersion = 1,
  interfaceBuild = 120205,
  lastBuildAt = 1712131200,
  tierNames = { ... },
  difficultyMeta = { ... },
  records = { ... },
}
```

### 8.2 失效条件

下列情况触发缓存失效并重建：

- `interfaceBuild` 变化  
- `schemaVersion` 变化  
- 用户在 Settings 中点击「重建缓存」

若上次会话结束时持久化状态仍为 `building`，本次加载应视为“上次构建中断”，不得把旧的 `building` 当作有效完成态；实现可选择：

- 启动后自动重新进入 `building`
- 或先重置为 `idle`，再由初始化流程重新启动构建

### 8.3 重建行为

点击「重建缓存」时：

1. 取消当前构建任务（若有）  
2. 清空旧缓存  
3. 重新进入 `building` 状态  
4. 重置进度条与阶段文本  
5. 递增 `token`，使旧回调自动失效  
6. 启动新的异步构建流程  

### 8.4 最小设置项

Settings 中建议至少提供：

- 状态文本：未构建 / 构建中 / 已完成 / 失败  
- 进度条  
- 当前阶段与当前副本名  
- 「重建缓存」按钮  

文案走 `Toolbox.L`，归入 `settingsGroupId = "misc"`。

---

## 9. 对外接口（建议）

### 9.1 构建与状态

- `Toolbox.DungeonRaidDirectory.Initialize()`  
- `Toolbox.DungeonRaidDirectory.StartBuild(isManual)`  
- `Toolbox.DungeonRaidDirectory.CancelBuild()`  
- `Toolbox.DungeonRaidDirectory.GetBuildState()`  
- `Toolbox.DungeonRaidDirectory.GetBuildProgress()`  
- `Toolbox.DungeonRaidDirectory.RebuildCache()`  
- `Toolbox.DungeonRaidDirectory.RefreshLockouts()`  

### 9.2 目录查询

- `Toolbox.DungeonRaidDirectory.ListAll()`  
- `Toolbox.DungeonRaidDirectory.GetByJournalInstanceID(journalInstanceID)`  
- `Toolbox.DungeonRaidDirectory.ListByKind(kind)`  
- `Toolbox.DungeonRaidDirectory.ListByTier(tierIndex)`  

### 9.3 摘要读取

- `Toolbox.DungeonRaidDirectory.GetDifficultyRecords(journalInstanceID)`  
- `Toolbox.DungeonRaidDirectory.GetMountSummary(journalInstanceID)`  
- `Toolbox.DungeonRaidDirectory.HasAnyMountLoot(journalInstanceID)`  
- `Toolbox.DungeonRaidDirectory.GetLockoutSummary(journalInstanceID)`  

接口返回值应明确 `nil` 的语义，避免业务层把“未构建完成”误当作“确定没有”。若接口返回 `lockout`，应理解为“持久化目录缓存 + 运行时锁定覆盖层”的合成视图，而不是数据库原样结构。

---

## 10. 与后续功能的集成

### 10.1 `ej_mount_filter`

后续应迁移为：

- 只关心当前列表每个 `journalInstanceID`
- 调 `DungeonRaidDirectory.HasAnyMountLoot(journalInstanceID)`
- `nil` 时先显示该行
- `false` 时隐藏
- `true` 时显示

不再自行扫描 EJ 掉落或维护私有掉落缓存。

### 10.2 冒险手册详情增强

未来可直接复用：

- 当前副本的全部支持难度
- 当前角色各难度 `lockout`
- `hasMountLoot` 摘要

### 10.3 独立面板或其它模块

只要围绕“地下城 / 团队副本目录”工作，均应优先复用该层，而不是跨模块访问别人的 `modules.<id>` 存档。

---

## 11. 文件与文档改动建议

### 11.1 代码文件

- `Toolbox/Core/DungeonRaidDirectory.lua` — 新领域 API
- `Toolbox/Core/DB.lua` — 新增 `global.dungeonRaidDirectory` 默认值
- `Toolbox/Core/Locales.lua` — 新增设置页与进度条文案
- `Toolbox/UI/SettingsHost.lua` — 新增目录缓存状态区与重建按钮
- `Toolbox/Toolbox.toc` — 插入新 Core 文件，加载顺序在 `ModuleRegistry.lua` 之前或与其它领域 API 相邻

### 11.2 文档

实现完成后需更新：

- `docs/Toolbox-addon-design.md`
  - 鸟瞰图
  - §2.1 领域对外 API 表
  - §2.2 模块 / 能力映射
  - §3 数据模型示例
  - §6 TOC 顺序
- 若 `ej_mount_filter` 改为消费目录层，其规格应同步更新“数据来源与缓存策略”描述

---

## 12. 风险与待验证项

### 12.1 主要风险

- **EJ 状态维护复杂**：扫描过程中若未正确恢复，会污染玩家之后打开手册时的选中状态。  
- **账号级缓存与角色态混存**：若误把 `lockout` 写进 `global`，会导致多角色串数据。  
- **世界副本 ID 映射**：`journalInstanceID` 与锁定 `instanceId` 不是同一 ID，映射策略必须在实现前做小型验证。  
- **异步预算**：预算过小会让首次构建过慢；预算过大则会卡顿。  
- **补丁变更**：新资料片或手册实现变化后，候选难度集合与映射字段可能变化。  

### 12.2 实现前小实验（建议）

1. 在不打开可见 EJ 窗口时，验证：
   - 初始化 `EncounterJournal` 运行上下文
   - `SelectTier` / `SelectInstance` / `SetDifficulty`
   - `GetNumLoot` / `GetLootInfoByIndex`
2. 验证最稳定的 `worldInstanceID` 提取路径。  
3. 验证候选 `difficultyID` 集合在当前 Retail 版本中的有效性。  

---

## 13. 设计结论

`Toolbox.DungeonRaidDirectory` 首版应作为新的共享目录层落地：  
以冒险手册目录为事实源，目录主键为 `journalInstanceID`；每个副本显式包含全部支持难度，并在后台异步构建掉落摘要。缓存持久化到账号级 `SavedVariables`，但角色锁定仅保留在运行时覆盖层；设置页提供进度条与手动重建缓存入口。`Toolbox.EJ` 继续保持已有薄门面角色，`DungeonRaidDirectory` 建立在其之上，作为以后所有“冒险手册增强”功能的共享目录层。
