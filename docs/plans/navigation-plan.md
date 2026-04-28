# 地图导航 V1（最少步数路线图）实施计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents are explicitly authorized) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 `navigation` 从“按 `UiMap` + `cost` 规划旧路径”的实现，重构为“按当前角色配置、最少路径步数、枢纽 / 动作图”工作的 V1 导航闭环，并稳定输出每段方式与经过地图。

**Architecture:** `Toolbox.Navigation` 统一消费 DataContracts 导出的静态路线骨架；查询时按当前角色配置展开 `hearthstone / class_teleport / class_portal` 模板边，并为起点、终点和同本地连通域枢纽补 `walk_local` 接入；主求解器使用 BFS，并按固定平局规则输出 `segments`。`navigation` 模块只负责 waypoint 入口、角色快照采集和顶部路径条渲染。

**Tech Stack:** WoW Retail Lua、DataContracts JSON、`scripts/export/export_toolbox_one.py`、`ToolboxDB.modules.navigation`、`busted` 逻辑测试、`python tests/validate_data_contracts.py`、`python tests/validate_settings_subcategories.py`、`python tests/run_all.py --ci`。

---

## 1. 历史说明

- 本文件自 2026-04-29 起，以上方“当前角色配置 + 最少路径步数 + 枢纽 / 动作图”为唯一执行基线。
- 2026-04-27 那一版“预计耗时 + Dijkstra + `UiMap` 联接边”的实施记录不再作为执行步骤保留；历史细节改由 git 记录追溯。
- 后续实现、测试、导出和文档回写，全部以 `docs/specs/navigation-spec.md` 与 `docs/designs/navigation-design.md` 为准。

## 2. 已确认边界

- 最短路主指标：`最少路径步数`
- 当前角色输入至少包含：
  - `Faction`
  - `Class`
  - `KnownSpellIDs`
  - `KnownTaxiNodeIDs`
  - `HearthBindNodeID`
- V1 只闭合这 5 类动作：
  - `walk_local`
  - `taxi`
  - `hearthstone`
  - `class_teleport`
  - `class_portal`
- 路线输出必须包含：
  - `totalSteps`
  - `segments`
  - 每段 `mode`
  - 每段起点 / 终点
  - 每段 `TraversedUiMapIDs`
  - 每段 `TraversedUiMapNames`
- 连续 `walk` 段最终显示时必须压缩为 1 段。
- 运行时静态数据只允许来自 DataContracts 导出；不得重新引入手工导航边。
- `transport / public_portal / areatrigger / 道标石 / 全世界 WalkComponent` 全部延后到 V2。
- 在 V2 闭合前，不允许下 `only_taxi`、`must_use_transport`、`no_public_route` 这类排除法结论。

## 3. 文件布局

### 3.1 运行时核心

- 修改：`Toolbox/Core/API/Navigation.lua`
- 修改：`Toolbox/Modules/Navigation.lua`
- 修改：`Toolbox/Modules/Navigation/Shared.lua`
- 修改：`Toolbox/Modules/Navigation/WorldMap.lua`
- 修改：`Toolbox/Modules/Navigation/RouteBar.lua`
- 修改：`Toolbox/Core/Foundation/Config.lua`
- 修改：`Toolbox/Core/Foundation/Locales.lua`

### 3.2 导出契约与生成数据

- 修改：`DataContracts/navigation_route_edges.json`
- 修改：`DataContracts/navigation_taxi_edges.json`
- 新增：`DataContracts/navigation_ability_templates.json`
- 修改：`Toolbox/Data/NavigationRouteEdges.lua`（生成）
- 修改：`Toolbox/Data/NavigationTaxiEdges.lua`（生成）
- 新增：`Toolbox/Data/NavigationAbilityTemplates.lua`（生成）
- 修改：`Toolbox/Toolbox.toc`

### 3.3 测试与验证

