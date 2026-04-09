# EJ Quest Tab Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Encounter Journal 任务页签从旧树表结构迁移到 schema v2（`quests/questLines/questLineQuestIDs/expansionQuestLineIDs`），并完成“左导航树 + 右内容区”联动实现。

**Architecture:** 保留 `Toolbox.Questlines` 作为唯一任务数据领域 API，在该层完成 strict 校验、索引构建、进度聚合与展示模型转换；`Modules/EncounterJournal.lua` 只消费领域 API，维护页签状态机与 UI 事件联动。采用增量替换：先完成数据契约与 API，再替换 UI 渲染层，最后收口校验与测试。

**Tech Stack:** Lua (WoW Retail API), Python (现有结构验证脚本), WoW AddOn TOC/Locales/Config。

---

## Scope Check

该需求聚焦单一子系统（`encounter_journal` 任务页签）。不拆分为多计划；按数据层 -> UI 层 -> 验证层分 chunk 执行。

## File Structure (Planned)

- Modify: `Toolbox/Data/InstanceQuestlines.lua`
  - 切换为 schema v2 mock 基线数据，保留当前样例任务线内容。
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
  - 增加 strict 校验器、schema v2 查询/聚合接口、旧接口兼容包装。
- Modify: `Toolbox/Modules/EncounterJournal.lua`
  - 重写任务页签 UI 为“左树 + 右区”，实现状态机与双向联动。
- Modify: `Toolbox/Core/Foundation/Config.lua`
  - 新增页签状态持久化默认值（选中节点/展开状态）。
- Modify: `Toolbox/Core/Foundation/Locales.lua`
  - 新增右侧区块标题、空态、错误态文案键（`enUS/zhCN`）。
- Modify: `tests/validate_settings_subcategories.py`
  - 将旧 schema 断言更新为 schema v2 + 新 API/新 UI 断言。
- Optional (blocked by external repo): `../WoWDB/scripts/*.py`
  - 导出侧 strict 对齐；当前工作区不可见，作为后续联调任务记录。

## Chunk 1: Schema v2 Data + API Contract

### Task 1: 先更新测试断言（让旧实现先失败）

**Files:**
- Modify: `tests/validate_settings_subcategories.py`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 写入 schema v2 断言（替换旧 `expansions/indexes` 断言）**

```python
require_contains(data_text, "schemaVersion = 2", "questline data schema version v2")
require_contains(data_text, "quests = {", "questline data quests table")
require_contains(data_text, "questLines = {", "questline data questLines table")
require_contains(data_text, "questLineQuestIDs = {", "questline data questLine map")
require_contains(data_text, "expansionQuestLineIDs = {", "questline data expansion map")
```

- [ ] **Step 2: 写入 API 新能力断言（strict/新查询入口）**

```python
require_contains(questline_api_text, "Validate", "questline strict validation api")
require_contains(questline_api_text, "GetQuestTabModel", "questline tab model api")
require_contains(questline_api_text, "GetQuestListByQuestLineID", "questline list api")
require_contains(questline_api_text, "GetQuestDetailByID", "quest detail api")
```

- [ ] **Step 3: 运行测试确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: FAIL，提示缺少 schema v2 或新 API 标识。

- [ ] **Step 4: 提交测试先行变更**

```bash
git add tests/validate_settings_subcategories.py
git commit -m "test: assert EJ quest tab schema v2 and api contracts"
```

### Task 2: 迁移静态数据到 schema v2（mock 基线）

**Files:**
- Modify: `Toolbox/Data/InstanceQuestlines.lua`
- Test: `python tests/validate_settings_subcategories.py`

- [ ] **Step 1: 重写数据头结构为 schema v2**

```lua
Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 2,
  sourceMode = "mock",
  generatedAt = "2026-04-09T16:30:00Z",
  quests = {},
  questLines = {},
  questLineQuestIDs = {},
  expansionQuestLineIDs = {},
}
```

- [ ] **Step 2: 将现有样例任务转换填充 `quests`/`questLines`/映射表**

```lua
questLines = {
  [100001] = { questLineID = 100001, name = "A Shadowy Invitation", expansionID = 10, primaryMapID = 2371 },
}
questLineQuestIDs = {
  [100001] = { 84956, 84957, 85003 },
}
```

- [ ] **Step 3: 运行测试（预期仍失败于 API/UI 未改）**

Run: `python tests/validate_settings_subcategories.py`  
Expected: FAIL，主要集中在 `QuestlineProgress.lua` 新 API 断言。

