--[[
  模块 ej_mount_filter：冒险指南「仅坐骑」副本列表筛选。
  数据：ToolboxDB.modules.ej_mount_filter（enabled、debug）；副本掉落结论统一读取 `Toolbox.DungeonRaidDirectory`。
  UI：资料片下拉左侧「仅坐骑」复选框与标签。
  挂接：Blizzard_EncounterJournal 的 ADDON_LOADED；instanceSelect OnShow；EncounterJournal_ListInstances post-hook；
  Mainline 列表为 WowScrollBox：筛选开启后改为用覆盖列表接管显示，不再直接隐藏原生池化行。
  目录构建由 `Toolbox.DungeonRaidDirectory` 异步完成；本模块仅负责 UI 与覆盖列表显示。
  页签判定：Mainline 以 `EJ_ContentTab_Select` → `EncounterJournal.selectedTab` 与团本/地下城按钮 `GetID()` 为准；
  **`EncounterJournal_SetTab` 是副本详情内子页签**（首领/战利品等），不得用于本模块。
  `instanceSelect` 在 Loot/Journeys 等页仍会 Show，需结合 `Toolbox.EJ.IsRaidOrDungeonInstanceListTab` 与 `ScrollBox` 可见性。
]]

local MODULE_ID = "ej_mount_filter"

-- 已挂接 OnShow 的面板（避免重复 HookScript）
local showHooked = {}

local listInstancesHooked = false

-- 前向声明：页签切换钩子会刷新复选框显隐
local updateMountFilterChromeVisibility

-- 前向声明：ScrollBox 滚动回调会再次应用列表筛选
local applyMountFilterVisibility

-- 前向声明：刷新当前列表可用态，以及同步目录层暂停状态
local RefreshMountFilterAvailability
local syncEncounterJournalPauseState
local showMountFilterTooltip
local buildDirectoryRecordMap
local ensureDirectoryBuildForCurrentList

-- `EJ_ContentTab_Select` post-hook（仅刷新显隐，不写错误层级的「页签缓存」）
local contentTabSelectHooked = false

-- 主框架 OnShow（首帧 selectedTab 与布局就绪后再判一次）
local ejMainOnShowHooked = false
local ejMainOnHideHooked = false

-- 难度枚举（与暴雪一致，非拍脑袋列表）：
-- - `API_EJ_SetDifficulty`（Wowpedia）写明参数为 `GetDifficultyInfo` 所用的标准 `DifficultyID`。
-- - `DifficultyID`（Wowpedia 零售表）中团本相关示例：7 旧版 LFR、9 40 人、14–16 普通/英雄/史诗、17 LFR、33 时光团本、151 时光 LFR；以及 3/4/5/6 旧 10/25 与对应英雄、等。
-- 扫描时对候选 ID 做并集尝试；旧资料片列表若仅用 14–17 可能读不到战利品，故保留 3–9。勿仅用 `EJ_IsValidInstanceDifficulty` 排除 ID：Wiki 上该 API 的示例表未列全历史团本难度（见 `Toolbox.EJ.IsValidInstanceDifficulty` 注释）。
-- 难度从高到低尝试（先史诗/神话再普通与 LFR），命中坐骑即返回，减少无效读表
local RAID_DIFFICULTIES = { 16, 15, 14, 17, 33, 151, 7, 9, 3, 4, 5, 6 }
local DUNGEON_DIFFICULTIES = { 23, 8, 24, 2, 1 }

local ejHostFrame
local ejInstanceListScrollBoxRef = nil
local mountFilterOverlay = nil
local dbgApplyThrottle = 0

-- 当前仅对两个已知异常副本做定向追踪，避免聊天框被泛化日志淹没。
local TARGET_DEBUG_INSTANCE_NAMES = {
  "风行者之塔",
  "斯坦索姆 - 仆从入口",
}

local targetDebugInstanceNameSet

local mountFilterAvailability = {
  total = 0,
  readyCount = 0,
  pendingCount = 0,
  hasMountCount = 0,
  noMountCount = 0,
  buildState = "idle",
  failureMessage = nil,
  isPausedForEncounterJournal = false,
  isCurrentListReady = false,
}

local uiRefreshElapsed = 0
local lastUiRefreshSignature = ""
local lastDirectoryBuildRequestAt = 0

-- 仅提示一次如何开启调试（避免重复 /reload 刷屏）
local ejMountFilterDebugNoteLogged = false

--- 一次性迁移：旧版曾把 entries/scanLogicVersion 写入 SavedVariables，现改为仅内存会话表，去掉持久化键。
local mountFilterLegacyDbCleaned = false

---@return table
local function getModuleDb()
  Toolbox.DB.Init()
  local m = Toolbox.DB.GetModule(MODULE_ID)
  if not mountFilterLegacyDbCleaned then
    mountFilterLegacyDbCleaned = true
    if m.entries ~= nil then
      m.entries = nil
    end
    if m.scanLogicVersion ~= nil then
      m.scanLogicVersion = nil
    end
    if m.interfaceBuild ~= nil then
      m.interfaceBuild = nil
    end
  end
  return m
end

local function isDirectoryFeatureEnabled()
  local db = Toolbox.DB.GetModule("dungeon_raid_directory")
  return db.enabled ~= false
end

local function syncCheckboxFromDb()
  local cb = _G.ToolboxEJMountFilterCheck
  if cb then
    cb:SetChecked(getModuleDb().enabled == true)
  end
end

--- 是否在聊天输出调试行（`ToolboxDB.modules.ej_mount_filter.debug`）。
---@return boolean
local function isDebugChat()
  local m = getModuleDb()
  return m.debug == true
end

---@param name string|nil
---@return string|nil
local function normalizeDebugInstanceName(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local value = string.lower(name)
  value = value:gsub("[%s%p]", "")
  if value == "" then
    return nil
  end
  return value
end

---@return table<string, boolean>
local function getTargetDebugInstanceNameSet()
  if targetDebugInstanceNameSet then
    return targetDebugInstanceNameSet
  end

  targetDebugInstanceNameSet = {}
  for _, name in ipairs(TARGET_DEBUG_INSTANCE_NAMES) do
    local normalized = normalizeDebugInstanceName(name)
    if normalized then
      targetDebugInstanceNameSet[normalized] = true
    end
  end
  return targetDebugInstanceNameSet
end

---@param name string|nil
---@return boolean
local function isTargetDebugInstanceName(name)
  local normalized = normalizeDebugInstanceName(name)
  return normalized ~= nil and getTargetDebugInstanceNameSet()[normalized] == true
end

---@param journalInstanceID number|nil
---@param fallbackName string|number|nil
---@return string
local function formatJournalInstanceNameForDebug(journalInstanceID, fallbackName)
  if type(fallbackName) == "string" and fallbackName ~= "" then
    return fallbackName
  end

  if type(journalInstanceID) == "number" then
    local record = Toolbox.DungeonRaidDirectory.GetByJournalInstanceID(journalInstanceID)
    local name = record and record.base and record.base.name
    if type(name) == "string" and name ~= "" then
      return name
    end
    return string.format("jid=%s", tostring(journalInstanceID))
  end

  if fallbackName ~= nil then
    return tostring(fallbackName)
  end
  return "?"
end

---@param journalInstanceID number|nil
---@param fallbackName string|number|nil
---@return string|nil
local function getTargetDebugInstanceName(journalInstanceID, fallbackName)
  if type(journalInstanceID) == "number" then
    local record = Toolbox.DungeonRaidDirectory.GetByJournalInstanceID(journalInstanceID)
    local name = record and record.base and record.base.name
    if isTargetDebugInstanceName(name) then
      return tostring(name)
    end
  end

  if type(fallbackName) == "string" and isTargetDebugInstanceName(fallbackName) then
    return fallbackName
  end

  return nil
end

---@param difficultyID number|nil
---@return string
local function formatDifficultyNameForDebug(difficultyID)
  if type(difficultyID) ~= "number" then
    return "?"
  end
  local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID) or nil
  if type(name) == "string" and name ~= "" then
    return string.format("%s(%s)", name, tostring(difficultyID))
  end
  return tostring(difficultyID)
