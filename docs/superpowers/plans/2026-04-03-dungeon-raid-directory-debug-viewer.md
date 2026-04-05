# DungeonRaidDirectory Debug Viewer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scrollable, read-only debug snapshot viewer to the existing DungeonRaidDirectory settings section so developers can inspect the full cached directory and runtime lockout overlay from `/toolbox`.

**Architecture:** Keep snapshot ownership inside `Toolbox.DungeonRaidDirectory`: the core layer should expose a structured debug snapshot plus a formatted multi-line text version. `Toolbox.SettingsHost` should only host the UI container, refresh button, and low-frequency auto-refresh behavior. Use a scroll frame with a text child instead of a forest of per-record widgets to keep the implementation simple, stable, and debugging-oriented.

**Tech Stack:** WoW Retail Lua addon, `Settings` API, `ScrollFrame`, multiline text display via `FontString`/scroll child, `SavedVariables`, `Toolbox.Chat`, `luaparser` for local syntax verification, in-game `/toolbox` verification

---

## Execution Notes

- Execute in the **current workspace**. The user explicitly rejected worktree usage.
- The workspace already contains unrelated pending changes. If creating checkpoint commits while executing, **stage only the files listed in each task**.
- There is no automated in-repo Lua test harness today. Use:
  - `luaparser` syntax verification for changed Lua files
  - targeted in-game `/dump` and `/toolbox` checks for behavior

## File Map

- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
  Responsibility: expose debug snapshot data, format multi-line debug text, keep formatting rules close to the directory model.
- Modify: `Toolbox/UI/SettingsHost.lua`
  Responsibility: add the snapshot viewer UI, refresh button, low-frequency auto-refresh, and scroll behavior.
- Modify: `Toolbox/Core/Locales.lua`
  Responsibility: add viewer title/button/empty-state strings in `enUS` / `zhCN`.
- Modify: `docs/superpowers/specs/2026-04-03-dungeon-raid-directory-debug-viewer-design.md`
  Responsibility: mark implementation status and note any small execution-time adjustments.
- Optional Modify: `docs/Toolbox-addon-design.md`
  Responsibility: mention that the directory settings section now includes a read-only debug snapshot viewer if the implementation meaningfully changes the long-lived settings description.

---

## Chunk 1: Core Debug Snapshot API

### Task 1: Add Viewer Locale Keys

**Files:**
- Modify: `Toolbox/Core/Locales.lua`
- Test: local syntax parse + in-game `/reload`

- [ ] **Step 1: Write the failing verification**

Run in WoW chat after `/reload`:

```lua
/run print(Toolbox.L and Toolbox.L.DRD_SNAPSHOT_TITLE, Toolbox.L and Toolbox.L.DRD_SNAPSHOT_REFRESH)
```

Expected before implementation: `nil	nil`.

- [ ] **Step 2: Add locale keys for the snapshot viewer**

Add keys in both `enUS` and `zhCN` bundles:

```lua
DRD_SNAPSHOT_TITLE
DRD_SNAPSHOT_REFRESH
DRD_SNAPSHOT_HINT
DRD_SNAPSHOT_EMPTY
DRD_SNAPSHOT_LOADING
```

Suggested semantics:
- title for the viewer area
- refresh button text
- short hint above or below the viewer
- placeholder when no text is available
- placeholder while the directory is still building

- [ ] **Step 3: Run syntax verification**

