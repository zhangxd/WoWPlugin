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

- `navigation` 新模块第一版已接入路径核心、世界地图“规划路线”按钮、顶部路径条、地图基础节点导出数据与手工玩法边。
- 本测试记录覆盖自动化验证结果与需要游戏内复测的关键点。

## 2. 测试范围

- `Toolbox.Navigation` Dijkstra 最短路径求解。
- 当前角色可用性过滤：职业、阵营、已确认技能。
- 多枢纽路径验收：法师多主城传送、银月城公共传送门网络、奥格瑞玛传送门房、死亡骑士 / 德鲁伊 / 武僧职业位移样例。
- `NavigationMapNodes` 数据契约与文件头。
- `NavigationManualEdges` 手工边引用完整性。
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
| NAV-003 | 法师、部落、已确认 `3567` | 规划杜隆塔尔目标 | 优先返回“传送：奥格瑞玛”路线 |
| NAV-004 | 法师但未确认 `3567` | 规划同一目标 | 不使用奥格瑞玛传送边 |
| NAV-005 | 注入自定义 `NavigationManualEdges` | 规划目标地图 | 结果使用 Data 中的 label 和 cost |
| NAV-006 | 加载 `NavigationMapNodes` 与 `NavigationManualEdges` | 校验手工边引用 | 所有手工节点、边、目标规则可解析 |
| NAV-007 | 加载 `RouteBar.lua` | 调用 `ShowRoute()` / `ClearRoute()` | 顶部路径条显示步骤并可隐藏 |
| NAV-008 | 模拟 `WorldMapFrame` | 调用 `WorldMap.Install()` 并触发 OnShow / OnClick | 只创建一次按钮，并调用规划链路 |
| NAV-009 | 加载 `Navigation.lua` 模块 | 调用模块 enable / disable 回调 | 启用安装世界地图入口，禁用隐藏入口并清除路线 |
| NAV-010 | 当前角色位于银月城且无职业传送 | 规划海加尔山目标 | 返回“当前位置：银月城 -> 奥格瑞玛 -> 海加尔山”公共传送门路线 |
| NAV-011 | 法师已确认银月城 / 雷霆崖 / 幽暗城 / 沙塔斯传送 | 规划对应主城目标 | 使用对应法师传送而不是只走奥格瑞玛 |
| NAV-012 | 死亡骑士 / 德鲁伊 / 武僧已确认职业位移技能 | 规划阿彻鲁斯 / 海加尔山 / 昆莱山目标 | 使用死亡之门、梦境行者、禅宗朝圣等职业入口 |

## 5. 执行结果

- `python tests/validate_data_contracts.py`
  - 结果：通过，包含 `navigation_map_nodes`。
- `python tests/validate_settings_subcategories.py`
  - 结果：通过，包含 `navigation` 模块、TOC、Locales 与 Data 入口。
- `busted tests/logic/spec/navigation_*_spec.lua`
  - 结果：通过。
- `python tests/run_all.py --ci`
  - 结果：通过，`111 successes / 0 failures / 0 errors / 0 pending`。

## 6. 问题与阻塞

- 尚未进行真实客户端内的鼠标坐标与按钮位置复测。
- 当前路线边已覆盖第一批高频部落传送门与部分职业位移，但仍不是全量交通数据库。

## 7. 结论

- 自动化验证已通过。
- 第一版代码链路满足“世界地图目标 -> 当前角色能力过滤 -> 路径求解 -> 顶部路径 UI”的基础验收。
- 后续重点是继续扩充 `NavigationManualEdges` 中的玩具、炉石、节日传送、联盟侧完整传送门网络与更多职业特殊交通，并在游戏内复测不同地图缩放 / 平移状态下的鼠标坐标读取。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：记录 `navigation` 第一版自动化验证结果 |