end

--- 当前手册选中的 Journal 实例 ID（仅 `GetInstanceInfo` 为 table 时可得；多返回值形态无此项，见 `Toolbox.EJ.GetInstanceInfoFlat`）。
---@return number|nil
local function getSelectedJournalInstanceID()
  local _, jid = Toolbox.EJ.GetInstanceInfoFlat()
  return jid
end

--- 恢复选中实例与难度（扫描间插入，避免长时间停留在错误实例）。
---@param savedJid number|nil
---@param savedDiff number|nil
local function restoreEJSelection(savedJid, savedDiff)
  if savedJid and type(savedJid) == "number" then
    Toolbox.EJ.SelectInstance(savedJid)
  end
  if savedDiff and type(savedDiff) == "number" and savedDiff > 0 then
    Toolbox.EJ.SetDifficulty(savedDiff)
  end
end

--- 战利品行是否含坐骑物品（经 C_MountJournal）。
---@param info EncounterJournalItemInfo|nil
---@return boolean
local function lootInfoIsMount(info)
  if type(info) ~= "table" then
    return false
  end
  local itemID = info.itemID or info.id
  if type(itemID) ~= "number" then
    return false
  end
  local mid = Toolbox.MountJournal.GetMountFromItem(itemID)
  return type(mid) == "number" and mid > 0
end

--- 战利品 table 摘要（debug，避免整表刷屏）。
---@param info table|nil
---@return string
local function summarizeLootInfoForDebug(info)
  if type(info) ~= "table" then
    return tostring(info)
  end
  local parts = {}
  for _, k in ipairs({
    "itemID",
    "id",
    "name",
    "link",
    "itemLink",
    "icon",
    "slot",
    "texture",
    "slotType",
    "quality",
    "displayAsLink",
  }) do
    local v = info[k]
    if v ~= nil then
      local s = tostring(v)
      if #s > 48 then
        s = string.sub(s, 1, 48) .. "…"
      end
      table.insert(parts, k .. "=" .. s)
    end
  end
  if #parts == 0 then
    return "(table no known keys)"
  end
  return table.concat(parts, " ")
end

---@param itemID number|nil
---@return string
local function getItemNameForDebug(itemID)
  if type(itemID) ~= "number" then
    return ""
  end
  local ok, name = pcall(function()
    if C_Item and C_Item.GetItemNameByID then
      return C_Item.GetItemNameByID(itemID)
    end
    if GetItemInfo then
      return (GetItemInfo(itemID))
    end
    return nil
  end)
  if ok and type(name) == "string" and name ~= "" then
    return name
  end
  return ""
end

--- 在 SelectInstance(journalInstanceID) 之后解析是否为团本（用于选难度列表）。
---@return boolean|nil
local function getInstanceRaidFlagFromInfo()
  local _, _, isRaid = Toolbox.EJ.GetInstanceInfoFlat()
  return isRaid
end

--- 当前手册实例显示名（需已 `SelectInstance`）。
---@return string
local function getJournalInstanceDisplayName()
  local name = select(1, Toolbox.EJ.GetInstanceInfoFlat())
  if type(name) == "string" and name ~= "" then
    return name
  end
  return "?"
end

--- 当 `GetNumEncounters()` 为 0 时：不虚构首领总数，仅作有限探测（列表级 loot 与少量 encounter 索引）。
--- 说明：未展开手册详情或客户端未填充首领数时，多返回值仍可能返回 0；与副本「设计上有无首领」无关。
---@return boolean
local function scanLootWhenEncounterCountZero()
  for l = 1, 50 do
    local info = Toolbox.EJ.GetLootInfoByIndex(l)
    if info == nil then
      break
    end
    if lootInfoIsMount(info) then
      return true
    end
  end
  for e = 1, 16 do
    Toolbox.EJ.SelectEncounter(e)
    local nLoot = Toolbox.EJ.GetNumLoot()
    if type(nLoot) ~= "number" or nLoot < 1 then
      -- 继续尝试下一 encounter 索引
    else
      for l = 1, math.min(nLoot, 40) do
        local info = Toolbox.EJ.GetLootInfoByIndex(l)
        local infoE = Toolbox.EJ.GetLootInfoByIndex(l, e)
        if lootInfoIsMount(info) or lootInfoIsMount(infoE) then
          return true
        end
      end
    end
  end
  return false
end

--- 在已 SelectInstance + SetDifficulty 下扫描当前实例战利品。
--- 逻辑：`GetNumEncounters()` 为有效正数则遍历 1..n；每首领先 `SelectEncounter`，再按 `GetNumLoot()` 行数读 `GetLootInfoByIndex`（单参/双参均试）。
--- 若 `GetNumEncounters() < 1` 则走 `scanLootWhenEncounterCountZero`（仅有限探测，不虚构首领总数）。
---@param debugJid number|nil `debug` 时打印明细
---@param difficultyID number|nil 当前 SetDifficulty 的难度 ID
---@return boolean 是否发现坐骑物品
local function scanCurrentInstanceLootForMount(debugJid, difficultyID)
  local instName = getJournalInstanceDisplayName()
  local diffName = formatDifficultyNameForDebug(difficultyID)
  local nEnc = Toolbox.EJ.GetNumEncounters()
  if type(nEnc) ~= "number" or nEnc < 1 then
    return scanLootWhenEncounterCountZero()
  end
  if nEnc > 40 then
    nEnc = 40
  end

  for e = 1, nEnc do
    Toolbox.EJ.SelectEncounter(e)
    local encName = Toolbox.EJ.GetEncounterName(e)
    if type(encName) ~= "string" or encName == "" then
      encName = "?"
    end
    local nLoot = Toolbox.EJ.GetNumLoot()
    if isDebugChat() and debugJid and difficultyID then
      local L = Toolbox.L or {}
      Toolbox.Chat.PrintAddonMessage(
        string.format(
          L.EJ_MOUNT_FILTER_DEBUG_SCAN_ENC or "",
          tostring(instName),
          tostring(diffName),
          tostring(e),
          tostring(encName),
          tostring(type(nLoot) == "number" and nLoot or -1)
        )
      )
    end
    if type(nLoot) == "number" and nLoot >= 1 then
      for l = 1, nLoot do
        local info = Toolbox.EJ.GetLootInfoByIndex(l)
        local infoE = Toolbox.EJ.GetLootInfoByIndex(l, e)
        if isDebugChat() and debugJid and difficultyID then
          local function logOneRow(variant, row)
            local L = Toolbox.L or {}
            if type(row) ~= "table" then
              Toolbox.Chat.PrintAddonMessage(
                string.format(
                  L.EJ_MOUNT_FILTER_DEBUG_SCAN_LOOT or "",
                  tostring(instName),
                  tostring(diffName),
                  tostring(e),
                  tostring(l),
                  "0",
                  "",
                  "",
                  tostring(variant),
                  "non-table=" .. tostring(row)
                )
              )
              return
            end
            local itemID = row.itemID or row.id
            local iid = type(itemID) == "number" and itemID or 0
            local mid = iid > 0 and Toolbox.MountJournal.GetMountFromItem(iid) or nil
            local iname = row.name or (iid > 0 and getItemNameForDebug(iid) or "")
            Toolbox.Chat.PrintAddonMessage(
              string.format(
                L.EJ_MOUNT_FILTER_DEBUG_SCAN_LOOT or "",
                tostring(instName),
                tostring(diffName),
                tostring(e),
                tostring(l),
                tostring(iid),
                tostring(iname),
                tostring(mid or ""),
                tostring(variant),
                summarizeLootInfoForDebug(row)
              )
            )
          end
          logOneRow("GetLootInfoByIndex(l)", info)
          logOneRow("GetLootInfoByIndex(l,e)", infoE)
        end
        if lootInfoIsMount(info) then
          return true
        end
        if lootInfoIsMount(infoE) then
          return true
        end
      end
    end
  end
  return false