- 修改：`tests/logic/spec/navigation_api_spec.lua`
- 修改：`tests/logic/spec/navigation_data_spec.lua`
- 修改：`tests/logic/spec/navigation_worldmap_spec.lua`
- 修改：`tests/logic/spec/navigation_routebar_spec.lua`
- 修改：`tests/logic/spec/navigation_module_spec.lua`
- 修改：`tests/validate_data_contracts.py`
- 修改：`tests/validate_settings_subcategories.py`
- 按需修改：`scripts/export/lua_contract_writer.py`
- 按需修改：`scripts/export/tests/test_lua_contract_writer.py`

### 3.4 文档

- 修改：`docs/features/navigation-features.md`
- 修改：`docs/tests/navigation-test.md`
- 修改：`docs/Toolbox-addon-design.md`
- 修改：`docs/plans/navigation-plan.md`

## 4. 关键实现约束

- `navigation_route_edges` 不再表达 `MAP_LINK`、`WAYPOINT_LINK`、`UiMap` 邻接猜想；它只表达 V1 运行时真正消费的静态路线骨架。
- V1 静态骨架至少包含两类节点：
  - `map_anchor`：每张参与 V1 的 `UiMap` 锚点
  - `taxi`：飞行点 / 飞行管理员节点
- V1 静态骨架至少包含一类静态边：
  - `taxi`
- `walk_local` 不提前导出成全世界边；运行时根据本次查询动态补接：
  - 起点 `QueryPoint` -> 同本地连通域枢纽
  - 枢纽 -> 终点 `QueryPoint`
  - 同一 `walkClusterKey` 内的可步行换乘
- 能力类动作不写死在 `Navigation.lua`；用 `navigation_ability_templates` 导出模板，再按当前角色配置展开。
- 如果某个职业技能无法稳定导出“法术 -> 目标节点 / 目标规则”，就不进入 V1。
- 如果 `navigation_ability_templates` 或 `navigation_route_edges` 需要输出数组字段（如 `TraversedUiMapIDs`），导出链路必须保留 Lua 数组，不允许退化成逗号字符串。

## 5. 执行步骤

## Chunk 1: 锁定新口径的测试与结果模型

**Files:**
- Modify: `tests/logic/spec/navigation_api_spec.lua`
- Modify: `tests/logic/spec/navigation_data_spec.lua`
- Modify: `tests/logic/spec/navigation_worldmap_spec.lua`
- Modify: `tests/logic/spec/navigation_routebar_spec.lua`
- Modify: `tests/logic/spec/navigation_module_spec.lua`

- [ ] **Step 1: 重写 API 断言口径**

把 `totalCost` / `stepLabels` 主断言改成 `totalSteps` / `segments`，并增加以下覆盖：
- 最少步数优先于旧 `cost`
- 平局规则：更少 `walk` -> 更短本地步行 -> 更少步骤名称切换 -> 稳定 ID
- 连续 `walk` 在输出里被压缩
- `taxi` 段带 `TraversedUiMapIDs` 和 `TraversedUiMapNames`

- [ ] **Step 2: 重写数据断言口径**

把 `tests/logic/spec/navigation_data_spec.lua` 从“只允许 `MAP_LINK` / `WAYPOINT_LINK`”改成“只允许 V1 静态骨架字段”：
- 节点至少断言 `Kind / UiMapID / WalkClusterKey`
- `taxi` 节点断言 `TaxiNodeID`
- 边至少断言 `Mode / StepCost / TraversedUiMapIDs / TraversedUiMapNames`

- [ ] **Step 3: 重写 UI 断言口径**

让 `navigation_worldmap_spec.lua` 和 `navigation_routebar_spec.lua` 断言：
- 世界地图入口仍读取用户 waypoint
- `RouteBar` 读取 `segments` 渲染，而不是直接拼 `stepLabels`
- 顶部路径条显示总步数和逐段方式

- [ ] **Step 4: 运行定向逻辑测试，确认先失败**

