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
- 最后更新：2026-04-30（数字 node ID 回归已收口）

## 1. 测试背景

- `navigation` 当前测试基线已重定义为“当前角色配置 + 最少路径步数”的多模态路线图。
- V1 已接入路径核心、世界地图“规划路线”按钮、顶部路径条、Taxi 静态骨架、能力模板导出，以及当前角色的已学法术 / 已开航点 / 炉石绑定点运行时快照。
- 本测试记录覆盖自动化验证结果与需要游戏内复测的关键点。

## 2. 测试范围

- `Toolbox.Navigation` 最少步数求解、平局规则与连续 `walk_local` 压缩。
- 当前角色可用性过滤：职业、阵营、已确认技能、已开航点、炉石绑定点。
- 多枢纽路径验收：统一消费契约导出的静态骨架与能力模板；手工维护 ID 的传送门与职业位移样例已废弃。
- `NavigationMapNodes` / `NavigationTaxiEdges` / `NavigationRouteEdges` / `NavigationAbilityTemplates` 数据契约与文件头。
- `NavigationManualEdges` 不得被 TOC 加载，`Toolbox.Navigation` 不得消费该文件。
- `NavigationRouteEdges` / `NavigationAbilityTemplates` 的 opaque numeric node ID 口径：测试必须通过 `Source / SourceID / Kind` 或数字 `NodeID` 解析节点，不能再依赖旧字符串节点键。
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
| NAV-001 | 构造三节点与多条候选边 | 调用 `FindShortestPath()` | 返回最少步数路线，而不是旧 `totalCost` 路线 |
| NAV-002 | 构造含职业 / 阵营 / 技能 / 飞行点要求的边 | 调用 `FilterRouteGraph()` | 只保留当前角色已确认可用的边 |
| NAV-003 | 构造导出形状的路线骨架与能力模板 | 调用 `GetRequiredSpellIDList()` | 收集运行时需要确认的技能列表 |
| NAV-004 | TOC 包含 navigation Data 列表 | 运行设置 / TOC 校验 | `NavigationManualEdges.lua` 不得出现 |
| NAV-005 | 注入自定义导出形状的 `NavigationRouteEdges` 与 `NavigationAbilityTemplates` | 规划目标地图 | 结果按 `segments / totalSteps` 输出，并可展开 `hearthstone / class travel` |
| NAV-006 | 加载 `NavigationMapNodes`、`NavigationRouteEdges` 与 `NavigationAbilityTemplates` | 校验导出引用 | 所有导出节点、边与能力模板都可解析 |
| NAV-007 | 加载 `RouteBar.lua` | 调用 `ShowRoute()` / `ClearRoute()` | 顶部路径条显示步骤并可隐藏 |
| NAV-008 | 模拟 `WorldMapFrame` | 调用 `WorldMap.Install()` 并触发 OnShow / OnClick | 只创建一次按钮，并调用规划链路 |
| NAV-009 | 加载 `Navigation.lua` 模块 | 调用模块 enable / disable 回调 | 启用安装世界地图入口，禁用隐藏入口并清除路线 |
| NAV-010 | 当前角色位于起点地图，具备已开航点与炉石绑定点 | 规划可达目标 | 可用 `taxi`、`hearthstone` 与职业旅行模板组成 V1 路线 |
| NAV-011 | 新增 `navigation_instance_entrances` 契约后 | 导出剃刀高地入口 | `journalInstanceID=233` 输出外部入口目标，不指向副本内部 `MapID=129` |
| NAV-012 | 新增 `navigation_map_assignments` 契约后 | 校验入口坐标转换 | 入口目标 `uiMapID/x/y` 来自 `uimapassignment` 覆盖规则 |
| NAV-013 | 从真实 `wow.db` 导出 `navigation_taxi_edges` | 运行 `export_toolbox_one.py navigation_taxi_edges` | 生成 `NavigationTaxiEdges.lua`，文件头、节点与边结构符合契约 |
| NAV-014 | 从真实 `wow.db` 导出 `navigation_ability_templates` | 运行 `export_toolbox_one.py navigation_ability_templates` | 生成 `NavigationAbilityTemplates.lua`，只保留 V1 可静态解析目标的职业旅行模板 |
| NAV-015 | 从真实 `wow.db` 导出 `navigation_route_edges` | 运行 `export_toolbox_one.py navigation_route_edges` | 生成 `NavigationRouteEdges.lua`，运行时规划测试只覆盖统一静态路线骨架入口 |
| NAV-016 | 注入 `transport` 模式边与两端已开航点 | `PlanRouteToMapTarget()` 规划跨大陆路线 | 路线输出含 `mode = "transport"` 段；缺少任一端航点时返回无路 |

