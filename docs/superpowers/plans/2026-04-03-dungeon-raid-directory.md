# DungeonRaidDirectory Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Toolbox.DungeonRaidDirectory` as the shared Adventure Guide-backed dungeon/raid directory with persisted mount-summary cache, runtime lockout overlay, async build progress, settings-based cache rebuild, and migrate `ej_mount_filter` to consume it.

**Architecture:** Add a new `Core/DungeonRaidDirectory.lua` above the existing thin `Toolbox.EJ` wrapper. Persist only directory skeleton + supported difficulties + mount summaries in account-wide `ToolboxDB.global.dungeonRaidDirectory`; keep lockouts and build-state ephemeral in a runtime overlay. Drive cache construction with a budgeted `OnUpdate` cursor state machine, then switch the Adventure Guide mount filter from self-owned scans to directory summaries.

**Tech Stack:** WoW Retail Lua addon, `C_EncounterJournal` / `EJ_*`, `GetSavedInstanceInfo`, `Settings` API, `SavedVariables`, `OnUpdate` frame driver, localized strings in `Toolbox/Core/Locales.lua`

---

## File Map

- Create: `Toolbox/Core/DungeonRaidDirectory.lua`
  Responsibility: shared directory cache, EJ state driver, async build driver, runtime lockout overlay, public query API.
- Modify: `Toolbox/Toolbox.toc`
  Responsibility: load the new core file after existing EJ/Lockouts/MountJournal dependencies and before bootstrap.
- Modify: `Toolbox/Core/DB.lua`
  Responsibility: add `global.dungeonRaidDirectory` defaults and migration-safe merge behavior.
- Modify: `Toolbox/Core/Bootstrap.lua`
  Responsibility: initialize the directory layer during addon startup so settings and consumers can query build state immediately.
- Modify: `Toolbox/Core/Locales.lua`
  Responsibility: add cache-status, progress, rebuild-button, stage-label, and error strings in `enUS` / `zhCN`.
- Modify: `Toolbox/UI/SettingsHost.lua`
  Responsibility: render the cache status / progress / rebuild controls and poll `GetBuildProgress()`.
- Modify: `Toolbox/Modules/EJMountFilter.lua`
  Responsibility: stop owning mount-summary scans; consume `Toolbox.DungeonRaidDirectory.HasAnyMountLoot()` and build-state semantics instead.
- Modify: `docs/Toolbox-addon-design.md`
  Responsibility: add the new core API to the architecture map, data model, and TOC guidance after implementation.
- Modify: `docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md`
  Responsibility: update the filter spec so its data source points at `DungeonRaidDirectory` rather than private scan state.

## Verification Strategy

- There is no local Lua test harness in this repository today. Use **small, repeatable in-game checks** plus local file-level verification.
- Prefer `/dump` and `/run` checks that read public API state over hidden debug helpers.
- Keep role-specific lockout checks conditional: use a character with saved lockouts when verifying positive lockout mapping; otherwise verify “no error + empty result”.
- For each task, stage **only** the listed files when committing because the current workspace may contain unrelated edits.

## Chunk 1: Preflight And Core Scaffolding

### Task 0: Isolate The Work

**Files:**
- Modify: none
- Test: manual Git verification in a dedicated worktree

- [ ] **Step 1: Confirm the current workspace is dirty and must not receive mixed commits**

Run: `git status --short`
Expected: existing unrelated edits are present; do not stage them with this feature.

- [ ] **Step 2: Create an isolated worktree before executing the plan**

Run:

```powershell
git worktree add d:\WoWPlugin-drd -b feat/dungeon-raid-directory HEAD
```

Expected: a clean sibling worktree at `d:\WoWPlugin-drd`.

- [ ] **Step 3: Re-open the new worktree and confirm it is clean**

Run:

```powershell
git status --short
```

Expected: no output.

### Task 1: Add Persisted Cache Defaults, Load Order, And Locale Keys

**Files:**
- Modify: `Toolbox/Toolbox.toc`
- Modify: `Toolbox/Core/DB.lua`
- Modify: `Toolbox/Core/Locales.lua`
- Test: in-game `/reload`, `/run`, `/dump`

- [ ] **Step 1: Verify the cache keys do not exist yet**

Run in WoW chat after `/reload`:

```lua
/run print(type(ToolboxDB.global and ToolboxDB.global.dungeonRaidDirectory))
```