Run:
```bash
busted tests/logic/spec/navigation_api_spec.lua
busted tests/logic/spec/navigation_data_spec.lua
busted tests/logic/spec/navigation_worldmap_spec.lua
busted tests/logic/spec/navigation_routebar_spec.lua
```

Expected:
- 旧实现仍返回 `totalCost`
- 旧数据仍是 `MAP_LINK` / `WAYPOINT_LINK`
- 旧 RouteBar 仍依赖 `stepLabels`

- [ ] **Step 5: Commit**

```bash
git add tests/logic/spec/navigation_api_spec.lua tests/logic/spec/navigation_data_spec.lua tests/logic/spec/navigation_worldmap_spec.lua tests/logic/spec/navigation_routebar_spec.lua tests/logic/spec/navigation_module_spec.lua
git commit -m "test: lock navigation v1 minimum-step route semantics"
```

## Chunk 2: 重写 V1 静态路线骨架导出

**Files:**
- Modify: `DataContracts/navigation_taxi_edges.json`
- Modify: `DataContracts/navigation_route_edges.json`
- Modify: `Toolbox/Data/NavigationTaxiEdges.lua`
- Modify: `Toolbox/Data/NavigationRouteEdges.lua`
- Modify: `tests/validate_data_contracts.py`
- Modify: `tests/logic/spec/navigation_data_spec.lua`
- Modify: `scripts/export/lua_contract_writer.py` (if arrays need extra support)
- Modify: `scripts/export/tests/test_lua_contract_writer.py` (if writer changed)

- [ ] **Step 1: 先把契约字段定死**

`navigation_route_edges` 的 `nodes` 块至少输出：
- `NodeID`
- `Kind` (`map_anchor` / `taxi`)
- `UiMapID`
- `MapID`
- `Name_lang`
- `WalkClusterKey`
- `TaxiNodeID`（仅 taxi）
- `PosX / PosY`（有则输出）

`navigation_route_edges` 的 `edges` 块至少输出：
- `ID`
- `Mode`
- `FromNodeID`
- `ToNodeID`
- `StepCost`（V1 固定为 `1`）
- `TraversedUiMapIDs`
- `TraversedUiMapNames`
- `FromTaxiNodeID / ToTaxiNodeID`（仅 taxi）

- [ ] **Step 2: 把 Taxi 来源侧补到可消费级别**

更新 `navigation_taxi_edges.json`，确保 Taxi 来源数据能稳定提供：
- 路线节点
- 起终飞行点 ID
- 节点落点地图
- 经过地图序列

如果导出链不能直接从 SQL 输出数组，就在导出 Python 层聚合成数组后再交给 Lua writer；不要把经过地图序列扁平化成字符串。

- [ ] **Step 3: 把统一静态骨架收口到 V1**

重写 `navigation_route_edges.json`，只把 V1 真正消费的静态骨架汇总进去：
- `map_anchor`
- `taxi` 节点
- `taxi` 静态边

明确移除旧运行时语义：
- `MAP_LINK`
- `WAYPOINT_LINK`
- `UiMap` 邻接推导
- `waypoint` 直连边直接参与 V1 路径

`navigation_uimap_relations` 和 `navigation_waypoint_edges` 可以保留为来源 / 研究数据，但不能再作为 V1 runtime truth。

- [ ] **Step 4: 导出并生成 Lua**

Run:
```bash
python scripts/export/export_toolbox_one.py navigation_taxi_edges
python scripts/export/export_toolbox_one.py navigation_route_edges
```

Expected:
- `Toolbox/Data/NavigationTaxiEdges.lua` 和 `Toolbox/Data/NavigationRouteEdges.lua` 更新
- header 中 `schema_version` 与契约一致

- [ ] **Step 5: 跑契约验证**

Run:
```bash
python tests/validate_data_contracts.py
busted tests/logic/spec/navigation_data_spec.lua
```

