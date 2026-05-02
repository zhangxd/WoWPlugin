# 地图导航模块设计

- 文档类型：设计
- 状态：已确认
- 主题：navigation
- 适用范围：`navigation` 模块、`Toolbox.Navigation` 领域 API、导航静态契约与路线展示
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-05-02（确认开动后补齐 semantic path、walk component 首批覆盖与 RouteBar 布局回归要求）

## 1. 背景

- 当前需求已经从“地图之间大概怎么连”收敛为“任意地图选点后，按当前角色配置给出可执行的最短路线”。
- 用户要的不是单纯地图邻接，而是完整的路线语义：从起点到终点会经过哪些地图、每一段通过什么方式抵达。
- 路线计算优先依赖静态导出数据，避免大规模运行时 API 批量采样；运行时只负责读取当前角色配置和当前用户 waypoint。
- 典型世界级场景不再是“地图 A 和地图 B 是否相邻”，而是“银月城到北风苔原是否应该先回奥格瑞玛再换飞艇”。

## 2. 设计目标

- 保持 `navigation` 为独立模块，不把世界旅行规划塞进 `quest`、`encounter_journal` 或其它模块。
- 路线图按“当前角色配置”裁剪，而不是按“理论全能力”规划。
- 最短路主指标明确为“最少路径步数”，不再按预计耗时排序。
- 统一表达多模态路线：`walk`、`taxi`、`portal / areatrigger / 道标石`、`transport`、`hearthstone`、`class_teleport`、`class_portal`。
- 规划成功时的诊断输出必须包含每一段的方式、起终点和经过地图序列。
- 所有运行时静态数据继续只允许来自 DataContracts 契约导出，不允许手工维护导航 ID 表。

## 3. 非目标

- 不做账号级跨角色能力推断。
- 不在当前阶段证明“只能飞 / 只能坐船 / 没有公共路径”这类排除法命题；只有当所有相关模态都闭合后才允许下此类结论。
- 不实现真实地形寻路、避障或逐米移动路线。
- 不把战斗状态、CD 是否转好、临时剧情禁用等瞬时条件纳入第一版静态规则。
- 不通过固定正数秒 `C_Timer.After` 等待世界地图布局。
- 本轮不修改 `Toolbox/Core/API/Tooltip.lua`。
- `Toolbox/Core/API/EncounterJournal.lua` 的入口查询性能修复仍单独立项，不并入当前导航重定义。

## 4. 方案对比

### 4.1 方案 A：继续以地图邻接为核心

- 做法：把 `UiMap` 当成主要节点，优先补“地图 A 能否前往地图 B”的关系。
- 优点：导出表面上较简单。
- 风险 / 缺点：无法稳定表达主城传送、炉石、飞艇、道标石等“先跳再走”的路线，也无法解释同一对地图在不同角色配置下最短路不同的情况。

### 4.2 方案 B：枢纽 / 动作图 + 角色能力覆盖层

- 做法：把世界交通建成“节点 + 动作边”的统一路线图；公共世界事实静态导出，角色能力在查询时按当前配置展开。
- 优点：最接近玩家真实旅行路径，也最适合表达“经过哪些地图”和“通过什么方式”。
- 风险 / 缺点：需要把节点、静态边、能力边模板和步行接入分层建模。

### 4.3 方案 C：静态图不够时运行时补洞

- 做法：静态导出负责主体，缺失的关系通过运行时 API 或临时手工表补齐。
- 优点：短期容易把更多路线跑起来。
- 风险 / 缺点：和“尽量静态导出、可批量计算”的目标冲突，后续很难判断哪些结论是稳定的。

### 4.4 选型结论

- 选定方案：方案 B。
- 选择原因：世界级最短路的本质是“多模态动作图”，不是“地图矩形关系图”；只有方案 B 能同时容纳公共交通、角色技能和地图内步行接入。

## 5. 选定方案

### 5.1 模块与文件结构