Expected: `nil`.

- [ ] **Step 2: Add the new core file to the TOC after existing EJ dependencies**

Add this line in `Toolbox/Toolbox.toc` between the existing journal-related core files and `Core\ModuleRegistry.lua`:

```toc
Core\DungeonRaidDirectory.lua
```

- [ ] **Step 3: Add account-wide cache defaults to `Toolbox/Core/DB.lua`**

Add a new `global.dungeonRaidDirectory` default shape:

```lua
global = {
  debug = false,
  locale = "auto",
  settingsGroupsExpanded = {},
  dungeonRaidDirectory = {
    schemaVersion = 1,
    interfaceBuild = 0,
    lastBuildAt = 0,
    tierNames = {},
    difficultyMeta = {},
    records = {},
  },
},
```

Do **not** add persisted `lockout` data here.

- [ ] **Step 4: Add all user-facing strings for the cache section and build stages**

Add locale keys in `Toolbox/Core/Locales.lua` for:

```lua
DRD_SECTION_TITLE
DRD_STATUS_IDLE
DRD_STATUS_BUILDING
DRD_STATUS_COMPLETED
DRD_STATUS_FAILED
DRD_STATUS_CANCELLED
DRD_STAGE_SKELETON
DRD_STAGE_DIFFICULTY
DRD_STAGE_MOUNT_SUMMARY
DRD_REBUILD_BUTTON
DRD_PROGRESS_FMT
DRD_CURRENT_FMT
DRD_LOCKOUT_REFRESHED
DRD_BUILD_FAILED_FMT
```

- [ ] **Step 5: Reload and verify the new DB shape loads without Lua errors**

Run in WoW chat after `/reload`:

```lua
/dump ToolboxDB.global.dungeonRaidDirectory
```

Expected: a table with `schemaVersion`, `interfaceBuild`, `lastBuildAt`, `tierNames`, `difficultyMeta`, and `records`.

- [ ] **Step 6: Commit only the scaffolding files**

Run:

```powershell
git add Toolbox/Toolbox.toc Toolbox/Core/DB.lua Toolbox/Core/Locales.lua
git commit -m "feat: add dungeon raid directory cache scaffolding"
```

### Task 2: Create The Core API Skeleton And Bootstrap Initialization

**Files:**
- Create: `Toolbox/Core/DungeonRaidDirectory.lua`
- Modify: `Toolbox/Core/Bootstrap.lua`
- Test: in-game `/dump`

- [ ] **Step 1: Verify the public API is still absent**

Run in WoW chat after `/reload`:

```lua
/run print(type(Toolbox.DungeonRaidDirectory))
```

Expected: `nil`.

- [ ] **Step 2: Create the new core file with runtime/cache scaffolding**

Start `Toolbox/Core/DungeonRaidDirectory.lua` with file-header docs and these public entry points:

```lua
Toolbox.DungeonRaidDirectory = Toolbox.DungeonRaidDirectory or {}

function Toolbox.DungeonRaidDirectory.Initialize() end
function Toolbox.DungeonRaidDirectory.StartBuild(isManual) end
function Toolbox.DungeonRaidDirectory.CancelBuild() end
function Toolbox.DungeonRaidDirectory.RebuildCache() end
function Toolbox.DungeonRaidDirectory.GetBuildState() end
function Toolbox.DungeonRaidDirectory.GetBuildProgress() end
function Toolbox.DungeonRaidDirectory.ListAll() end
function Toolbox.DungeonRaidDirectory.GetByJournalInstanceID(journalInstanceID) end
function Toolbox.DungeonRaidDirectory.GetDifficultyRecords(journalInstanceID) end
function Toolbox.DungeonRaidDirectory.GetMountSummary(journalInstanceID) end
function Toolbox.DungeonRaidDirectory.HasAnyMountLoot(journalInstanceID) end
function Toolbox.DungeonRaidDirectory.RefreshLockouts() end
function Toolbox.DungeonRaidDirectory.GetLockoutSummary(journalInstanceID) end
```

Initialize `_cache` from `ToolboxDB.global.dungeonRaidDirectory` and `_runtime` with:

```lua
local runtime = {
  state = "idle",
  currentStage = nil,
  totalUnits = 0,
  completedUnits = 0,
  currentLabel = nil,
  isManualRebuild = false,
  token = 0,
  driverFrame = nil,
  recordOrder = {},
  cursor = {},
  lockoutsByJournalInstanceID = {},
}
```

