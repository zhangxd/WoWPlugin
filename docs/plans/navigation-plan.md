# 地图导航模块实施计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents are explicitly authorized) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 `navigation` 新模块，在世界地图读取当前用户 waypoint 后按当前角色可用能力规划跨地图最短路线，并在屏幕顶部中间显示路径步骤。

**Architecture:** `Toolbox.Navigation` 负责路径图、可用性过滤和 Dijkstra 求解；`navigation` 模块负责世界地图入口、设置、顶部路径 UI 与生命周期。所有导航运行时数据走 DataContracts 契约导出，并以“静态骨架图 + 动态 current/target 节点”接入目标 `x/y` 成本；数据库未导出的路径不进入运行时图。

**Tech Stack:** WoW Retail Lua、Toolbox 模块注册体系、`ToolboxDB.modules.navigation`、DataContracts 导出体系、现有 Lua 逻辑测试 harness、`python tests/run_all.py --ci`。

---

- 文档类型：计划
- 状态：可执行
- 主题：navigation
- 适用范围：`navigation` 新模块、导航领域 API、路径数据、顶部路径 UI 与测试
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 目标

- 新增 `navigation` 模块与导航领域 API，实现世界地图目标到顶部路径 UI 的第一版完整链路。
- 复审修订阶段聚焦两个 correctness 问题：按钮目标源改为当前用户 waypoint，且 `target.x / target.y` 真正参与路径成本。

## 2. 输入文档

- 需求：
  `docs/specs/navigation-spec.md`
- 设计：
  `docs/designs/navigation-design.md`
- 其他约束：
  `AGENTS.md` 三关门禁、Lua 开发规范、WoWDB 静态数据导出规则、暴雪 UI 挂接时机；实现前必须查证不确定 WoW API。

## 2.1 当前修订边界

- 纳入本计划：
  - `WorldMap.lua` 目标源从按钮点击时鼠标坐标改为当前用户 waypoint
  - `Navigation.lua` 接入 `target.x / target.y` 的终段成本
  - 用模拟公共交通数据验证飞艇 / 船样板进入导航骨架与求解
  - 移除 `NavigationManualEdges.lua` 的运行时消费与 TOC 加载
  - 导航基础图索引、过滤缓存与结果缓存
- 不纳入本计划：
  - `Toolbox/Core/API/Tooltip.lua` 的 taint 风险修复
  - `Toolbox/Core/API/EncounterJournal.lua` 的副本入口查询性能修复
  - 传送门并入公共交通数据链路
  - 飞行点推荐
- 说明：
  - `EncounterJournal` 相关 review 项主方案尚未确认，待用户单独拍板“预热缓存 / 静态索引 / 混合方案”后再写入可执行计划。

## 2.2 导航数据全导出重规划

- 核心规则：
  - `navigation` 运行时不得消费手工维护 ID 数据。
  - `Toolbox/Data/NavigationManualEdges.lua` 必须从 TOC 与 `Toolbox.Navigation` 构图链路移除。
  - 所有节点、边、目标规则、入口坐标、候选枢纽、职业 / 阵营限制、成本与标签必须来自 `DataContracts/<contract_id>.json` 和 `scripts/export/` 的实跑导出。
  - 数据库链路尚未查实的玩法路径不进入运行时图，不用手写 ID 兜底。

- 第一优先级契约：
  - `navigation_instance_entrances`：从 `journalinstanceentrance`、`journalinstance`、`areapoi`、`uimapassignment` 导出副本入口目标。目标是把“导航到副本入口位置”固定为导出数据，而不是导航到副本内部地图。
  - `navigation_map_assignments`：从 `uimapassignment` 导出世界坐标到 UiMap 的覆盖范围与归一化转换参数，供入口导出与后续定位复用。
  - `navigation_route_edges`：只汇总已经可直接从数据库导出的最终边；第一阶段仅合并 `navigation_taxi_edges`，后续传送门 / 职业技能必须等独立候选契约查实后再提升为最终边。