## 5. 执行结果

- `python tests/validate_data_contracts.py`
  - 结果：通过，包含 `navigation_map_nodes`、`navigation_taxi_edges`、`navigation_route_edges` 与 `navigation_ability_templates`，并校验生成型 Data 文件已加入 TOC。
- `python -m unittest scripts.export.tests.test_lua_contract_writer`
  - 结果：通过，覆盖 document `map_object` 字符串键渲染为 Lua 字面量。
- `python -m unittest scripts.export.tests.test_contract_export`
  - 结果：通过。
- `python scripts/export/export_toolbox_one.py navigation_taxi_edges --contract-dir DataContracts --data-dir Toolbox/Data`
  - 结果：通过，生成 91 个 Taxi 节点与 129 条公共交通边。
- `python scripts/export/export_toolbox_one.py navigation_route_edges --contract-dir DataContracts --data-dir Toolbox/Data`
  - 结果：通过，生成统一运行时静态路线骨架文件；当前统一边表包含已闭合的 `taxi / transport / public_portal` 公共边，并要求 `edges` 保持 1-based 连续序列，供运行时 `ipairs()` 安全消费。
- `python scripts/export/export_toolbox_one.py navigation_ability_templates --contract-dir DataContracts --data-dir Toolbox/Data`
  - 结果：通过，生成 `NavigationAbilityTemplates.lua`；当前保留 `炉石 + 可静态解析目标的职业旅行法术`。
- `python tests/validate_settings_subcategories.py`
  - 结果：通过，包含 `navigation` 模块、TOC、Locales 与 Data 入口。
- `busted tests/logic/spec/navigation_*_spec.lua`
  - 结果：通过，覆盖最少步数、`walk_local` 压缩、`taxi` 可用性、`hearthstone / class travel` 模板展开、世界地图入口与顶部路径条。
- `python tests/run_all.py --ci`
  - 结果：通过，`144 successes / 0 failures / 0 errors / 0 pending`。

## 6. 问题与阻塞

- 尚未进行真实客户端内的鼠标坐标与按钮位置复测。
- `transport` 与当前需要的 `public_portal` 样例链路已闭合；`areatrigger / 全世界 walk component` 仍待后续契约导出。
- 当前数据回归还锁定了一个边界：在补到静态 destination 数据源之前，`NavigationRouteEdges.lua` 不允许导出 `areatrigger` 运行时节点或边。

## 7. 结论

- 本轮 Taxi、地图覆盖、副本入口、能力模板与统一静态路线骨架的契约、导出脚本、TOC 接线与逻辑测试已通过；项目总验证全绿。
- 本轮 `navigation_route_edges` 与 `navigation_ability_templates` 已成为运行时 V1 的两条正式数据入口；`Toolbox.Navigation` 不再直接消费来源侧候选边，也不消费手工路径数据。
- 当前代码链路满足”世界地图目标 / 副本入口目标 -> 导出数据消费 -> 最少步数求解 -> 顶部路径 UI”的 V1 验收。
- 自 2026-04-30 起，`银月城 -> 东瘟疫之地` 已成为正向回归样例：`portal_118/556`、`taxi_82`、奥格传送门房并入与 `edges` 连续序列约束均由测试锁定。
- 自 2026-04-30 起，`navigation_api_spec.lua` 与 `navigation_data_spec.lua` 已完成数字 node ID 迁移；回归断言统一通过 `Source / SourceID / Kind` 或数字 `NodeID` 解析节点，不再依赖 `portal_118`、`taxi_3131` 这类旧字符串键。
- 后续重点转向 `areatrigger / 道标石 / walk component` 等未闭合模态，以及更强的“唯一公共路径 / 只能飞”判定能力。

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
| 2026-04-29 | V1 口径切换为”当前角色配置 + 最少路径步数”，新增 `navigation_ability_templates` 与 `KnownTaxiNodeIDs / HearthBindNodeID` 回归验证 |
| 2026-04-30 | 导出闭环回归：`银月城 -> 东瘟疫之地` 由 `NO_ROUTE` 缺口样例升级为正向样例；新增 `edges` 连续序列与东部王国公共交通链路回归 |
| 2026-04-29 | V2 推进：`transport`（飞艇/船）闭合，新增 NAV-016 验证 transport 模式边的可用性过滤与路线输出 |
| 2026-04-30 | 数字 node ID 收口：导航 API / Data 逻辑测试迁移到 `Source / SourceID / Kind` 与数字 `NodeID` 口径；`run_all.py --ci` 更新为 `144 successes` |