end

--- 扫描单个手册实例是否含坐骑掉落（多难度并集）。
--- 每个难度下重新 `SelectInstance` 再 `SetDifficulty`，避免仅改难度时实例上下文未与当前 jid 对齐。
---@param journalInstanceID number
---@return boolean
local function scanJournalInstanceForMount(journalInstanceID)
  Toolbox.EJ.SelectInstance(journalInstanceID)
  local isRaid = getInstanceRaidFlagFromInfo()
  if isDebugChat() then
    local iname = formatJournalInstanceNameForDebug(journalInstanceID, select(1, Toolbox.EJ.GetInstanceInfoFlat()))
    local L = Toolbox.L or {}
    Toolbox.Chat.PrintAddonMessage(
      string.format(
        L.EJ_MOUNT_FILTER_DEBUG_SCAN_BEGIN or "",
        tostring(iname),
        tostring(isRaid)
      )
    )
  end
  local diffs
  if isRaid == true then
    diffs = RAID_DIFFICULTIES
  elseif isRaid == false then
    diffs = DUNGEON_DIFFICULTIES
  else
    -- isRaid 未知：团本难度（高→低）再接地下城难度（高→低），去重由下方 seen 处理
    diffs = { 16, 15, 14, 17, 33, 151, 7, 9, 3, 4, 5, 6, 23, 8, 24, 2, 1 }
  end

  local seen = {}
  for _, d in ipairs(diffs) do
    if type(d) == "number" and not seen[d] then
      seen[d] = true
      Toolbox.EJ.SelectInstance(journalInstanceID)
      local okDiff = Toolbox.EJ.SetDifficulty(d)
      if isDebugChat() then
        local curDiff = Toolbox.EJ.GetDifficulty()
        local nEncRaw = Toolbox.EJ.GetNumEncounters()
        local instNameDiff = formatJournalInstanceNameForDebug(journalInstanceID, getJournalInstanceDisplayName())
        local L = Toolbox.L or {}
        Toolbox.Chat.PrintAddonMessage(
          string.format(
            L.EJ_MOUNT_FILTER_DEBUG_SCAN_DIFF or "",
            tostring(instNameDiff),
            formatDifficultyNameForDebug(d),
            formatDifficultyNameForDebug(curDiff),
            tostring(nEncRaw),
            tostring(okDiff)
          )
        )
      end
      if okDiff and scanCurrentInstanceLootForMount(journalInstanceID, d) then
        return true
      end
    end
  end
  return false
end

--- 与 `EncounterJournal_ListInstances` 一致：当前为团本列表还是地下城列表（`EJ_GetInstanceByIndex` 第二参）。
--- Mainline：`selectedTab` 与 `dungeonsTab`/`raidsTab`:GetID() 对齐，**4=地下城、5=副本**（团队副本列表；以实机 GetID 为准）。
---@return boolean|nil true=团本 false=地下城 nil=无法判断
local function getEncounterJournalInstanceListIsRaid()
  local ej = _G.EncounterJournal
  if not ej or not ej.raidsTab or not ej.dungeonsTab then
    return nil
  end
  local sid = ej.selectedTab
  if type(sid) ~= "number" then
    return nil
  end
  local okR, rid = pcall(function()
    return ej.raidsTab:GetID()
  end)
  local okD, did = pcall(function()
    return ej.dungeonsTab:GetID()
  end)
  if okR and type(rid) == "number" and sid == rid then
    return true
  end
  if okD and type(did) == "number" and sid == did then
    return false
  end
  return nil
end

--- `EJ_GetInstanceByIndex` 第二参取值集合：仅**当前**团本/地下城页签下的**一份**列表（与 `EncounterJournal_ListInstances` 数据源一致）。
--- 无法判断当前是团本还是地下城列表时返回空表，**不**再合并双列表扫描。
---@return boolean[]
local function getCurrentTierInstanceListModes()
  local raidFlag = getEncounterJournalInstanceListIsRaid()
  if raidFlag == true then
    return { true }
  end
  if raidFlag == false then
    return { false }
  end
  return {}
end

--- 当前资料片 + **当前页签**下 journalInstanceID（团本或地下城二选一，与可见列表一致）。
---@return number[]
local function collectAllJournalInstanceIDsInTier()
  local out = {}
  local seen = {}
  for _, isRaid in ipairs(getCurrentTierInstanceListModes()) do
    local idx = 1
    while true do
      local jid = select(1, Toolbox.EJ.GetInstanceByIndexFlat(idx, isRaid))
      if not jid then
        break
      end
      if not seen[jid] then
        seen[jid] = true
        table.insert(out, jid)
      end
      idx = idx + 1
    end
  end
  return out
end

--- 取含 `ExpansionDropdown` 的 instanceSelect（主栏或 Landing 内嵌），用于遍历当前可见列表行。
---@return Frame|nil
local function resolveEJInstanceSelect()
  local ej = _G.EncounterJournal
  if not ej then
    return nil
  end
  local function hasExpansionPanel(panel)
    return panel and panel.ExpansionDropdown
  end
  if hasExpansionPanel(ej.instanceSelect) then
    return ej.instanceSelect
  end
  local lp = ej.LandingPage or ej.landingPage
  if lp then
    local nested = lp.instanceSelect or lp.InstanceSelect
    if hasExpansionPanel(nested) then
      return nested
    end
  end
  return nil
end

--- 仅主栏 `EncounterJournal.instanceSelect`（复选框只挂在此处，不挂 Landing 内嵌面板）。
---@return Frame|nil
local function resolveEJMainInstanceSelectForCheckbox()
  local ej = _G.EncounterJournal
  if not ej or not ej.instanceSelect or not ej.instanceSelect.ExpansionDropdown then
    return nil
  end
  return ej.instanceSelect
end

--- 是否显示「仅坐骑」复选框与标签：团本/地下城 **内容页** 且列表区（ScrollBox） intended 可见。
---@return boolean
local function shouldShowMountFilterChrome()
  local is = resolveEJMainInstanceSelectForCheckbox()
  if not is or not is:IsVisible() then
    return false
  end
  local ej = _G.EncounterJournal
  if ej and is == ej.instanceSelect then
    local sb = is.ScrollBox or is.scrollBox
    if sb and sb.IsShown then
      local okSb, sbShown = pcall(function()
        return sb:IsShown()
      end)
      if okSb and sbShown == false then
        return false
      end
    end
  end
  local verdict = Toolbox.EJ.IsRaidOrDungeonInstanceListTab()
  return verdict == true
end

--- 当前是否处于需要为玩家浏览让路的 EJ 列表语境。
---@return boolean
local function shouldRunMountScansForCurrentUi()
  local ok, v = pcall(shouldShowMountFilterChrome)
  return ok and v == true
end

