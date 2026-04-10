# EJ Quest UI Multi-View Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Encounter Journal quest tab multi-view UI (status/type/map) with type indexing, locale-mapped type labels, and selection persistence.

**Architecture:** Extend `Toolbox.Questlines` to build type indexes and resolve type labels from a manual mapping table, while `Modules/EncounterJournal.lua` renders three views from the shared model and persists selection state. All UI hooks must use `OnShow`/`hooksecurefunc` binding paths and avoid fixed delays.

**Tech Stack:** Lua (WoW addon), WoW API (C_QuestLog/C_Map), logic tests via `busted` harness, Python test runner.

---

**File Map**
- Create: `Toolbox/Data/QuestTypeNames.lua`
- Modify: `Toolbox/Toolbox.toc`
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
- Modify: `Toolbox/Core/Foundation/Locales.lua`
- Modify: `Toolbox/Core/Foundation/Config.lua`
- Modify: `Toolbox/Modules/EncounterJournal.lua`
- Modify: `tests/logic/fixtures/InstanceQuestlines_Mock.lua`
- Modify: `tests/logic/spec/questline_progress_spec.lua`
- Modify: `tests/logic/spec/questline_progress_live_data_spec.lua`
- Modify: `docs/Toolbox-addon-design.md`

---

## Chunk 0: Preflight Decisions (Blocking)

### Task 0: Confirm gate and schema decision

- [ ] **Step 1: Gate 3 confirmation ("开动")**

Confirm explicit "开动" before any changes to `Toolbox/Modules/**`, `Toolbox/Core/**`, `Toolbox/UI/**`, or `Toolbox/Toolbox.toc`.

- [ ] **Step 2: Schema version decision**

Decide whether `InstanceQuestlines` moves to `schemaVersion = 4` now, or stays at `v3` with `Type` optional.

- If `v4`: plan must include regeneration of live data file via WoWDB export before release.
- If `v3`: keep production validation tolerant for missing `Type`.

---

## Chunk 1: Type Data Contracts and QuestlineProgress API

### Task 1: Add type mapping table and locale fallback

**Files:**
- Create: `Toolbox/Data/QuestTypeNames.lua`
- Modify: `Toolbox/Core/Foundation/Locales.lua`

- [ ] **Step 1: Write the failing tests**

Add specs in `tests/logic/spec/questline_progress_spec.lua` that call the new `Toolbox.Questlines.GetQuestTypeLabel(typeId)`:
- initialize `Toolbox.L` and `EJ_QUEST_TYPE_UNKNOWN_FMT` within the test setup (ensure no nil access)
- expect fallback output when no mapping exists
- expect a localized label when mapping exists

```lua
it("returns unknown type label when mapping missing", function()
  Toolbox.Data = Toolbox.Data or {}
  Toolbox.L = Toolbox.L or {}
  Toolbox.L.EJ_QUEST_TYPE_UNKNOWN_FMT = "Unknown Type (%s)"
  local label = Toolbox.Questlines.GetQuestTypeLabel(9999)
  assert.is_truthy(label and label:match("9999"))
end)

it("returns mapped type label when mapping exists", function()
  Toolbox.Data = Toolbox.Data or {}
  local originalNames = Toolbox.Data.QuestTypeNames
  Toolbox.L = Toolbox.L or {}
  local originalLabel = Toolbox.L.EJ_QUEST_TYPE_TEST
  Toolbox.Data.QuestTypeNames = { [12] = "EJ_QUEST_TYPE_TEST" }
  Toolbox.L.EJ_QUEST_TYPE_TEST = "Test Type"
  local label = Toolbox.Questlines.GetQuestTypeLabel(12)
  assert.are.equal("Test Type", label)
  Toolbox.Data.QuestTypeNames = originalNames
  Toolbox.L.EJ_QUEST_TYPE_TEST = originalLabel
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: FAIL with `GetQuestTypeLabel` missing.

- [ ] **Step 3: Create mapping file, locale keys, and TOC entry**

Create `Toolbox/Data/QuestTypeNames.lua` with Template B header and a minimal mapping entry used by tests. Add locale keys `EJ_QUEST_TYPE_UNKNOWN_FMT` and `EJ_QUEST_TYPE_TEST` to `Toolbox/Core/Foundation/Locales.lua` for `zhCN` and `enUS`. Add `Data/QuestTypeNames.lua` to `Toolbox/Toolbox.toc` after `Data/InstanceQuestlines.lua` to ensure it loads before `Modules/EncounterJournal.lua`. (TOC change is also gated by "开动".)

```lua
-- in QuestTypeNames.lua
Toolbox.Data.QuestTypeNames = {
  [12] = "EJ_QUEST_TYPE_TEST",
}
```

```lua
-- in Locales.lua
EJ_QUEST_TYPE_UNKNOWN_FMT = "未知类型(%s)", -- zhCN
EJ_QUEST_TYPE_UNKNOWN_FMT = "Unknown Type (%s)", -- enUS
```

- [ ] **Step 4: Run test to verify it still fails**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: still FAIL (implementation missing).

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Data/QuestTypeNames.lua Toolbox/Core/Foundation/Locales.lua Toolbox/Toolbox.toc tests/logic/spec/questline_progress_spec.lua
git commit -m "数据: 添加任务类型映射表与兜底文案" -m "- [功能] 新增 QuestTypeNames 数据表并补充未知类型兜底" -m "- 影响: 任务类型展示依赖本地映射"
```

