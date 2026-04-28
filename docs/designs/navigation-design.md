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
- 最后更新：2026-04-29

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
- 运行时输出必须包含每一段的方式、起终点和经过地图序列。
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
| `Toolbox/Modules/Navigation/WorldMap.lua` | 世界地图 waypoint 入口，负责读取目标点并触发规划。 |
| `Toolbox/Modules/Navigation/RouteBar.lua` | 顶部路径 UI，负责显示步骤、清除路线、刷新布局。 |
| `Toolbox/Data/NavigationAbilityTemplates.lua` | 查询时能力模板表；运行时按当前角色配置展开 `hearthstone / class_teleport / class_portal`。 |
| `Toolbox/Data/NavigationRouteEdges.lua` | 统一运行时静态边表；运行时只消费这一个静态边入口。 |
| `DataContracts/navigation_ability_templates.json` | 能力模板契约，负责导出可稳定闭合的 V1 旅行法术模板。 |
| `DataContracts/navigation_route_edges.json` | 统一运行时静态边契约，负责汇总当前已闭合的公共路线边。 |

说明：

- 来源侧可以保留 `navigation_taxi_edges` 这类追溯契约，但运行时路径图只能消费统一静态边出口。
- 能力模板定义本身也走导出契约；运行时只负责根据当前角色配置决定哪些模板可展开。
- 未来若增加 `transport`、`portal`、`walk component` 等来源契约，也必须先汇总进统一运行时边表后才能参与构图。

### 5.2 路线图模型

路线图分成五个逻辑对象：

1. `RouteNode`
   - 代表一个可落脚、可换乘、可施法落点的统一节点。
   - 典型例子：飞行点、传送门入口 / 出口、主城枢纽、飞艇塔、炉石落点、职业传送落点。

2. `RouteEdgeStatic`
   - 纯静态、与角色配置无关的边。
   - 模式示例：`taxi`、`portal`、`areatrigger`、`transport`、`walk`。

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

#### V2 继续补齐

- `transport`
- `public_portal`
- `areatrigger`
- `道标石`
- 全世界 `WalkComponent`

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

- 主求解器改为 BFS；图上每条有效边的基础代价都是 1。
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

运行时过滤规则：

- 不满足职业 / 阵营 / 已学法术 / 已开航点条件的边直接视为不可用。
- 未知可用性的边不进入候选图。
- 当前角色配置是运行时输入，不回写静态导出。

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

能力边规则：

- `hearthstone` 最适合做查询时模板边：法术固定，可用性来自角色输入，落点来自 `HearthBindNodeID`。
- `class_teleport` / `class_portal` 也适合做模板边：法术来源可从 `spell / spelleffect` 族表识别，落点是固定主城 / 固定节点。
- 模板边定义本身由 `navigation_ability_templates` 导出；`Navigation.lua` 不再手写“法术 -> 目的地”表。

未闭合模态：

- `transport`、`public_portal`、`areatrigger`、`道标石` 仍需继续解静态目标端点。
- `walk` 仍需独立构建连通组件，不能再由地图矩形关系或 `UiMap` 邻接推导。

### 5.8 路线输出

运行时输出至少要有：

- 总步数
- 每一段的 `mode`
- 每一段的起点 / 终点节点
- 每一段的 `TraversedUiMapIDs`
- 每一段的 `TraversedUiMapNames`

连续步行压缩规则：

- 图内部允许多个局部接入动作存在。
- 最终展示时，连续 `walk` 段必须压缩成一段。

这样最终路线可以稳定显示为：

- `walk: 银月城起点 -> 本地枢纽`
- `class_teleport: -> 奥格瑞玛`
- `walk: 奥格瑞玛落点 -> 西部飞艇塔`
- `zeppelin: -> 北风苔原`
- `walk: 北风苔原飞艇塔 -> 目标点`

## 6. 影响面

- `Toolbox.Navigation` 的求解口径将从“按预计耗时的 Dijkstra”收敛为“按最少步数的 BFS”。
- `navigation` 模块的角色可用性输入将不止职业 / 阵营 / 已学技能，还要显式包含已开航点和炉石绑定点。
- `navigation_route_edges` 继续保留为运行时唯一静态边入口，但设计语义从“当前能导出的所有可行边”升级为“统一静态骨架边”。
- 文档与后续实现必须把“世界地图关系”和“交通枢纽关系”分开描述。

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
- 表达验证：
  - 输出的每一段都带方式和经过地图。
  - 连续 `walk` 被压缩为单段展示。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：确认新建 `navigation` 模块、混合数据源、Dijkstra 路径图与顶部路径 UI 设计 |
| 2026-04-27 | 数据源规则收紧：`NavigationManualEdges.lua` 不再作为运行时数据源，所有导航节点、边、目标规则、坐标与限制必须从契约导出 |
| 2026-04-27 | 复审修订：目标源改为用户 waypoint，加入 `x/y` 成本模型、静态连接器 / 运行时过滤拆层与缓存策略，并明确排除 tooltip 与 EJ 性能修复 |
| 2026-04-27 | 用户确认“开动”：真实 `Taxi*` 导出进入执行范围，`navigation_taxi_edges` 从 draft 推进为 active，生成 `NavigationTaxiEdges.lua` 并加入 TOC |
| 2026-04-27 | 路线边统一导出：新增 `navigation_route_edges` active 契约，`NavigationRouteEdges.lua` 成为 `Toolbox.Navigation` 唯一运行时路线边入口 |
| 2026-04-29 | 设计基线重定义：导航图改为“当前角色配置 + 最少步数 + 枢纽 / 动作图”，V1 先支持 `taxi / hearthstone / class_teleport / class_portal / walk_local`，`transport / public_portal / areatrigger / walk component` 延后到 V2 |