- 第二优先级候选契约：
  - `navigation_portal_candidates`：从 `areatrigger`、`gameobjects` 等表导出传送门候选位置与名称；未能从数据库确认目的地前，只做候选数据，不进入最终路径图。
  - `navigation_spell_travel_candidates`：从 `skilllineability`、`chrclasses`、`spellname`、`spelleffect` 导出职业旅行技能候选；未能从数据库确认落点前，只做候选数据，不进入最终路径图。

- 剃刀高地验收链：
  - `journalinstance.ID=233` / `Name_lang=剃刀高地` 必须导出到 `NavigationInstanceEntrances.lua`。
  - 入口必须使用 `journalinstanceentrance` 的入口世界坐标，不使用 `journalinstance.MapID=129` 的副本内部地图作为导航目标。
  - 导出结果必须能解析到可设置 waypoint 的外部 `uiMapID/x/y`；若一个入口命中多个 UiMapAssignment，导出候选列表并标记首选规则，禁止手填首选 ID。

## 3. 影响文件

- 新增：
  - `Toolbox/Core/API/Navigation.lua`
  - `Toolbox/Modules/Navigation.lua`
  - `Toolbox/Modules/Navigation/Shared.lua`
  - `Toolbox/Modules/Navigation/WorldMap.lua`
  - `Toolbox/Modules/Navigation/RouteBar.lua`
  - `Toolbox/Data/NavigationMapNodes.lua`
  - `DataContracts/navigation_map_nodes.json`
  - `tests/logic/spec/navigation_api_spec.lua`
  - `tests/logic/spec/navigation_module_spec.lua`
  - `docs/features/navigation-features.md`
  - `docs/tests/navigation-test.md`
- 修改：
  - `Toolbox/Toolbox.toc`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
  - `docs/FEATURES.md`
  - `tests/validate_settings_subcategories.py`
  - `tests/validate_data_contracts.py` 或相关数据契约测试入口
- 验证：
  - `python tests/run_all.py --ci`

## 4. 执行步骤

## Chunk 1: API 查证与路径核心

- [x] 步骤 1：查证世界地图目标、当前地图坐标、spell 可用性、职业 / 阵营、waypoint 相关 Retail API，记录采用的 API 与来源链接到 `docs/designs/navigation-design.md` 或代码注释。
- [x] 步骤 2：为 `Toolbox.Navigation` 写失败测试：节点 / 边输入后 Dijkstra 返回最低耗时路线。
- [x] 步骤 3：新增 `Toolbox/Core/API/Navigation.lua` 的最小实现，使 Dijkstra 测试通过。
- [x] 步骤 4：为可用性过滤写失败测试：未知技能边、职业不匹配边、阵营不匹配边被过滤。
- [x] 步骤 5：实现可用性过滤，失败路径不抛 Lua 错。
- [x] 步骤 6：为法师奥格瑞玛样例写失败测试：已确认技能时优先传送，未确认技能时不使用传送边。
- [x] 步骤 7：实现法师奥格瑞玛样例所需的临时测试注入能力；该手工数据方案已在 Chunk 10 废弃。

## Chunk 2: 数据契约与静态边

- [x] 步骤 8：新增 `DataContracts/navigation_map_nodes.json`，定义地图基础节点导出契约。
- [x] 步骤 9：通过正式导出脚本生成 `Toolbox/Data/NavigationMapNodes.lua`，不得手写覆盖数据库生成文件。
- [x] 步骤 10：历史临时实现曾新增人工路径边；该方案已在 Chunk 10 废弃并从运行时链路移除。
- [x] 步骤 11：数据校验改为校验契约导出边，禁止 TOC 加载手工路径边。
- [x] 步骤 12：把 Data 文件加入 `Toolbox/Toolbox.toc`，顺序位于 API / 模块消费前。

## Chunk 3: 模块注册、存档与设置