Expected:
- 新字段齐全
- 不再断言旧 `MAP_LINK` / `WAYPOINT_LINK`

- [ ] **Step 6: Commit**

```bash
git add DataContracts/navigation_taxi_edges.json DataContracts/navigation_route_edges.json Toolbox/Data/NavigationTaxiEdges.lua Toolbox/Data/NavigationRouteEdges.lua tests/validate_data_contracts.py tests/logic/spec/navigation_data_spec.lua
git commit -m "feat: export navigation v1 static route skeleton"
```

## Chunk 3: 导出能力模板并补当前角色输入

**Files:**
- Create: `DataContracts/navigation_ability_templates.json`
- Create: `Toolbox/Data/NavigationAbilityTemplates.lua`
- Modify: `Toolbox/Toolbox.toc`
- Modify: `tests/validate_data_contracts.py`
- Modify: `Toolbox/Core/API/Navigation.lua`
- Modify: `tests/logic/spec/navigation_api_spec.lua`

- [ ] **Step 1: 先查证运行时角色输入 API**

在实现前确认并记录：
- 当前角色职业 / 阵营 API
- 已学法术 API
- 已开飞行点 API
- 炉石绑定点 API

如果某个字段不能直接拿到最终 `NodeID`，先定义稳定的解析层；不要把不确定 API 直接塞进求解器。

- [ ] **Step 2: 为模板边写失败测试**

在 `tests/logic/spec/navigation_api_spec.lua` 新增失败用例：
- `hearthstone` 只在存在 `HearthBindNodeID` 且法术已知时展开
- `class_teleport` / `class_portal` 只在职业、阵营、法术满足时展开
- `taxi` 边只在 `KnownTaxiNodeIDs` 满足时可用

- [ ] **Step 3: 定义模板契约**

`navigation_ability_templates.json` 至少导出：
- `TemplateID`
- `Mode`
- `SpellID`
- `ClassFile`（可空）
- `FactionGroup`（可空）
- `TargetRuleKind`（`fixed_node` / `hearth_bind`）
- `ToNodeID`（`fixed_node` 必填）
- `Label`
- `SelfUseOnly`

规则：
- `hearthstone` 用 `hearth_bind`
- 固定主城技能 / 传送门用 `fixed_node`
- 导不稳的技能先不进表

- [ ] **Step 4: 导出并接入 TOC**

Run:
```bash
python scripts/export/export_toolbox_one.py navigation_ability_templates
```

然后把 `Data\\NavigationAbilityTemplates.lua` 加入 `Toolbox/Toolbox.toc`，位置与其它 navigation Data 文件相邻。

- [ ] **Step 5: 让角色快照先读新字段**

在 `Toolbox/Core/API/Navigation.lua` 中把当前角色输入口径扩成：
- `classFile`
- `faction`
- `knownSpellByID`
- `knownTaxiNodeByID`
- `hearthBindNodeID`

此步只负责采集 / 解析，不提前做完整路径求解。

- [ ] **Step 6: 跑定向测试**

Run:
```bash
busted tests/logic/spec/navigation_api_spec.lua
python tests/validate_data_contracts.py
```

Expected:
- 模板数据可加载
- 角色输入包含 `KnownTaxiNodeIDs` 与 `HearthBindNodeID`

- [ ] **Step 7: Commit**

```bash
git add DataContracts/navigation_ability_templates.json Toolbox/Data/NavigationAbilityTemplates.lua Toolbox/Toolbox.toc Toolbox/Core/API/Navigation.lua tests/validate_data_contracts.py tests/logic/spec/navigation_api_spec.lua
git commit -m "feat: add navigation ability templates and character availability inputs"
```

## Chunk 4: 用 BFS + 平局规则替换旧 solver，并补 walk_local

**Files:**
- Modify: `Toolbox/Core/API/Navigation.lua`
- Modify: `tests/logic/spec/navigation_api_spec.lua`

- [ ] **Step 1: 为新 solver 写失败测试**