--- 统计当前页签 + 当前资料片下列表项的目录摘要就绪情况。
--- 约定：只有当前列表中的每个 journalInstanceID 都已得到 true/false 结论，复选框才可真正启用。
---@return table
local function GetCurrentListReadiness()
  local progress = Toolbox.DungeonRaidDirectory.GetBuildProgress()
  local readiness = {
    total = 0,
    readyCount = 0,
    pendingCount = 0,
    hasMountCount = 0,
    noMountCount = 0,
    buildState = progress.state or "idle",
    failureMessage = progress.failureMessage,
    isPausedForEncounterJournal = Toolbox.DungeonRaidDirectory.IsPausedForEncounterJournal(),
    isCurrentListReady = false,
  }

  if not isDirectoryFeatureEnabled() then
    return readiness
  end

  if not shouldShowMountFilterChrome() then
    return readiness
  end

  local recordMap = buildDirectoryRecordMap()
  for _, jid in ipairs(collectAllJournalInstanceIDsInTier()) do
    readiness.total = readiness.total + 1
    local record = recordMap[jid]
    local summary = record and record.summary or nil
    local hasMountLoot = summary and summary.hasAnyMountLoot or nil
    if hasMountLoot == nil then
      readiness.pendingCount = readiness.pendingCount + 1
    else
      readiness.readyCount = readiness.readyCount + 1
      if hasMountLoot == true then
        readiness.hasMountCount = readiness.hasMountCount + 1
      else
        readiness.noMountCount = readiness.noMountCount + 1
      end
    end
  end

  readiness.isCurrentListReady = readiness.total > 0 and readiness.pendingCount == 0
  return readiness
end

--- 当前复选框是否允许真正驱动列表筛选。
---@return boolean
local function isMountFilterReadyForUse()
  return isDirectoryFeatureEnabled()
    and mountFilterAvailability.isCurrentListReady == true
    and shouldShowMountFilterChrome()
end

---@return table<number, table>
buildDirectoryRecordMap = function()
  local out = {}
  for _, record in ipairs(Toolbox.DungeonRaidDirectory.ListAll()) do
    local base = record and record.base
    local jid = base and base.journalInstanceID
    if type(jid) == "number" then
      out[jid] = record
    end
  end
  return out
end

--- 按当前可用态更新复选框与标签的视觉状态；保留勾选偏好，但未就绪时不允许真正切换。
--- 注意：SetAlpha/SetTextColor 会触发 WoW 重新评估鼠标命中状态，导致 OnLeave/OnEnter 循环触发使 tooltip 闪烁。
--- 因此只在值真正变化时才调用，避免 OnUpdate 每帧无意义重复调用。
---@param readiness table|nil
local function applyMountFilterAvailabilityVisual(readiness)
  local cb = _G.ToolboxEJMountFilterCheck
  local lab = _G.ToolboxEJMountFilterLabel
  if not cb or not lab then
    return
  end

  local show = shouldShowMountFilterChrome()
  local enabled = show and readiness and readiness.isCurrentListReady == true
  local alpha = show and (enabled and 1 or 0.45) or 1
  cb._ToolboxMountFilterReady = enabled == true

  -- 仅在 alpha 变化时调用 SetAlpha，避免无意义重复调用触发 WoW 鼠标状态重评估导致 tooltip 闪烁
  if cb._ToolboxLastAlpha ~= alpha then
    cb._ToolboxLastAlpha = alpha
    cb:SetAlpha(alpha)
    lab:SetAlpha(alpha)
  end

  if lab.SetTextColor then
    local tr, tg, tb = enabled and 1 or 0.6, enabled and 0.82 or 0.6, enabled and 0 or 0.6
    if cb._ToolboxLastColorR ~= tr or cb._ToolboxLastColorG ~= tg or cb._ToolboxLastColorB ~= tb then
      cb._ToolboxLastColorR, cb._ToolboxLastColorG, cb._ToolboxLastColorB = tr, tg, tb
      lab:SetTextColor(tr, tg, tb)
    end
  end
end

--- 当当前列表存在未决摘要且目录未在构建时，主动拉起构建或重建，避免长期停留在“刷新中”。
---@param readiness table|nil
ensureDirectoryBuildForCurrentList = function(readiness)
  if not isDirectoryFeatureEnabled() or not shouldShowMountFilterChrome() then
    return
  end
  if type(readiness) ~= "table" then
    return
  end
  if (tonumber(readiness.total) or 0) <= 0 or (tonumber(readiness.pendingCount) or 0) <= 0 then
    return
  end

  local state = tostring(readiness.buildState or "idle")
  if state == "building" then
    return
  end

  local now = GetTime and GetTime() or 0
  if (now - (lastDirectoryBuildRequestAt or 0)) < 1.5 then
    return
  end
  lastDirectoryBuildRequestAt = now

  Toolbox.DungeonRaidDirectory.PrioritizeCurrentEncounterJournalTier()
  if state == "completed" or state == "failed" or state == "cancelled" then
    Toolbox.DungeonRaidDirectory.RebuildCache()
  else
    Toolbox.DungeonRaidDirectory.StartBuild(false)
  end
end

--- 刷新当前列表是否已可用于筛选的状态。
---@return table
RefreshMountFilterAvailability = function()
  mountFilterAvailability = GetCurrentListReadiness()
  ensureDirectoryBuildForCurrentList(mountFilterAvailability)
  applyMountFilterAvailabilityVisual(mountFilterAvailability)
  return mountFilterAvailability
end

--- 根据当前目录层状态构建复选框 Tooltip。
--- 缓存上次内容签名：内容未变时跳过 ClearLines + 重填，避免 tooltip 尺寸抖动触发 SetDefaultAnchor hook 导致闪烁变宽。
---@param owner Frame
local function showMountFilterTooltipForState(owner)
  local L = Toolbox.L or {}
  -- 标记此 tooltip 不受 tooltip_anchor 模块接管，避免 cursor 模式下 ClearAllPoints 导致闪烁变宽
  GameTooltip._ToolboxSkipAnchorOverride = true

  -- 直接读缓存，避免在 tooltip 显示期间调用 RefreshMountFilterAvailability()
  -- 后者会修改 checkbox alpha/颜色，可能触发 WoW 重新评估鼠标状态，导致 OnLeave/OnEnter 循环闪烁
  local readiness = mountFilterAvailability

  -- 构建内容签名：内容未变则跳过重填，避免 ClearLines 触发尺寸变化 → SetDefaultAnchor hook → tooltip 闪烁变宽
  local contentSig
  if not isDirectoryFeatureEnabled() then
    contentSig = "disabled"
  elseif readiness.isCurrentListReady then
    contentSig = "ready"
  elseif readiness.buildState == "failed" then
    contentSig = "failed"
  elseif readiness.isPausedForEncounterJournal then
    contentSig = "paused"
  else
    contentSig = string.format("refreshing:%d/%d", tonumber(readiness.readyCount) or 0, tonumber(readiness.total) or 0)
  end

  local ownerChanged = GameTooltip:GetOwner() ~= owner
  if ownerChanged then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  end

  -- owner 未变且内容签名相同：tooltip 已正确显示，无需重填
  if not ownerChanged and GameTooltip:IsShown() and GameTooltip._ToolboxMountFilterSig == contentSig then
    if isDebugChat() then
      Toolbox.Chat.PrintAddonMessage(string.format("[tooltip] skip sig=%s", contentSig))
    end
    return
  end
  if isDebugChat() then
    Toolbox.Chat.PrintAddonMessage(
      string.format("[tooltip] fill sig=%s ownerChanged=%s", contentSig, tostring(ownerChanged)))
  end
  GameTooltip._ToolboxMountFilterSig = contentSig

  GameTooltip:ClearLines()

  if not isDirectoryFeatureEnabled() then
    GameTooltip:SetText(L.EJ_MOUNT_FILTER_LABEL or "")
    GameTooltip:AddLine(L.EJ_MOUNT_FILTER_SETTINGS_DEPENDENCY_DISABLED or "", 1, 0.2, 0.2, true)
    GameTooltip:Show()
    return
  end

  if readiness.isCurrentListReady then
    GameTooltip:SetText(L.EJ_MOUNT_FILTER_HINT or "")
    GameTooltip:Show()
    return
  end

  GameTooltip:SetText(L.EJ_MOUNT_FILTER_LABEL or "")

  if readiness.buildState == "failed" then
    GameTooltip:AddLine(L.EJ_MOUNT_FILTER_FAILED_HINT or "", 1, 0.2, 0.2, true)
  elseif readiness.isPausedForEncounterJournal then
    GameTooltip:AddLine(L.EJ_MOUNT_FILTER_PAUSED_HINT or "", 1, 0.82, 0, true)
  else
    GameTooltip:AddLine(
      string.format(
        L.EJ_MOUNT_FILTER_REFRESHING_HINT_FMT or "%d/%d",
        tonumber(readiness.readyCount) or 0,
        tonumber(readiness.total) or 0
      ),
      1,
      0.82,
      0,
      true
    )
  end

  GameTooltip:Show()
