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
- 顶部路线 UI 采用“默认精简胶囊 + 点击展开导航信息页”的交互，不改成世界地图内嵌面板。
- 路线图组件允许拖动，且位置与展开状态都需要存档。
- 路线图需要实时刷新当前步骤与偏航提示，而不是只在规划成功时静态显示。
- 到达终点后路线图保留，手动关闭或重新规划前不自动消失。
- 路线图需要维护最近 10 条历史记录。
- 点击历史记录时，先弹 Blizzard 通用确认 / 取消提示；确认后使用“玩家当前位置 + 历史终点”重新规划；不恢复旧起点。
- 胶囊标题只显示 `状态 + 步骤进度`，不显示路线摘要。
- 胶囊主体固定为 `起始位置 / 当前位置 / 终点位置` 三段，其中 `当前位置` 需要实时刷新。
- 胶囊三段之间需要有明确分隔线，能清楚区分左 / 中 / 右信息区。
- 胶囊整体宽度需要根据标题和三段文本的实际长度自适应扩展，并保留最小宽度 / 最大宽度 / 内边距护栏。
- 展开后的导航信息页主视图只显示 WoW 可落地约束下的竖向导航节点链，不显示完整步骤列表与路线摘要。
- 节点链必须由 `semantic path` 驱动，默认按 `地图节点 -> 动作节点 -> 地图节点` 组织；`taxi` 不单独生成飞行点动作节点。
- `walk_local` 只负责同一 `WalkComponent` 内接入，不直接显示成玩家节点；返程方向名和技术节点名不得泄漏到玩家链路或规划摘要。
- 节点链左侧节点标记需要至少区分 `地图 / 动作` 两类，并支持 `传送门 / 飞艇 / 炉石 / 职业技能` 等动作细分。
- 节点链每行需要有固定宽度的 WoW 风格容器，避免退化成纯文本列表。
- 节点链需要有明显的竖向串行连线与节点标记，并对当前步骤节点做高亮。
- 起点节点与终点节点改为单行位置文本，格式固定为 `地址 x,y`，分别对应规划起点坐标与目标坐标；不再拆第二行坐标明细，中间节点仍不显示坐标。
- 展开态节点区底框 / 背景框需要按实际节点范围自适应撑高，覆盖尾部节点、连线与外边距，不能再出现后半段节点超框。
- 最近路线列表独立侧贴展开，不放到导航内容下方。
- 本轮同时建立 `walk component` 正式契约框架，但首批覆盖只落：主城、传送门房、飞艇塔 / 港口、常用交通落点。
- `walk component` 数据来源固定为“`wow.db` + 已正式导出的 runtime 节点 / 边 -> 规则化自动归并 -> 正式导出”；自动规则不能稳定判定时宁缺毋滥，不允许源侧 override 或 runtime Lua 手写补边。

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
- 新增：`DataContracts/navigation_walk_components.json`
- 修改：`Toolbox/Data/NavigationRouteEdges.lua`（生成）
- 修改：`Toolbox/Data/NavigationTaxiEdges.lua`（生成）
- 新增：`Toolbox/Data/NavigationAbilityTemplates.lua`（生成）
- 新增：`Toolbox/Data/NavigationWalkComponents.lua`（生成）
- 修改：`Toolbox/Toolbox.toc`
- 修改：`scripts/export/toolbox_db_export.py`

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
- `RouteBar.lua`、`WorldMap.lua` 和规划摘要不能再直接把 `TraversedUiMapNames` 或技术节点名当玩家显示文本，必须先走 semantic 层。
- `walk_local` 不做 UI 过滤式修补；必须在 `Toolbox.Navigation` 内部被吸收到 `semantic path` 和 `WalkComponent` 语义里。

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

**待执行补充（暂不在本轮开动）**