### Task 2: Update mock fixture to include Type and (optionally) schema v4

**Files:**
- Modify: `tests/logic/fixtures/InstanceQuestlines_Mock.lua`
- Modify: `tests/logic/spec/questline_progress_spec.lua`

- [ ] **Step 1: Write the failing test**

Extend `questline_progress_spec.lua` to assert type indexes exist, include known type IDs from the mock fixture, and are sorted by numeric type ID. Also verify `typeToQuestLineIDs` and `typeToMapIDs` are present. If `typeList` is empty, skip the ordering assertion. Add explicit checks for at least one expected `typeId` and its `typeToQuestIDs` entry.

```lua
it("builds type indexes from quest data", function()
  local model = Toolbox.Questlines.GetQuestTabModel()
  assert.is_truthy(model.typeList)
  assert.is_truthy(model.typeToQuestIDs)
  assert.is_truthy(model.typeToQuestLineIDs)
  assert.is_truthy(model.typeToMapIDs)
  assert.is_true(model.typeToQuestIDs[12] ~= nil)
  if #model.typeList > 1 then
    for index = 1, #model.typeList - 1 do
      assert.is_true(model.typeList[index] <= model.typeList[index + 1])
    end
  end
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: FAIL (indexes not built yet).

- [ ] **Step 3: Update mock fixture**

If schemaVersion is confirmed as v4, bump `schemaVersion` to 4 and add numeric `Type` on each mock quest. If staying v3, keep schemaVersion 3 but include `Type` and adjust validation expectations accordingly.

- [ ] **Step 4: Run test to verify it still fails**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: still FAIL (indexes not built yet).

- [ ] **Step 5: Commit**

```bash
git add tests/logic/fixtures/InstanceQuestlines_Mock.lua tests/logic/spec/questline_progress_spec.lua
git commit -m "测试: 更新任务类型 mock 数据" -m "- [测试] mock 任务加入 Type 字段以覆盖类型索引" -m "- 影响: 仅测试数据与断言更新"
```

### Task 3: Implement type validation, indexes, and label resolver in QuestlineProgress

**Files:**
- Modify: `Toolbox/Core/API/QuestlineProgress.lua`
- Modify: `tests/logic/spec/questline_progress_spec.lua`
- Modify: `tests/logic/spec/questline_progress_live_data_spec.lua`

- [ ] **Step 1: Run tests to see failures**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: FAIL (type indexes + label resolver missing).

- [ ] **Step 2: Implement minimal logic**

Add to `QuestlineProgress.lua`:
- Validation for `Type` (number) when `schemaVersion >= 4`; if staying v3, treat `Type` as optional and **build indexes from entries that do have `Type`** (skip quests without `Type`; do not create synthetic `0` bucket).
- Build `typeList`, `typeToQuestIDs`, `typeToQuestLineIDs`, `typeToMapIDs` in `buildQuestTabModel` and **sort `typeList` ascending numeric**.
- Add `Toolbox.Questlines.GetQuestTypeLabel(typeId)` that uses `Toolbox.Data.QuestTypeNames[typeId]` -> `Toolbox.L[localeKey]`, falling back to `EJ_QUEST_TYPE_UNKNOWN_FMT` with typeId.
- Add `---` doc comment with `@param`/`@return` for `GetQuestTypeLabel` per AGENTS.
- If schemaVersion is bumped to 4, add a **release checklist step** in this plan to regenerate `Toolbox/Data/InstanceQuestlines.lua` via WoWDB export and verify file header/strict mode; otherwise keep production validation tolerant.

- [ ] **Step 3: Update live-data spec if needed**

Adjust `questline_progress_live_data_spec.lua` to allow missing Type when schemaVersion is 3 (or to expect strict failure if schemaVersion is 4 without Type).

- [ ] **Step 4: Run tests to verify pass**

Run: `busted tests/logic/spec/questline_progress_spec.lua`
Expected: PASS

Run: `busted tests/logic/spec/questline_progress_live_data_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Core/API/QuestlineProgress.lua tests/logic/spec/questline_progress_spec.lua tests/logic/spec/questline_progress_live_data_spec.lua
git commit -m "功能: 任务类型索引与展示名解析" -m "- [功能] Questlines 构建类型索引并提供类型名解析" -m "- [测试] 更新任务线逻辑测试" -m "- 影响: 仅任务页签数据模型"
```

---

## Chunk 2: Selection State and Persistence

### Task 4: Add selection persistence keys

**Files:**
- Modify: `Toolbox/Core/Foundation/Config.lua`

- [ ] **Step 1: Write the failing test**

Add or extend a logic test to assert `Toolbox.Config.GetModule("encounter_journal")` includes new default keys when initialized.

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: FAIL due to missing keys (adjust if this spec lacks coverage).

- [ ] **Step 3: Implement defaults and migration**

Add defaults for:
- `questViewMode`
- `questViewSelectedMapID`
- `questViewSelectedTypeID`
- `questViewSelectedQuestLineID`
- `questViewSelectedQuestID`

Ensure migration is idempotent per AGENTS.

- [ ] **Step 4: Run test to verify pass**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Core/Foundation/Config.lua tests/logic/spec/encounter_journal_event_lifecycle_spec.lua
git commit -m "配置: 任务页签视图状态持久化" -m "- [功能] 增加任务页签视图与选择状态默认值" -m "- 影响: 仅存档默认值与迁移"
```