Run:

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\Core\Locales.lua', 'r', encoding='utf-8').read())
print('OK Locales.lua')
'@ | python -
```

Expected: `OK Locales.lua`

- [ ] **Step 4: Reload and verify the locale keys now exist**

Run in WoW chat after `/reload`:

```lua
/run print(Toolbox.L.DRD_SNAPSHOT_TITLE, Toolbox.L.DRD_SNAPSHOT_REFRESH)
```

Expected: localized non-empty strings.

- [ ] **Step 5: Optional checkpoint commit**

If creating a checkpoint, run:

```powershell
git add Toolbox/Core/Locales.lua
git commit -m "feat: add dungeon raid directory snapshot viewer locale keys"
```

### Task 2: Expose Structured Debug Snapshot And Formatted Text

**Files:**
- Modify: `Toolbox/Core/DungeonRaidDirectory.lua`
- Test: local syntax parse + in-game `/dump` and `/run`

- [ ] **Step 1: Write the failing verification**

Run in WoW chat after `/reload`:

```lua
/run print(type(Toolbox.DungeonRaidDirectory.GetDebugSnapshot), type(Toolbox.DungeonRaidDirectory.FormatDebugSnapshot))
```

Expected before implementation: both `nil`.

- [ ] **Step 2: Add counting helpers for snapshot summaries**

Inside `DungeonRaidDirectory.lua`, add focused local helpers for:

```lua
local function countRecordTotal() ... end
local function countSupportedDifficultyTotal() ... end
local function countMountPositiveRecordTotal() ... end
local function countMappedLockoutTotal() ... end
```

Use the current cache/runtime state rather than introducing duplicate persisted fields.

- [ ] **Step 3: Add `GetDebugSnapshot()`**

Expose:

```lua
function Directory.GetDebugSnapshot()
  return {
    progress = Directory.GetBuildProgress(),
    recordCount = ...,
    supportedDifficultyCount = ...,
    mountPositiveRecordCount = ...,
    lockoutMappedCount = ...,
    records = {
      {
        base = { ... },
        summary = { ... },
        difficulties = {
          {
            difficultyID = 15,
            name = "Heroic",
            hasMountLoot = true,
            lockout = { ... } or nil,
          },
        },
      },
    },
  }
end
```

Requirements:
- preserve `nil` semantics for unknown mount summary values
- keep records ordered by `runtime.recordOrder`
- keep difficulties ordered by `difficultyOrder`
- include runtime lockout overlay data in the snapshot output

- [ ] **Step 4: Add `FormatDebugSnapshot()`**

Expose:

```lua
function Directory.FormatDebugSnapshot()
  local snapshot = Directory.GetDebugSnapshot()
  ...
  return text
end
```

Formatting requirements:
- top summary block first
- then one section per record
- explicit `nil`, `[]`, or `none` style text for missing/empty values
- stable, plain-text output suitable for a single scrollable text viewer

Recommended record shape:

```text
[1190] Nerub-ar Palace
  kind=raid tierIndex=10 mapID=2215 worldInstanceID=2648
  summary.hasAnyMountLoot=true mountDifficultyIDs=[15,16]
  difficulties:
    14 Normal hasMountLoot=false lockout=nil
    15 Heroic hasMountLoot=true lockout={ reset=123456 progress=6/8 extended=false }
```

- [ ] **Step 5: Verify the new API shape**

Run in WoW chat:

```lua
/dump Toolbox.DungeonRaidDirectory.GetDebugSnapshot()
/run local text=Toolbox.DungeonRaidDirectory.FormatDebugSnapshot() print(type(text), text and string.len(text) or -1)
```

Expected:
- first command shows a table
- second command prints `string` and a positive length

- [ ] **Step 6: Run local syntax verification**

Run:

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\Core\DungeonRaidDirectory.lua', 'r', encoding='utf-8').read())
print('OK DungeonRaidDirectory.lua')
'@ | python -
```

Expected: `OK DungeonRaidDirectory.lua`

- [ ] **Step 7: Optional checkpoint commit**

If creating a checkpoint, run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua Toolbox/Core/Locales.lua
git commit -m "feat: add dungeon raid directory debug snapshot api"
```

## Chunk 2: Settings Viewer UI

### Task 3: Add Scrollable Snapshot Viewer To Settings

**Files:**
- Modify: `Toolbox/UI/SettingsHost.lua`
- Modify: `Toolbox/Core/Locales.lua`
- Test: local syntax parse + in-game `/toolbox`

- [ ] **Step 1: Write the failing verification**

Open `/toolbox` and inspect the “地下城 / 团队副本目录缓存” section.

Expected before implementation:
- there is no dedicated “目录快照” / snapshot area
- there is no refresh button for the snapshot
- there is no internal scrollable text viewer for the directory data

- [ ] **Step 2: Add a snapshot sub-section inside `BuildDungeonRaidDirectorySection()`**

Below the existing:
- status text
- stage text
- current label
- progress bar
- rebuild button
- debug chat toggle

add:
- snapshot title
- refresh button
- fixed-height scroll container
- multiline read-only text display child

Recommended implementation:
- keep the existing outer box, but increase its height
- use a nested `ScrollFrame` plus a single text child (`FontString` on a scroll child frame)
- set a fixed viewer height around `220-320` pixels for first pass

- [ ] **Step 3: Add refresh logic with change detection**

Inside `BuildDungeonRaidDirectorySection()`:

```lua
local lastSnapshotText = nil