- review 跟进项：收紧 `NavigationRouteEdges.lua` 的运行时 taxi 出口，只保留 V1 稳定公共边。
- 导出层主修复：
  - 剔除 `FromTaxiNodeID == ToTaxiNodeID` 的自环 taxi 边。
  - 剔除明显 `Quest Path` / `Quest -` / `Test -` 的 taxi 节点与边，不让其进入运行时图。
  - 如后续确认 `ConditionID / VisibilityConditionID` 有稳定过滤口径，再补进导出层，而不是先塞进运行时求解。
- 运行时仅保留轻量兜底：
  - `taxi` 边若 `from == to`，直接判不可用。
- 回归要求：
  - `tests/logic/spec/navigation_data_spec.lua` 增加“无自环 / 无 quest-test taxi 数据进入 runtime export”断言。
  - `tests/validate_data_contracts.py` 增加对应静态校验。
- 当前状态：`待执行`。后续安排修改时，先更新本计划状态，再进入代码实现。

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

成功规划时，聊天框输出改为一次性的“规划期诊断文本”：
- 首行输出起点地图 / 坐标、终点地图 / 坐标、总步数、节点摘要
- 后续逐段输出 `mode / from / to / traversedUiMapNames`
- 不输出实时步骤切换、偏航或到达日志

- [ ] **Step 2: 重写 RouteBar 渲染**

`RouteBar.lua` 改为从 `routeResult.totalSteps` 和 `routeResult.segments` 渲染：
- 胶囊标题只显示 `状态 + 步骤进度`
- 胶囊主体显示 `起始位置 / 当前位置 / 终点位置` 三栏，并带分隔线
- 展开态主视图只显示竖向导航节点链，不回退到完整步骤列表
- 节点链显示地图级节点与显式交通枢纽节点，飞行点详情不进入玩家可见链路
- 节点链补齐通用类型图标、竖向串行连线、当前节点高亮与起终点坐标明细

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

## 6. V2 已完成 / 待推进

**V2 已闭合：**
- ✅ `transport`（飞艇/船）：导出脚本根据 node name 含 “Transport” / “交通工具” 识别 transport 节点，对应边输出 `mode = “transport”`；运行时 `isEdgeAvailable` 对 transport 模式与 taxi 同等待遇（两端航点需已开）。
- ✅ `public_portal`（公共传送门）已进入统一边表并参与运行时求解；当前问题不再是“是否接入”，而是“世界覆盖是否闭合”。

**V2 已接入但仍需补覆盖：**
- `public_portal`
  - 数据来源：复用 `navigation_waypoint_edges` 管道（`waypointedge` + `waypointnode`），筛选 Type=1→Type=2 portal 边
  - 节点映射：新建 `portal_{waypoint_id}` 节点，保留精确坐标；enrichment 走 `walk_cluster_uimap_id_by_uimap_id` 确定 `WalkClusterKey`
  - 接入方式：`WalkClusterKey` 连接同连通域 `map_anchor`，复用 `addDynamicWalkLocalEdges`
  - 可用性：`PlayerConditionID = 0` 无条件纳入；`924`/`923` 标 faction；其余暂不纳入
  - 出口：portal 边汇入 `navigation_route_edges` 统一静态边表

### 6.1 已闭合回归样例：`银月城 -> 东瘟疫之地`

自 2026-04-30 起，这个样例不再是 `NAVIGATION_ERR_NO_ROUTE` 缺口，而是“静态导出图已经闭合”的回归样例。当前结论来自导出数据与逻辑测试，不依赖运行时猜测：

- `tests/logic/spec/navigation_data_spec.lua`
  - 断言 `portal_117 -> portal_101`
  - 断言 `portal_118 -> portal_119`
  - 断言 `portal_556 -> portal_557`
  - 断言存在至少一条与 `taxi_82` 相连的统一运行时边
  - 断言奥格传送门房相关节点稳定落到 `UiMapID = 85` / `WalkClusterKey = "uimap_85"`