---

## Chunk 3: Encounter Journal Multi-View UI

### Task 5: Add view switcher and shared selection state

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: Write a failing test or harness assertion**

Add a minimal harness test in `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua` to verify the quest tab registers a view switcher frame and that selection state is stored in module DB.

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: FAIL (switcher not created).

- [ ] **Step 3: Implement view switcher**

In `EncounterJournal.lua`:
- Add a small switcher UI (buttons or tabs) on the quest tab header.
- Wire to `SelectionState.selectedView` and save to `questViewMode`.
- Respect AGENTS: bind creation to `OnShow`/`hooksecurefunc` (no fixed delay).

- [ ] **Step 4: Run test to verify pass**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Modules/EncounterJournal.lua tests/logic/spec/encounter_journal_event_lifecycle_spec.lua
git commit -m "功能: 增加任务页签视图切换" -m "- [功能] 任务页签支持状态/类型/地图视图切换" -m "- 影响: 新增玩家可见入口"
```

### Task 6: Implement status view with map tree filter

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: Write harness assertions**

Add harness checks for:
- default map selection = current map
- status view renders three columns

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement status view rendering**

Use shared model; apply map tree filter; group tasks into Ready/Active/Pending.

- [ ] **Step 4: Run test to verify pass**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Modules/EncounterJournal.lua tests/logic/spec/encounter_journal_event_lifecycle_spec.lua
git commit -m "功能: 状态视图渲染" -m "- [功能] 状态视图三列泳道与地图树过滤" -m "- 影响: 任务页签展示逻辑"
```

### Task 7: Implement type view tree + list mode

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: Write harness assertions**

Add harness checks for:
- type view uses typeList order
- list mode filters by current map selection

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement type view**

- Tree mode: type -> map -> questline -> quest (mapless goes to “其他”).
- List mode: only tasks under current selected map; if mapless, list only “其他”.

- [ ] **Step 4: Run test to verify pass**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Modules/EncounterJournal.lua tests/logic/spec/encounter_journal_event_lifecycle_spec.lua
git commit -m "功能: 类型视图树形与列表模式" -m "- [功能] 类型视图支持树形/列表切换" -m "- 影响: 任务页签类型展示"
```

### Task 8: Implement map view renderer

**Files:**
- Modify: `Toolbox/Modules/EncounterJournal.lua`

- [ ] **Step 1: Add harness assertions**

Verify map view defaults to last selected map and renders questline list.

- [ ] **Step 2: Run test to verify it fails**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: FAIL

- [ ] **Step 3: Implement map view**

Render questline list / quest list based on map tree selection.

- [ ] **Step 4: Run test to verify pass**

Run: `busted tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Toolbox/Modules/EncounterJournal.lua tests/logic/spec/encounter_journal_event_lifecycle_spec.lua
git commit -m "功能: 地图视图渲染" -m "- [功能] 地图视图与选择状态联动" -m "- 影响: 任务页签地图展示"
```

---

## Chunk 4: Documentation and Final Verification

### Task 9: Update overall design doc

**Files:**
- Modify: `docs/Toolbox-addon-design.md`

- [ ] **Step 1: Add/Update mapping entries**

Update module map, data examples, and notes for new view switcher, type mapping file, and persistence keys.

- [ ] **Step 2: Run static tests**

Run: `python tests/validate_settings_subcategories.py`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add docs/Toolbox-addon-design.md
git commit -m "文档: 更新任务页签多视图说明" -m "- [文档] 增加视图切换与类型映射说明" -m "- 影响: 仅文档"
```

### Task 10: Full test run

**Files:**
- Test: `tests/run_all.py`

- [ ] **Step 1: Run full tests**

Run: `python tests/run_all.py`
Expected: PASS (requires `busted` installed)

- [ ] **Step 2: Commit final fixes (if any)**

If tests required fixes, commit them with descriptive messages.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-10-ej-quest-ui-multiview-implementation-plan.md`. Ready to execute?**
