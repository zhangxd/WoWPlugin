# 地图导航模块需求规格

- 文档类型：需求
- 状态：已确认
- 主题：navigation
- 适用范围：`navigation` 模块的世界地图目标选择、跨地图路径规划与顶部路径 UI
- 关联模块：`navigation`
- 关联文档：
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-29（实现/导出对齐，统一边表基线同步到 v17）

## 1. 背景

- 玩家要的不是“打开目标地图”或“只设置系统 waypoint”，而是“从当前角色当前位置到目标点该怎么走”。
- 路线需要支持多模态旅行：本地步行、飞行点、传送门、船 / 飞艇、炉石和职业传送。
- 最终结果必须能解释路径过程：中间经过哪些地图、每一段通过什么方式抵达。
- 当前项目优先使用静态导出数据批量构图，只把当前角色配置和当前用户 waypoint 放在运行时处理。

## 2. 目标

- 新增独立 `navigation` 模块，负责世界地图目标选择、路线图构建、当前角色可用性过滤、最短路径求解与路线 UI 展示。
- 最短路主指标明确为“最少路径步数”。
- 第一版先交付一条稳定闭环：`walk_local + taxi + hearthstone + class_teleport + class_portal`。
- 路线输出必须展示每一段的方式、起终点和经过地图序列。
- 运行时静态数据只允许来自 DataContracts 契约导出，不允许手工补导航边。

## 3. 范围

### 3.1 In Scope

- 新建 `navigation` 模块，模块 id 为 `navigation`。
- 世界地图以当前用户 waypoint 作为目标点入口。
- 路线计算按当前角色配置裁剪，至少读取：
  - `Faction`
  - `Class`
  - `KnownSpellIDs`
  - `KnownTaxiNodeIDs`
  - `HearthBindNodeID`
- 路线主排序规则为“最少路径步数”。
- 当前实现支持以下路线模式：
  - `walk_local`
  - `taxi`
  - `transport`
  - `public_portal`
  - `hearthstone`
  - `class_teleport`
  - `class_portal`
- `class_portal` 在“当前角色自己使用自己开的门”这个语义下记为一条可执行路线边。
- 连续本地步行在图里允许拆分，在最终输出里必须压缩显示为一段 `walk`。
- 统一运行时静态边只允许来自导出契约；来源侧允许保留追溯契约，但运行时不能直接消费来源边表。
- `hearthstone / class_teleport / class_portal` 的模板定义也必须来自导出契约，不得在运行时代码里手工维护“法术 -> 目的地”关系。
- `taxi` 边必须保留经过地图序列。
- 顶部路径 UI 显示在屏幕顶部中间位置，至少展示：
  - 总步数
  - 每段方式
  - 每段起点 / 终点
  - 每段经过地图

### 3.2 Out of Scope

- 账号级跨角色能力推断。
- 战斗状态、沉默状态、技能 CD 是否转好等瞬时条件。
- 全世界真实地形寻路、避障、逐米路径与碰撞网格。
- `areatrigger` 和完整世界 `WalkComponent`。
- 第一版内的账号共享玩具、节日传送、工程道具和一次性剧情位移。
- 对“只能飞 / 没有别的公共路径”这类排除法结论的正式判定。

## 4. 已确认决策

- 路线按“当前角色配置”计算，不按“理论拥有所有能力”计算。
- 最短路主指标选定为“路径步数”，不是预计耗时。
- 每次“完成的移动方式”记 1 步，不按按键次数记步。
- 当前角色自用 `class_portal` 记 1 步。
- 同一可步行连通域内的一段本地移动记 1 步。
- 连续 `walk` 在最终输出里压缩为一段。
- 平局规则固定为：
  1. 更少的 `walk` 段数优先；
  2. 更短的本地步行总距离优先；
  3. 更少的步骤名称切换优先；
  4. 最后按稳定 ID 排序。
- 世界关系按“枢纽 + 动作边”表达，不再按“地图是否相邻”表达。
- `silvermoon -> borean tundra` 这类世界级路线允许先用角色能力到主城，再换公共交通。
- 运行时静态数据继续只允许来自 DataContracts 导出；不得用手工导航边补洞。
- `only_taxi`、`must_use_transport`、`no_public_route` 等强结论要等所有相关模态闭合后再引入。

## 5. 导出与运行时边界

- 当前运行时静态数据消费入口为：
  - `navigation_route_edges`
  - `navigation_map_nodes`
  - `navigation_ability_templates`
- `navigation_taxi_edges` 保留为 Taxi 来源侧追溯数据，不直接参与运行时构图。
- `navigation_ability_templates` 负责导出 `hearthstone` 和职业旅行能力的模板定义；运行时只按当前角色配置展开，不手写法术目的地表。
- 当前角色状态与查询点细化允许使用运行时 API，但只限于：
  - 已开航点：`C_TaxiMap.GetTaxiNodesForMap`
  - 炉石绑定点：`GetBindLocation`
  - 当前点 / 目标点命中的更具体地图：`C_Map.GetMapInfoAtPosition`
