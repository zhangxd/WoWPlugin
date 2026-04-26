# 地图导航模块设计

- 文档类型：设计
- 状态：已确认
- 主题：navigation
- 适用范围：`navigation` 新模块、导航领域 API、路径数据与顶部路径 UI
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 背景

- `encounter_journal` 已有副本入口 waypoint 能力，但它只服务副本列表条目，不负责通用旅行规划。
- 新需求面向世界地图任意目标，需要综合当前角色职业能力、传送门、炉石、主城与地图距离生成路线。
- 该能力有独立入口、独立 UI、独立存档和独立算法边界，适合作为新模块接入。

## 2. 设计目标

- 建立独立 `navigation` 模块，避免把旅行规划逻辑塞进 `quest`、`encounter_journal` 或 `mover`。
- 建立清晰的路径图模型：节点、边、边权、可用性过滤和最短路径求解分层。
- 第一版能用保守数据给出稳定路线，而不是因未知能力误推荐不可用路径。
- 顶部路径 UI 简洁展示每个地点 / 步骤，先解决“该怎么走”，不做复杂地图内动画。
- 数据维护可演进：基础地图数据走契约导出，玩法路径边人工维护并可逐步扩充。

## 3. 非目标

- 不实现账号级跨角色能力推断。
- 不把飞行点纳入第一版路径图。
- 不实现真实地形寻路、避障或逐米路线。
- 不承诺一次覆盖所有职业、玩具、节日传送或低频交通。
- 不通过固定正数秒 `C_Timer.After` 等待世界地图布局。

## 4. 方案对比

### 4.1 方案 A：并入 `quest` 模块

- 做法：在 `quest` 的地图 / 任务线导航中增加目的地路线推荐。
- 优点：能复用现有任务 UI 与部分地图数据。
- 风险 / 缺点：需求本身面向世界地图任意坐标，不限任务；并入后会让 `quest` 承担旅行规划、职业能力和交通网络，模块边界失真。

### 4.2 方案 B：新建独立 `navigation` 模块

- 做法：新增 `navigation` 模块与导航领域 API，世界地图入口、顶部路径 UI、路径图、可用性过滤和存档都归属该模块。
- 优点：边界清晰，可独立启停、独立测试、独立扩展；后续 `quest` 或 `encounter_journal` 也可以调用导航能力而不反向依赖。
- 风险 / 缺点：需要新增 TOC 行、存档默认值、设置页、本地化和新模块文档。

### 4.3 方案 C：只调用暴雪 waypoint / SuperTrack

- 做法：世界地图选中目标后只设置系统 waypoint，依赖暴雪导航箭头。
- 优点：实现成本低。
- 风险 / 缺点：无法表达法师传送、传送门房、炉石、主城枢纽等“先大段位移再走过去”的路径，也无法满足完整跨地图路径规划需求。

### 4.4 选型结论

- 选定方案：方案 B。
- 选择原因：该需求已经具备独立模块、独立玩家可见 UI 和独立数据模型；只有独立 `navigation` 才能保持模块边界清晰，并为后续其它模块复用留下稳定接口。

## 5. 选定方案

### 5.1 模块与文件结构

| 文件 | 职责 |
|------|------|
| `Toolbox/Core/API/Navigation.lua` | 导航领域 API：路径图构建、可用性过滤、边权计算、Dijkstra 求解、调试快照。 |
| `Toolbox/Modules/Navigation.lua` | `navigation` 模块注册、设置页、世界地图挂接、顶部路径 UI 生命周期。 |
| `Toolbox/Modules/Navigation/Shared.lua` | 模块内共享命名空间、DB 访问、启用状态判断。 |
| `Toolbox/Modules/Navigation/WorldMap.lua` | 世界地图目标选择入口；查证并封装 `C_Map` / WorldMapFrame 相关调用。 |
| `Toolbox/Modules/Navigation/RouteBar.lua` | 顶部中间路径 UI，负责显示步骤、清除路线、刷新布局。 |
| `Toolbox/Data/NavigationMapNodes.lua` | DB2 / WoWDB 导出的地图基础节点或区域节点，需对应 `DataContracts` 契约。 |
| `Toolbox/Data/NavigationManualEdges.lua` | 人工维护玩法路径边：职业传送、传送门房、炉石类能力、主城与资料片枢纽。 |
| `DataContracts/navigation_map_nodes.json` | 地图基础节点导出契约。 |

说明：