- [x] 步骤 13：在 `Core/Foundation/Config.lua` 增加 `modules.navigation` 默认值和迁移。
- [x] 步骤 14：新增 `Toolbox/Modules/Navigation/Shared.lua`，提供模块 DB 和启用状态访问。
- [x] 步骤 15：新增 `Toolbox/Modules/Navigation.lua`，通过 `RegisterModule` 注册 `navigation`。
- [x] 步骤 16：新增设置页，包含公共启用 / 调试区域和最小模块说明；玩家可见文案进入 `Locales.lua`。
- [x] 步骤 17：更新设置子页面验证，确保 `navigation` 页面注册不破坏现有模块。

## Chunk 4: 世界地图入口与顶部路径 UI

- [x] 步骤 18：新增 `WorldMap.lua`，使用查证后的 WorldMap 生命周期挂接目标选择入口。
- [x] 步骤 19：为世界地图挂接生命周期写逻辑测试或 harness 覆盖：模块禁用时注销事件 / 隐藏入口，重复 OnShow 不重复创建控件。
- [x] 步骤 20：新增 `RouteBar.lua`，创建顶部中间路径 UI，显示路径步骤并支持清除路线。
- [x] 步骤 21：接通“世界地图目标 -> 路径求解 -> 顶部路径 UI”链路。
- [x] 步骤 22：确认战斗中不执行受保护 UI 操作；如需延后，使用明确事件而非固定正数秒延迟。

## Chunk 5: 文档、总设计与验证

- [x] 步骤 23：新增 `docs/features/navigation-features.md` 与 `docs/tests/navigation-test.md`。
- [x] 步骤 24：回写 `docs/Toolbox-addon-design.md` 的鸟瞰图、模块映射、数据示例、TOC 顺序与里程碑。
- [x] 步骤 25：回写 `docs/FEATURES.md`，增加 `navigation` 能力总览入口。
- [x] 步骤 26：运行 `python tests/run_all.py --ci`。
- [x] 步骤 27：记录测试结果到 `docs/tests/navigation-test.md`，并把本计划状态推进到 `已完成` 或记录阻塞。

## Chunk 6: waypoint 目标源与终段成本（已完成）

- [x] 步骤 28：为 `WorldMap.lua` 写失败测试，覆盖“存在用户 waypoint 时读取其 `uiMapID/x/y`”“无 waypoint 时不规划路线”。
- [x] 步骤 29：把世界地图按钮目标源从 `GetNormalizedCursorPosition()` 改为 `C_Map.GetUserWaypoint()`，并补无效 waypoint 兜底路径。
- [x] 步骤 30：为 `Navigation.lua` 写失败测试，覆盖同一 `uiMapID` 下不同 `target.x / target.y` 至少产生不同终段成本。
- [x] 步骤 31：在 `Toolbox.Navigation` 中实现同图移动成本估算函数，并将 `target.x / target.y` 接入 `current -> target` 与 `viaNode -> target` 两类边。

## Chunk 7: 静态连接器、索引与缓存（待用户开动后执行）

- [x] 步骤 32：废弃 `Toolbox/Data/NavigationManualEdges.lua` 扩展方向，改由 Chunk 10 的导出契约重规划承接。
- [ ] 步骤 33：补失败测试与数据校验，确保 `arrivalUiMapID`、`arrivalX`、`arrivalY` 和节点引用有效。
- [ ] 步骤 34：在 `Toolbox.Navigation` 中预建基础图索引，并按 `availabilityRevision` 缓存已过滤图。
- [ ] 步骤 35：为路线结果增加缓存键，避免同一能力快照与同一目标桶重复求解。

## Chunk 7A: 模拟公共交通样板（已完成，基于模拟数据）

- [x] 步骤 35A：为 `navigation` 新增公共交通消费测试，覆盖奥格瑞玛到北风苔原这类飞艇 / 船样板可通过模拟数据进入路径图。
- [x] 步骤 35B：在测试或最小静态数据层中注入模拟公共交通边，验证 `Toolbox.Navigation` 能将其并入基础图并参与求解。
- [x] 步骤 35C：确认传送门与飞行点未被误并入本轮模拟公共交通样板或推荐逻辑。

## Chunk 8: 文档回写与验证（进行中）

注：用户已确认本轮“只写代码，不运行测试，静态代码检测”，因此步骤 37 保持未执行。