| 文件 | 职责 |
|------|------|
| `Toolbox/Core/API/Navigation.lua` | 导航领域 API：图裁剪、能力展开、最少步数求解、路线回溯与调试输出。 |
| `Toolbox/Modules/Navigation.lua` | `navigation` 模块注册、设置页、世界地图入口和顶部路径 UI 生命周期。 |
| `Toolbox/Modules/Navigation/Shared.lua` | 模块内共享命名空间、DB 访问、启用状态判断。 |
| `Toolbox/Modules/Navigation/WorldMap.lua` | 世界地图 waypoint 入口，负责读取目标点、触发规划，并输出一次性的规划期诊断消息。 |
| `Toolbox/Modules/Navigation/RouteBar.lua` | 顶部路径 UI，负责显示路线状态、历史记录、清除路线与刷新布局。 |
| `Toolbox/Data/NavigationMapNodes.lua` | 查询时地图基础节点表；负责 `UiMap` 名称、层级和目标落点引用。 |
| `Toolbox/Data/NavigationAbilityTemplates.lua` | 查询时能力模板表；运行时按当前角色配置展开 `hearthstone / class_teleport / class_portal`。 |
| `Toolbox/Data/NavigationRouteEdges.lua` | 统一运行时静态边表；运行时只消费这一个静态边入口。 |
| `DataContracts/navigation_map_nodes.json` | 地图基础节点契约，负责导出 `NavigationMapNodes.lua`。 |
| `DataContracts/navigation_ability_templates.json` | 能力模板契约，负责导出可稳定闭合的 V1 旅行法术模板。 |
| `DataContracts/navigation_route_edges.json` | 统一运行时静态边契约，负责汇总当前已闭合的公共路线边。 |

说明：

- 来源侧可以保留 `navigation_taxi_edges` 这类追溯契约，但运行时路径图只能消费统一静态边出口。
- 当前 runtime 实际静态消费为 `NavigationRouteEdges.lua + NavigationMapNodes.lua + NavigationAbilityTemplates.lua`。
- 能力模板定义本身也走导出契约；运行时只负责根据当前角色配置决定哪些模板可展开。
- 未来若增加 `transport`、`portal`、`walk component` 等来源契约，也必须先汇总进统一运行时边表后才能参与构图。

### 5.2 路线图模型

路线图分成五个逻辑对象：

1. `RouteNode`
   - 代表一个可落脚、可换乘、可施法落点的统一节点。
   - 典型例子：飞行点、传送门入口 / 出口、主城枢纽、飞艇塔、炉石落点、职业传送落点。

2. `RouteEdgeStatic`
   - 纯静态、与角色配置无关的边。
   - 模式示例：`taxi`、`transport`、`public_portal`、`areatrigger`、`walk_local`。

3. `AbilityEdgeTemplate`
   - 查询时按当前角色配置展开的边模板。
   - 模式示例：`hearthstone`、`class_teleport`、`class_portal`。

4. `WalkComponent`
   - 同一片可步行连通区域的逻辑组件。
   - 作用是限制“哪些枢纽之间理论上可走到”，而不是把每一米地形都离散成节点。

5. `QueryPoint`
   - 查询时临时生成的起点 / 终点。
   - 只在本次求解中存在，用于把“任意地图选点”接入统一路线图。

### 5.3 路线模式与阶段划分

#### V1 必须支持

- `walk_local`
- `taxi`
- `hearthstone`
- `class_teleport`
- `class_portal`

其中：

- `walk_local` 只负责“起点 / 终点 / 交通落点”到本地枢纽的接入，不要求先完成全世界步行连通图。
- `taxi` 允许保留经过地图序列，并按当前角色已开航点裁剪。
- `hearthstone` 和职业旅行能力通过导出的模板边在查询时展开。

#### V2 继续补齐（已闭合标记 ✅）

- ✅ `transport`（飞艇/船）
- ✅ `public_portal`（公共传送门）
- `areatrigger`（当前仅占位）
- 全世界 `WalkComponent`

**public_portal 当前实现口径：**
- 数据来源：复用 `navigation_waypoint_edges` 的 `waypointedge` + `waypointnode` 管道，筛选 Type=1→Type=2 portal 边
- 节点类型：运行时导出为不透明数字 `NodeID`，portal 来源定位统一走 `Source = "portal"` + `SourceID = waypoint_id`；保留 waypoint 精确坐标（`PosX`/`PosY`），并通过 `WalkClusterNodeID` 接入本地步行网
- 边模式：`mode = "public_portal"`，`stepCost = 1`
- 可用性：`PlayerConditionID = 0` 的边无条件纳入；`924`（Alliance）/ `923`（Horde）标注 `faction`；其余 V2 暂不纳入
- 出口：portal 边通过 enrichment 汇入 `navigation_route_edges` 统一静态边表，不新增运行时数据文件
- 当前仓库默认导出基线已推进到 `navigation_route_edges` schema v17；如果需要严格 V1-only 数据包，必须额外拆分冻结输出。