- 文件拆分可在实施时按实际复杂度收缩，但 `Core/API/Navigation.lua` 与 `Modules/Navigation.lua` 的 API / 模块边界必须保留。
- 若第一版人工维护边不适合放在 `Toolbox/Data`，可以先放在 `Toolbox/Modules/Navigation/Data.lua`；但玩家路径数据若需要跨模块复用，应尽早迁入 `Toolbox/Data`。

### 5.2 路径图模型

- 节点：
  - 当前角色当前位置。
  - 世界地图目标坐标或地图区域中心点。
  - 主城、资料片枢纽、传送门房、职业传送落点、炉石落点。
  - 地图内抽象连接点，例如目标地图入口或区域中心。
- 边：
  - 地图内移动边：按地图距离估算耗时。
  - 职业技能边：例如法师传送 / 传送门。
  - 炉石类边：普通炉石、特殊炉石或同类能力。
  - 传送门房 / 枢纽边：人工维护可达关系。
- 边权：
  - 读条时间。
  - 交互 / 换乘固定成本。
  - 地图内距离估算成本。
  - 跨地图加载时间明确不计入成本。
- 求解：
  - 第一版使用 Dijkstra。路径图规模可控，Dijkstra 更透明，也便于逻辑测试。
  - 后续若地图节点规模明显增大，再评估 A*。

### 5.3 可用性过滤

- 可用性来源只看当前角色：
  - 职业：例如 `UnitClass("player")`。
  - 阵营：例如 `UnitFactionGroup("player")`。
  - 已学技能：实现前必须查证 `C_Spell` 或替代 API。
  - 玩具 / 道具：实现前必须查证 `C_ToyBox`、背包或 spell 触发能力 API。