end

showMountFilterTooltip = function(owner)
  showMountFilterTooltipForState(owner)
end

--- 根据当前 EJ 浏览语境，决定是否暂停目录层后台构建。
local function syncEncounterJournalPauseStateInternal()
  if not isDirectoryFeatureEnabled() then
    Toolbox.DungeonRaidDirectory.ResumeForEncounterJournal()
    return
  end
  local isCurrentUi = shouldRunMountScansForCurrentUi()
  if isCurrentUi then
    Toolbox.DungeonRaidDirectory.PrioritizeCurrentEncounterJournalTier()
  end
  local shouldPause = Toolbox.DungeonRaidDirectory.GetBuildState() == "building" and isCurrentUi
  if shouldPause then
    Toolbox.DungeonRaidDirectory.PauseForEncounterJournal()
  else
    Toolbox.DungeonRaidDirectory.ResumeForEncounterJournal()
  end
end

syncEncounterJournalPauseState = function()
  syncEncounterJournalPauseStateInternal()
end

--- 刷新复选框与标签的显示状态（不销毁控件）。
updateMountFilterChromeVisibility = function()
  local cb = _G.ToolboxEJMountFilterCheck
  local lab = _G.ToolboxEJMountFilterLabel
  if not cb or not lab then
    return
  end
  local ok, show = pcall(shouldShowMountFilterChrome)
  if not ok then
    show = false
  end
  cb:SetShown(show == true)
  lab:SetShown(show == true)
end

--- 名称 -> journalInstanceID，用于行控件未暴露 instanceID 时回退匹配（与当前列表团本/地下城一致）。
---@return table<string, number>
local function buildJournalNameToIdMap()
  local m = {}
  for _, isRaid in ipairs(getCurrentTierInstanceListModes()) do
    local idx = 1
    while true do
      local jid, name = Toolbox.EJ.GetInstanceByIndexFlat(idx, isRaid)
      if not jid then
        break
      end
      if type(name) == "string" and name ~= "" then
        m[name] = jid
      end
      idx = idx + 1
    end
  end
  return m
end

--- 从实例列表行读取显示名（常见子区域名）。
---@param row Frame
---@return string|nil
local function getInstanceRowText(row)
  if not row then
    return nil
  end
  local candidates = { row.Name, row.name, row.Text, row.text, row.Title, row.Label }
  for _, fs in ipairs(candidates) do
    if fs and fs.GetText then
      local ok, t = pcall(function()
        return fs:GetText()
      end)
      if ok and type(t) == "string" and t ~= "" then
        return t
      end
    end
  end
  return nil
end

--- 从列表行解析 journalInstanceID。
---@param row Frame
---@param nameMap table<string, number>|nil
---@return number|nil
local function getJournalInstanceIdFromRow(row, nameMap)
  if not row then
    return nil
  end
  local jid = row.instanceID or row.journalInstanceID or row.journalInstanceId
  if type(jid) == "number" then
    return jid
  end
  if row.GetElementData then
    local ok, data = pcall(function()
      return row:GetElementData()
    end)
    if ok and type(data) == "table" then
      -- Mainline `EncounterJournal_ListInstances` 插入字段名为 `instanceID`（即 journal 实例 ID）
      local id = data.instanceID or data.journalInstanceID or data.id
      if type(id) == "number" then
        return id
      end
    end
  end
  if nameMap then
    local txt = getInstanceRowText(row)
    if txt then
      local mid = nameMap[txt]
      if type(mid) == "number" then
        return mid
      end
    end
  end
  return nil
end

--- 从 DataProvider 元素表解析 journalInstanceID（与行上 `GetElementData` 字段一致）。
---@param elementData table|nil
---@param nameMap table<string, number>|nil
---@return number|nil
local function getJournalInstanceIdFromElementData(elementData, nameMap)
  if type(elementData) ~= "table" then
    return nil
  end
  local id = elementData.instanceID or elementData.journalInstanceID or elementData.journalInstanceId or elementData.id
  if type(id) == "number" then
    return id
  end
  local nested = elementData.data or elementData.elementData or elementData.entryData or elementData.node
  if type(nested) == "table" and nested ~= elementData then
    local nestedId = getJournalInstanceIdFromElementData(nested, nameMap)
    if type(nestedId) == "number" then
      return nestedId
    end
  end
  if nameMap then
    for _, textValue in ipairs({
      elementData.name,
      elementData.instanceName,
      elementData.title,
      elementData.text,
      elementData.label,
    }) do
      if type(textValue) == "string" and textValue ~= "" then
        local mappedId = nameMap[textValue]
        if type(mappedId) == "number" then
          return mappedId
        end
      end
    end
  end
  return nil
end

--- 取当前 EJ 实例列表使用的 ScrollBox。
---@return Frame|nil
local function getCurrentInstanceListScrollBox()
  local is = resolveEJInstanceSelect()
  local box = (is and (is.ScrollBox or is.scrollBox or is.instanceScroll or is.InstanceScrollBox or is.InstanceScroll)) or nil
  if box then
    return box
  end
  return ejInstanceListScrollBoxRef
end

--- 取当前 EJ 实例列表的 DataProvider。
---@return table|nil
local function getCurrentInstanceListDataProvider()
  local box = getCurrentInstanceListScrollBox()
  if not box or type(box.GetDataProvider) ~= "function" then
    return nil
  end
  local okDp, dp = pcall(function()
    return box:GetDataProvider()
  end)
  if okDp and type(dp) == "table" and type(dp.ForEach) == "function" then
    return dp
  end
  return nil
end

---@param jid number|nil
---@param fallback string|number|nil
---@return string
local function formatPreviewTokenWithMountState(jid, fallback)
  local base = formatJournalInstanceNameForDebug(jid, fallback)
  local L = Toolbox.L or {}
  if type(jid) ~= "number" then
    return base .. ":" .. tostring(L.EJ_MOUNT_FILTER_DEBUG_STATE_UNKNOWN or "未知")
  end
  local hasMountLoot = Toolbox.DungeonRaidDirectory.HasAnyMountLoot(jid)
  if hasMountLoot == true then
    return base .. ":" .. tostring(L.EJ_MOUNT_FILTER_DEBUG_STATE_HAS or "有")
  end
  if hasMountLoot == false then
    return base .. ":" .. tostring(L.EJ_MOUNT_FILTER_DEBUG_STATE_NONE or "无")
  end
  return base .. ":" .. tostring(L.EJ_MOUNT_FILTER_DEBUG_STATE_PENDING or "待")
end

---@param rows string[]|nil
---@return string
local function formatTargetDebugRowList(rows)
  if type(rows) ~= "table" or #rows == 0 then
    return ""
  end
  return table.concat(rows, "，")
end

--- 记录当前主栏列表区引用，供覆盖列表锚点与回退判断使用。
local function refreshEJInstanceListScrollViewCache()
  local ej = _G.EncounterJournal
  if not ej or not ej.instanceSelect then
    ejInstanceListScrollBoxRef = nil
    return
  end
  ejInstanceListScrollBoxRef = ej.instanceSelect.ScrollBox or ej.instanceSelect.scrollBox