#### V3 才允许下强结论

- `only_taxi`
- `must_use_transport`
- `no_public_route`

这些结论都需要建立在 V2 之后的多模态闭合图之上。

### 5.4 代价模型与求解器

主规则：

- 路线代价按“最少路径步数”计算。

记步规则：

- 同一可步行连通域内的一段本地 `walk` 记 1 步。
- 一次 `taxi` 起飞到落地记 1 步。
- 一次 `transport` 乘坐记 1 步。
- 一次 `hearthstone` 记 1 步。
- 一次 `class_teleport` 记 1 步。
- 当前角色自用的 `class_portal` 记 1 步。
- 一次 `portal / areatrigger / 道标石` 记 1 步。

求解器：

- 主求解器按“最少步数优先 + 平局规则”展开候选状态，不再按预计耗时做 Dijkstra 排序。
- 图上每条有效边的基础步数代价都是 1；连续 `walk_local` 在展示层压缩为一段。
- 不再把“施法时间”“换乘时间”“世界距离”作为主排序权重。

平局规则：

1. 更少的 `walk` 段数优先。
2. 更短的本地步行总距离优先。
3. 更少的步骤名称切换优先。
4. 最后按稳定 ID 排序，保证导出可复现。

### 5.5 当前角色配置

查询时必须显式传入当前角色配置。第一版至少包含：

- `Faction`
- `Class`
- `KnownSpellIDs`
- `KnownTaxiNodeIDs`
- `HearthBindNodeID`
  - 当前稳定兼容字段；数字 node ID 迁移后优先传入不透明数字节点 ID
  - 运行时内部同时保留 `hearthBindInfo`，在只掌握 `UiMapID` 时允许按 route source lookup 回填节点

运行时过滤规则：

- 不满足职业 / 阵营 / 已学法术 / 已开航点条件的边直接视为不可用。
- 未知可用性的边不进入候选图。
- 当前角色配置是运行时输入，不回写静态导出。
- 当前角色可用性快照允许使用运行时 API，但仅限于：
  - `C_TaxiMap.GetTaxiNodesForMap`：收集已开航点
  - `GetBindLocation`：未来可作为炉石绑定点补源；当前若无稳定静态映射，则先保留 `faction -> 主城 UiMapID -> route node` 的降级路径
  - `C_Map.GetMapInfoAtPosition`：把当前点 / 目标点细化到更具体的地图节点

### 5.6 世界关系表达

世界关系不再建成“地图 A 是否挨着地图 B”，而是“从一个枢纽经过哪种动作到达另一个枢纽”。

例如：

- `奥利波斯 -> 晋升堡垒`
  - 在当前已闭合的静态图中，可以由 `taxi` 构成一条公共交通边。
- `银月城 -> 北风苔原`
  - 正确的问题不是“两张图是否直连”，而是：
    - 当前角色能否先 `hearthstone` / `class_teleport` 到奥格瑞玛；
    - 奥格瑞玛是否存在 `zeppelin` 到北风苔原；
    - 这些动作边总共需要几步。

这也是为什么导航图必须以枢纽和动作建模，而不是以 `UiMap` 邻接建模。

### 5.7 导出与运行时边界

静态数据规则：

- 运行时静态边只能来自 DataContracts 契约导出。
- 统一运行时边表继续作为唯一静态消费入口。
- `taxi` 已经是当前最成熟的一层：既能导出节点和边，也能导出经过地图序列。
- 旧的 `targetRules` / `WAYPOINT_LINK` 运行时旁路已经移除；路线真值不再依赖它们。

能力边规则：

- `hearthstone` 最适合做查询时模板边：法术固定，可用性来自角色输入，落点来自 `HearthBindNodeID`（不透明数字节点 ID；兼容层同时接受 `hearthBindInfo`）。
- `class_teleport` / `class_portal` 也适合做模板边：法术来源可从 `spell / spelleffect` 族表识别，落点是固定主城 / 固定节点。
- 模板边定义本身由 `navigation_ability_templates` 导出；`Navigation.lua` 不再手写“法术 -> 目的地”表。

未闭合模态：

- `areatrigger`、`道标石` 仍需继续解静态目标端点。
- `walk` 仍需独立构建连通组件，不能再由地图矩形关系或 `UiMap` 邻接推导。