增加失败用例，覆盖：
- `FindShortestPath` 不再按 `cost` 排序
- BFS 先找最少步数
- 同步数时按 `walk` 段数 / 本地步行距离 / 步骤切换 / 稳定 ID 打平
- 输出 `segments`
- 输出 `totalSteps`

- [ ] **Step 2: 把图构建拆成 4 层**

在 `Toolbox/Core/API/Navigation.lua` 中拆清以下阶段：
1. 读取静态骨架节点 / 边
2. 按角色配置过滤 `taxi`
3. 按模板展开 `hearthstone / class_teleport / class_portal`
4. 动态补 `walk_local`

要求：
- `walk_local` 至少能连接起点 / 终点与同 `WalkClusterKey` 的枢纽
- 同 `WalkClusterKey` 的枢纽间允许本地换乘

- [ ] **Step 3: 实现最少步数求解**

把旧 Dijkstra `cost` 求解换成 BFS 或等价的单位权最短路实现，并保留固定平局规则。

运行时结果至少返回：
- `totalSteps`
- `segments`
- `rawNodePath`
- `rawEdgePath`

`stepLabels` 如果还需要给旧 UI 过渡使用，只能作为派生字段，不能再作为主数据结构。

- [ ] **Step 4: 压缩连续步行段**

在结果回溯阶段把连续 `walk_local` 合并为 1 段展示，并累计：
- `WalkDistance`
- `TraversedUiMapIDs`
- `TraversedUiMapNames`

- [ ] **Step 5: 跑定向逻辑测试**

Run:
```bash
busted tests/logic/spec/navigation_api_spec.lua
```

Expected:
- 所有最短路主断言改看 `totalSteps`
- 旧 `totalCost` 相关用例全部改写

- [ ] **Step 6: Commit**

```bash
git add Toolbox/Core/API/Navigation.lua tests/logic/spec/navigation_api_spec.lua
git commit -m "feat: switch navigation to minimum-step bfs solver"
```

## Chunk 5: 接通 waypoint 入口、角色快照与顶部路径条

**Files:**
- Modify: `Toolbox/Modules/Navigation/WorldMap.lua`
- Modify: `Toolbox/Modules/Navigation/RouteBar.lua`
- Modify: `Toolbox/Modules/Navigation.lua`
- Modify: `Toolbox/Core/Foundation/Config.lua`
- Modify: `Toolbox/Core/Foundation/Locales.lua`
- Modify: `tests/logic/spec/navigation_worldmap_spec.lua`
- Modify: `tests/logic/spec/navigation_routebar_spec.lua`
- Modify: `tests/logic/spec/navigation_module_spec.lua`

- [ ] **Step 1: 让世界地图入口传入完整查询输入**

`WorldMap.lua` 除 waypoint 外，还要把当前角色配置交给 `Toolbox.Navigation`：
- `Faction`
- `Class`
- `KnownSpellIDs`
- `KnownTaxiNodeIDs`
- `HearthBindNodeID`

没有 waypoint 时，行为保持“清空路线 + 聊天提示”。

- [ ] **Step 2: 重写 RouteBar 渲染**

`RouteBar.lua` 改为从 `routeResult.totalSteps` 和 `routeResult.segments` 渲染：
- 顶部摘要显示总步数
- 每段显示 `mode`
- 每段显示起点 / 终点
- 每段附 `TraversedUiMapNames`

- [ ] **Step 3: 保留模块生命周期约束**

确认这些行为不回退：
- 模块禁用时按钮隐藏、路径条清空
- 重复 `Install()` 不重复挂 hook
- 不在战斗中做受保护 UI 操作

- [ ] **Step 4: 跑定向 UI 逻辑测试**

Run:
```bash
busted tests/logic/spec/navigation_worldmap_spec.lua
busted tests/logic/spec/navigation_routebar_spec.lua
busted tests/logic/spec/navigation_module_spec.lua
```

