# 地图导航测试记录

- 文档类型：测试
- 状态：已通过
- 主题：navigation
- 适用范围：`navigation` 路径核心、Data 层、模块注册、世界地图入口与顶部路径 UI
- 关联模块：`navigation`
- 关联文档：
  - `docs/features/navigation-features.md`
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
- 最后更新：2026-04-27

## 1. 测试背景

- `navigation` 新模块第一版已接入路径核心、世界地图“规划路线”按钮、顶部路径条、地图基础节点导出数据与 Taxi 公共交通导出边。
- 本测试记录覆盖自动化验证结果与需要游戏内复测的关键点。

## 2. 测试范围

- `Toolbox.Navigation` Dijkstra 最短路径求解。
- 当前角色可用性过滤：职业、阵营、已确认技能。
- 多枢纽路径验收：仅保留契约导出数据样例；手工维护 ID 的传送门与职业位移样例已废弃。
- `NavigationMapNodes` / `NavigationTaxiEdges` / `NavigationRouteEdges` 数据契约与文件头。
- `NavigationManualEdges` 不得被 TOC 加载，`Toolbox.Navigation` 不得消费该文件。
- `navigation` 模块注册、设置页契约、TOC 与本地化键。
- `RouteBar` 顶部路径条显示 / 清除。
- `WorldMap` 世界地图按钮创建与点击规划链路。

## 3. 测试环境

- 本地仓库：`D:\WoWProject\WoWPlugin`
- Python：本机 `python`
- Lua 测试：`busted`
- 数据库：`WoWTools/data/sqlite/wow.db`
- 客户端目标：魔兽世界正式服 Retail

## 4. 测试用例

| 编号 | 前置条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| NAV-001 | 构造三个节点与多条边 | 调用 `FindShortestPath()` | 返回最低总耗时路线与步骤 |
| NAV-002 | 构造含职业 / 阵营 / 技能要求的边 | 调用 `FilterRouteGraph()` | 只保留当前角色已确认可用的边 |
| NAV-003 | 构造导出形状的路径数据并带技能要求 | 调用 `GetRequiredSpellIDList()` / `FilterRouteGraph()` | 只收集并保留已确认可用的导出边 |
| NAV-004 | TOC 包含 navigation Data 列表 | 运行设置 / TOC 校验 | `NavigationManualEdges.lua` 不得出现 |
| NAV-005 | 注入自定义导出形状的 `NavigationRouteEdges` | 规划目标地图 | 结果使用统一导出数据中的 label 和 cost |
| NAV-006 | 加载 `NavigationMapNodes` 与 `NavigationRouteEdges` | 校验导出边引用 | 所有导出节点、边、目标规则可解析 |
| NAV-007 | 加载 `RouteBar.lua` | 调用 `ShowRoute()` / `ClearRoute()` | 顶部路径条显示步骤并可隐藏 |
| NAV-008 | 模拟 `WorldMapFrame` | 调用 `WorldMap.Install()` 并触发 OnShow / OnClick | 只创建一次按钮，并调用规划链路 |
| NAV-009 | 加载 `Navigation.lua` 模块 | 调用模块 enable / disable 回调 | 启用安装世界地图入口，禁用隐藏入口并清除路线 |
| NAV-010 | 当前角色位于导出的 UiMapLink 起点地图 | 规划 DB 明确关系可达目标 | 使用 `UiMapLink` 导出的统一路线边 |
| NAV-011 | 新增 `navigation_instance_entrances` 契约后 | 导出剃刀高地入口 | `journalInstanceID=233` 输出外部入口目标，不指向副本内部 `MapID=129` |
| NAV-012 | 新增 `navigation_map_assignments` 契约后 | 校验入口坐标转换 | 入口目标 `uiMapID/x/y` 来自 `uimapassignment` 覆盖规则 |
| NAV-013 | 从真实 `wow.db` 导出 `navigation_taxi_edges` | 运行 `export_toolbox_one.py navigation_taxi_edges` | 生成 `NavigationTaxiEdges.lua`，文件头、节点与边结构符合契约 |
| NAV-014 | 当前角色位于银月城，目标为剃刀高地副本入口 | 规划副本入口目标 | 若相关连接边未由数据库导出，允许保守返回直接目标或无中转路线，不允许使用手工传送门 ID |
| NAV-015 | 从真实 `wow.db` 导出 `navigation_route_edges` | 运行 `export_toolbox_one.py navigation_route_edges` | 生成 `NavigationRouteEdges.lua`，运行时规划测试只覆盖统一路线边入口，且不包含 `MAP_REGION` / `MAP_TRACE` |

