# 地图导航功能说明

- 文档类型：功能
- 状态：已发布
- 主题：navigation
- 适用范围：`navigation` 模块第一版地图目标路线规划
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/tests/navigation-test.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-29（实现/导出对齐，补充当前覆盖边界）

## 1. 定位

- `navigation` 是独立地图导航模块，用于从世界地图目标生成当前角色可用的旅行路线。
- 当前基线已重定义为“当前角色配置 + 最少路径步数”的多模态路线图；运行时统一消费静态路线骨架，并按当前角色的已学法术、已开航点与炉石绑定点裁剪可用路径。

## 2. 适用场景

- 玩家打开世界地图并放置用户 waypoint 后，希望插件按已导出的地图与交通数据给出路线步骤。
- 典型场景：副本入口导航必须使用导出的外部入口位置，而不是副本内部地图；例如剃刀高地应导出 `journalInstanceID=233` 的入口目标。

## 3. 当前能力

- 在 `navigation` 模块启用后，世界地图显示时会创建“规划路线”按钮。
- 点击“规划路线”会读取当前用户 waypoint 的 `uiMapID` 与归一化坐标。
- 路径规划只消费 DataContracts 契约导出的导航数据；当前角色快照至少包含 `Class / Faction / KnownSpellIDs / KnownTaxiNodeIDs / HearthBindNodeID`。
- 顶部路径条 `ToolboxNavigationRouteBar` 会在屏幕顶部中间显示总步数与逐段路线。
- 当前静态数据按职责分成多份导出表：
  - `Toolbox.Data.NavigationMapNodes`：由 `DataContracts/navigation_map_nodes.json` 通过正式导出脚本生成的 UiMap 基础节点。
  - `Toolbox.Data.NavigationMapAssignments`：由 `DataContracts/navigation_map_assignments.json` 从 `uimapassignment` 导出的世界坐标覆盖范围。
  - `Toolbox.Data.NavigationInstanceEntrances`：由 `DataContracts/navigation_instance_entrances.json` 从 `journalinstanceentrance` 等表导出的副本入口外部目标。
  - `Toolbox.Data.NavigationTaxiEdges`：由 `DataContracts/navigation_taxi_edges.json` 从 `wow.db` 的 `TaxiNodes / TaxiPath / TaxiPathNode` 导出的 Taxi 来源侧数据。
  - `Toolbox.Data.NavigationRouteEdges`：由 `DataContracts/navigation_route_edges.json` 统一导出的运行时静态路线骨架；当前包含已闭合的 `taxi / transport / public_portal` 公共边，以及对应运行时节点。
  - `Toolbox.Data.NavigationAbilityTemplates`：由 `DataContracts/navigation_ability_templates.json` 导出的能力模板；当前覆盖 `hearthstone` 与可静态解析目标的职业旅行法术。
- 当前运行时已支持：
  - `walk_local`
  - `taxi`
  - `transport`
  - `public_portal`
  - `hearthstone`
  - `class_teleport`
  - `class_portal`

## 4. 入口与使用方式

- 打开世界地图。
- 放置或保留当前用户 waypoint。
- 点击世界地图上的“规划路线”按钮。
- 查看屏幕顶部中间显示的路线步骤。

## 5. 设置项

- 模块设置页提供公共启用 / 调试 / 重置入口。
- 顶部路径条第一版固定在屏幕顶部中间，不开放拖动设置。
- 最近目标调试字段保存在 `ToolboxDB.modules.navigation.lastTargetUiMapID / lastTargetX / lastTargetY`。

## 6. 已知限制

- 第一版不做账号其他角色能力推断，只看当前角色。
- 第一版不实现真实地形寻路、避障或逐米移动路线。
- `public_portal` 已进入运行时图，但世界覆盖仍未闭合；“节点存在”不等于“这条世界路线已经静态可证明”。
- `areatrigger / 全世界 walk component` 仍未闭合，不进入实际可达路径。
- 截至 2026-04-30，`areatrigger` 的阻塞点不是运行时求解器，而是当前 `wow.db` 只有 source 点位、没有可导出的 destination 数据源。
- 截至 2026-04-30，world `walk component` 也没有现成静态真值；现有 `WalkClusterKey` 只是本地归并辅助键，不是世界步行连通证明。
- 无法仅靠静态导出稳定解析目标的职业/剧情传送法术，当前不会进入 `NavigationAbilityTemplates`。
- 当前不拦截世界地图原生点击；目标坐标由“鼠标指向 + 点击规划按钮”确定。
- 自 2026-04-30 起，`银月城 -> 东瘟疫之地` 已不再是 `NAVIGATION_ERR_NO_ROUTE` 样例；当前静态导出图已通过 `portal_118 -> portal_119`、`portal_556 -> portal_557`、`taxi_82` 与奥格传送门房并入规则闭合这条路线。
- 但这条正向样例仍不代表系统已经闭合全部世界关系；`areatrigger`、全世界 `walk component` 与“只能飞 / 没有别路”这类排除法结论仍待后续阶段完成。

## 7. 关联文档

- 需求：`docs/specs/navigation-spec.md`
- 设计：`docs/designs/navigation-design.md`
- 计划：`docs/plans/navigation-plan.md`
- 测试：`docs/tests/navigation-test.md`
- 总设计：`docs/Toolbox-addon-design.md`

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：发布 `navigation` 第一版地图目标路线规划功能说明 |
| 2026-04-27 | 扩充为多枢纽旅行图：纳入当前位置、部落公共传送门、奥格瑞玛传送门房与部分非 mage 职业位移 |
| 2026-04-27 | 接入 Taxi 公共交通导出数据：新增 `NavigationTaxiEdges.lua` 作为正式 Data 层 |
| 2026-04-27 | 数据源规则收紧：移除手工路径边运行时消费，导航数据只允许通过 DataContracts 导出 |
| 2026-04-27 | 路线边消费入口统一：新增 `NavigationRouteEdges.lua`，运行时构图不再直接读取 `NavigationTaxiEdges.lua` |
| 2026-04-27 | 接入副本入口导出数据：新增 `NavigationMapAssignments.lua` 与 `NavigationInstanceEntrances.lua`，副本入口导航使用导出的外部目标坐标 |
| 2026-04-29 | V1 基线重定义：路线按当前角色配置和最少路径步数计算，接入 `NavigationAbilityTemplates.lua`、已开航点过滤与炉石绑定点解析 |
| 2026-04-29 | V2 推进：`transport`（飞艇/船）闭合，导出脚本新增 transport 节点检测，`mode = "transport"` 边加入运行时路线图 |
| 2026-04-29 | V2 推进：`public_portal` 方案确认，进入实施 |
| 2026-04-29 | 文档同步：对齐当前实现，明确 `public_portal` 已参与运行时求解，并补充 `银月城 -> 东瘟疫之地` 的导出边界样例 |
| 2026-04-30 | 导出闭环：`银月城 -> 东瘟疫之地` 改为已闭合回归样例；同步记录 `portal_118/556`、`taxi_82` 与奥格传送门房并入已进入统一静态图 |