- [ ] **Step 4: 提交数据迁移**

```bash
git add Toolbox/Data/InstanceQuestlines.lua
git commit -m "data: migrate instance questlines to schema v2 mock baseline"
```

### Task 3: 实现 strict 校验与查询 API（领域层）

**Files:**
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 增加 strict 校验入口与错误返回结构**

```lua
function Toolbox.Questlines.ValidateInstanceQuestlinesData(dataTable, strictMode)
  -- return true, nil
  -- return false, { code = "E_BAD_REF", message = "...", path = "questLineQuestIDs[100001][3]" }
end
```

- [ ] **Step 2: 增加 schema v2 读取索引构建（expansion/map/questline）**

```lua
local function buildQuestlineIndexes(dataTable)
  -- byExpansion, byMap, questToQuestLine, orderedQuestLineIDs
end
```

- [ ] **Step 3: 增加 UI 消费 API（保持模块无数据拼装逻辑）**

```lua
function Toolbox.Questlines.GetQuestTabModel() end
function Toolbox.Questlines.GetQuestLinesForSelection(selectedKind, expansionID, mapID) end
function Toolbox.Questlines.GetQuestListByQuestLineID(questLineID) end
function Toolbox.Questlines.GetQuestDetailByID(questID) end
```

- [ ] **Step 4: 保留兼容入口（不再依赖旧 schema）**

```lua
function Toolbox.Questlines.GetExpansionTree(expansionID)
  -- wrapper: convert v2 model to legacy tree shape for callers still using old API
end
```

- [ ] **Step 5: 运行测试确认 Chunk 1 通过**

Run: `python tests/validate_settings_subcategories.py`  
Expected: PASS 或仅剩 UI 断言失败（若 Task 1 已加 UI 新断言）。

- [ ] **Step 6: 提交 API 重构**

```bash
git add Toolbox/Core/API/QuestlineProgress.lua
git commit -m "feat: add questline schema v2 validation and query apis"
```

## Chunk 2: Quest Tab UI Split Layout + State Machine

### Task 4: 先写 UI 侧断言（状态机/分栏结构）

**Files:**
- Modify: `tests/validate_settings_subcategories.py`
- Test: `python tests/validate_settings_subcategories.py`

- [ ] **Step 1: 增加分栏结构断言**

```python
require_contains(module_text, "leftTree", "quest tab left tree container")
require_contains(module_text, "rightContent", "quest tab right content container")
```

- [ ] **Step 2: 增加状态机与联动断言**

```python
require_contains(module_text, "selectedKind", "quest tab selection state kind")
require_contains(module_text, "GetQuestLinesForSelection", "quest tab consumes query api")
require_contains(module_text, "GetQuestListByQuestLineID", "quest tab consumes questline list api")
require_contains(module_text, "GetQuestDetailByID", "quest tab consumes quest detail api")
```

- [ ] **Step 3: 运行测试确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: FAIL，提示模块中缺少新结构标识。

- [ ] **Step 4: 提交断言更新**

```bash
git add tests/validate_settings_subcategories.py
git commit -m "test: add EJ quest tab split-layout and state-machine assertions"
```