- `tests/logic/spec/navigation_api_spec.lua`
  - 断言 `银月城 -> 提瑞斯法林地` 可以通过导出的公共传送门出口求解
  - 断言 `银月城 -> 奥格瑞玛` 可以通过修正后的枢纽并入规则求解
  - 断言 `银月城 -> 东瘟疫之地` 在当前统一静态图下可求解

对这一样例，当前已正式闭合的导出能力如下：

- [x] `public_portal` 端点闭环：`portal_556`（萨拉斯小径 -> 东瘟疫之地）已导出为统一 route edge。
- [x] `public_portal` 端点闭环：`portal_118`（银月城宝珠 -> 幽暗城/洛丹伦一侧）已导出为统一 route edge。
- [x] `taxi` 闭环：`taxi_82`（银月城）已并入统一公共 taxi 图。
- [x] 主城枢纽并入：`portal_101` 以及同房间 portal 落点已稳定并入奥格主城簇 `uimap_85`。
- [x] 导出数据形状护栏：`NavigationRouteEdges.edges` 现要求保持 1-based 连续序列，保证运行时与测试侧 `ipairs()` 遍历不会在中途截断。

这组结论只说明“当前静态导出图已能证明这条路线可达”，不代表：

- 已经闭合全世界 `walk` 连通关系；
- 已经完成 `areatrigger` / 道标石等后续模态；
- 已经能对“只能飞 / 只能传送 / 没有公共路径”给出排除法强结论。

### 6.2 `areatrigger / WalkComponent` 静态来源评估（2026-04-30）

当前结论已经足够指导后续实现切口：

- `areatrigger`
  - `wow.db.areatrigger` 能稳定提供 source 点位：`ID / ContinentID / Pos_0 / Pos_1 / Pos_2 / AreaTriggerActionSetID`
  - 但 `wow.db.areatriggeractionset` 当前只有 `ID / Flags`
  - 现状不是“导出脚本还没补”，而是“缺少 destination 数据源”
  - 因此：
    - [x] 维持运行时 `areatrigger` 节点 / 边为空
    - [ ] 后续若补到 `AreaTriggerActionSetID -> 目标地图 / 坐标` 的独立静态源，再接入统一边表

- `WalkComponent`
  - 当前仓库和 `wow.db` 中，没有现成、稳定、可直接当作“世界步行连通真值”的静态来源
  - 现有 `WalkClusterKey` 来自 `uimap + uimapassignment` 的归并启发式，只能用于本地枢纽挂接，不能升级为世界步行真值
  - `waypointnode / waypointedge` 中带 `WaypointMapVolumeID` 的样本过少，只适合作为“显式连接器”候选，不足以覆盖全世界步行组件
  - 因此：
    - [x] 不把 `UiMap` 父链、矩形或 `WalkClusterKey` 启发式写成 world walk truth
    - [x] 已补首批 `navigation_walk_components` 正式导出链（主城 / 传送门房 / 港口与飞艇塔 / 常用交通落点）
    - [ ] 后续仍需要独立的离线几何 / 导航资产管线来导出真正的全世界 `navigation_walk_components`
    - [ ] 在全世界真值闭合前，继续补 `portal / volume / areatrigger` 这类显式连接器

**V2 待推进（单人导航，不含需多人协助的模态）：**
- `areatrigger`
- 全世界 `WalkComponent` 真值闭合
- “只能飞 / 只能传送 / 没有公共路径”一类强结论（需等所有 V2 模态闭合后引入）

## 6.3 路线图组件改造（已确认，可执行）

这部分只允许修改 `navigation` 自己的代码路径，不回退或覆盖其它仍在演进中的导航功能。

**目标：**

- 用可折叠路线图组件替换现有单行文本条
- 保留当前规划入口，不改世界地图按钮语义
- 在同一组件内补齐历史记录、拖动、实时步骤与偏航提示

**本轮优先文件：**