当前已确认的静态来源边界（2026-04-30）：

- `areatrigger`：`wow.db` 当前只能稳定给出 source 点位；`areatriggeractionset` 只有 `ID / Flags`，不能恢复目标地图与目标坐标，因此不能导出完整运行时边。
- `walk component`：当前仓库与 `wow.db` 没有现成、稳定、可直接当作“开放世界步行连通真值”的来源；现有 `WalkClusterNodeID` 只是本地归并启发式，旧 `WalkClusterKey` 仅保留为兼容字段。
- 下一步最现实的方向不是继续猜地图邻接，而是：
  1. 继续把显式连接器静态化；
  2. 另起离线几何 / 导航资产管线生成真正的 `WalkComponent` 契约。

### 5.7.1 当前静态闭环回归样例：`银月城 -> 东瘟疫之地`

自 2026-04-30 起，这个样例改为正向回归样例，用来固定“当前 unified graph 已能靠静态导出证明该路线可达”的口径。

当前以测试锁定的关键事实包括：

- `Source = "portal"`、`SourceID = 117 -> 101` 的公共传送门边已导出，且 `SourceID = 101 / 115 / 120 / 122 / 129 / 132 / 140 / 144 / 203 / 218 / 285` 这些 portal 节点都稳定落到 `UiMapID = 85`、`WalkClusterNodeID = 奥格主城锚点`。
- `Source = "portal"`、`SourceID = 118 -> 119` 的公共传送门边已导出，可把银月城宝珠稳定接入提瑞斯法 / 幽暗城周边交通网。
- `Source = "portal"`、`SourceID = 556 -> 557` 的公共传送门边已导出，可把东部王国北部 portal 入口稳定接入东瘟疫之地。
- `Source = "taxi"`、`SourceID = 82` 已并入统一 taxi 图。
- `NavigationRouteEdges.edges` 必须保持 1-based 连续序列，保证运行时与测试侧使用 `ipairs()` 遍历时不会在中途截断。

因此，按当前默认导出基线，`银月城 -> 东瘟疫之地` 不应再返回 `NAVIGATION_ERR_NO_ROUTE`；逻辑测试要求它在统一静态图下可求解。

同时，这个正向样例仍然不代表：

1. 已经闭合全世界 `walk` 连通规则；
2. 已经完成 `areatrigger` / 道标石等后续模态；
3. 已经能对“只能飞 / 只能传送 / 没有公共路径”给出排除法强结论。

也就是说，当前结论是“静态导出图已闭合出至少一条可证明路线”，而不是“系统已经穷尽了所有世界关系”。

### 5.7.2 `WalkComponent` 契约与首批覆盖

为避免继续把 `WalkClusterNodeID / WalkClusterKey` 当成 world walk truth，本轮已经把 `walk component` 拆成独立正式导出契约，并让 runtime 优先消费正式组件归属，而不是继续只靠临时归并。

当前已落地的正式出口：

| 文件 | 职责 |
|------|------|
| `DataContracts/navigation_walk_components.json` | 定义 `WalkComponent` 与节点归属 / 代理规则的正式契约。 |
| `Toolbox/Data/NavigationWalkComponents.lua` | runtime 只读的步行组件数据出口。 |

当前导出链路改为“两层正式来源 + 自动归并”：

1. 正式来源节点 / 边
   - 复用当前已有的 `navigation_map_nodes / navigation_route_edges / waypoint / transport / portal` 正式来源。
   - 先拿到 runtime 已确认存在的节点事实、节点类型、来源 ID、地图归属、落点关系和显式连接器。
2. 规则化自动归并
   - 导出脚本只允许基于正式来源事实自动推导 `WalkComponent`、节点归属、显示代理和首选锚点。
   - 允许使用稳定规则，例如：同一局部交通房间、同一主城锚点、明确的 portal/transport 落点簇、技术入口与玩家可见落点之间的确定性代理关系。
   - 若某个组件归属、`hidden / proxy`、`preferred_anchor` 或 `visible_name` 不能被稳定规则证明，就先不导出该节点或该组件；不再允许额外 override 文件补顶。
3. 正式导出
   - 当前只把首批自动确认后的 `WalkComponent` 局部真值、节点归属和代理信息写入 `NavigationWalkComponents.lua`，供 `Toolbox.Navigation` 与展示层统一消费。

