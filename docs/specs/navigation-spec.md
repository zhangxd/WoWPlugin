# 地图导航模块需求规格

- 文档类型：需求
- 状态：可执行
- 主题：navigation
- 适用范围：`navigation` 新模块的世界地图目标选择、跨地图路径规划与顶部路径 UI
- 关联模块：`navigation`
- 关联文档：
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 背景

- 玩家在世界地图中选中目的地后，希望插件能给出“从当前角色当前位置到目标地点”的推荐路径。
- 推荐路径需要理解职业传送、传送门房、炉石、主城与资料片枢纽等高价值旅行能力，而不是只把目标地图打开或只放置系统 waypoint。
- 典型场景：当前角色是法师且已确认拥有奥格瑞玛传送或传送门能力时，选中奥格瑞玛或杜隆塔尔目标，路径应优先建议使用法师传送能力，再从落点前往目标区域。
- 首版实现复审发现两个 correctness 问题：世界地图按钮错误读取按钮点击时的鼠标位置，且路径规划完全丢弃了目标 `x/y`；本轮文档修订用于收敛这两项修正方案。

## 2. 目标

- 新增独立 `navigation` 模块，负责世界地图目标选择、路径图构建、可用性过滤、最短路径求解与路径 UI 展示。
- 第一版支持完整跨地图路线规划：技能、传送门、炉石、传送门房、地图内移动与目标坐标共同参与路径排序。
- 路径排序按预计耗时最短，但不计算跨地图加载时间。
- 未确认当前角色可用的技能、传送门、道具或路径边不参与推荐。

## 3. 范围

### 3.1 In Scope

- 新建 `navigation` 模块，模块 id 为 `navigation`。
- 在世界地图上以当前用户 waypoint 作为目标，并触发导航规划。
- 新增独立顶部路径 UI，第一版显示在屏幕顶部中间位置。
- 顶部路径 UI 显示每个路径地点或步骤，至少包含起点、传送/交通步骤、落点与目标地点。
- 仅支持当前角色的可用能力，不读取或推断账号内其他角色能力。
- 导航运行时数据只允许来自 `DataContracts/<contract_id>.json` 与 `scripts/export/` 生成的 `Toolbox/Data/*.lua`；禁止手工维护 `uiMapID`、路径边、目标规则、候选枢纽、落点坐标、职业技能边、阵营限制、成本与标签。
- 职业技能、传送门房、炉石、特殊道具等玩法路径若无法从数据库导出，当前阶段不进入运行时导航图；不得用手写 ID 补洞。
- 运行时路线边允许来自两类 DB 明确关系：`UiMapLink` 明确 UiMap 链接，以及基于 `waypointedge` + `UiMap/MapID` 关系解析出的主城传送 / 公共交通 `UiMap -> UiMap` 直连边；禁止用坐标或 SafeLoc 补接入。
- `navigation_taxi_edges` 只作为 Taxi 来源侧追溯数据，不进入运行时构图；普通飞行管理员路线不作为导航节点或路线边。
- 世界传送门后续优先评估 `AreaTrigger`，必要时辅以 `GameObjects`；按当前已确认表定义，先只承诺导出“传送门候选”，不承诺直接导出完整导航边。
- 职业旅行技能后续优先评估 `SkillLineAbility / ChrClasses / SpellEffect`；按当前已确认表定义，先只承诺导出“职业旅行技能候选”，目的地与落点仍需归一化。
- 路径求解前过滤不可用或未知可用性的路径边。
- 目标 `x/y` 必须参与路径排序，至少进入“当前点到入口”“落点到目标点”的图内移动成本估算。
- 固定世界事实（地图节点、传送门入口、落点、固定交互成本）静态化；职业、阵营、法术、玩具与玩家解锁状态运行时过滤。
- 法师奥格瑞玛传送 / 传送门能力作为第一版验收样例。

### 3.2 Out of Scope