- [ ] 步骤 36：更新 `docs/features/navigation-features.md` 与 `docs/tests/navigation-test.md`，补 waypoint 取点与 `x/y` 成本说明。
- [ ] 步骤 37：运行 `python tests/run_all.py --ci`，记录与本轮修订相关的测试结果。
- [ ] 步骤 38：回写 `docs/Toolbox-addon-design.md` 与 `docs/FEATURES.md` 中关于导航入口和路径模型的描述。

## Chunk 9: 真实 Taxi* 数据库导出（进行中）

- [x] 步骤 39：用户确认“开动”后，将真实 `Taxi*` 导出范围写回 `docs/specs/navigation-spec.md`、`docs/designs/navigation-design.md` 与本计划。
- [x] 步骤 40：先补失败验证，要求 `navigation_taxi_edges` 纳入生成契约校验、输出 `NavigationTaxiEdges.lua`，且 TOC 加载该数据文件。
- [x] 步骤 41：将 `DataContracts/navigation_taxi_edges.json` 从 draft 推进为 active，并对齐 summary / versioning 描述。
- [x] 步骤 42：通过 `scripts/export/export_toolbox_one.py navigation_taxi_edges` 从 `wow.db` 正式导出 `Toolbox/Data/NavigationTaxiEdges.lua`。
- [x] 步骤 43：把 `Data\NavigationTaxiEdges.lua` 加入 `Toolbox/Toolbox.toc`，位置紧邻 navigation 其他 Data 文件。
- [x] 步骤 44：运行数据契约验证、导出脚本测试与总测试，记录结果。

## Chunk 10: 导航数据全导出重规划（进行中）