- `transport`、`public_portal`、`areatrigger`、`道标石` 只有在目标端点静态闭合后，才允许进入统一运行时静态边表。
- 旧的 `targetRules` / `WAYPOINT_LINK` 运行时旁路已经移除；路线真值不再依赖它们。
- 当前仓库默认导出基线已经推进到 `navigation_route_edges` schema v17，统一边表可包含 `taxi / transport / public_portal`；`areatrigger` 仍为占位，不参与实际可达路径。
- 如果需要“严格 V1-only”导出结果，必须另设冻结契约或独立输出，不能继续和当前统一边表共用同一份 `NavigationRouteEdges.lua`。
- `walk` 不允许再由地图矩形、`UiMap` 父链或视觉相邻关系推导，必须等待独立连通规则。

### 5.1 当前无路由样例口径

- 对 `银月城 (110) -> 东瘟疫之地 (23)`，当前默认导出基线的期望结果是 `NAVIGATION_ERR_NO_ROUTE`。
- 该结果表示：现有静态导出图尚未闭合出一条可证明路线；不表示系统已经静态证明“游戏内无法到达”。
- 运行时不得因为以下事实存在就擅自补全路线：
  - `uimap_94` 与 `uimap_95` 在视觉上接壤
  - `portal_118`、`portal_556` 节点已经导出
  - `taxi_82` 节点已经导出
- 只有在对应 `walk` 连通规则、portal edge 或 taxi edge 被正式导出进 unified graph 后，这条路线才允许从 `no route` 变为可达。

## 6. 验收标准

1. 世界地图存在当前用户 waypoint 时，可以基于该 waypoint 生成导航路线；没有 waypoint 时不生成路线。
2. 查询输入支持当前角色配置，至少包含职业、阵营、已学法术、已开航点和炉石绑定点。
3. 路线主求解器按最少步数收敛，而不是按预计耗时排序。
4. 当前路线可同时消费：
   - `taxi`
   - `transport`
   - `public_portal`
   - `hearthstone`
   - `class_teleport`
   - `class_portal`
   - 起点 / 终点本地接入
5. 未满足职业、阵营、已学法术或已开航点条件的边不会进入求解。
6. `taxi` 段输出中包含经过地图序列。
7. 顶部路径 UI 显示总步数，并逐段展示方式、起终点和经过地图。
8. 连续本地步行在最终输出里被压缩为一段 `walk`。
9. 同步存在多条同步数路径时，按“更少 walk -> 更短本地步行 -> 更稳定 ID”打破平局。
10. 对 `奥利波斯 -> 晋升堡垒` 这类当前已闭合的 `taxi` 样例，系统能给出包含经过地图的 `taxi` 路径。
11. 对 `hearthstone` 和职业旅行能力，系统只在当前角色配置满足时展开对应边。
12. 涉及未使用过或记忆不确定的 WoW API 时，先核对 BlizzardInterfaceCode / Warcraft Wiki / 官方资料后实现。
13. 战斗中不执行会触发 taint 的受保护 UI 操作。

## 7. 实施状态

- 本规格自 2026-04-29 起，成为 `navigation` 的新需求基线。
- 当前实现已经完成“统一导出驱动 + 最少步数求解”的主干收敛：
  - 运行时不再直接消费 `NavigationManualEdges.lua`、`NavigationTaxiEdges.lua`、`NavigationUiMapRelations.lua`、`NavigationWaypointEdges.lua`
  - 统一边表默认基线已同步到 `navigation_route_edges` schema v17
  - `public_portal` 已进入统一边表并参与运行时求解
  - `areatrigger` 仍只有契约骨架与占位节点，不参与实际路径
  - `targetRules` / `WAYPOINT_LINK` 旧旁路已从运行时判断中移除
- 2026-04-27 的旧实现计划和旧文档仍保留为历史追溯，但它们基于“预计耗时 + Dijkstra + 旧范围”的口径。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：按用户确认建立 `navigation` 新模块需求，状态设为可执行 |
| 2026-04-27 | 复审修订：目标源改为用户 waypoint，明确 `x/y` 进入成本模型，排除 tooltip 修改，并将 EncounterJournal 性能修复列为待确认关联项 |
| 2026-04-27 | 数据源规则收紧：所有 navigation 运行时数据必须由 DataContracts 契约导出，移除 `NavigationManualEdges.lua` 的运行时消费与 TOC 加载 |
| 2026-04-27 | 路线边统一导出：新增 `navigation_route_edges` 契约，运行时构图统一消费 `NavigationRouteEdges.lua`，来源侧 `NavigationTaxiEdges.lua` 不再被 `Toolbox.Navigation` 直接读取 |
| 2026-04-29 | 规格基线重定义：路线改为”当前角色配置 + 最少步数”；V1 先支持 `walk_local / taxi / hearthstone / class_teleport / class_portal`，世界级 `transport / public_portal / areatrigger / walk component` 延后到后续阶段 |
| 2026-04-29 | V2 推进：`transport`（飞艇/船）正式进入 In Scope，导出脚本增加 transport 检测与 `mode = “transport”` 输出 |
| 2026-04-29 | V2 推进：`public_portal` 方案确认，waypoint 管道接入统一静态边表 |
| 2026-04-29 | 文档同步：运行时基线对齐当前实现，明确默认统一边表已推进到 schema v17，`public_portal` 已参与求解，`areatrigger` 仍为占位，旧 `targetRules / WAYPOINT_LINK` 旁路已移除 |
| 2026-04-29 | 边界样例同步：固定 `银月城 -> 东瘟疫之地` 当前期望为 `NAVIGATION_ERR_NO_ROUTE`，并明确这代表导出图未闭合，而不是静态证明游戏内不可达 |