- 第一版不支持账号其他角色能力。
- 第一版不把飞行管理员 / 飞行点作为导航边。
- 第一版不承诺覆盖所有玩具、节日传送、低频特殊交通或一次性任务传送。
- 第一版不承诺地图内真实寻路网格、避障、地形路径或逐米移动路线。
- 第一版不替代暴雪系统 waypoint；如需设置 waypoint，只作为辅助结果，不作为核心路径规划能力。
- 第一版不新增额外 slash 命令作为主入口。
- 本轮不把传送门并入公共交通验证链路；职业传送、传送门房与其他门类传送必须后续以独立导出契约接入，未导出前不参与规划。
- 本轮不处理 `tooltip_anchor` 的 taint 风险回退问题。
- `encounter_journal` 副本入口查询性能修复不并入本规格执行范围，需单独确认主方案后再落文档。

## 4. 已确认决策

- 模块归属选定为新建独立模块 `navigation`。
- 触发入口选定为读取当前用户 waypoint；世界地图按钮不再读取按钮点击时的鼠标坐标。
- 第一版验收边界选定为完整跨地图路径规划，技能、传送门、交通、地图内路径都参与排序。
- 数据来源选定为全导出方案：地图、区域、基础节点、公共交通边、副本入口、目标规则、路径边、候选枢纽、落点坐标、职业 / 阵营 / 成本 / 标签等所有导航运行时数据必须由数据库契约导出。
- “最佳路径”排序指标选定为预计耗时最短，并明确忽略跨地图加载时间。
- 未知能力 / 未知数据策略选定为保守：未确认当前角色可用的技能、传送门、飞行点、道具等不参与推荐。
- 第一版只支持当前角色能力，不做账号其他角色能力推断。
- 第一版不纳入飞行点导航。
- 第一版路线展示使用单独 UI，显示在屏幕顶部中间位置，内容包含每个路径地点 / 步骤。
- 未建立导出契约的传送、炉石、特殊道具、节日传送和低频特殊交通不进入运行时路径图。
- `DataContracts/navigation_route_edges.json` 是运行时路线边统一契约；允许导出 `UiMapLink` 与 `waypointedge` 解析出的直连边，禁止从矩形覆盖、相交、包含、采样点、轨迹坐标、SafeLoc、同父级或 `ParentUiMapID` 推导地图联接边。
- `DataContracts/navigation_map_assignments.json` 只保留 `UiMap <-> MapID` 关系，不再导出 `Region_*` / `UiMin*` / `UiMax*` 坐标字段。
- `DataContracts/navigation_taxi_edges.json` 只保留 Taxi 来源侧追溯形状与表关系；`Toolbox.Navigation` 不直接读取来源侧边表，也不把 TaxiPath 飞行管理员轨迹转换为“前往”边。
- 世界传送门的长期方向选定为“候选优先”：先评估 `AreaTrigger`，必要时再叠加 `GameObjects`；在目的地链路查实前，不生成最终导航边。
- 职业旅行技能的长期方向选定为“候选优先”：先评估 `SkillLineAbility / ChrClasses / SpellEffect` 导出职业与法术候选，再由归一化层补齐目的地与落点。
- 当前阶段必须移除 `NavigationManualEdges.lua` 的运行时消费与 TOC 加载；求解器只能消费已导出的 `targetRules` 或其它契约数据，未导出的目标不走中转规则。
- 固定世界事实采用静态连接器数据维护，玩家是否可用由运行时快照过滤，不把解锁状态写入静态导出。
- `target.x / target.y` 必须进入终段成本，同一 `uiMapID` 下不同目标点可产生不同成本或不同路线。
- 本轮范围显式排除 `Tooltip.lua` 修改。

## 5. 待确认项

- 关联 review 项：`EncounterJournal.lua` 的副本入口查询性能修复主方案未定，待用户在“预热缓存 / 静态索引 / 混合方案”之间确认；该项不阻塞当前 `navigation` 修订文档落地，但不进入本规格执行范围。

## 6. 验收标准

