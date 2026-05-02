# 地图导航模块需求规格

- 文档类型：需求
- 状态：可执行
- 主题：navigation
- 适用范围：`navigation` 模块的世界地图目标选择、跨地图路径规划与顶部路径 UI
- 关联模块：`navigation`
- 关联文档：
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-05-02（用户确认开动；补充 local topology 分层模型、删除 WalkCluster runtime 真值与无兼容收口）

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
- 玩家可见路线链必须先由 `semantic path` 归一化，再交给 RouteBar 与规划诊断输出消费。
- `semantic path` 默认按 `地图节点 -> 动作节点 -> 地图节点` 交替组织。
- `walk_local` 只负责把起点、终点和交通落点接入同一 `WalkComponent`，不直接显示成玩家节点。
- `taxi` 保留为有效 segment 和记步来源，但不单独生成飞行点动作节点。
- `transport / public_portal / hearthstone / class_teleport / class_portal` 需要生成玩家可见动作节点，且动作节点文案必须表示“前往目标地图的动作”，不能泄漏返程名或技术方向节点名。
- 顶部路径 UI 显示在屏幕顶部中间位置，至少展示：
  - 总步数
  - 每段方式
  - 每段起点 / 终点
  - 每段经过地图
- 顶部路径 UI 改为可折叠路线图组件：默认显示精简胶囊，点击后展开完整时间线，再点收起。
- 路线图组件允许拖动，且位置与展开状态都需要跨重载记忆。
- 路线图组件需要保存最近 10 条历史记录。
- 点击历史记录时，使用“玩家当前位置 + 历史终点”重新规划路线。
- 路线图组件需要实时刷新当前步骤与偏航提示。
- 起点节点与终点节点使用单行位置文本，格式固定为 `地址 x,y`。
- 精简胶囊宽度需要根据标题与三段文本长度自适应扩展，并保留最小宽度 / 最大宽度 / 内边距护栏。
- 展开态节点区底框 / 背景框需要按实际节点范围自动撑开，覆盖尾部节点、连线与外边距。
- 本轮允许引入 `walk component` 正式契约与 runtime 数据出口，但首批覆盖只落主城、传送门房、飞艇塔 / 港口与常用交通落点。
- `walk component` 数据来源固定为“`wow.db` + 已正式导出的 runtime 节点 / 边 -> 规则化自动归并 -> 正式导出”；自动规则不能稳定判定时宁缺毋滥，不允许源侧 override 或 runtime Lua 手写补边。

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
- 玩家可见路线表达拆成 `raw path -> semantic path -> display` 三层；`RouteBar` 与规划诊断不得直接消费技术节点名。
- `semantic path` 中，地图节点承载“身处 / 将到达的地图”，动作节点承载“如何前往下一张地图”。
- `transport / public_portal / class_portal` 到站后，显示链和规划摘要必须使用到站地图或动作代理名，不能显示返程技术节点名。
- 方向性 `transport / public_portal` 节点只允许作为跨图动作连接器参与求解，不再作为普通本地步行成员或本地接线真值。
- `navigation_route_edges` 只保留 raw route facts 与跨图动作边；`WalkClusterNodeID`、`WalkClusterKey` 不再属于该契约，也不再作为 runtime 本地接线输入。
- `navigation_walk_components` 升级为 schema v2，正式导出 `components / nodeAssignments / localEdges / displayProxies`；runtime 本地连通只读取这份显式局部拓扑。
- `nodeAssignments.Role` 口径固定为 `anchor / landmark / departure_connector / arrival_connector / technical`，不再使用把方向性连接器当普通 hub 的旧语义。
- `Toolbox.Navigation` 必须删除 `addDynamicWalkLocalEdges`、`walkClusterNodeID`、`walkClusterKey` 及其兼容 fallback；本轮明确不做历史兼容，不保留无用过渡代码。

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
- `navigation_route_edges` 后续节点字段只保留 `NodeID / Kind / Source / SourceID / UiMapID / MapID / Name_lang / TaxiNodeID / PosX / PosY / PosZ` 这类 raw facts，不再混入本地接线字段。
- `navigation_walk_components` 可以进入本轮执行范围，但只承载首批局部覆盖，不等同于全世界步行真值已经闭合；其 schema v2 至少包含：
  - `components`：局部组件定义、成员节点、入口节点与默认锚点
  - `nodeAssignments`：节点归属、角色、可见名与显示代理
  - `localEdges`：显式本地 `walk_local` 拓扑，定义哪些节点在组件内部可步行接入
  - `displayProxies`：仅用于语义 / 展示代理，不再反向驱动求解
- `navigation_walk_components` 只能消费正式来源表与规则化自动归并结果；禁止再引入额外人工配置文件参与 walk component 真值判定。

### 5.1 当前静态闭环样例口径

- 自 2026-04-30 起，对 `银月城 (110) -> 东瘟疫之地 (23)`，当前默认导出基线的期望结果是“统一静态图下可求解”，不再是 `NAVIGATION_ERR_NO_ROUTE`。
- 该结果必须来自正式导出的 unified graph，而不是运行时猜测；当前至少由以下数据回归锁定：
  - `portal_117 -> portal_101`
  - `portal_118 -> portal_119`
  - `portal_556 -> portal_557`
  - 至少一条与 `taxi_82` 相连的运行时 taxi 边
  - 奥格传送门房相关节点稳定归入奥格本地组件，并通过显式 `localEdges` 接到奥格主城锚点