## 5. 执行结果

- `python tests/validate_data_contracts.py`
  - 结果：通过，包含 `navigation_map_nodes`、`navigation_taxi_edges` 与 `navigation_route_edges`，并校验生成型 Data 文件已加入 TOC。
- `python -m unittest scripts.export.tests.test_lua_contract_writer`
  - 结果：通过，覆盖 document `map_object` 字符串键渲染为 Lua 字面量。
- `python -m unittest scripts.export.tests.test_contract_export`
  - 结果：通过。
- `python scripts/export/export_toolbox_one.py navigation_taxi_edges --contract-dir DataContracts --data-dir Toolbox/Data`
  - 结果：通过，生成 91 个 Taxi 节点与 129 条公共交通边。
- `python scripts/export/export_toolbox_one.py navigation_route_edges --contract-dir DataContracts --data-dir Toolbox/Data`
  - 结果：通过，生成统一运行时路线边文件；只保留 `UiMapLink` 明确链接边，不包含 `MAP_REGION` / `MAP_TRACE` / `WAYPOINT` / `WAYPOINT_ACCESS`。
- `python tests/validate_settings_subcategories.py`
  - 结果：通过，包含 `navigation` 模块、TOC、Locales 与 Data 入口。
- `busted tests/logic/spec/navigation_*_spec.lua`
  - 结果：通过，包含银月城到剃刀高地入口回归用例。
- `python tests/run_all.py --ci`
  - 结果：通过，`115 successes / 0 failures / 0 errors / 0 pending`。

## 6. 问题与阻塞

- 尚未进行真实客户端内的鼠标坐标与按钮位置复测。
- 当前路线边只覆盖已导出的地图节点与 `UiMapLink` 明确链接边；其它交通需要后续契约导出，禁止用坐标区域或 SafeLoc 关系补洞。

## 7. 结论

- 本轮 Taxi、地图覆盖与副本入口数据契约、导出脚本、TOC 接线与 writer 单测已通过；项目总验证已全绿。
- 本轮 `navigation_map_assignments` 与 `navigation_instance_entrances` 数据契约、导出脚本、TOC 接线与剃刀高地入口回归校验已通过。
- 本轮 `navigation_route_edges` 数据契约、导出脚本、TOC 接线与运行时统一消费入口已接通；`Toolbox.Navigation` 不再直接消费 `NavigationTaxiEdges`，也不消费坐标区域、轨迹或 SafeLoc 派生联接边。
- 第一版代码链路满足“世界地图目标 / 副本入口目标 -> 导出数据消费 -> 路径求解 / waypoint -> 顶部路径 UI”的基础验收。
- 后续重点是导出 `navigation_map_assignments` 与 `navigation_instance_entrances`，优先修复副本入口目标，再评估传送门与职业旅行技能候选契约。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：记录 `navigation` 第一版自动化验证结果 |
| 2026-04-27 | 补充 Taxi 公共交通正式导出验证结果与当前总测试剩余失败 |
| 2026-04-27 | 重规划导航数据导出：废弃手工路径边验收，新增副本入口与地图覆盖导出验收 |
| 2026-04-27 | 副本入口导出链路落地：`python tests/run_all.py --ci` 通过，剃刀高地入口目标导出为外部千针石林坐标 |
| 2026-04-27 | 路线边统一导出落地：新增 `navigation_route_edges` 验收，运行时测试改为注入 `NavigationRouteEdges` |
| 2026-04-27 | 修正路线边验收：禁止 `MAP_REGION` / `MAP_TRACE` 坐标派生联接进入运行时数据 |
| 2026-04-27 | 再次收紧路线边验收：禁止 `WAYPOINT` / `WAYPOINT_ACCESS` 与 SafeLoc 坐标接入进入运行时数据 |