当前首批覆盖范围只落高价值局部区域，不承诺一口气闭合全世界：

- 主城
- 传送门房
- 飞艇塔 / 港口
- 常用交通落点

建议的数据结构至少包含：

- `components`
  - `ComponentID`
  - `DisplayName`
  - `MemberNodeIDs`
  - `EntryNodeIDs`
  - `PreferredAnchorNodeID`
- `nodeAssignments`
  - `NodeID`
  - `ComponentID`
  - `Role`（如 `anchor / hub / technical`）
  - `HiddenInSemanticChain`
  - `DisplayProxyNodeID`
  - `VisibleName`

### 5.8 路线输出

运行时输出至少要有：

- 总步数
- 每一段的 `mode`
- 每一段的起点 / 终点节点
- 每一段的 `TraversedUiMapIDs`
- 每一段的 `TraversedUiMapNames`

同时把路线表达拆成 3 层：

1. `raw path`
   - 求解器真实走过的技术节点 / 技术边。
   - 允许包含方向性 transport 节点、portal 落点节点、局部 `walk_local` 接入边等 runtime 细节。
2. `semantic path`
   - 玩家可见路线链，只允许由 `地图节点` 与 `动作节点` 组成。
   - 默认形态为 `地图节点 -> 动作节点 -> 地图节点 -> 动作节点 -> 地图节点`。
3. `display`
   - `RouteBar`、节点摘要和规划期聊天诊断都必须先消费 `semantic path`，不能直接把 `raw path` 或 `TraversedUiMapNames` 当玩家文案。

`semantic path` 的确认规则如下：

- `walk_local` 只负责把起点、终点和交通落点接入同一 `WalkComponent`，不直接显示成独立玩家节点。
- `transport / public_portal / hearthstone / class_teleport / class_portal` 生成显式 `动作节点`。
- `taxi` 继续作为有效 segment 和记步来源，但不单独生成飞行点动作节点；玩家可见链路直接展示起降地图。
- 动作节点显示的是“前往目标地图的动作”，不是返程名字或技术方向节点名。
  - 例如：到达北风苔原后的语义落点必须是 `北风苔原`，不能再泄漏 `乘坐战歌要塞的飞艇前往奥格瑞玛` 这类返程节点名。
- 规划起点与最终终点的地图节点文案继续使用单行 `地址 x,y`；中间地图节点默认不附带坐标。
- `TraversedUiMapNames` 保留给调试、求解和局部推断，但不再直接驱动玩家可见节点链。

连续步行压缩规则：

- 图内部允许多个局部接入动作存在。
- 最终展示时，连续 `walk` 段必须压缩成一段。

这样最终路线可以稳定显示为：

- `walk: 银月城起点 -> 本地枢纽`
- `class_teleport: -> 奥格瑞玛`
- `walk: 奥格瑞玛落点 -> 西部飞艇塔`
- `zeppelin: -> 北风苔原`
- `walk: 北风苔原飞艇塔 -> 目标点`

规划期输出口径：

- 诊断输出只在单次规划完成时触发一次，不做实时滚动日志。
- 首行至少包含：起点地图与坐标、终点地图与坐标、总步数、节点摘要。
- 后续按 segment 顺序逐段输出：`mode / from / to / traversedUiMapNames`。
- 节点摘要用于概览地图级节点与显式交通枢纽，不承担逐段细节的完整回放。

### 5.9 顶部路线图组件重设计

当前单行文本条已经不足以承载复杂链路，因此 `RouteBar.lua` 的职责从“顶部文本框”升级为“可折叠、可拖动、带历史记录的路线图组件”。

#### 5.9.1 交互基线

- 默认显示一行精简胶囊，不再默认展开完整链路。
- 点击胶囊本体时，在“精简胶囊 / 导航信息页”之间切换；展开态继续固定在屏幕顶部区域，不改为世界地图内嵌面板。
- 胶囊右侧提供独立的“最近路线”按钮；该按钮只负责展开 / 收起侧贴历史抽屉，不复用胶囊本体点击区域。
- 历史抽屉必须贴在导航信息页侧边展开，不能放到导航内容下方。
- 整个路线图组件允许玩家拖动；拖动的是组件根 Frame，不是只拖标题文本。
- 玩家手动关闭后，当前路线仍保留在模块状态里；直到重新规划路线前，都允许再次点开同一条路线。