- 已查证 API：
  - [`UnitClass`](https://warcraft.wiki.gg/wiki/API_UnitClass)：用于获取当前角色职业文件名，例如 `MAGE`。
  - [`UnitFactionGroup`](https://warcraft.wiki.gg/wiki/API_UnitFactionGroup)：用于获取当前角色阵营，例如 `Horde` / `Alliance`。
  - [`C_SpellBook.IsSpellInSpellBook`](https://warcraft.wiki.gg/wiki/API_C_SpellBook.IsSpellInSpellBook)：Retail 推荐的 spellbook 查询入口；第一版职业传送技能可用性优先使用该 API。
  - [`C_SpellBook.IsSpellKnown`](https://warcraft.wiki.gg/wiki/API_C_SpellBook.IsSpellKnown)：旧查询入口；仅作为 `IsSpellInSpellBook` 缺失时的兼容兜底。
  - [`C_Map.GetPlayerMapPosition(uiMapID, unitToken)`](https://warcraft.wiki.gg/wiki/API_C_Map.GetPlayerMapPosition)：Warcraft Wiki 标注该函数在部分区域不可用；后续当前位置获取必须允许失败并走保守兜底。
  - [`C_Map.GetBestMapForUnit(unitToken)`](https://warcraft.wiki.gg/wiki/API_C_Map.GetBestMapForUnit)：用于获得当前角色所在 `uiMapID`；第一版将其写入可用性快照，以便把“我现在就在银月城 / 奥格瑞玛 / 职业大厅”等场景作为零成本起点边。
  - `WorldMapFrame:GetMapID()` 与 `WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()`：第一版只在 `WorldMapFrame` 存在且对应方法存在时调用；失败时不规划路线。该交互仍列入游戏内复测项。
- 保守策略：
  - 无法确认当前角色可用的边不进入路径图。
  - API 不存在、返回失败或数据缺失时，边视为不可用。
  - 可用性失败不弹 Lua 错；必要时通过调试开关输出 `Toolbox.Chat` 调试信息。

### 5.4 世界地图入口

- 主入口：
  - 绑定 `WorldMapFrame` 生命周期，优先使用 `HookScript("OnShow", ...)` 创建或刷新导航入口。
  - 第一版不拦截世界地图原生点击，而是在 `WorldMapFrame` 显示后创建“规划路线”按钮；玩家把鼠标放在目标点上点击按钮，模块读取 `WorldMapFrame:GetMapID()` 与 `WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()` 作为目标。
- 禁止：
  - 不用固定正数秒 `C_Timer.After` 作为等待世界地图控件或布局的主路径。
  - 不在 combat lockdown 中操作受保护框体。
- 第一版 UI 行为建议：
  - 世界地图按钮点击后，模块生成当前路线并更新顶部路径 UI。
  - 如需要在地图上放置系统 waypoint，必须作为辅助动作，且 API 查证后再接入。

### 5.5 顶部路径 UI

- 位置：
  - 屏幕顶部中间。
  - 作为 `navigation` 模块自有非保护 Frame，不嵌入世界地图正文。
- 内容：
  - 按顺序显示每个地点 / 步骤。
  - 每个步骤包含动作类型、地点名和可选耗时估算。
  - 第一版至少能清除当前路线。
- 生命周期：
  - 模块启用且有路线时显示。
  - 模块禁用、路线清除或无路线时隐藏。
  - 若后续加入 `OnUpdate`，必须节流并在禁用时清理；第一版不需要每帧逻辑。

### 5.6 设置与存档

`ToolboxDB.modules.navigation` 第一版建议字段：

| 字段 | 含义 |
|------|------|
| `enabled` | 公共启用开关，由模块框架维护。 |
| `debug` | 公共调试开关，由模块框架维护。 |
| `lastTargetUiMapID` | 最近一次目标地图 ID，用于调试和恢复。 |
| `lastTargetX` | 最近一次目标坐标 X，0 到 1。 |
| `lastTargetY` | 最近一次目标坐标 Y，0 到 1。 |

说明：

- 新字段必须写入 `Core/Foundation/Config.lua` 默认值，并补迁移。
- 第一版路径条固定在顶部中间，不保留未消费的位置锁定存档字段；后续若开放拖动，再接入 Mover 或模块内位置存档。

### 5.7 本地化与玩家输出

- 玩家可见字符串统一放入 `Toolbox/Core/Foundation/Locales.lua`。
- 聊天输出必须通过 `Toolbox.Chat`。
- 路线步骤名称优先使用本地化地点名；静态数据中应提供 `name_lang` 或同等字段，缺失时用 ID 兜底。

## 6. 影响面

- 数据与存档：
  新增 `ToolboxDB.modules.navigation`；新增地图基础数据契约与人工维护路径边。
- API 与模块边界：
  新增 `Toolbox.Navigation` 领域 API；`navigation` 模块只负责入口、设置和 UI。
- 文件与目录：
  需要新增 Core API、模块文件、可能的模块子目录、Data 文件、DataContracts 契约、测试文件，并修改 TOC、Config、Locales、Settings 相关验证。
- 文档回写：
  落地后必须更新 `docs/Toolbox-addon-design.md`、`docs/FEATURES.md`、`docs/features/navigation-features.md` 与对应测试文档。

## 7. 风险与回退

- 风险：
  WoW 地图和 spell / toy API 存在版本差异；未经查证直接实现容易导致正式服报错。
- 缓解：
  实现前逐项查证 API，并对不稳定 API 使用存在性判断或 `pcall`。
- 风险：
  人工维护路径边数据不全会导致路线偏保守。
- 缓解：
  第一版明确保守策略，不把未知边推荐为首选；逐步扩充高价值边。
- 风险：
  世界地图点击或 pin 挂接若选错生命周期，可能出现偶发不显示。
- 缓解：
  使用 `OnShow`、可靠地图事件或经查证的 post-hook，不用固定正数秒延迟等布局。
- 回退：
  模块可通过设置页禁用；禁用时注销事件、隐藏顶部路径 UI，并不影响 `quest`、`encounter_journal` 与现有 waypoint 功能。

## 8. 验证策略

- 逻辑测试：
  - Dijkstra 按最小耗时选择路线。
  - 未知可用性边被过滤。
  - 法师奥格瑞玛 / 银月城 / 雷霆崖 / 幽暗城 / 沙塔斯城等已确认主城传送优先于纯地图内移动。
  - 当前位置为手工枢纽节点时，可使用公共传送门网络继续规划。
  - 死亡骑士、德鲁伊、武僧等已确认职业位移边可作为独立入口参与求解。
  - 非对应职业或未确认技能时不使用对应职业边。
- 配置测试：
  - `ToolboxDB.modules.navigation` 默认值和迁移存在。
  - 设置子页面注册校验通过。
- 数据测试：
  - `DataContracts/navigation_map_nodes.json` 与生成文件头校验通过。
  - 人工维护边不包含无法解析的节点 ID。
- 游戏内验证：
  - 世界地图目标选择后顶部路径 UI 出现。
  - 路径步骤顺序可读，清除路线后 UI 隐藏。
  - 战斗中不触发受保护 UI 错误。
- 总验证：
  - `python tests/run_all.py --ci`

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：确认新建 `navigation` 模块、混合数据源、Dijkstra 路径图与顶部路径 UI 设计 |