### Task 5: 重构 EncounterJournal 任务页签为左右分栏

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`
- Modify: `Toolbox/Core/Foundation/Config.lua`
- Modify: `Toolbox/Core/Foundation/Locales.lua`
- Test: `python tests/validate_settings_subcategories.py`

- [ ] **Step 1: 在模块内定义状态对象（单一状态源）**

```lua
local questTabState = {
  selectedKind = "expansion",
  selectedExpansionID = nil,
  selectedMapID = nil,
  selectedQuestLineID = nil,
  selectedQuestID = nil,
}
```

- [ ] **Step 2: 改造 `ensureWidgets` 创建左右容器**

```lua
-- leftTreePanel / rightContentPanel
-- rightContentPanel 下分 questLineList / questList / questDetail
```

- [ ] **Step 3: 实现左树渲染（资料片->地图->任务线）与折叠持久化**

Run-time rule:
- 默认展开当前资料片和当前地图
- 折叠键格式：`expansion:<id>` / `map:<expansionID>:<mapID>`

- [ ] **Step 4: 实现右侧三种视图切换**

```lua
-- selectedKind == expansion|map => render questline list
-- selectedKind == questline => render quest list
-- selectedKind == quest => render quest detail
```

- [ ] **Step 5: 实现右侧点击反向联动左树选中**

```lua
-- click questline item => update selectedKind/selectedQuestLineID + sync left tree
-- click quest item => update selectedKind/selectedQuestID + sync left tree
```

- [ ] **Step 6: 增加 Config 默认值与迁移保护**

```lua
questlineTreeSelection = { selectedKind = "expansion" }
questlineTreeCollapsed = questlineTreeCollapsed or {}
```

- [ ] **Step 7: 增加 Locales 文案键（enUS/zhCN）**

```lua
EJ_QUESTLINE_LIST_TITLE
EJ_QUEST_TASK_LIST_TITLE
EJ_QUEST_DETAIL_TITLE
EJ_QUEST_DATA_INVALID
```

- [ ] **Step 8: 运行测试确认通过**

Run: `python tests/validate_settings_subcategories.py`  
Expected: PASS。

- [ ] **Step 9: 提交 UI 重构**

```bash
git add Toolbox/Modules/EncounterJournal.lua Toolbox/Core/Foundation/Config.lua Toolbox/Core/Foundation/Locales.lua
git commit -m "feat: refactor EJ quest tab to split tree-content layout"
```

## Chunk 3: Strict Behavior, Regression, and Handoff

### Task 6: 严格失败路径与回退策略收口

**Files:**
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
- Modify: `Toolbox/Modules/EncounterJournal.lua`
- Test: `python tests/validate_settings_subcategories.py`

- [ ] **Step 1: 将 strict 校验失败透传为 UI 可显示错误态**

```lua
local ok, err = Toolbox.Questlines.ValidateInstanceQuestlinesData(dataTable, true)
if not ok then
  -- show EJ_QUEST_DATA_INVALID + err.code/path
end
```

- [ ] **Step 2: 实现“选中对象失效”的两级回退**

1. 回退到同资料片节点。  
2. 同资料片不存在时回退首个资料片节点。

- [ ] **Step 3: 验证 `nil` 字段不显示、空分组不显示**

Run: in-game manual check（见下方手工验证）。

- [ ] **Step 4: 运行自动验证**

Run: `python tests/validate_settings_subcategories.py`  
Expected: PASS 且输出 `OK: settings subcategories structure validated`。

- [ ] **Step 5: 提交收口修复**

```bash
git add Toolbox/Core/API/QuestlineProgress.lua Toolbox/Modules/EncounterJournal.lua
git commit -m "fix: finalize EJ quest tab strict errors and selection fallback"
```

### Task 7: 人工回归（Retail 实机）

**Files:**
- No file change required unless bug found

- [ ] **Step 1: 重载并进入冒险手册任务页签**

Run: `/reload`  
Expected: 页签可见，无 Lua 报错。

- [ ] **Step 2: 验证左树默认展开与默认选中**

Expected:
- 默认选中当前资料片
- 当前资料片和当前地图默认展开

- [ ] **Step 3: 验证右侧联动**

Expected:
- 点资料片/地图 => 右侧任务线列表
- 点任务线 => 右侧任务列表
- 点任务 => 右侧任务详情

- [ ] **Step 4: 验证进度与显示规则**

Expected:
- 地图/任务线显示 `completed/total`
- 任务列表仅任务名+图标/颜色
- `nil` 字段不显示

- [ ] **Step 5: 若通过则提交回归结论（文档或 PR 描述）**

```bash
git commit --allow-empty -m "chore: validate EJ quest tab refactor manual regression"
```

## External Dependency Follow-up (Not in Current Workspace)

1. 在 `../WoWDB/scripts` 对齐 `mock/live` 同 schema 导出。
2. 将 strict 失败码映射到导出日志。
3. 用 `export_toolbox_all.py` 进行导出回归。

> 当前仓库未包含 `WoWDB` 目录，上述项在本计划中标记为外部联调任务，不阻塞本仓库实现。

## Done Criteria

1. `python tests/validate_settings_subcategories.py` 通过。
2. 任务页签读取不再依赖旧 `expansions -> types -> nodes -> chains` 数据结构。
3. UI 为“左导航树 + 右内容区”，并满足双向联动与状态回退规则。
4. strict 校验生效，坏数据失败而非静默跳过。

## Commit Strategy

1. `test:` 先行断言提交（schema/API）。
2. `data:` schema v2 数据迁移。
3. `feat:` API 重构。
4. `test:` UI 断言提交。
5. `feat:` UI 分栏重构。
6. `fix:` 严格失败与回退收口。
7. `chore:` 人工回归结论。