- `Toolbox/Modules/Navigation/RouteBar.lua`
- `Toolbox/Modules/Navigation/WorldMap.lua`
- `Toolbox/Modules/Navigation/Shared.lua`
- `Toolbox/Modules/Navigation.lua`
- `Toolbox/Core/Foundation/Config.lua`
- `Toolbox/Core/Foundation/Locales.lua`
- `tests/logic/spec/navigation_routebar_spec.lua`
- `tests/logic/spec/navigation_worldmap_spec.lua`
- `tests/validate_settings_subcategories.py`

**本轮拆分顺序：**

1. 先补 `RouteBar` 组件状态与历史记录的失败测试。
2. 再实现胶囊 / 展开态、拖动、位置存档、展开状态存档。
3. 再接通历史记录与“当前位置 -> 历史终点”重规划。
4. 最后补实时步骤 / 偏航刷新与回归验证。

**实现护栏：**

- 不改 DataContracts、导出脚本和统一路线边语义。
- 不改变 `WorldMap` 现有 waypoint 入口，以及“无 waypoint / 规划失败”提示口径；仅把成功时的单行摘要改为一次性的规划期诊断输出。
- 不影响 `navigation` 之外的模块。
- 若发现当前未提交的导航改动与路线图组件直接冲突，先局部避让，不主动回退别人的未提交修改。

## 6.4 语义路线链与 `WalkComponent` 根治（已实现首批出口，待继续扩世界真值）

这部分的目标不是“再加一层 UI 过滤”，而是把技术路径、语义路径和展示消费正式拆开，并为全世界 `walk component` 真值导出建立固定出口。当前已完成 formal component 首批出口与 runtime 优先消费；未完成的是全世界闭合。

**目标：**

- 从根上切断 `transport / portal / walk_local` 技术节点名泄漏到玩家链路的问题。
- 让 `RouteBar`、规划期节点摘要和逐段诊断统一消费 `semantic path`。
- 为 `walk component` 增加正式契约与 runtime 数据出口，先落首批高价值覆盖范围。

**本轮优先文件：**

- `Toolbox/Core/API/Navigation.lua`
- `Toolbox/Modules/Navigation/RouteBar.lua`
- `Toolbox/Modules/Navigation/WorldMap.lua`
- `tests/logic/spec/navigation_api_spec.lua`
- `tests/logic/spec/navigation_routebar_spec.lua`
- `tests/logic/spec/navigation_worldmap_spec.lua`
- `tests/logic/spec/navigation_data_spec.lua`
- `tests/validate_data_contracts.py`
- `DataContracts/navigation_walk_components.json`
- `Toolbox/Data/NavigationWalkComponents.lua`
- `scripts/export/toolbox_db_export.py`
- `Toolbox/Toolbox.toc`

**本轮拆分顺序：**

1. 先补失败测试，锁定以下语义：
   - `transport / public_portal / class_portal` 到站后，显示链和规划摘要必须使用到站地图或动作代理名，不能泄漏返程技术节点名。
   - `taxi` 不生成独立动作节点，但仍保留正确 segment 和记步结果。
   - 精简胶囊宽度会随文本长度扩展，不再因为固定宽度裁切内容。
   - 展开态节点区底框会覆盖完整节点范围，不再出现尾部节点超框。
2. 在 `Toolbox.Navigation` 中拆出 `raw path -> semantic path -> display`：
   - `buildRouteSegments()` 继续负责 segment；
   - 新增 semantic builder，专门产出地图节点 / 动作节点链。
3. 让 `RouteBar.lua` 与 `WorldMap.lua` 改为只消费 semantic 结果：
   - 不再直接拿 `TraversedUiMapNames` 生成玩家文案；
   - 逐段日志中的 `from / to` 也要先过 semantic 代理。
   - RouteBar 布局同步改成“胶囊宽度自适应 + 节点区底框按内容高度撑开”。