#### 5.9.2 展示结构

精简胶囊至少显示：

- 标题区只显示 `状态` 与 `步骤进度`
- 不再显示路线摘要
- 主体区固定为三段式：
  - 左段：`起始位置`
  - 中段：`当前位置`（实时刷新）
  - 右段：`终点位置`
- 三段之间需要有明确的竖向分隔线，视觉上能看出左 / 中 / 右三个信息区，而不是单纯三段文本并排
- 胶囊整体宽度需要根据标题与三段文本的实际长度自适应扩展，不能继续写死为固定宽度后截断或挤压内容
- 自适应宽度仍需保留 WoW 风格的最小宽度、左右内边距和最大宽度护栏，避免文本过短时过窄、过长时直接顶满屏幕

展开后的导航信息页采用“节点链主视图 + 侧贴历史抽屉”的结构：

- 导航信息页主视图不再显示完整步骤列表
- 导航信息页主视图不再重复显示路线摘要
- 主视图只显示 `semantic path` 节点串联，不直接显示 `raw path` 技术节点
- 节点链采用竖向“串站”表达，类似地铁站站点列表，而不是时间线步骤流
- 节点链默认按 `地图节点 -> 动作节点 -> 地图节点` 交替组织
- 地图节点承载“我现在位于哪张地图 / 将到达哪张地图”
- 动作节点承载“如何前往下一张地图”，例如：
  - `使用西部大地神殿的传送门前往暮光高地`
  - `乘坐奥格瑞玛的飞艇前往北风苔原`
  - `使用法师传送前往奥格瑞玛`
- 飞行点详情不进入玩家可见动作节点；`taxi` 只保留在 segment 与状态层，不单独长出一个“飞行点动作节点”
- 方向性技术节点、返程节点名和 portal 落点技术名必须在 semantic 层被隐藏或代理，不能直接显示到节点链
- 左侧节点标记至少区分 `地图` 与 `动作` 两类；动作节点可继续细分 `传送门 / 飞艇 / 炉石 / 职业技能`
- 节点标签宽度一致、文字居中对齐，整体按 WoW 可落地能力约束设计
- 每个节点需要有稳定的行容器样式，避免退化成“图标 + 纯文本”列表
- 节点链需要有贯穿上下的竖向串联连线，并在节点位显示明确的节点标记
- 当前所在步骤对应的节点需要高亮，至少要体现在图标或节点容器的激活态上
- 起点节点与终点节点采用单行位置文本，格式固定为 `地址 x,y`，分别承载规划原始位置坐标与目标位置坐标；不再拆成“地址 + 第二行坐标明细”，中间节点仍不追加坐标
- 中间动作节点不追加坐标；需要强调落点或入口时，通过动作文案本身或 tooltip 补充
- 展开态节点区的底框 / 背景框必须按实际渲染出的节点范围自适应撑开，包含尾部节点、连线和节点外边距；不得出现后半段节点超出容器的情况
- 不在节点链面板内部预留提示横幅；后续提示信息统一走 WoW `tips / tooltip` 风格表达

历史抽屉至少显示：

- 最近 10 条历史记录
- 每条记录显示 `目标名 + 一行摘要`

#### 5.9.3 状态与存档

`ToolboxDB.modules.navigation` 需要新增路线图组件专属状态，且只由 `navigation` 模块自己读写：

- `routeWidgetPosition`
  - 组件锚点与偏移
- `routeWidgetExpanded`
  - 当前是否展开
- `routeHistoryExpanded`
  - 历史抽屉当前是否展开
- `routeHistory`
  - 最近 10 条历史记录

存档规则：

- 组件位置需要跨重载记忆。
- 展开 / 收起状态需要跨重载记忆。
- 历史抽屉开关状态需要跨重载记忆。
- 历史记录按最近优先，超出 10 条后丢弃最旧项。

#### 5.9.4 历史记录语义

历史记录保存的是“曾经规划过的目标终点快照 + 展示摘要”，不是旧路线的完整回放。

点击一条历史记录时：

- 起点使用玩家当前实时位置
- 终点回填为这条历史里的目标终点
- 先弹出 Blizzard 通用确认 / 取消提示
- 只有在玩家确认后，才基于“当前位置 -> 历史终点”重新规划新路线

也就是说，历史记录的用途是“快速重规划到旧目标”，不是恢复旧起点。