1. 世界地图存在当前用户 waypoint 时，可以基于该 waypoint 生成导航路线；没有 waypoint 时不生成路线。
2. 路线规划只消费由 DataContracts 契约导出的导航数据；TOC 与 `Toolbox.Navigation` 不加载、不读取 `NavigationManualEdges.lua`，且运行时路线边只从 `NavigationRouteEdges.lua` 进入构图。
3. 路径排序按预计耗时最短，且不计算跨地图加载时间。
4. 未确认当前角色可用的技能、传送门、道具或路径边不参与推荐。
5. 第一版不推荐飞行点 / 飞行管理员路径。
6. 当前角色为法师且已确认拥有奥格瑞玛传送或传送门能力时，选择奥格瑞玛或杜隆塔尔目标会优先推荐该技能路径。
7. 当前角色非法师，或法师技能未确认可用时，不推荐法师传送路径。
8. 顶部路径 UI 显示在屏幕顶部中间位置，并按顺序显示每个路径地点 / 步骤。
9. `navigation` 模块有独立启用开关，存档位于 `ToolboxDB.modules.navigation`。
10. 新增玩家可见字符串进入 `Toolbox/Core/Foundation/Locales.lua`。
11. 世界地图挂接使用 `WorldMapFrame:HookScript("OnShow", ...)`、可靠事件或经查证的地图 API 生命周期，不使用固定正数秒延迟作为主路径。
12. 涉及未使用过或记忆不确定的 WoW API 时，先核对 BlizzardInterfaceCode / Warcraft Wiki / 官方资料后实现。
13. 战斗中不执行会触发 taint 的受保护 UI 操作。
14. 同一 `uiMapID` 下不同目标 `x/y` 会进入成本计算；至少在终段成本上产生差异。
15. 模拟公共交通数据至少覆盖飞艇 / 船样板，并能把奥格瑞玛到北风苔原这类公共交通目标纳入导航测试骨架。
16. 本轮自动化验证通过 `python tests/run_all.py --ci`，并覆盖路径求解、可用性过滤、waypoint 目标读取、同图不同坐标成本差异、模拟公共交通边消费与 Config 默认值。

## 7. 实施状态

- 当前状态：真实 `Taxi*` 数据库导出已确认开动，进入契约对齐、正式导出、TOC 接线与验证阶段。
- 下一步：按 `docs/plans/navigation-plan.md` 推进 `navigation_taxi_edges` 契约转 active、生成 `NavigationTaxiEdges.lua`、加入 TOC 并补跑自动化验证。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：按用户确认建立 `navigation` 新模块需求，状态设为可执行 |
| 2026-04-27 | 复审修订：目标源改为用户 waypoint，明确 `x/y` 进入成本模型，排除 tooltip 修改，并将 EncounterJournal 性能修复列为待确认关联项 |
| 2026-04-27 | 范围补充：公共交通边长期方案确认走 `Taxi*` 自动导出，但当前执行边界改为先用模拟飞艇 / 船数据跑测试，真实数据库导出待后续单独开动 |
| 2026-04-27 | 实施更新：waypoint 目标源、`x/y` 成本接入与模拟公共交通消费代码已落地；按本轮用户要求暂未运行自动化测试 |
| 2026-04-27 | 数据契约补充：新增 `navigation_taxi_edges` draft 契约，先固定 TaxiNodes / TaxiPath / TaxiPathNode 的导出形状与过滤规则，真实环境验证待后续执行 |
| 2026-04-27 | 数据源规则收紧：所有 navigation 运行时数据必须由 DataContracts 契约导出，移除 `NavigationManualEdges.lua` 的运行时消费与 TOC 加载 |
| 2026-04-27 | 用户确认“开动”：真实 `Taxi*` 数据库导出进入当前范围，`navigation_taxi_edges` 将从 draft 推进为 active，并生成 `NavigationTaxiEdges.lua` 加入 TOC |
| 2026-04-27 | 路线边统一导出：新增 `navigation_route_edges` 契约，运行时构图统一消费 `NavigationRouteEdges.lua`，来源侧 `NavigationTaxiEdges.lua` 不再被 `Toolbox.Navigation` 直接读取 |