- [x] 步骤 45：补充 AGENTS 规则，明确 navigation 运行时数据禁止手工维护 ID，`NavigationManualEdges.lua` 不得作为运行时数据源。
- [x] 步骤 46：从 TOC 与 `Toolbox.Navigation` 构图链路移除 `NavigationManualEdges.lua`，测试改为禁止 TOC 加载该文件。
- [x] 步骤 47：新增 `DataContracts/navigation_map_assignments.json`，导出 `uimapassignment` 覆盖范围、`UiMin/UiMax`、`Region` 与 `MapID/AreaID/UiMapID`。
- [x] 步骤 48：新增 `DataContracts/navigation_instance_entrances.json`，导出 `journalinstanceentrance` + `journalinstance` + `areapoi` 的副本入口记录，并用副本内部 UiMap 父地图规则生成外部目标候选。
- [x] 步骤 49：通过 `export_toolbox_one.py navigation_map_assignments` 与 `export_toolbox_one.py navigation_instance_entrances` 实跑生成 Data 文件，加入 TOC。
- [x] 步骤 50：补数据验证：剃刀高地 `journalInstanceID=233` 输出外部入口目标，且不指向副本内部 `MapID=129`。
- [x] 步骤 51：调整 `Toolbox.EJ.NavigateToDungeonEntrance` / `FindDungeonEntranceForJournalInstance` 的入口消费链路，读取 `NavigationInstanceEntrances` 导出的入口目标。
- [x] 步骤 52：新增 `navigation_route_edges` 聚合契约或导出脚本，把可直接用于运行时图的导出边统一为一个消费入口；第一阶段只纳入 Taxi 公共交通边。
- [ ] 步骤 53：评估 `navigation_portal_candidates` 与 `navigation_spell_travel_candidates` 的数据库可达性，只输出候选，不进入运行时路径图，直到目的地 / 落点可由数据库闭环证明。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`
- 命令 / 检查点 2：
  搜索 `DEFAULT_CHAT_FRAME`、固定正数秒 `C_Timer.After`、未本地化玩家文案，确认 `navigation` 新代码没有违反项目约束。
- 命令 / 检查点 3：
  校验 `Toolbox/Toolbox.toc` 加载顺序：`Navigation.lua` 所需的 Core API、Data 与 Shared 文件先于使用者加载。
- 游戏内验证点：
  世界地图选择奥格瑞玛、杜隆塔尔、海加尔山或已维护传送门目标时，当前角色会按已确认职业能力、当前所在地与公共传送门网络选择最低成本路线；非法师或技能未知时不推荐对应法师边；顶部路径 UI 能显示并清除路线。
  奥格瑞玛到北风苔原这类飞艇 / 船公共交通目标会出现在模拟导航骨架中，并参与路线求解。

## 6. 风险与回滚

- 风险：
  API 查证结果可能显示部分场景下无法稳定读取当前用户 waypoint 或当前位置坐标。
- 回滚方式：
  回退到“仅按 waypoint 的 `uiMapID` 规划地图级路线”，但保留接口与数据模型，不再把鼠标坐标作为主目标源。
- 风险：
  DB2 导出数据不足以支撑地图基础节点。
- 回滚方式：
  保留契约入口；未导出的基础节点或路径边不进入运行时图。
- 风险：
  路线边数据过少导致推荐偏保守。
- 回滚方式：
  继续保守过滤未知边，并在测试文档记录覆盖范围。

## 7. 执行记录

- 2026-04-27：用户回复“开动”后，已将确认规则落入 `docs/specs/navigation-spec.md`，并建立设计与计划文档；业务代码尚未修改。
- 2026-04-27：当前分支直接开发；已按 TDD 新增 `Toolbox.Navigation` 路径核心、可用性过滤、当前角色 spellbook 快照与法师奥格瑞玛验收样例，尚未接入世界地图入口和模块 UI。
- 2026-04-27：已新增 `navigation` 模块注册、Config 默认值、Locales 文案、TOC 加载项和设置页静态校验；`Shared.lua` 暂缓到 WorldMap / RouteBar 拆分时创建。
- 2026-04-27：已新增 `RouteBar.lua` 与 `WorldMap.lua`，世界地图 `OnShow` 创建“规划路线”按钮，按钮点击读取当前地图与鼠标归一化坐标，规划路线后在屏幕顶部中间显示步骤；该阶段的最小手工图方案已在 Chunk 10 废弃。
- 2026-04-27：已完成 `navigation_map_nodes` 契约与正式导出；历史 `NavigationManualEdges.lua` 手工玩法边已在 Chunk 10 从运行时链路移除。
- 2026-04-27：按 Retail API 查证结果把技能可用性检测改为优先 `C_SpellBook.IsSpellInSpellBook`、旧 `IsSpellKnown` 兜底；完整自动化验证通过，计划状态改为已完成。
- 2026-04-27：按用户实测反馈重构旅行图模型：`targetRules` 支持多个候选枢纽，当前 `uiMapID` 可作为零成本起点；后续 `targetRules` 只能由导出契约提供。
- 2026-04-27：复审阶段仅落文档：确认目标源改为用户 waypoint、`x/y` 接入终段成本；`Tooltip.lua` 排除出本轮范围，`EncounterJournal.lua` 性能方案待单独确认。
- 2026-04-27：用户确认公共交通边长期方向走 `Taxi*` 自动导出，但当前执行边界先用模拟飞艇 / 船数据跑测试；真实数据库导出待后续单独开动。
- 2026-04-27：数据源评估补充完成：`Taxi*` 适合直接导出飞艇 / 船 / 电车最终边；世界传送门与职业旅行技能只适合先导出候选表，未形成数据库闭环前不进入运行时图。
- 2026-04-27：用户回复“开动”后，真实 `Taxi*` 数据库导出进入当前执行范围；确认先把该决策落到规格、设计与计划文档，再修改契约、Data 与 TOC。
- 2026-04-27：已为 `wow.db` 建立 Taxi 导出相关索引（`taxipathnode.PathID`、`taxipathnode(PathID, Flags, Delay)`、`taxipath(FromTaxiNode, ToTaxiNode)`、`taxinodes.ContinentID`、`uimapassignment(MapID, UiMapID)`），导出查询恢复到秒级内。
- 2026-04-27：已将 `navigation_taxi_edges` 契约转 active，正式导出 `NavigationTaxiEdges.lua`（91 个节点、129 条边）并加入 TOC；补充 writer 字符串 key 单测和生成型 Data TOC 校验。
- 2026-04-27：验证结果：`validate_data_contracts.py`、`test_lua_contract_writer`、`test_contract_export` 通过；`python tests/run_all.py --ci` 剩余 1 个与本轮无关的 EncounterJournal 用例失败（默认 `listPinAlwaysVisible = false` 与测试常驻显示期望不一致）。
- 2026-04-27：已新增 `navigation_map_assignments` 与 `navigation_instance_entrances` active 契约，正式导出 `NavigationMapAssignments.lua` 与 `NavigationInstanceEntrances.lua` 并加入 TOC；剃刀高地 `journalInstanceID=233` 导出为外部入口 `TargetUiMapID=64`、`TargetX=0.762069`、`TargetY=0.521909`，`InstanceMapID=129` 仅作为追溯字段。
- 2026-04-27：已将 `Toolbox.EJ.FindDungeonEntranceForJournalInstance` 改为消费 `NavigationInstanceEntrances` 导出数据，不再扫描运行时 `C_EncounterJournal.GetDungeonEntrancesForMap`；`python tests/run_all.py --ci` 通过（114 successes / 0 failures）。
- 2026-04-27：已新增 `navigation_route_edges` active 契约并正式导出 `NavigationRouteEdges.lua`；`Toolbox.Navigation` 与 `WorldMap` 技能需求链路改为消费统一路线边表，`NavigationTaxiEdges.lua` 仅保留为 Taxi 来源侧导出。
- 2026-04-27：统一路线边验证通过：`python tests/validate_data_contracts.py`、`python tests/validate_settings_subcategories.py`、导出脚本单测与 `python tests/run_all.py --ci` 均通过（115 successes / 0 failures）。
- 2026-04-27：修正路线边导出口径：删除 `navigation_route_edges` 中由 `UiMapAssignment.Region_*` 覆盖/相交、`TaxiPathNode` 轨迹坐标与 `WaypointSafeLocs` 坐标接入派生的地图联接边；当前运行时路线边只保留 `UiMapLink` 明确链接。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：建立 `navigation` 新模块实施计划 |
| 2026-04-27 | 复审修订：新增 waypoint / `x/y` 成本修正任务，计划状态改为“首版已完成，复审修订待用户开动” |
| 2026-04-27 | 范围补充：公共交通边长期方向确认走 `Taxi*`；当前执行边界改为先用模拟飞艇 / 船数据跑测试，计划状态保持可执行 |
| 2026-04-27 | 实施更新：Chunk 6 与 Chunk 7A 代码及测试脚本已完成，按用户要求仅完成静态检查，自动化测试与功能文档回写待后续执行 |
| 2026-04-27 | 数据准备：新增 `navigation_taxi_edges` draft 契约，先固定 Taxi* 表关系、过滤规则与导出形状；真实数据库导出继续待环境支持后执行 |
| 2026-04-27 | 方案评估补充：明确 `Taxi*` 走最终边导出，传送门 / 职业旅行技能走候选导出；`targetRules` 只能由契约导出提供 |
| 2026-04-27 | 数据导出重规划：移除 `NavigationManualEdges.lua` 运行时消费，新增 `navigation_map_assignments`、`navigation_instance_entrances` 与 `navigation_route_edges` 规划 |
| 2026-04-27 | 用户确认“开动”：新增 Chunk 9，真实 `Taxi*` 导出、`NavigationTaxiEdges.lua` 生成与 TOC 接线进入执行 |
| 2026-04-27 | Chunk 9 执行：建立本地 wow.db 索引，契约转 active，生成 `NavigationTaxiEdges.lua`，接入 TOC，并记录验证结果 |
| 2026-04-27 | Chunk 10 执行：新增 `navigation_route_edges` 统一路线边导出，运行时构图入口改为 `NavigationRouteEdges.lua` |
| 2026-04-27 | 修正 Chunk 10：移除坐标区域、轨迹与 SafeLoc 派生联接，统一路线边当前只保留 `UiMapLink` 明确链接 |