- [ ] **Step 3: Wire bootstrap initialization before settings build**

In `Toolbox/Core/Bootstrap.lua`, after `Toolbox.DB.Init()` and `Toolbox.Locale_Apply()`, call:

```lua
Toolbox.DungeonRaidDirectory.Initialize()
```

Keep this before `Toolbox.SettingsHost:Build()` so the settings section can read state immediately.

- [ ] **Step 4: Reload and verify the API exists and starts idle**

Run in WoW chat after `/reload`:

```lua
/dump Toolbox.DungeonRaidDirectory.GetBuildState()
/dump Toolbox.DungeonRaidDirectory.GetBuildProgress()
```

Expected:
- state reports `"idle"` or `"building"` depending on whether `Initialize()` already starts the builder
- progress table exists and contains the documented keys

- [ ] **Step 5: Commit the core skeleton**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua Toolbox/Core/Bootstrap.lua
git commit -m "feat: add dungeon raid directory core skeleton"
```

## Chunk 2: Directory Build Engine

### Task 3: Implement EJ State Driver And Skeleton Enumeration

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game `/dump`, `/run`

- [ ] **Step 1: Write the failing verification**

Clear cache via rebuild or manual table reset, then run:

```lua
/run local all = Toolbox.DungeonRaidDirectory.ListAll() print(all and #all or -1)
```

Expected before implementation: `0` or an empty list.

- [ ] **Step 2: Implement the internal `EJStateDriver`**

Add a private helper with:

```lua
local EJStateDriver = {}

function EJStateDriver.Initialize()
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
  end
  if C_EncounterJournal and C_EncounterJournal.OnOpen then
    pcall(C_EncounterJournal.OnOpen)
  end
  if C_EncounterJournal and C_EncounterJournal.InitalizeSelectedTier then
    pcall(C_EncounterJournal.InitalizeSelectedTier)
  end
end

function EJStateDriver.Capture() ... end
function EJStateDriver.Restore(snapshot) ... end
function EJStateDriver.WithSnapshot(workFn) ... end
```

Capture and restore at least: `tierIndex`, `journalInstanceID`, `difficultyID`, `encounterIndex`.

- [ ] **Step 3: Implement skeleton-stage enumeration**

Add `ProcessSkeletonUnit()` and supporting writers that:

```lua
Toolbox.EJ.SelectTier(tierIndex)
local jid, name, isRaid = Toolbox.EJ.GetInstanceByIndexFlat(instanceIndex, raidFlag)
```

Write each record as:

```lua
records[jid] = {
  base = {
    journalInstanceID = jid,
    name = name,
    kind = isRaid and "raid" or "dungeon",
    tierIndex = tierIndex,
    mapID = mapID,
    worldInstanceID = nil,
  },
  difficultyOrder = {},
  difficulties = {},
  summary = {
    hasAnyMountLoot = nil,
    mountDifficultyIDs = {},
  },
}
```

Also build `tierNames[tierIndex]` and `runtime.recordOrder`.

- [ ] **Step 4: Verify that base records are now populated**

Run in WoW chat:

```lua
/run local all = Toolbox.DungeonRaidDirectory.ListAll() print(#all, all[1] and all[1].base and all[1].base.name)
```

Expected: count `> 0` and a non-empty first name.

- [ ] **Step 5: Commit the skeleton stage**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: enumerate adventure guide dungeon and raid skeleton"
```

### Task 4: Implement Supported-Difficulty Probing

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game `/dump`

- [ ] **Step 1: Write the failing verification**

Pick the first record and check whether it has any supported difficulties:

```lua
/run local r = Toolbox.DungeonRaidDirectory.ListAll()[1] print(r and r.base.name or "nil", r and #(r.difficultyOrder or {}) or -1)
```

Expected before implementation: `0`.

- [ ] **Step 2: Add grouped candidate difficulty tables**

Create private tables like:

```lua
local RAID_DIFFICULTY_CANDIDATES = { 14, 15, 16, 17, 33, 151, 7, 9, 3, 4, 5, 6 }
local DUNGEON_DIFFICULTY_CANDIDATES = { 1, 2, 8, 23, 24 }
```

Keep them inside `DungeonRaidDirectory.lua`; do not copy them into modules.

- [ ] **Step 3: Implement `ProcessDifficultyUnit()`**

For each `(journalInstanceID, difficultyID)` pair:

```lua
EJStateDriver.WithSnapshot(function()
  Toolbox.EJ.SelectTier(record.base.tierIndex)
  Toolbox.EJ.SelectInstance(journalInstanceID)
  local ok = Toolbox.EJ.IsValidInstanceDifficulty(difficultyID)
  if ok then
    record.difficulties[difficultyID] = { hasMountLoot = nil }
    record.difficultyOrder[#record.difficultyOrder + 1] = difficultyID
    cache.difficultyMeta[difficultyID] = cache.difficultyMeta[difficultyID] or {
      name = GetDifficultyInfo(difficultyID),
    }
  end
end)
```

Expose `GetDifficultyRecords(journalInstanceID)` to return an ordered list using `difficultyOrder`.

- [ ] **Step 4: Verify supported-difficulty ordering exists**

Run in WoW chat:

```lua
/run local r = Toolbox.DungeonRaidDirectory.ListAll()[1] print(r.base.name, table.concat(r.difficultyOrder, ","))
```

Expected: at least one numeric difficulty ID prints.

- [ ] **Step 5: Commit the difficulty stage**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: probe supported dungeon and raid difficulties"
```

### Task 5: Implement The Async Build Driver And Progress API

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game `/dump`, `/run`

- [ ] **Step 1: Write the failing verification**

Run in WoW chat:

```lua
/dump Toolbox.DungeonRaidDirectory.GetBuildProgress()
```

Expected before implementation: progress never advances beyond a static placeholder.

- [ ] **Step 2: Add the `OnUpdate` driver and token-aware state machine**

Implement:

```lua
local BUILD_BUDGET_MS = 4

local function EnsureDriverFrame()
  ...
  runtime.driverFrame:SetScript("OnUpdate", function()
    local startMs = debugprofilestop()
    while runtime.state == "building" do
      local done, err = AdvanceOneUnit()
      if err then
        FailBuild(err)
        break
      end
      if done then
        FinishBuild()
        break
      end
      if debugprofilestop() - startMs >= BUILD_BUDGET_MS then
        break
      end
    end
  end)
end
```

Use a cursor table instead of a prebuilt queue.

- [ ] **Step 3: Implement cache lifecycle helpers**

Add:

```lua
local function ResetRuntimeForBuild(isManual) ... end
local function LoadCacheFromDb() ... end
local function SaveCacheToDb() ... end
local function IsCacheInvalid() ... end
```

Do not persist `runtime.state` into `ToolboxDB.global.dungeonRaidDirectory`.

- [ ] **Step 4: Verify progress changes over time**

Run in WoW chat after `/reload`:

```lua
/dump Toolbox.DungeonRaidDirectory.GetBuildProgress()
```

Wait a moment and run it again.

Expected: `completedUnits` increases and `state` moves from `"building"` to `"completed"` on a full build.

- [ ] **Step 5: Commit the build driver**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: add async dungeon raid directory build driver"
```

### Task 6: Implement Mount-Summary Scanning

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game `/run`

- [ ] **Step 1: Write the failing verification**

Run in WoW chat after a completed build:

```lua
/run local n=0 for _,r in ipairs(Toolbox.DungeonRaidDirectory.ListAll()) do local v=Toolbox.DungeonRaidDirectory.HasAnyMountLoot(r.base.journalInstanceID) if v then n=n+1 end end print(n)
```

Expected before implementation: `0` or no positive entries.

- [ ] **Step 2: Implement `ProcessMountSummaryUnit()`**

For each supported difficulty:

```lua
EJStateDriver.WithSnapshot(function()
  Toolbox.EJ.SelectTier(record.base.tierIndex)
  Toolbox.EJ.SelectInstance(journalInstanceID)
  Toolbox.EJ.SetDifficulty(difficultyID)
  local hasMount = ScanCurrentSelectionForMount()
  record.difficulties[difficultyID].hasMountLoot = hasMount
  RecomputeMountSummary(record)
end)
```

`ScanCurrentSelectionForMount()` should stop early on the first `itemID` that maps to a mount via `Toolbox.MountJournal.GetMountFromItem(itemID)`.

- [ ] **Step 3: Preserve `nil` while work is incomplete**

Ensure:

```lua
record.summary.hasAnyMountLoot = nil
```

whenever any supported difficulty for that record remains unscanned.

- [ ] **Step 4: Verify positive and unknown semantics**

Run in WoW chat during a rebuild:

```lua
/run local unknown=0 for _,r in ipairs(Toolbox.DungeonRaidDirectory.ListAll()) do local v=Toolbox.DungeonRaidDirectory.HasAnyMountLoot(r.base.journalInstanceID) if v == nil then unknown=unknown+1 end end print("unknown", unknown)
```

Expected: unknown count `> 0` during rebuild and trends toward `0` after completion.

Then rerun:

```lua
/run local positive=0 for _,r in ipairs(Toolbox.DungeonRaidDirectory.ListAll()) do if Toolbox.DungeonRaidDirectory.HasAnyMountLoot(r.base.journalInstanceID) then positive=positive+1 end end print("positive", positive)
```

Expected: positive count `> 0` after completion.

- [ ] **Step 5: Commit mount-summary scanning**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: cache mount summaries for dungeon raid directory"
```

## Chunk 3: Runtime Overlay, UI, Consumer Migration, And Docs

### Task 7: Implement Runtime Lockout Overlay

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game `/run`, `/dump`

- [ ] **Step 1: Write the failing verification**

Run in WoW chat:

```lua
/dump Toolbox.DungeonRaidDirectory.GetLockoutSummary(Toolbox.DungeonRaidDirectory.ListAll()[1].base.journalInstanceID)
```

Expected before implementation: `nil` or a placeholder even after `RequestRaidInfo()`.

- [ ] **Step 2: Implement `RefreshLockouts()` without mutating persisted cache**

Use:

```lua
function Toolbox.DungeonRaidDirectory.RefreshLockouts()
  wipe(runtime.lockoutsByJournalInstanceID)
  for i = 1, Toolbox.Lockouts.GetNumSavedInstances() do
    local name, _, reset, difficultyId, locked, extended, _, _, _, _, numEncounters, encounterProgress, _, instanceId =
      Toolbox.Lockouts.GetSavedInstanceInfo(i)
    ...
  end
end
```

Map `instanceId + difficultyId` back onto `journalInstanceID`, then store the overlay under:

```lua
runtime.lockoutsByJournalInstanceID[journalInstanceID][difficultyId] = { ... }
```

- [ ] **Step 3: Refresh on login and lockout updates**

Register / handle:

```lua
PLAYER_LOGIN
UPDATE_INSTANCE_INFO
```

through the directory core’s event frame, then expose `GetLockoutSummary(journalInstanceID)` as a composed view.

- [ ] **Step 4: Verify lockout refresh behavior**

Run in WoW chat:

```lua
/run RequestRaidInfo() C_Timer.After(1, function() local r=Toolbox.DungeonRaidDirectory.ListAll()[1] DevTools_Dump(Toolbox.DungeonRaidDirectory.GetLockoutSummary(r.base.journalInstanceID)) end)
```

Expected:
- if the character has saved lockouts, at least one record eventually shows lockout data
- if not, the API still returns `nil`/empty without Lua errors

- [ ] **Step 5: Commit the runtime overlay**

Run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: overlay runtime lockouts on dungeon raid directory"
```

### Task 8: Add Settings Progress UI And Rebuild Control

**Files:**
- Modify: `Toolbox/Core/Locales.lua`
- Modify: `Toolbox/UI/SettingsHost.lua`
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: in-game Settings UI

- [ ] **Step 1: Write the failing verification**

Open `/toolbox` and confirm there is no cache-status section, no progress bar, and no rebuild button.

- [ ] **Step 2: Implement a core-owned settings section**

In `Toolbox/UI/SettingsHost.lua`, add a dedicated builder such as:

```lua
function Toolbox.SettingsHost:BuildDungeonRaidDirectorySection(child, startY)
  ...
end
```

Render:
- title
- status text
- current stage label
- current record label
- progress bar
- rebuild button

The rebuild button should call:

```lua
Toolbox.DungeonRaidDirectory.RebuildCache()
```

- [ ] **Step 3: Poll build progress while the settings panel is visible**

Use a lightweight updater on the settings section (not a global busy loop) that periodically refreshes from:

```lua
Toolbox.DungeonRaidDirectory.GetBuildProgress()
```

Refresh roughly every `0.1` seconds while the panel is shown.

- [ ] **Step 4: Verify the settings controls**

Manual in-game verification:
1. Open `/toolbox`
2. Observe status text and progress bar during build
3. Click “重建缓存” / localized equivalent
4. Confirm the bar resets and begins advancing again

Expected: no Lua errors, visible progress updates, rebuild restarts the task.

- [ ] **Step 5: Commit the settings UI**

Run:

```powershell
git add Toolbox/Core/Locales.lua Toolbox/UI/SettingsHost.lua Toolbox/Core/DungeonRaidDirectory.lua
git commit -m "feat: add dungeon raid directory settings progress UI"
```

### Task 9: Migrate `ej_mount_filter` To Consume Directory Summaries

**Files:**
- Modify: `Toolbox/Modules/EJMountFilter.lua`
- Modify: `Toolbox/Core/DB.lua`
- Modify: `Toolbox/Core/Locales.lua`
- Test: in-game Adventure Guide mount filter flow

- [ ] **Step 1: Write the failing verification**

With the current checkbox enabled in the Adventure Guide, observe that the module still owns scan queues / session entries instead of reading the directory cache.

- [ ] **Step 2: Replace private mount-summary ownership with directory lookups**

Update visibility decisions to use:

```lua
local verdict = Toolbox.DungeonRaidDirectory.HasAnyMountLoot(journalInstanceID)
if verdict == false then
  -- hide
elseif verdict == true or verdict == nil then
  -- show
end
```

Preserve `nil => show` semantics while the cache is still building.

- [ ] **Step 3: Remove now-obsolete session cache and enqueue logic**

Delete or collapse:
- `mountFilterSessionEntries`
- build-time silent enqueue machinery
- redundant scan/status chat lines tied to the module-owned scanner

Keep only UI concerns:
- checkbox creation
- row iteration / hiding
- progress-aware visibility

- [ ] **Step 4: Verify the new filter behavior**

Manual in-game verification:
1. Trigger a rebuild in settings
2. Open the Adventure Guide and enable “仅坐骑”
3. During build, confirm unknown rows remain visible
4. After build completes, confirm mount-negative rows hide and mount-positive rows stay visible
5. `/reload` and confirm the module reuses cached results instead of rescanning immediately

- [ ] **Step 5: Commit the filter migration**

Run:

```powershell
git add Toolbox/Modules/EJMountFilter.lua Toolbox/Core/DB.lua Toolbox/Core/Locales.lua
git commit -m "refactor: route adventure guide mount filter through directory cache"
```

### Task 10: Update Long-Lived Docs And Close The Loop

**Files:**
- Modify: `docs/Toolbox-addon-design.md`
- Modify: `docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md`
- Modify: `docs/superpowers/specs/2026-04-03-dungeon-raid-directory-design.md`
- Test: local doc consistency

- [ ] **Step 1: Update the long-lived architecture document**

Add `Toolbox.DungeonRaidDirectory` to the core API map, data model, TOC guidance, and capability mapping in `docs/Toolbox-addon-design.md`.

- [ ] **Step 2: Update the mount-filter spec to name its new data source**

Revise `docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md` so the filter depends on `DungeonRaidDirectory` summaries instead of private session scans.

- [ ] **Step 3: Mark the design spec as implemented where appropriate**

Update `docs/superpowers/specs/2026-04-03-dungeon-raid-directory-design.md` status and any details that changed during implementation.

- [ ] **Step 4: Run local consistency checks**

Run:

```powershell
rg -n "DungeonRaidDirectory" d:\WoWPlugin\Toolbox d:\WoWPlugin\docs
rg -n "mountFilterSessionEntries|enqueueMountScans|runMountScansSync" d:\WoWPlugin\Toolbox\Modules\EJMountFilter.lua
```

Expected:
- first command shows the new architecture and implementation touchpoints
- second command shows old scanner symbols removed or reduced to intentional compatibility shims

- [ ] **Step 5: Commit the documentation updates**

Run:

```powershell
git add docs/Toolbox-addon-design.md docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md docs/superpowers/specs/2026-04-03-dungeon-raid-directory-design.md
git commit -m "docs: document dungeon raid directory architecture"
```

---

Plan complete and saved to `docs/superpowers/plans/2026-04-03-dungeon-raid-directory.md`. Ready to execute?