#### 5.9.5 实时刷新

路线图组件需要持续刷新，而不是只在规划成功时静态渲染一次：

- 持续判断当前处于哪一个步骤
- 持续刷新当前步骤高亮
- 持续判断是否偏离路线
- 偏离后立即把提示反馈到精简胶囊和展开态

这里允许使用低频 `OnUpdate` 节流或等价的持续刷新机制，但必须满足：

- 非实时必要逻辑不能每帧重算整条路线
- 模块禁用时必须停止刷新
- 不能影响其他 `navigation` 以外的模块行为
- 这里的实时刷新只限 `RouteBar` 组件内部状态，不扩展为聊天框或调试通道的实时日志流

## 6. 影响面

- `Toolbox.Navigation` 的求解口径将从“按预计耗时的 Dijkstra”收敛为“按最少步数的 BFS”。
- `navigation` 模块的角色可用性输入将不止职业 / 阵营 / 已学技能，还要显式包含已开航点和炉石绑定点。
- `navigation_route_edges` 继续保留为运行时唯一静态边入口，但设计语义从“当前能导出的所有可行边”升级为“统一静态骨架边”。
- `Toolbox.Navigation` 需要显式拆出 `raw path -> semantic path -> display` 三层，不能再让 `RouteBar.lua` 或 `WorldMap.lua` 直接消费技术节点名。
- `RouteBar.lua`、规划期节点摘要和逐段诊断输出都要统一改成消费 `semantic path` 或 semantic 代理字段，避免技术节点泄漏。
- `navigation_walk_components` 会新增正式契约与 runtime 数据出口；walk 相关真值不再只靠 `WalkClusterNodeID` 启发式。
- 文档与后续实现必须把“世界地图关系”和“交通枢纽关系”分开描述。
- `RouteBar.lua` 的实现重点将从“文本拼接”转向“路线图状态管理、拖动与历史记录”，对应测试也要从字符串断言扩展到组件状态断言。

## 7. 风险与回退

- 风险：`transport`、`public_portal` 和 `walk` 闭合速度不一致，可能导致第一版图覆盖不均。
- 缓解：按 V1 / V2 分层交付，先让 `taxi + hearthstone + class travel` 成为稳定最小闭环。
- 风险：旧实现和旧文档仍以“预计耗时 + Dijkstra”为口径，可能和新设计冲突。
- 缓解：从本次设计起，以本文件和 `navigation-spec.md` 为新基线；旧计划只保留历史追溯价值。
- 回退：如果某一类新边无法稳定从静态数据闭合，就退回“候选数据 / 模板边”层，不把它直接纳入运行时统一静态边表。

## 8. 验证策略

- 路线求解验证：
  - BFS 能在最少步数路径上收敛。
  - 平局时按更少 `walk`、更短本地步行距离稳定打破。
- 角色裁剪验证：
  - 未学法术、未开航点、阵营不符的边不会进入求解。
  - `hearthstone` 和 `class_teleport` 只在当前角色配置满足时出现。
- 数据验证：
  - `taxi` 边继续校验经过地图序列完整性。
  - 统一运行时静态边表仍禁止手工维护 ID。
  - 文档和运行时都以当前 contract schema 为准，默认统一边表当前为 v17。
- 表达验证：
  - 输出的每一段都带方式和经过地图。
  - 连续 `walk` 被压缩为单段展示。
  - `semantic path` 必须能稳定产出 `地图节点 / 动作节点` 链。
  - `transport / public_portal / class_portal` 等到站后，显示链与规划摘要不得再泄漏返程或技术节点名。
  - `taxi` 不生成独立飞行点动作节点，但仍保留正确的 segment 和记步结果。
- `walk component` 验证：
  - 首批覆盖范围只检查主城、传送门房、飞艇塔 / 港口和常用交通落点。
  - 组件归属与代理信息只能由正式来源表自动推导，不允许再引入源侧 override 或 runtime 手写导航数据。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：确认新建 `navigation` 模块、混合数据源、Dijkstra 路径图与顶部路径 UI 设计 |