local function refreshSnapshot(force)
  local text = Toolbox.DungeonRaidDirectory.FormatDebugSnapshot()
  if not force and text == lastSnapshotText then
    return
  end
  lastSnapshotText = text
  snapshotText:SetText(text ~= "" and text or (L.DRD_SNAPSHOT_EMPTY or ""))
  snapshotChild:SetHeight(math.max(minHeight, snapshotText:GetStringHeight() + padding))
end
```

Requirements:
- manual refresh button should call `refreshSnapshot(true)`
- while panel is visible, auto-refresh every `0.2` to `0.5` seconds
- skip unnecessary `SetText` when nothing changed

- [ ] **Step 4: Ensure the content scrolls correctly**

After setting text:
- update child height from rendered string height
- reset or preserve scroll position intentionally
- avoid letting the viewer stretch the whole settings page instead of scrolling internally

- [ ] **Step 5: Run local syntax verification**

Run:

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\UI\SettingsHost.lua', 'r', encoding='utf-8').read())
print('OK SettingsHost.lua')
'@ | python -
```

Expected: `OK SettingsHost.lua`

- [ ] **Step 6: Verify the settings UI in game**

Manual in-game verification:

1. `/toolbox`
2. Confirm the snapshot viewer appears under the directory cache section
3. Confirm the viewer has an internal scrollbar / scroll behavior
4. Click the refresh button and confirm the text updates
5. Trigger a rebuild and confirm the snapshot text changes while the build progresses

Expected:
- the viewer stays within its own fixed-height area
- long text is scrollable
- current cache/build data is visible as plain text

- [ ] **Step 7: Optional checkpoint commit**

If creating a checkpoint, run:

```powershell
git add Toolbox/UI/SettingsHost.lua Toolbox/Core/Locales.lua
git commit -m "feat: add dungeon raid directory debug snapshot viewer"
```

## Chunk 3: Docs And Final Verification

### Task 4: Sync Design Docs And Re-Verify

**Files:**
- Modify: `docs/superpowers/specs/2026-04-03-dungeon-raid-directory-debug-viewer-design.md`
- Optional Modify: `docs/Toolbox-addon-design.md`
- Test: local syntax parse + targeted repo grep

- [ ] **Step 1: Update the debug-viewer spec status**

In `docs/superpowers/specs/2026-04-03-dungeon-raid-directory-debug-viewer-design.md`, update the status from “设计稿” to an implementation-aware status after the code lands.

- [ ] **Step 2: Update long-lived design docs if the settings surface changed meaningfully**

If needed, mention in `docs/Toolbox-addon-design.md` that the directory settings section now includes:
- build status/progress
- debug chat toggle
- read-only snapshot viewer

- [ ] **Step 3: Run targeted verification commands**

Run:

```powershell
@'
from luaparser import ast
for path in [
    r'd:\WoWPlugin\Toolbox\Core\DungeonRaidDirectory.lua',
    r'd:\WoWPlugin\Toolbox\Core\Locales.lua',
    r'd:\WoWPlugin\Toolbox\UI\SettingsHost.lua',
]:
    ast.parse(open(path, 'r', encoding='utf-8').read())
    print(f'OK {path}')
'@ | python -
```

Then run:

```powershell
rg -n "GetDebugSnapshot|FormatDebugSnapshot|DRD_SNAPSHOT_" d:\WoWPlugin\Toolbox d:\WoWPlugin\docs
```

Expected:
- syntax check reports all `OK`
- grep shows the core API, settings UI, locales, and spec/doc touchpoints

- [ ] **Step 4: Final in-game verification checklist**

Verify in game:

1. `/toolbox` opens
2. directory cache section still shows progress and rebuild button
3. debug snapshot viewer renders text immediately
4. the viewer scrolls independently from the page
5. rebuild + refresh update the snapshot text
6. unknown mount summaries remain visible as explicit `nil`/unknown text in the viewer

- [ ] **Step 5: Optional final checkpoint commit**

If creating a checkpoint, run:

```powershell
git add Toolbox/Core/DungeonRaidDirectory.lua Toolbox/Core/Locales.lua Toolbox/UI/SettingsHost.lua docs/superpowers/specs/2026-04-03-dungeon-raid-directory-debug-viewer-design.md docs/Toolbox-addon-design.md
git commit -m "feat: add dungeon raid directory debug snapshot viewer"
```

---

Plan complete and saved to `docs/superpowers/plans/2026-04-03-dungeon-raid-directory-debug-viewer.md`. Ready to execute?
