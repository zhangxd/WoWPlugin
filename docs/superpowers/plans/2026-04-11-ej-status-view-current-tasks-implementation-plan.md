# Encounter Journal Status View Current Tasks Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `encounter_journal` 的 `状态` 视图改成“左侧角色任务日志中的全部当前任务，右侧完整任务线并高亮当前任务；未映射任务回退为纯任务详情”。

**Architecture:** 保持现有三视图框架不变，先在 `Toolbox.Questlines` 增加 Quest Log 当前任务枚举 API，再由 `status` 视图消费该 API。选择记忆继续复用现有 `questViewSelected*` 键，不新增存档结构。

**Tech Stack:** Lua, WoW Retail UI API, 现有逻辑测试 harness（`busted`）

---

## Chunk 1: 文档与测试先行

### Task 1: 写状态视图回归测试

**Files:**
- Modify: `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
- Modify: `tests/logic/spec/questline_progress_spec.lua`

- [ ] **Step 1: 写失败测试**
- [ ] **Step 2: 运行 `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua` 并确认因旧行为失败**
- [ ] **Step 3: 运行 `busted tests/logic/spec/questline_progress_spec.lua` 并确认新 API 用例失败**

### Task 2: 覆盖两条核心行为

**Files:**
- Modify: `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`

- [ ] **Step 1: 断言状态视图左侧覆盖 Quest Log 当前任务，不显示 pending**
- [ ] **Step 2: 断言点击已映射任务后右侧渲染完整任务线并高亮当前任务**
- [ ] **Step 3: 断言点击未映射任务后右侧回退为纯任务详情**

## Chunk 2: 最小实现

### Task 3: 扩展 Questline 领域 API

**Files:**
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
- Modify: `tests/logic/spec/questline_progress_spec.lua`

- [ ] **Step 1: 新增 Quest Log 当前任务枚举 API**
- [ ] **Step 2: 返回已映射/未映射任务的统一结构**
- [ ] **Step 3: 跑 QuestlineProgress 单测转绿**

### Task 4: 调整状态视图选择恢复与渲染

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: 左侧在 `status` 视图下改为 Quest Log 当前任务列表**
- [ ] **Step 2: 在 `resolveSelectionWithModel` 中让 `status` 视图优先落到有效当前任务**
- [ ] **Step 3: 右侧在 `status` 视图下对已映射任务显示完整任务线**
- [ ] **Step 4: 对未映射任务回退为纯任务详情**
- [ ] **Step 5: 当前任务节点沿用现有选中高亮**

## Chunk 3: 验证

### Task 5: 运行回归与全量测试

**Files:**
- Verify: `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
- Verify: `tests/logic/spec`

- [ ] **Step 1: 运行单文件逻辑测试**
- [ ] **Step 2: 运行 `busted tests/logic/spec`**
- [ ] **Step 3: 运行 `python tests/run_all.py`**

## Chunk 4: 任务列表状态染色

### Task 6: 为类型/地图任务节点补状态色回归测试

**Files:**
- Modify: `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`

- [ ] **Step 1: 写地图视图任务节点 completed=绿色 的失败测试**
- [ ] **Step 2: 写类型视图任务节点 completed=绿色 且 selected 优先蓝色 的失败测试**
- [ ] **Step 3: 运行单文件逻辑测试确认因旧样式失败**

### Task 7: 最小实现类型/地图任务节点着色

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: 为地图视图左侧任务节点补 `status` 字段**
- [ ] **Step 2: 为类型视图任务节点补 `status/selected` 字段**
- [ ] **Step 3: 复用现有状态着色 helper，保持 selected 优先**

### Task 8: 验证状态染色回归

**Files:**
- Verify: `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
- Verify: `tests/logic/spec`

- [ ] **Step 1: 运行单文件逻辑测试**
- [ ] **Step 2: 运行 `busted tests/logic/spec`**
- [ ] **Step 3: 运行 `python tests/run_all.py`**