- `NavigationRouteEdges.edges` 必须保持 1-based 连续序列，保证运行时 `ipairs()` 遍历不会在中途截断。
- 这个正向样例只说明“当前静态导出图已经闭合出至少一条可证明路线”，不表示系统已经穷尽所有世界关系；`areatrigger`、全世界 `walk component` 与“只能飞 / 没有别路”之类强结论仍待后续阶段。
- 当前已确认的来源边界：
  - `areatrigger` 在 `wow.db` 中只有 source 点位；`areatriggeractionset` 当前只有 `ID / Flags`，不能恢复 destination
  - 旧 `WalkClusterNodeID / WalkClusterKey` 模型已经判定为错误方向，不再作为本地挂接辅助键继续保留
  - 真正的 world `WalkComponent` 需要独立离线几何 / 导航资产导出管线；当前只先导出首批局部 explicit local topology

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
14. 路线图默认以精简胶囊显示，点击后可展开 / 收起完整时间线。
15. 路线图可拖动，且重载后仍保持上次位置和展开状态。
16. 路线图实时高亮当前步骤，并在偏离路线时给出持续可见提示。
17. 最近 10 条历史记录可见，点击任意一条后会以玩家当前位置为起点、以该历史终点为目标重新规划。
18. 到达终点后路线图不自动消失；手动关闭或重新规划前保持可再次展开查看。
19. 玩家可见节点链必须按 `semantic path` 渲染；`walk_local` 不直接显示成节点，`taxi` 不单独生成飞行点动作节点。
20. `transport / public_portal / class_portal` 等动作到站后，显示链与规划摘要不得泄漏返程名、方向性技术节点名或 portal 落点技术名。
21. 起点节点与终点节点使用单行 `地址 x,y` 文本，中间节点默认不附带坐标。
22. 精简胶囊宽度会随标题与三段文本长度自适应扩展，且不会因固定宽度裁切内容。
23. 展开态节点区底框 / 背景框会覆盖完整节点范围，不再出现尾部节点超框。
24. `walk component` 首批正式导出覆盖主城、传送门房、飞艇塔 / 港口与常用交通落点；组件归属、代理名与首选锚点均由正式来源表自动推导，不再依赖人工 override 文件。
25. 类似 `83 -> 3251 -> 83 -> 2805 -> 2819` 的零成本本地回环在新模型下必须结构性不可生成，而不是靠步数惩罚“尽量不选”。
26. `3251` 这类方向性连接器不再被当作普通 `walk component` 成员；若存在本地接入，只能通过 `localEdges` 明确声明。
27. 运行时代码与导出数据中都不再保留 `WalkClusterNodeID`、`walkClusterNodeID`、`WalkClusterKey`、`walkClusterKey` 作为求解真值或兼容 fallback。

## 7. 实施状态

- 本规格自 2026-04-29 起，成为 `navigation` 的新需求基线。
- 用户已于 2026-05-02 明确“开动”，并确认 semantic path、walk component 首批覆盖与 RouteBar 布局回归要求进入执行范围。
- 当前实现已经完成“统一导出驱动 + 最少步数求解”的主干收敛：
  - 运行时不再直接消费 `NavigationManualEdges.lua`、`NavigationTaxiEdges.lua`、`NavigationUiMapRelations.lua`、`NavigationWaypointEdges.lua`
  - 统一边表默认基线已同步到 `navigation_route_edges` schema v17
  - `public_portal` 已进入统一边表并参与运行时求解
  - `areatrigger` 仍只有契约骨架与占位节点，不参与实际路径
  - `targetRules` / `WAYPOINT_LINK` 旧旁路已从运行时判断中移除
- 2026-04-27 的旧实现计划和旧文档仍保留为历史追溯，但它们基于“预计耗时 + Dijkstra + 旧范围”的口径。
- 2026-05-02 起，`WalkClusterNodeID / WalkClusterKey + addDynamicWalkLocalEdges` 旧本地接线模型被正式废弃；执行基线改为 `navigation_route_edges` raw facts + `navigation_walk_components` schema v2 explicit local topology，且本轮不做历史兼容。

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
| 2026-04-30 | 正向样例同步：`银月城 -> 东瘟疫之地` 改为静态闭环回归；补充 `portal_118/556`、`taxi_82`、奥格传送门房并入与 `edges` 连续序列要求 |
| 2026-04-30 | 路线图需求扩展：确认顶部胶囊 + 展开时间线、可拖动、位置 / 展开状态存档、实时偏航提示与最近 10 条历史终点重规划 |
| 2026-05-02 | 用户确认开动：需求状态推进为 `可执行`，并补充 `raw path -> semantic path -> display` 三层、`walk component` 首批覆盖、胶囊宽度自适应与展开态节点区底框自动撑开要求 |
| 2026-05-02 | 根因修复确认：废弃 `WalkClusterNodeID / WalkClusterKey` runtime 真值与兼容 fallback；`navigation_walk_components` 升级为 schema v2 显式局部拓扑，方向性连接器不再作为普通步行成员 |