Expected:
- waypoint 入口仍稳定
- 路径条按 `segments` 展示
- 模块 enable / disable 生命周期不回退

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Modules/Navigation/WorldMap.lua Toolbox/Modules/Navigation/RouteBar.lua Toolbox/Modules/Navigation.lua Toolbox/Core/Foundation/Config.lua Toolbox/Core/Foundation/Locales.lua tests/logic/spec/navigation_worldmap_spec.lua tests/logic/spec/navigation_routebar_spec.lua tests/logic/spec/navigation_module_spec.lua
git commit -m "feat: wire navigation v1 route segments into world map and route bar"
```

## Chunk 6: 清理旧口径、回写文档、做全量验证

**Files:**
- Modify: `docs/features/navigation-features.md`
- Modify: `docs/tests/navigation-test.md`
- Modify: `docs/Toolbox-addon-design.md`
- Modify: `docs/plans/navigation-plan.md`
- Modify: `tests/validate_data_contracts.py`
- Modify: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 清理旧文档与旧断言措辞**

统一移除或改写这些旧口径：
- `Dijkstra`
- `totalCost`
- `MAP_LINK`
- `WAYPOINT_LINK`
- “地图邻接关系图是 runtime truth”

- [ ] **Step 2: 更新功能文档**

把 `docs/features/navigation-features.md` 改成新基线：
- 当前角色配置
- 最少路径步数
- V1 仅闭合 `walk_local / taxi / hearthstone / class_teleport / class_portal`
- 输出为逐段方式和经过地图

- [ ] **Step 3: 更新测试记录**

在 `docs/tests/navigation-test.md` 记录：
- 导出命令
- 定向 `busted` 命令
- 全量 `python tests/run_all.py --ci`
- 如果某个角色输入 API 需要 fallback，也要写清楚采用了哪个 fallback

- [ ] **Step 4: 运行导出与校验**

Run:
```bash
python scripts/export/export_toolbox_one.py navigation_taxi_edges
python scripts/export/export_toolbox_one.py navigation_ability_templates
python scripts/export/export_toolbox_one.py navigation_route_edges
python tests/validate_data_contracts.py
python tests/validate_settings_subcategories.py
python tests/run_all.py --ci
```

Expected:
- 所有 navigation 契约通过
- TOC 和设置页验证通过
- 逻辑测试通过

- [ ] **Step 5: Commit**

```bash
git add docs/features/navigation-features.md docs/tests/navigation-test.md docs/Toolbox-addon-design.md docs/plans/navigation-plan.md tests/validate_data_contracts.py tests/validate_settings_subcategories.py
git commit -m "docs: finalize navigation v1 minimum-step route plan and validation notes"
```

## 6. V2 明确延期项

- `transport`
- `public_portal`
- `areatrigger`
- `道标石`
- 全世界 `WalkComponent`
- “只能飞 / 只能传送 / 没有公共路径”一类强结论

这些项都不应阻塞 V1 落地，但也不允许被 V1 的实现偷偷假定为“不存在”。

## 7. 风险与处置

- 风险：已开飞行点和炉石绑定点的 Retail API 口径可能不直接返回最终 `NodeID`
  - 处置：先做稳定解析层，再把解析结果交给求解器；不要让求解器自己猜
- 风险：某些职业技能无法稳定导出到明确目标节点
  - 处置：该技能留在 V2，不用手工表补
- 风险：现有 `Navigation.lua` 和 tests 里对 `totalCost` 的依赖面比预期大
  - 处置：先让 `segments` / `totalSteps` 成为主返回，再删兼容字段

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初版计划：围绕旧的 `cost` 路线图与世界地图入口组织实施 |
| 2026-04-29 | 整体重写：以“当前角色配置 + 最少路径步数 + 枢纽 / 动作图”替换旧计划，V1 收口到 `walk_local / taxi / hearthstone / class_teleport / class_portal` |