end

--- 枚举当前资料片 + 当前页签的整份副本列表（不受原生分页限制）。
---@return table[]
local function collectCurrentTierInstanceEntries()
  local out = {}
  local seen = {}
  local recordMap = buildDirectoryRecordMap()
  for _, isRaid in ipairs(getCurrentTierInstanceListModes()) do
    local index = 1
    while true do
      local jid, name = Toolbox.EJ.GetInstanceByIndexFlat(index, isRaid)
      if not jid then
        break
      end
      if not seen[jid] then
        seen[jid] = true
        local record = recordMap[jid]
        local summary = record and record.summary or nil
        out[#out + 1] = {
          journalInstanceID = jid,
          name = (type(name) == "string" and name ~= "" and name)
            or (record and record.base and record.base.name)
            or tostring(jid),
          hasMountLoot = summary and summary.hasAnyMountLoot or nil,
        }
      end
      index = index + 1
    end
  end
  return out
end

---@param entries table[]|nil
---@return string signature
---@return string preview
---@return string sourcePath
---@return string targetPreview
---@return number rowCount
local function buildCurrentVisibleInstanceListSignature(entries)
  if not shouldShowMountFilterChrome() then
    return "", "(hidden)", "hidden", "", 0
  end

  entries = type(entries) == "table" and entries or collectCurrentTierInstanceEntries()
  local parts = {}
  local previewParts = {}
  local targetPreviewParts = {}
  local targetSeen = {}

  for index, entry in ipairs(entries) do
    parts[#parts + 1] = tostring(entry.journalInstanceID or entry.name or index)
    if #previewParts < 6 then
      previewParts[#previewParts + 1] = formatPreviewTokenWithMountState(entry.journalInstanceID, entry.name or index)
    end
    local targetName = getTargetDebugInstanceName(entry.journalInstanceID, entry.name)
    if targetName and not targetSeen[targetName] then
      targetSeen[targetName] = true
      targetPreviewParts[#targetPreviewParts + 1] = formatPreviewTokenWithMountState(entry.journalInstanceID, targetName)
    end
  end

  return
    string.format("%d:%s", #entries, table.concat(parts, "|")),
    string.format("rows=%d first=%s", #entries, table.concat(previewParts, ",")),
    "TierAPI",
    table.concat(targetPreviewParts, "，"),
    #entries
end

---@param overlay Frame
---@param box Frame
local function anchorMountFilterOverlay(overlay, box)
  overlay:ClearAllPoints()
  overlay:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  overlay:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  if box.GetFrameStrata and overlay.SetFrameStrata then
    overlay:SetFrameStrata(box:GetFrameStrata())
  end
  if box.GetFrameLevel and overlay.SetFrameLevel then
    overlay:SetFrameLevel(box:GetFrameLevel() + 15)
  end
end

---@param overlay Frame
---@return number
local function getMountFilterOverlayContentWidth(overlay)
  local width = (overlay and overlay.GetWidth and overlay:GetWidth()) or 0
  return math.max(width - 24, 120)
end

---@param overlay Frame
---@param index number
---@return Button
local function ensureMountFilterOverlayRow(overlay, index)
  overlay.rows = overlay.rows or {}
  if overlay.rows[index] then
    return overlay.rows[index]
  end

  local row = CreateFrame("Button", nil, overlay.scrollChild)
  row:SetHeight(22)

  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(1, 0.82, 0, 0.10)
  row.selected:Hide()

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.06)
  row:SetHighlightTexture(highlight)

  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)

  row:SetScript("OnClick", function(self)
    if type(self.journalInstanceID) == "number" then
      Toolbox.EJ.SelectInstance(self.journalInstanceID)
    end
  end)

  overlay.rows[index] = row
  return row
end

---@return Frame|nil
local function ensureMountFilterOverlay()
  local parent = resolveEJMainInstanceSelectForCheckbox()
  local box = getCurrentInstanceListScrollBox()
  if not parent or not box then
    return nil
  end

  if not mountFilterOverlay then
    mountFilterOverlay = CreateFrame("Frame", "ToolboxEJMountFilterOverlay", parent)
    mountFilterOverlay:Hide()

    mountFilterOverlay.bg = mountFilterOverlay:CreateTexture(nil, "BACKGROUND")
    mountFilterOverlay.bg:SetAllPoints()
    mountFilterOverlay.bg:SetColorTexture(0.03, 0.03, 0.03, 0.18)

    mountFilterOverlay.scrollFrame = CreateFrame("ScrollFrame", "ToolboxEJMountFilterOverlayScrollFrame", mountFilterOverlay, "UIPanelScrollFrameTemplate")
    mountFilterOverlay.scrollFrame:SetPoint("TOPLEFT", mountFilterOverlay, "TOPLEFT", 0, 0)
    mountFilterOverlay.scrollFrame:SetPoint("BOTTOMRIGHT", mountFilterOverlay, "BOTTOMRIGHT", 0, 0)

    mountFilterOverlay.scrollChild = CreateFrame("Frame", nil, mountFilterOverlay.scrollFrame)
    mountFilterOverlay.scrollChild:SetSize(1, 1)
    mountFilterOverlay.scrollFrame:SetScrollChild(mountFilterOverlay.scrollChild)

    mountFilterOverlay.emptyText = mountFilterOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mountFilterOverlay.emptyText:SetPoint("TOPLEFT", mountFilterOverlay, "TOPLEFT", 12, -12)
    mountFilterOverlay.emptyText:SetPoint("BOTTOMRIGHT", mountFilterOverlay, "BOTTOMRIGHT", -12, 12)
    mountFilterOverlay.emptyText:SetJustifyH("CENTER")
    mountFilterOverlay.emptyText:SetJustifyV("MIDDLE")

    mountFilterOverlay.rows = {}
    mountFilterOverlay:SetClipsChildren(true)
    mountFilterOverlay:EnableMouse(true)
    mountFilterOverlay:EnableMouseWheel(true)
    mountFilterOverlay:SetScript("OnMouseWheel", function(self, delta)
      local scrollFrame = self.scrollFrame
      if not scrollFrame or not scrollFrame.GetVerticalScroll or not scrollFrame.SetVerticalScroll then
        return
      end
      local current = scrollFrame:GetVerticalScroll() or 0
      local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
      local nextValue = current - (delta * 36)
      if nextValue < 0 then
        nextValue = 0
      elseif nextValue > range then
        nextValue = range
      end
      scrollFrame:SetVerticalScroll(nextValue)
    end)
  end

  anchorMountFilterOverlay(mountFilterOverlay, box)
  return mountFilterOverlay
end

---@param suppressed boolean
local function setNativeInstanceListSuppressed(suppressed)
  local box = getCurrentInstanceListScrollBox()
  local targets = {}
  if box then
    targets[#targets + 1] = box
    if box.ScrollBar then
      targets[#targets + 1] = box.ScrollBar
    elseif box.scrollBar then
      targets[#targets + 1] = box.scrollBar
    end
  end

  for _, target in ipairs(targets) do
    if target.SetAlpha then
      pcall(function()
        target:SetAlpha(suppressed and 0 or 1)
      end)
    end
    if target.EnableMouse then
      pcall(function()
        target:EnableMouse(not suppressed)
      end)
    end
    if target.EnableMouseWheel then
      pcall(function()
        target:EnableMouseWheel(not suppressed)
      end)
    end
  end
end

local function hideMountFilterOverlay()
  setNativeInstanceListSuppressed(false)
  if mountFilterOverlay then
    mountFilterOverlay:Hide()
  end
end

---@param overlay Frame
---@param entries table[]
---@return number shownCount
local function renderMountFilterOverlay(overlay, entries)
  local filtered = {}
  for _, entry in ipairs(entries or {}) do
    if entry.hasMountLoot == true then
      filtered[#filtered + 1] = entry
    end
  end

  local layoutParts = {}
  for _, entry in ipairs(filtered) do
    layoutParts[#layoutParts + 1] = tostring(entry.journalInstanceID)
  end
  local layoutSignature = table.concat(layoutParts, "|")
  if overlay._lastEntrySignature ~= layoutSignature and overlay.scrollFrame and overlay.scrollFrame.SetVerticalScroll then
    overlay.scrollFrame:SetVerticalScroll(0)
  end
  overlay._lastEntrySignature = layoutSignature

  local L = Toolbox.L or {}
  local rowHeight = 22
  local rowGap = 2
  local topPadding = 4
  local bottomPadding = 4
  local contentWidth = getMountFilterOverlayContentWidth(overlay)
  local selectedJid = getSelectedJournalInstanceID()

  overlay.emptyText:SetText(L.EJ_MOUNT_FILTER_EMPTY or "")
  overlay.emptyText:SetShown(#filtered == 0)
  overlay.scrollFrame:SetShown(#filtered > 0)

  local prevRow = nil
  for index, entry in ipairs(filtered) do
    local row = ensureMountFilterOverlayRow(overlay, index)
    row:ClearAllPoints()
    row:SetPoint("LEFT", overlay.scrollChild, "LEFT", 4, 0)
    row:SetPoint("RIGHT", overlay.scrollChild, "RIGHT", -4, 0)
    if prevRow then
      row:SetPoint("TOP", prevRow, "BOTTOM", 0, -rowGap)
    else
      row:SetPoint("TOP", overlay.scrollChild, "TOP", 0, -topPadding)
    end
    row:SetHeight(rowHeight)
    row:SetShown(true)
    row.journalInstanceID = entry.journalInstanceID
    row.text:SetText(tostring(entry.name or entry.journalInstanceID or "?"))

    local isSelected = type(selectedJid) == "number" and entry.journalInstanceID == selectedJid
    row.selected:SetShown(isSelected)
    if row.text.SetTextColor then
      if isSelected then
        row.text:SetTextColor(1, 0.82, 0)
      else
        row.text:SetTextColor(0.95, 0.95, 0.95)
      end
    end
    prevRow = row
  end

  for index = #filtered + 1, #(overlay.rows or {}) do
    local row = overlay.rows[index]
    if row then
      row:Hide()
      row.journalInstanceID = nil
    end
  end

  local totalHeight = topPadding + bottomPadding
  if #filtered > 0 then
    totalHeight = totalHeight + (#filtered * rowHeight) + ((#filtered - 1) * rowGap)
  end
  overlay.scrollChild:SetSize(contentWidth, math.max(totalHeight, (overlay:GetHeight() or 1)))
  return #filtered
end

---@return boolean
local function isMountFilterOverlayActive()
  local cb = _G.ToolboxEJMountFilterCheck
  return cb ~= nil
    and cb:GetChecked() == true
    and shouldShowMountFilterChrome()
    and isMountFilterReadyForUse()
end

--- 根据缓存、勾选状态与当前列表就绪度更新覆盖列表显示。
applyMountFilterVisibility = function()
  local cb = _G.ToolboxEJMountFilterCheck
  if not cb then
    hideMountFilterOverlay()
    return
  end

  RefreshMountFilterAvailability()
  if not isMountFilterOverlayActive() then
    hideMountFilterOverlay()
    return
  end

  local overlay = ensureMountFilterOverlay()
  if not overlay then
    hideMountFilterOverlay()
    return
  end

  local entries = collectCurrentTierInstanceEntries()
  local shownCount = renderMountFilterOverlay(overlay, entries)
  overlay:Show()
  setNativeInstanceListSuppressed(true)

  if isDebugChat() then
    local targetRows = {}
    for _, entry in ipairs(entries) do
      local targetName = getTargetDebugInstanceName(entry.journalInstanceID, entry.name)
      if targetName then
        local state = entry.hasMountLoot == true and "有" or (entry.hasMountLoot == false and "无" or "待")
        local visibility = entry.hasMountLoot == true and "显示" or "隐藏"
        targetRows[#targetRows + 1] = string.format("%s=%s/%s", tostring(targetName), state, visibility)
      end
    end
    if #targetRows > 0 then
      local now = GetTime()
      if now - dbgApplyThrottle >= 0.55 then
        dbgApplyThrottle = now
        local L = Toolbox.L or {}
        Toolbox.Chat.PrintAddonMessage(
          string.format(
            L.EJ_MOUNT_FILTER_DEBUG_TARGET_APPLY or "",
            string.format("OverlayList rows=%s shown=%s", tostring(#entries), tostring(shownCount)),
            formatTargetDebugRowList(targetRows)
          )
        )
      end
    end
  end
end

--- 创建勾选与标签（仅成功一次；依赖主栏 `ExpansionDropdown` 已存在）。
local function tryCreateMountFilterCheck()
  if _G.ToolboxEJMountFilterCheck then
    updateMountFilterChromeVisibility()
    return
  end
  local is = resolveEJMainInstanceSelectForCheckbox()
  if not is or not is.ExpansionDropdown then
    return
  end
  local m = getModuleDb()
  local lcb = CreateFrame("CheckButton", "ToolboxEJMountFilterCheck", is, "UICheckButtonTemplate")
  lcb:SetSize(22, 22)
  lcb:SetChecked(m.enabled == true)
  lcb:SetScript("OnClick", function(self)
    local L = Toolbox.L or {}
    local readiness = RefreshMountFilterAvailability()
    if readiness.isCurrentListReady ~= true then
      self:SetChecked(m.enabled == true)
      return
    end
    m.enabled = self:GetChecked() and true or false
    if self:GetChecked() then
      Toolbox.Chat.PrintAddonMessage(L.EJ_MOUNT_FILTER_NOTIFY_ON or "")
    else
      Toolbox.Chat.PrintAddonMessage(L.EJ_MOUNT_FILTER_NOTIFY_OFF or "")
    end
    applyMountFilterVisibility()
  end)
  lcb:SetScript("OnEnter", function(self)
    if isDebugChat() then
      Toolbox.Chat.PrintAddonMessage(string.format("[OnEnter] owner=%s shown=%s sig=%s",
        tostring(GameTooltip:GetOwner() == self),
        tostring(GameTooltip:IsShown()),
        tostring(GameTooltip._ToolboxMountFilterSig)))
    end
    showMountFilterTooltip(self)
  end)
  lcb:SetScript("OnLeave", function()
    if isDebugChat() then
      Toolbox.Chat.PrintAddonMessage("[OnLeave] hiding tooltip")
    end
    GameTooltip._ToolboxMountFilterSig = nil
    GameTooltip._ToolboxSkipAnchorOverride = nil
    GameTooltip:Hide()
  end)
  local okAnchor = pcall(function()
    lcb:SetPoint("RIGHT", is.ExpansionDropdown, "LEFT", -8, 0)
  end)
  if not okAnchor then
    lcb:Hide()
    return
  end
  local llab = is:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  llab:SetJustifyH("RIGHT")
  llab:SetText((Toolbox.L and Toolbox.L.EJ_MOUNT_FILTER_LABEL) or "")
  pcall(function()
    llab:SetPoint("RIGHT", lcb, "LEFT", -4, 0)
  end)
  _G.ToolboxEJMountFilterLabel = llab

  updateMountFilterChromeVisibility()
  RefreshMountFilterAvailability()
end

--- 在某一 instanceSelect 面板上挂接一次 OnShow。
---@param panel Frame|nil
local function hookInstanceSelectOnShowOnce(panel)
  if not panel or not panel.HookScript or showHooked[panel] then
    return
  end
  showHooked[panel] = true
  panel:HookScript("OnShow", function()
    refreshEJInstanceListScrollViewCache()
    syncEncounterJournalPauseState()
    tryCreateMountFilterCheck()
    RefreshMountFilterAvailability()
    applyMountFilterVisibility()
    updateMountFilterChromeVisibility()
  end)
end

--- 挂接主栏 `instanceSelect` 的 OnShow（不挂 Landing 内嵌，避免非团本/地下城页出现挂件）。
local function attachEncounterJournalUiHooks()
  local ej = _G.EncounterJournal
  if not ej then
    return
  end
  hookInstanceSelectOnShowOnce(ej.instanceSelect)
  if ej.instanceSelect and ej.instanceSelect.IsVisible and ej.instanceSelect:IsVisible() then
    tryCreateMountFilterCheck()
  end
end

--- `Blizzard_EncounterJournal` 已加载后：挂 `ListInstances`、内容页 `EJ_ContentTab_Select`、手册 OnShow。
local function initEncounterJournalHooks()
  -- 内容页切换：`EncounterJournal.selectedTab` 由该函数写入（见 Blizzard Mainline 源码）。
  if hooksecurefunc and not contentTabSelectHooked and type(_G.EJ_ContentTab_Select) == "function" then
    local ok = pcall(function()
      hooksecurefunc("EJ_ContentTab_Select", function()
        C_Timer.After(0, function()
          refreshEJInstanceListScrollViewCache()
          syncEncounterJournalPauseState()
          RefreshMountFilterAvailability()
          applyMountFilterVisibility()
          updateMountFilterChromeVisibility()
        end)
      end)
    end)
    if ok then
      contentTabSelectHooked = true
    end
  end
  local ej = _G.EncounterJournal
  if ej and ej.HookScript and not ejMainOnShowHooked then
    ejMainOnShowHooked = true
    ej:HookScript("OnShow", function()
      C_Timer.After(0, function()
        refreshEJInstanceListScrollViewCache()
        syncEncounterJournalPauseState()
        tryCreateMountFilterCheck()
        RefreshMountFilterAvailability()
        applyMountFilterVisibility()
        updateMountFilterChromeVisibility()
      end)
    end)
  end
  if ej and ej.HookScript and not ejMainOnHideHooked then
    ejMainOnHideHooked = true
    ej:HookScript("OnHide", function()
      syncEncounterJournalPauseState()
      RefreshMountFilterAvailability()
      applyMountFilterVisibility()
    end)
  end
  if isDebugChat() and not ejMountFilterDebugNoteLogged then
    ejMountFilterDebugNoteLogged = true
    local L = Toolbox.L or {}
    Toolbox.Chat.PrintAddonMessage(L.EJ_MOUNT_FILTER_DEBUG_NOTE or "")
  end
  if hooksecurefunc and not listInstancesHooked then
    local ok = pcall(function()
      hooksecurefunc("EncounterJournal_ListInstances", function()
        refreshEJInstanceListScrollViewCache()
        attachEncounterJournalUiHooks()
        syncEncounterJournalPauseState()
        tryCreateMountFilterCheck()
        RefreshMountFilterAvailability()
        applyMountFilterVisibility()
        updateMountFilterChromeVisibility()
      end)
    end)
    if ok then
      listInstancesHooked = true
    end
  end
  attachEncounterJournalUiHooks()
  tryCreateMountFilterCheck()
  syncEncounterJournalPauseState()
  RefreshMountFilterAvailability()
  applyMountFilterVisibility()
  updateMountFilterChromeVisibility()
end

--- 注册：在手册插件 `ADDON_LOADED` 或已加载时初始化挂接（明确时机，无固定秒级延迟）。
local function registerEncounterJournalIntegration()
  if ejHostFrame then
    return
  end
  ejHostFrame = CreateFrame("Frame", "ToolboxEJMountFilterHost")
  ejHostFrame:RegisterEvent("ADDON_LOADED")
  ejHostFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then
      -- 一次性触发器：手册插件加载后自行注销，避免持续监听所有 ADDON_LOADED
      self:UnregisterEvent("ADDON_LOADED")
      initEncounterJournalHooks()
    end
  end)
  ejHostFrame:SetScript("OnUpdate", function(_, elapsed)
    uiRefreshElapsed = uiRefreshElapsed + (elapsed or 0)
    if uiRefreshElapsed < 0.25 then
      return
    end
    uiRefreshElapsed = 0

    if Toolbox.DungeonRaidDirectory.ConsumeEncounterJournalReadyNotice() then
      local L = Toolbox.L or {}
      Toolbox.Chat.PrintAddonMessage(L.EJ_MOUNT_FILTER_READY or "")
    end

    syncEncounterJournalPauseState()
    local readiness = RefreshMountFilterAvailability()

    local visibleSignature, _, visibleSourcePath, targetPreview, visibleRows = buildCurrentVisibleInstanceListSignature()
    local cb = _G.ToolboxEJMountFilterCheck
    local signature = table.concat({
      tostring(shouldShowMountFilterChrome()),
      tostring(cb and cb:GetChecked() or false),
      tostring(readiness.isCurrentListReady),
      tostring(readiness.pendingCount),
      tostring(readiness.total),
      tostring(readiness.buildState),
      tostring(readiness.isPausedForEncounterJournal),
      visibleSignature,
      tostring(getSelectedJournalInstanceID() or ""),
    }, "|")

    if signature ~= lastUiRefreshSignature then
      if isDebugChat() and targetPreview ~= "" then
        local L = Toolbox.L or {}
        Toolbox.Chat.PrintAddonMessage(string.format(
          L.EJ_MOUNT_FILTER_DEBUG_TARGET_PAGE or "",
          tostring(visibleSourcePath or ""),
          tostring(visibleRows or 0),
          tostring(targetPreview or "")
        ))
      end
      lastUiRefreshSignature = signature
      updateMountFilterChromeVisibility()
      applyMountFilterVisibility()
    end
  end)
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    initEncounterJournalHooks()
  end
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_EJ_MOUNT_FILTER",
  settingsIntroKey = "MODULE_EJ_MOUNT_FILTER_INTRO",
  settingsOrder = 60,
  OnModuleLoad = function()
    registerEncounterJournalIntegration()
  end,
  OnModuleEnable = function()
    syncCheckboxFromDb()
    RefreshMountFilterAvailability()
    applyMountFilterVisibility()
  end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_EJ_MOUNT_FILTER or MODULE_ID))
    -- ejHostFrame OnUpdate 随模块开关启停，避免禁用后仍每帧轮询
    if ejHostFrame then
      if enabled then
        ejHostFrame:Show()
      else
        ejHostFrame:Hide()
      end
    end
    syncCheckboxFromDb()
    RefreshMountFilterAvailability()
    applyMountFilterVisibility()
  end,
  OnDebugSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_EJ_MOUNT_FILTER or MODULE_ID))
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.DB.ResetModule(MODULE_ID)
    ejMountFilterDebugNoteLogged = false
    lastUiRefreshSignature = ""
    syncCheckboxFromDb()
    RefreshMountFilterAvailability()
    applyMountFilterVisibility()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {}
    local y = 0

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.EJ_MOUNT_FILTER_SETTINGS_HINT or "")
    y = y - 40

    local status = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    status:SetWidth(580)
    status:SetJustifyH("LEFT")

    if not isDirectoryFeatureEnabled() then
      status:SetText(L.EJ_MOUNT_FILTER_SETTINGS_DEPENDENCY_DISABLED or "")
    else
      local readiness = RefreshMountFilterAvailability()
      if readiness.isCurrentListReady then
        status:SetText(L.EJ_MOUNT_FILTER_HINT or "")
      else
        status:SetText(L.EJ_MOUNT_FILTER_SETTINGS_DEPENDENCY_BUILDING or "")
      end
    end
    y = y - 40

    box.realHeight = math.abs(y) + 8
  end,
})