| 2026-04-27 | 数据源规则收紧：`NavigationManualEdges.lua` 不再作为运行时数据源，所有导航节点、边、目标规则、坐标与限制必须从契约导出 |
| 2026-04-27 | 复审修订：目标源改为用户 waypoint，加入 `x/y` 成本模型、静态连接器 / 运行时过滤拆层与缓存策略，并明确排除 tooltip 与 EJ 性能修复 |
| 2026-04-27 | 用户确认“开动”：真实 `Taxi*` 导出进入执行范围，`navigation_taxi_edges` 从 draft 推进为 active，生成 `NavigationTaxiEdges.lua` 并加入 TOC |
| 2026-04-27 | 路线边统一导出：新增 `navigation_route_edges` active 契约，`NavigationRouteEdges.lua` 成为 `Toolbox.Navigation` 唯一运行时路线边入口 |
| 2026-04-29 | 设计基线重定义：导航图改为”当前角色配置 + 最少步数 + 枢纽 / 动作图”，V1 先支持 `taxi / hearthstone / class_teleport / class_portal / walk_local`，`transport / public_portal / areatrigger / walk component` 延后到 V2 |
| 2026-04-29 | V2 推进：`transport`（飞艇/船）闭合，`isEdgeAvailable` 增加 transport 模式处理，导出脚本按 node name 识别 transport 节点 |
| 2026-04-29 | V2 推进：`public_portal` 方案确认，进入实施（waypoint 管道 → 统一边表，portal_N 节点 + WalkClusterKey 接入，faction 分层过滤） |
| 2026-04-29 | 文档同步：明确 runtime 当前实际消费 `NavigationRouteEdges + NavigationMapNodes + NavigationAbilityTemplates`，默认统一边表已推进到 schema v17，`public_portal` 已参与求解，旧 `targetRules / WAYPOINT_LINK` 旁路已移除 |
| 2026-04-29 | 边界样例同步：固定 `银月城 -> 东瘟疫之地` 当前应返回 `NAVIGATION_ERR_NO_ROUTE`，其含义是“导出图未闭合”，不是“游戏内不可达” |
| 2026-04-30 | 回归样例升级：`银月城 -> 东瘟疫之地` 改为静态闭环正向样例；`portal_118/556`、`taxi_82`、奥格传送门房并入与 `edges` 连续序列约束由测试锁定 |
| 2026-04-30 | 数字 node ID 收尾：`NavigationRouteEdges` / `NavigationAbilityTemplates` 切到不透明数字 `NodeID` / `ToNodeID`，`WalkClusterNodeID` 成为主字段；运行时与逻辑测试改为按 `Source + SourceID + Kind` 解析节点 |
| 2026-04-30 | 路线图交互确认：顶部路线 UI 改为可折叠胶囊 + 展开态导航视图，可拖动、记忆位置与展开状态，并维护最近 10 条“旧终点重规划”历史 |
| 2026-05-01 | 路线图交互定稿：胶囊改为三段式起始/当前/终点，标题只保留状态与步骤进度；展开态改为 WoW 可落地约束下的竖向节点串站视图，独立侧贴最近路线抽屉与确认弹框流程正式写入设计 |
| 2026-05-01 | 规划期聊天输出定稿：仅在成功规划时输出一组排查诊断文本，包含起终点、总步数、节点摘要与逐段 `mode / from / to / traversedUiMapNames`；不新增实时导航聊天日志 |
| 2026-05-01 | 展开态节点链起点/终点文本口径调整：位置与坐标合并为单行 `地址 x,y`，胶囊与聊天诊断输出保持不变 |
| 2026-05-01 | 语义路线链定稿：玩家可见链路改为 `地图节点 / 动作节点` 分层表达，`walk_local` 只作隐藏接入，`taxi` 不单独生成动作节点，规划摘要与节点链禁止泄漏返程技术节点名 |
| 2026-05-01 | `walk component` 方案定稿：新增正式契约与 runtime 出口方向，首批覆盖主城、传送门房、飞艇塔 / 港口与常用交通落点 |
| 2026-05-02 | 路线图布局补充：精简胶囊宽度改为随文本长度自适应；展开态节点区底框必须随节点范围自动扩展，禁止尾部节点超框 |
| 2026-05-02 | `walk component` 首批实现：`navigation_walk_components` 契约与 `NavigationWalkComponents.lua` 已落地；runtime 本地接入优先读取 formal component，缺失时继续 fallback 到 `WalkClusterNodeID / WalkClusterKey` |
| 2026-05-02 | 方案改口：移除 `navigation_walk_component_overrides.json` 与对应 enrichment；首批 walk component 改为只允许基于正式来源表全自动推导 |
