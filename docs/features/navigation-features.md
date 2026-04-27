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
- 最后更新：2026-04-27

## 1. 定位

- `navigation` 是独立地图导航模块，用于从世界地图目标生成当前角色可用的旅行路线。
- 第一版已把当前地点、地图基础节点和统一导出的路线边纳入同一张旅行图，并把路线显示在屏幕顶部中间；其它传送类能力必须等数据库契约导出后再进入运行时图。

## 2. 适用场景

- 玩家打开世界地图并放置用户 waypoint 后，希望插件按已导出的地图与交通数据给出路线步骤。
- 典型场景：副本入口导航必须使用导出的外部入口位置，而不是副本内部地图；例如剃刀高地应导出 `journalInstanceID=233` 的入口目标。

## 3. 当前能力

- 在 `navigation` 模块启用后，世界地图显示时会创建“规划路线”按钮。
- 点击“规划路线”会读取当前用户 waypoint 的 `uiMapID` 与归一化坐标。
- 路径规划只消费 DataContracts 契约导出的导航数据；若导出边包含职业、阵营或技能要求，再按当前角色运行时状态过滤。
- 顶部路径条 `ToolboxNavigationRouteBar` 会在屏幕顶部中间显示路线步骤。
- 当前静态数据分两层：
  - `Toolbox.Data.NavigationMapNodes`：由 `DataContracts/navigation_map_nodes.json` 通过正式导出脚本生成的 UiMap 基础节点。
  - `Toolbox.Data.NavigationMapAssignments`：由 `DataContracts/navigation_map_assignments.json` 从 `uimapassignment` 导出的世界坐标覆盖范围。
  - `Toolbox.Data.NavigationInstanceEntrances`：由 `DataContracts/navigation_instance_entrances.json` 从 `journalinstanceentrance` 等表导出的副本入口外部目标。
  - `Toolbox.Data.NavigationTaxiEdges`：由 `DataContracts/navigation_taxi_edges.json` 从 `wow.db` 的 `TaxiNodes / TaxiPath / TaxiPathNode` 导出的 Taxi 来源侧数据。
  - `Toolbox.Data.NavigationRouteEdges`：由 `DataContracts/navigation_route_edges.json` 统一导出的运行时路线边；`Toolbox.Navigation` 构图只消费该表，不直接消费各来源侧边表。

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

- 第一版不纳入飞行点 / 飞行管理员。
- 第一版不做账号其他角色能力推断，只看当前角色。
- 第一版不实现真实地形寻路、避障或逐米移动路线。
- 玩具、炉石、节日传送、战役阶段限定传送门、联盟侧完整传送门网络和更多职业特殊交通尚未形成数据库导出闭环，当前不进入运行时导航图。
- 当前不拦截世界地图原生点击；目标坐标由“鼠标指向 + 点击规划按钮”确定。

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