4. 新增 `navigation_walk_components` 契约与导出文件：
   - [x] 已导出首批覆盖的组件、节点归属和显示代理；
   - [x] runtime 已优先读取正式 `PreferredAnchorNodeID / VisibleName / DisplayProxyNodeID`；
   - [x] formal 数据缺失时继续保留 `WalkClusterNodeID / WalkClusterKey` fallback。
5. 把首批 `navigation_walk_components` 收口为全自动导出：
   - 组件归属只允许由正式来源表和规则化自动归并推导；
   - `hidden / proxy / preferred_anchor / visible_name` 也必须从正式节点事实推导，不再依赖独立 override 文件；
   - 归并规则不够稳时先不导出该节点或组件，不允许人工补顶。
6. 最后跑导出、逻辑测试、文档回写与游戏内回归。

**实现护栏：**

- 不接受只在 `RouteBar.lua` 或 `WorldMap.lua` 里做字符串过滤的表面修复。
- 不把 `WalkClusterNodeID / WalkClusterKey` 直接升级成 world walk truth。
- 不允许再引入源侧 override 文件参与 walk component 真值判定，也不允许回流成 runtime 手写导航数据。
- `areatrigger` 仍然不伪造目标端；该模态继续等正式来源闭合。

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
| 2026-04-29 | 整体重写：以”当前角色配置 + 最少路径步数 + 枢纽 / 动作图”替换旧计划，V1 收口到 `walk_local / taxi / hearthstone / class_teleport / class_portal` |
| 2026-04-29 | V2 推进：`transport`（飞艇/船）闭合，导出脚本 + 运行时 + 测试全部落地，V2 待推进项更新为其余 4 项 |
| 2026-05-01 | 世界地图规划成功后的聊天输出改为一次性的规划期诊断文本；实时刷新仍只体现在路线图 UI，不进入聊天框 |
| 2026-04-29 | V2 推进：`public_portal` 方案确认，进入实施；路线图 5 段链路已校验可导出 |
| 2026-04-29 | 文档同步：把 `silvermoon -> eastern plaguelands` 固定为导出缺口样例，明确当前 `no route` 对应的 `walk / portal / taxi / hub merge` backlog |
| 2026-04-30 | 导出闭环：`silvermoon -> eastern plaguelands` 从缺口样例升级为回归样例；`portal_118/556`、`taxi_82`、奥格传送门房并入与 `edges` 连续序列约束全部落地并由测试锁定 |
| 2026-04-30 | 来源评估：确认当前 `wow.db` 只能提供 `areatrigger` source 点位，不能提供目标端点；确认 world `WalkComponent` 不存在现成静态真值，后续需独立离线管线 |
| 2026-04-30 | 路线图改造确认：顶部文本条升级为可折叠路线图组件；交互、存档、实时刷新与最近 10 条历史记录的执行边界写入本计划 |
| 2026-05-01 | 路线图节点文本补充确认：展开态起点/终点节点改为单行 `地址 x,y`，胶囊与聊天诊断输出不在本轮调整范围 |
| 2026-05-01 | 根治方向确认：路线显示改为 `raw path -> semantic path -> display` 三层；玩家链路显式区分地图节点与动作节点，`taxi` 不单独生成动作节点 |
| 2026-05-01 | `walk component` 计划补充：新增正式契约 / 导出 / runtime 出口方向，首批覆盖主城、传送门房、飞艇塔 / 港口与常用交通落点 |
| 2026-05-02 | 路线图布局修复补充：实现范围新增胶囊宽度自适应与展开态节点区底框按节点范围自动撑开两项回归要求 |
| 2026-05-02 | `walk component` 首批出口落地：新增 `navigation_walk_components` 契约、`NavigationWalkComponents.lua`、runtime 优先消费与 fallback 回归测试；全世界真值闭合继续留在后续阶段 |
| 2026-05-02 | 方案改口：用户确认移除 `navigation_walk_component_overrides.json` 与对应 enrichment；后续首批 walk component 只能由正式来源表全自动推导 |
