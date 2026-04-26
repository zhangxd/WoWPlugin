# 地图导航模块实施计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents are explicitly authorized) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 `navigation` 新模块，在世界地图选择目标后按当前角色可用能力规划跨地图最短路线，并在屏幕顶部中间显示路径步骤。

**Architecture:** `Toolbox.Navigation` 负责路径图、可用性过滤和 Dijkstra 求解；`navigation` 模块负责世界地图入口、设置、顶部路径 UI 与生命周期。地图基础数据走契约导出，玩法路径边先以人工维护数据覆盖高价值传送能力。

**Tech Stack:** WoW Retail Lua、Toolbox 模块注册体系、`ToolboxDB.modules.navigation`、DataContracts 导出体系、现有 Lua 逻辑测试 harness、`python tests/run_all.py --ci`。

---

- 文档类型：计划
- 状态：已完成
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

## 2. 输入文档

- 需求：
  `docs/specs/navigation-spec.md`
- 设计：
  `docs/designs/navigation-design.md`
- 其他约束：
  `AGENTS.md` 三关门禁、Lua 开发规范、WoWDB 静态数据导出规则、暴雪 UI 挂接时机；实现前必须查证不确定 WoW API。

## 3. 影响文件

- 新增：
  - `Toolbox/Core/API/Navigation.lua`
  - `Toolbox/Modules/Navigation.lua`
  - `Toolbox/Modules/Navigation/Shared.lua`
  - `Toolbox/Modules/Navigation/WorldMap.lua`
  - `Toolbox/Modules/Navigation/RouteBar.lua`
  - `Toolbox/Data/NavigationMapNodes.lua`
  - `Toolbox/Data/NavigationManualEdges.lua`
  - `DataContracts/navigation_map_nodes.json`
  - `tests/logic/spec/navigation_api_spec.lua`
  - `tests/logic/spec/navigation_module_spec.lua`
  - `docs/features/navigation-features.md`
  - `docs/tests/navigation-test.md`
- 修改：
  - `Toolbox/Toolbox.toc`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
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
- [x] 步骤 7：实现法师奥格瑞玛样例所需的手工边与测试注入能力。

## Chunk 2: 数据契约与静态边

- [x] 步骤 8：新增 `DataContracts/navigation_map_nodes.json`，定义地图基础节点导出契约。
- [x] 步骤 9：通过正式导出脚本生成 `Toolbox/Data/NavigationMapNodes.lua`，不得手写覆盖数据库生成文件。
- [x] 步骤 10：新增人工维护 `Toolbox/Data/NavigationManualEdges.lua`，包含第一批职业传送、主城、当前资料片枢纽、传送门房与炉石类边。
- [x] 步骤 11：新增或更新数据校验，确保人工边引用的节点 ID 都可解析。
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

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`
- 命令 / 检查点 2：
  搜索 `DEFAULT_CHAT_FRAME`、固定正数秒 `C_Timer.After`、未本地化玩家文案，确认 `navigation` 新代码没有违反项目约束。
- 命令 / 检查点 3：
  校验 `Toolbox/Toolbox.toc` 加载顺序：`Navigation.lua` 所需的 Core API、Data 与 Shared 文件先于使用者加载。
- 游戏内验证点：
  世界地图选择奥格瑞玛、杜隆塔尔、海加尔山或已维护传送门目标时，当前角色会按已确认职业能力、当前所在地与公共传送门网络选择最低成本路线；非法师或技能未知时不推荐对应法师边；顶部路径 UI 能显示并清除路线。

## 6. 风险与回滚

- 风险：
  API 查证结果可能显示世界地图目标点击无法稳定获得坐标。
- 回滚方式：
  第一版改为在世界地图上提供明确的“使用当前地图中心 / 当前鼠标坐标作为目标”按钮，但仍保持 `navigation` 模块边界。
- 风险：
  DB2 导出数据不足以支撑地图基础节点。
- 回滚方式：
  保留契约入口，第一版以人工维护基础节点启动，后续再补导出。
- 风险：
  路线边数据过少导致推荐偏保守。
- 回滚方式：
  继续保守过滤未知边，并在测试文档记录覆盖范围。

## 7. 执行记录

- 2026-04-27：用户回复“开动”后，已将确认规则落入 `docs/specs/navigation-spec.md`，并建立设计与计划文档；业务代码尚未修改。
- 2026-04-27：当前分支直接开发；已按 TDD 新增 `Toolbox.Navigation` 路径核心、可用性过滤、当前角色 spellbook 快照与法师奥格瑞玛验收样例，尚未接入世界地图入口和模块 UI。
- 2026-04-27：已新增 `navigation` 模块注册、Config 默认值、Locales 文案、TOC 加载项和设置页静态校验；`Shared.lua` 暂缓到 WorldMap / RouteBar 拆分时创建。
- 2026-04-27：已新增 `RouteBar.lua` 与 `WorldMap.lua`，世界地图 `OnShow` 创建“规划路线”按钮，按钮点击读取当前地图与鼠标归一化坐标，规划路线后在屏幕顶部中间显示步骤；当前仍使用最小手工图，正式 DataContracts / Data 文件待 Chunk 2。
- 2026-04-27：已完成 `navigation_map_nodes` 契约与正式导出，新增 `NavigationManualEdges.lua` 手工玩法边，并把路径规划改为优先消费 Data 层；已补功能文档、测试记录和 `FEATURES.md` 总览。
- 2026-04-27：按 Retail API 查证结果把技能可用性检测改为优先 `C_SpellBook.IsSpellInSpellBook`、旧 `IsSpellKnown` 兜底；完整自动化验证通过，计划状态改为已完成。
- 2026-04-27：按用户实测反馈重构旅行图模型：`targetRules` 支持多个候选枢纽，当前 `uiMapID` 可作为零成本起点，手工边扩充为部落公共传送门、奥格瑞玛传送门房、法师多主城传送与死亡骑士 / 德鲁伊 / 武僧职业位移样例。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：建立 `navigation` 新模块实施计划 |
