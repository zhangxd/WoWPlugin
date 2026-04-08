--[[
  冒险指南增强模块（encounter_journal）。
  功能：
    1. 「仅坐骑」复选框筛选：post-hook EncounterJournal_ListInstances，从 DataProvider 移除不含坐骑的条目。
    2. 副本 CD 叠加显示：列表条目内嵌剩余重置时间；鼠标悬停 tooltip 显示首领进度详情。
  数据来源：
    - 坐骑掉落：Toolbox.Data.MountDrops（Data/InstanceDrops_Mount.lua）
    - 锁定查询：Toolbox.EJ.GetAllLockoutsForInstance / GetKilledBosses（Core/EncounterJournal.lua）
  存档键：ToolboxDB.modules.encounter_journal
]]

local MODULE_ID = "encounter_journal"

-- ============================================================================
-- 模块状态辅助
-- ============================================================================

local function getModuleDb()
  Toolbox.Config.Init()
  return Toolbox.Config.GetModule(MODULE_ID)
end

local function isModuleEnabled()
  return Toolbox.Config.GetModule(MODULE_ID).enabled ~= false
end

local function isMountFilterChecked()
  return getModuleDb().mountFilterEnabled == true
end

local function isOverlayEnabled()
  return isModuleEnabled() and getModuleDb().lockoutOverlayEnabled ~= false
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 格式化重置时间
---@param seconds number
---@return string
local function formatResetTime(seconds)
  local loc = Toolbox.L or {}
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if days > 0 then
    return string.format(loc.EJ_LOCKOUT_TIME_DAY_HOUR_FMT or "%dd %dh", days, hours)
  elseif hours > 0 then
    return string.format(loc.EJ_LOCKOUT_TIME_HOUR_MIN_FMT or "%dh %dm", hours, mins)
  else
    return string.format(loc.EJ_LOCKOUT_TIME_MIN_FMT or "%dm", mins)
  end
end

--- 从 elementData 提取 journalInstanceID
---@param elementData table|nil
---@return number|nil
local function getJournalInstanceID(elementData)
  if type(elementData) ~= "table" then return nil end
  local instId = elementData.instanceID or elementData.journalInstanceID or elementData.id
  if type(instId) == "number" then return instId end
  local nested = elementData.data or elementData.elementData or elementData.node
  if type(nested) == "table" and nested ~= elementData then
    local nestedId = nested.instanceID or nested.journalInstanceID or nested.id
    if type(nestedId) == "number" then return nestedId end
  end
  return nil
end

--- 获取当前 ScrollBox（带缓存）
local scrollBoxCache = {
  ref = nil,
  lastUpdate = 0,
  ttl = 5,

  get = function(self)
    local now = GetTime()
    if self.ref and (now - self.lastUpdate) < self.ttl then
      return self.ref
    end

    local ej = _G.EncounterJournal
    if ej and ej.instanceSelect then
      self.ref = ej.instanceSelect.ScrollBox or ej.instanceSelect.scrollBox
      self.lastUpdate = now
    end

    return self.ref
  end
}

local function getCurrentScrollBox()
  return scrollBoxCache:get()
end

-- ============================================================================
-- 坐骑筛选对象
-- ============================================================================

local MountFilter = {
  checkButton = nil,
  label = nil,
}

--- 检查是否应显示坐骑筛选 UI
---@return boolean
local function shouldShowMountFilterUI()
  local ej = _G.EncounterJournal
  local instSel = ej and ej.instanceSelect
  if not instSel or not instSel.ExpansionDropdown then return false end
  if not instSel:IsVisible() then return false end
  local scrollBox = instSel.ScrollBox or instSel.scrollBox
  if scrollBox and scrollBox.IsShown then
    local success, shown = pcall(function() return scrollBox:IsShown() end)
    if success and shown == false then return false end
  end
  return Toolbox.EJ.IsRaidOrDungeonInstanceListTab() == true
end

--- 创建坐骑筛选 UI
function MountFilter:createUI()
  if self.checkButton then
    self:updateVisibility()
    return
  end

  local ej = _G.EncounterJournal
  local instSel = ej and ej.instanceSelect
  if not instSel or not instSel.ExpansionDropdown then return end

  -- 创建复选框
  local checkBtn = CreateFrame("CheckButton", "ToolboxEJMountFilterCheck", instSel, "UICheckButtonTemplate")
  checkBtn:SetSize(22, 22)
  checkBtn:SetChecked(isMountFilterChecked())
  checkBtn:SetScript("OnClick", function(btn)
    if not isModuleEnabled() then
      btn:SetChecked(false)
      return
    end
    local moduleDb = getModuleDb()
    moduleDb.mountFilterEnabled = btn:GetChecked() and true or false
    local loc = Toolbox.L or {}
    if moduleDb.mountFilterEnabled then
      Toolbox.Chat.PrintAddonMessage(loc.EJ_MOUNT_FILTER_NOTIFY_ON or "")
    else
      Toolbox.Chat.PrintAddonMessage(loc.EJ_MOUNT_FILTER_NOTIFY_OFF or "")
    end
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end)
  checkBtn:SetScript("OnEnter", function(btn)
    local loc = Toolbox.L or {}
    GameTooltip._ToolboxSkipAnchorOverride = true
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if not isModuleEnabled() then
      GameTooltip:SetText(loc.EJ_MOUNT_FILTER_LABEL or "")
      GameTooltip:AddLine(loc.EJ_MOUNT_FILTER_SETTINGS_DEPENDENCY_DISABLED or "", 1, 0.2, 0.2, true)
    else
      GameTooltip:SetText(loc.EJ_MOUNT_FILTER_HINT or "")
    end
    GameTooltip:Show()
  end)
  checkBtn:SetScript("OnLeave", function()
    GameTooltip._ToolboxSkipAnchorOverride = nil
    GameTooltip:Hide()
  end)

  local anchorSuccess = pcall(function() checkBtn:SetPoint("RIGHT", instSel.ExpansionDropdown, "LEFT", -8, 0) end)
  if not anchorSuccess then
    checkBtn:Hide()
    return
  end

  -- 创建标签
  local label = instSel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("RIGHT")
  label:SetText((Toolbox.L and Toolbox.L.EJ_MOUNT_FILTER_LABEL) or "")
  pcall(function() label:SetPoint("RIGHT", checkBtn, "LEFT", -4, 0) end)

  self.checkButton = checkBtn
  self.label = label
  _G.ToolboxEJMountFilterLabel = label

  self:updateVisibility()
end

--- 更新坐骑筛选 UI 可见性
function MountFilter:updateVisibility()
  if not self.checkButton or not self.label then return end
  local success, shouldShow = pcall(shouldShowMountFilterUI)
  if not success then shouldShow = false end
  self.checkButton:SetShown(shouldShow == true)
  self.label:SetShown(shouldShow == true)
end

--- 同步复选框状态
function MountFilter:syncCheckbox()
  if self.checkButton then
    self.checkButton:SetChecked(isMountFilterChecked())
  end
end

--- 检查筛选是否激活
---@return boolean
function MountFilter:isActive()
  return self.checkButton ~= nil
    and self.checkButton:GetChecked() == true
    and isModuleEnabled()
    and shouldShowMountFilterUI()
end

--- 应用坐骑筛选
function MountFilter:applyFilter()
  if not self:isActive() then return end

  local box = getCurrentScrollBox()
  if not box or type(box.GetDataProvider) ~= "function" then return end

  local success, dataProv = pcall(function() return box:GetDataProvider() end)
  if not success or type(dataProv) ~= "table" or type(dataProv.ForEach) ~= "function" then return end

  local toRemove = {}
  pcall(function()
    dataProv:ForEach(function(elementData)
      local jid = getJournalInstanceID(elementData)
      if jid and not Toolbox.EJ.HasMountDrops(jid) then
        toRemove[#toRemove + 1] = elementData
      end
    end)
  end)

  if #toRemove > 0 and type(dataProv.Remove) == "function" then
    for _, elementData in ipairs(toRemove) do
      pcall(function() dataProv:Remove(elementData) end)
    end
  end
end

-- ============================================================================
-- 详情页增强对象（仅坐骑筛选 + 标题后锁定文本）
-- ============================================================================

local function getEncounterInfoFrame()
  local ej = _G.EncounterJournal
  local encounterFrame = ej and ej.encounter
  return encounterFrame and encounterFrame.info or nil
end

local function getCurrentDetailJournalInstanceID()
  if type(EJ_GetCurrentInstance) ~= "function" then
    return nil
  end
  local ok, journalInstanceID = pcall(EJ_GetCurrentInstance)
  if ok and type(journalInstanceID) == "number" then
    return journalInstanceID
  end
  return nil
end

local function isEncounterDetailVisible()
  local ej = _G.EncounterJournal
  local encounterFrame = ej and ej.encounter
  return encounterFrame and encounterFrame.IsShown and encounterFrame:IsShown() or false
end

local function isEncounterLootTabVisible()
  local info = getEncounterInfoFrame()
  if not info then
    return false
  end

  local lootContainer = info.LootContainer or info.lootContainer
  if lootContainer and lootContainer.IsShown then
    local ok, shown = pcall(function() return lootContainer:IsShown() end)
    if ok and shown == true then
      return true
    end
  end

  local lootTab = _G.EncounterJournalEncounterFrameInfoLootTab
  if lootTab and lootTab.IsShown then
    local ok, shown = pcall(function() return lootTab:IsShown() end)
    if ok and shown == true then
      return true
    end
  end

  return false
end

local function parseItemIDFromLink(linkText)
  if type(linkText) ~= "string" then
    return nil
  end
  local itemID = tonumber(linkText:match("item:(%d+)"))
  return itemID
end

local function extractItemIDFromAny(value, seen)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    return parseItemIDFromLink(value)
  end
  if type(value) ~= "table" then
    return nil
  end
  seen = seen or {}
  if seen[value] then
    return nil
  end
  seen[value] = true

  local direct = value.itemID or value.itemId or value.id
  if type(direct) == "number" then
    return direct
  end

  local fromLink = parseItemIDFromLink(value.link or value.itemLink or value.hyperlink)
  if type(fromLink) == "number" then
    return fromLink
  end

  local nestedCandidates = {
    value.item,
    value.data,
    value.info,
    value.elementData,
    value.itemData,
  }
  for _, nested in ipairs(nestedCandidates) do
    local nestedItemID = extractItemIDFromAny(nested, seen)
    if type(nestedItemID) == "number" then
      return nestedItemID
    end
  end
  return nil
end

local function getDetailDifficultyControl()
  local info = getEncounterInfoFrame()
  if not info then
    return nil
  end
  return info.Difficulty or info.difficulty or _G.EncounterJournalEncounterFrameInfoDifficulty
end

local DetailEnhancer = {
  mountOnlyCheck = nil,
  lockoutLabel = nil,
}

function DetailEnhancer:isMountOnlyEnabled()
  return getModuleDb().detailMountOnlyEnabled == true
end

function DetailEnhancer:syncMountOnlyCheck()
  if self.mountOnlyCheck then
    local loc = Toolbox.L or {}
    if self.mountOnlyCheck.Text and self.mountOnlyCheck.Text.SetText then
      self.mountOnlyCheck.Text:SetText(loc.EJ_DETAIL_MOUNT_ONLY_LABEL or "")
    end
    self.mountOnlyCheck:SetChecked(self:isMountOnlyEnabled())
  end
end

function DetailEnhancer:requestLootRefresh()
  if type(_G.EncounterJournal_LootUpdate) == "function" then
    pcall(_G.EncounterJournal_LootUpdate)
  end
end

function DetailEnhancer:ensureMountOnlyCheck()
  if self.mountOnlyCheck then
    return
  end

  local info = getEncounterInfoFrame()
  if not info then
    return
  end

  local check = CreateFrame("CheckButton", "ToolboxEJDetailMountOnlyCheck", info, "UICheckButtonTemplate")
  check:SetSize(22, 22)
  check:SetScript("OnClick", function(btn)
    local moduleDb = getModuleDb()
    moduleDb.detailMountOnlyEnabled = btn:GetChecked() and true or false
    self:syncMountOnlyCheck()
    self:requestLootRefresh()
  end)
  check:SetScript("OnEnter", function(btn)
    local loc = Toolbox.L or {}
    GameTooltip._ToolboxSkipAnchorOverride = true
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(loc.EJ_DETAIL_MOUNT_ONLY_LABEL or "")
    GameTooltip:AddLine(loc.EJ_DETAIL_MOUNT_ONLY_HINT or "", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", function()
    GameTooltip._ToolboxSkipAnchorOverride = nil
    GameTooltip:Hide()
  end)

  local difficultyControl = getDetailDifficultyControl()
  if difficultyControl then
    check:SetPoint("LEFT", difficultyControl, "RIGHT", 10, 0)
  else
    check:SetPoint("TOPRIGHT", info, "TOPRIGHT", -12, -10)
  end

  self.mountOnlyCheck = check
  self:syncMountOnlyCheck()
end

function DetailEnhancer:ensureLockoutLabel()
  if self.lockoutLabel then
    return
  end

  local info = getEncounterInfoFrame()
  if not info then
    return
  end

  local label = info:CreateFontString("ToolboxEJDetailLockoutLabel", "OVERLAY", "GameFontHighlightSmall")
  label:SetJustifyH("LEFT")
  label:SetText("")

  local titleAnchor = info.InstanceTitle or info.instanceTitle or _G.EncounterJournalEncounterFrameInfoTitle
  local difficultyControl = getDetailDifficultyControl()
  if titleAnchor and titleAnchor.SetPoint then
    label:SetPoint("LEFT", titleAnchor, "RIGHT", 8, 0)
  elseif difficultyControl and difficultyControl.SetPoint then
    label:SetPoint("RIGHT", difficultyControl, "LEFT", -12, 0)
  else
    label:SetPoint("TOPLEFT", info, "TOPLEFT", 180, -10)
  end

  self.lockoutLabel = label
end

function DetailEnhancer:updateVisibility()
  local detailShown = isEncounterDetailVisible()
  local lootShown = isEncounterLootTabVisible()
  if self.mountOnlyCheck then
    self.mountOnlyCheck:SetShown(detailShown and lootShown and isModuleEnabled())
  end
  if self.lockoutLabel then
    self.lockoutLabel:SetShown(detailShown and isModuleEnabled())
  end
end

function DetailEnhancer:updateLockoutLabel()
  if not self.lockoutLabel then
    return
  end
  if not isEncounterDetailVisible() or not isModuleEnabled() then
    self.lockoutLabel:SetText("")
    return
  end

  local loc = Toolbox.L or {}
  local journalInstanceID = getCurrentDetailJournalInstanceID()
  local difficultyID = Toolbox.EJ.GetSelectedDifficultyID and Toolbox.EJ.GetSelectedDifficultyID() or nil
  local lockout = nil
  if Toolbox.EJ and Toolbox.EJ.GetLockoutForInstanceAndDifficulty then
    lockout = Toolbox.EJ.GetLockoutForInstanceAndDifficulty(journalInstanceID, difficultyID)
  end
  if lockout and (lockout.resetTime or 0) > 0 then
    local timeText = formatResetTime(lockout.resetTime or 0)
    self.lockoutLabel:SetText(string.format(loc.EJ_DETAIL_LOCKOUT_FMT or "重置：%s", timeText))
  else
    self.lockoutLabel:SetText(loc.EJ_DETAIL_LOCKOUT_NONE or "重置：无")
  end
end

function DetailEnhancer:applyMountOnlyFilter()
  if not isModuleEnabled() or not self:isMountOnlyEnabled() or not isEncounterLootTabVisible() then
    return
  end

  local journalInstanceID = getCurrentDetailJournalInstanceID()
  if type(journalInstanceID) ~= "number" then
    return
  end
  local mountSet = Toolbox.EJ and Toolbox.EJ.GetMountItemSetForInstance and Toolbox.EJ.GetMountItemSetForInstance(journalInstanceID) or nil
  if type(mountSet) ~= "table" then
    return
  end

  local info = getEncounterInfoFrame()
  local lootContainer = info and (info.LootContainer or info.lootContainer)
  local scrollBox = lootContainer and (lootContainer.ScrollBox or lootContainer.scrollBox) or nil
  if scrollBox and type(scrollBox.GetDataProvider) == "function" then
    local ok, dataProvider = pcall(function() return scrollBox:GetDataProvider() end)
    if ok and type(dataProvider) == "table" and type(dataProvider.ForEach) == "function" and type(dataProvider.Remove) == "function" then
      local toRemove = {}
      pcall(function()
        dataProvider:ForEach(function(elementData)
          local itemID = extractItemIDFromAny(elementData)
          if type(itemID) == "number" and not mountSet[itemID] then
            toRemove[#toRemove + 1] = elementData
          end
        end)
      end)
      for _, elementData in ipairs(toRemove) do
        pcall(function() dataProvider:Remove(elementData) end)
      end
      return
    end
  end

  -- 旧版兜底：尝试隐藏已创建的条目按钮（无 DataProvider 时）。
  local fallbackButtons = {}
  for index = 1, 60 do
    local button = _G["EncounterJournalLoot" .. index]
    if button then
      fallbackButtons[#fallbackButtons + 1] = button
    end
  end
  for _, button in ipairs(fallbackButtons) do
    local itemID = extractItemIDFromAny(button)
    if type(itemID) == "number" then
      button:SetShown(mountSet[itemID] == true)
    end
  end
end

function DetailEnhancer:refresh()
  self:ensureMountOnlyCheck()
  self:ensureLockoutLabel()
  self:syncMountOnlyCheck()
  self:updateVisibility()
  self:updateLockoutLabel()
  self:applyMountOnlyFilter()
end

-- ============================================================================
-- CD 叠加对象
-- ============================================================================

local LockoutOverlay = {}

local OVERLAY_FS_KEY = "_ToolboxLockoutFS"

--- 检查是否启用
---@return boolean
function LockoutOverlay:isEnabled()
  return isOverlayEnabled()
end

--- 创建 FontString
---@param frame table
---@return table fontString
function LockoutOverlay:createFontString(frame)
  local fontStr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  -- 锚定到 frame 的左下角
  fontStr:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
  fontStr:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  fontStr:SetJustifyH("LEFT")
  fontStr:SetJustifyV("BOTTOM")

  return fontStr
end

--- 渲染锁定文字
---@param frame table
---@param lockouts table[]
function LockoutOverlay:renderLockoutText(frame, lockouts)
  local fontString = frame[OVERLAY_FS_KEY]
  if not fontString then
    fontString = self:createFontString(frame)
    frame[OVERLAY_FS_KEY] = fontString
  end

  if #lockouts > 0 then
    local lines = {}
    for _, lockout in ipairs(lockouts) do
      local timeStr = formatResetTime(lockout.resetTime or 0)
      local line
      if lockout.isRaid then
        line = string.format("|cffFFD700%s %d/%d %s|r",
          lockout.difficultyName or "", lockout.encounterProgress or 0, lockout.numEncounters or 0, timeStr)
      else
        line = string.format("|cffFFD700%s %s|r", lockout.difficultyName or "", timeStr)
      end
      table.insert(lines, line)
    end
    fontString:SetText(table.concat(lines, "\n"))
    fontString:Show()
  else
    fontString:SetText("")
    fontString:Hide()
  end
end

--- 更新所有 frame 的锁定显示
function LockoutOverlay:updateFrames()
  if not self:isEnabled() then
    self:clearAllFrames()
    return
  end

  local box = getCurrentScrollBox()
  if not box or type(box.ForEachFrame) ~= "function" then return end

  pcall(function()
    box:ForEachFrame(function(frame)
      if not frame or not frame.GetElementData then return end
      local success, elementData = pcall(function() return frame:GetElementData() end)
      if not success or not elementData then return end
      local jid = getJournalInstanceID(elementData)
      if not jid then return end

      local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(jid)
      self:renderLockoutText(frame, lockouts)
    end)
  end)
end

--- 清理所有可见列表项上的锁定叠加文本（用于关闭功能时立即去残留）
function LockoutOverlay:clearAllFrames()
  local box = getCurrentScrollBox()
  if not box or type(box.ForEachFrame) ~= "function" then return end

  pcall(function()
    box:ForEachFrame(function(frame)
      if not frame then return end
      local fontString = frame[OVERLAY_FS_KEY]
      if fontString then
        fontString:SetText("")
        fontString:Hide()
      end
    end)
  end)
end

--- Hook frame tooltip
local hookedFrames = setmetatable({}, {__mode = "k"})

function LockoutOverlay:hookTooltips()
  local box = getCurrentScrollBox()
  if not box or type(box.ForEachFrame) ~= "function" then return end

  pcall(function()
    box:ForEachFrame(function(frame)
      if not frame or hookedFrames[frame] then return end
      if not frame.HookScript then return end
      hookedFrames[frame] = true
      frame:HookScript("OnEnter", function(self)
        if not isOverlayEnabled() then return end
        local success, elementData = pcall(function() return self:GetElementData() end)
        if not success or not elementData then return end
        local jid = getJournalInstanceID(elementData)
        if not jid then return end

        local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(jid)
        if #lockouts == 0 then return end

        local loc = Toolbox.L or {}
        GameTooltip:AddLine(" ")
        for _, lockout in ipairs(lockouts) do
          local timeStr = formatResetTime(lockout.resetTime or 0)
          local resetLabel = string.format(loc.EJ_LOCKOUT_RESET_FMT or "%s - Resets in: %s",
            lockout.difficultyName or "", timeStr)
          if lockout.isExtended then
            resetLabel = resetLabel .. " " .. (loc.EJ_LOCKOUT_EXTENDED or "(Extended)")
          end
          GameTooltip:AddLine(resetLabel, 1, 0.8, 0)
          if lockout.isRaid and (lockout.numEncounters or 0) > 0 then
            local progressLabel = string.format(loc.EJ_LOCKOUT_PROGRESS_FMT or "Progress: %d / %d bosses",
              lockout.encounterProgress or 0, lockout.numEncounters or 0)
            GameTooltip:AddLine(progressLabel, 0.8, 0.8, 0.8)
            local killed = Toolbox.EJ.GetKilledBosses(jid)
            for _, boss in ipairs(killed) do
              GameTooltip:AddLine("  " .. (boss.name or ""), 0.6, 0.6, 0.6)
            end
          end
        end
        GameTooltip:Show()
      end)
    end)
  end)
end

-- ============================================================================
-- 事件驱动架构
-- ============================================================================

--- 统一刷新入口
local function refreshAll()
  DetailEnhancer:refresh()
  MountFilter:updateVisibility()
  MountFilter:applyFilter()
  LockoutOverlay:updateFrames()
  LockoutOverlay:hookTooltips()
end

--- 刷新调度器（防抖）
local RefreshScheduler = {
  timer = nil,
  token = 0,
  delays = {
    frame_show = 0.15,
    list_refresh = 0.05,
    tab_change = 0.05,
    lockout_update = 0.1,
  },
}

function RefreshScheduler:schedule(reason)
  if self.timer and self.timer.Cancel then
    self.timer:Cancel()
  end
  self.timer = nil

  local delay = self.delays[reason] or 0.1
  self.token = (self.token or 0) + 1
  local currentToken = self.token

  if C_Timer and C_Timer.NewTimer then
    self.timer = C_Timer.NewTimer(delay, function()
      if self.token ~= currentToken then
        return
      end
      self.timer = nil
      self:execute()
    end)
    return
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(delay, function()
      if self.token ~= currentToken then
        return
      end
      self.timer = nil
      self:execute()
    end)
    return
  end

  self:execute()
end

function RefreshScheduler:cancel()
  if self.timer and self.timer.Cancel then
    self.timer:Cancel()
  end
  self.timer = nil
  self.token = (self.token or 0) + 1
end

function RefreshScheduler:execute()
  local success, err = pcall(refreshAll)
  if not success then
    if getModuleDb().debug then
      print("Toolbox EncounterJournal refresh error:", err)
    end
  end
  self.timer = nil
end

--- Hook 管理器（只 Hook 一次）
local hooked = false

local function initHooks()
  if hooked then return end
  hooked = true

  -- Hook 1: 列表刷新
  if hooksecurefunc and type(_G.EncounterJournal_ListInstances) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_ListInstances", function()
        scrollBoxCache.ref = nil
        scrollBoxCache.lastUpdate = 0
        MountFilter:createUI()
        RefreshScheduler:schedule("list_refresh")
      end)
    end)
  end

  -- Hook 1.5: 详情页战利品更新（用于“仅坐骑”筛选）
  if hooksecurefunc and type(_G.EncounterJournal_LootUpdate) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_LootUpdate", function()
        RefreshScheduler:schedule("detail_loot_update")
      end)
    end)
  end

  -- Hook 2: 标签切换
  if hooksecurefunc and type(_G.EJ_ContentTab_Select) == "function" then
    pcall(function()
      hooksecurefunc("EJ_ContentTab_Select", function()
        C_Timer.After(0, function()
          scrollBoxCache.ref = nil
          scrollBoxCache.lastUpdate = 0
          RefreshScheduler:schedule("tab_change")
        end)
      end)
    end)
  end

  -- Hook 2.5: 详情页切换实例/首领
  if hooksecurefunc and type(_G.EncounterJournal_DisplayInstance) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_DisplayInstance", function()
        RefreshScheduler:schedule("detail_display")
      end)
    end)
  end
  if hooksecurefunc and type(_G.EncounterJournal_DisplayEncounter) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_DisplayEncounter", function()
        RefreshScheduler:schedule("detail_display")
      end)
    end)
  end

  -- Hook 2.6: 右侧难度切换（标题后“重置：xxxx”需与当前难度匹配）
  if hooksecurefunc and type(_G.EJ_SetDifficulty) == "function" then
    pcall(function()
      hooksecurefunc("EJ_SetDifficulty", function()
        RefreshScheduler:schedule("detail_difficulty")
      end)
    end)
  end

  -- Hook 3: 主框架显示
  local ej = _G.EncounterJournal
  if ej and ej.HookScript then
    pcall(function()
      ej:HookScript("OnShow", function()
        RequestRaidInfo()
        RefreshScheduler:schedule("frame_show")
      end)
    end)
  end
end

--- 事件管理器
local eventFrame = nil

local function setLockoutUpdateEventEnabled(enabled)
  if not eventFrame then
    return
  end
  if enabled then
    eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
  else
    eventFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")
  end
end

local function registerIntegration()
  if eventFrame then return end

  eventFrame = CreateFrame("Frame", "ToolboxEncounterJournalHost")
  eventFrame:RegisterEvent("ADDON_LOADED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  setLockoutUpdateEventEnabled(isModuleEnabled())

  eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then
      self:UnregisterEvent("ADDON_LOADED")
      initHooks()
      RequestRaidInfo()
    elseif event == "UPDATE_INSTANCE_INFO" then
      if isModuleEnabled() then
        RefreshScheduler:schedule("lockout_update")
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      RequestRaidInfo()
    end
  end)

  -- 如果 EJ 已加载，立即初始化
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    initHooks()
  end

  RequestRaidInfo()
end

-- ============================================================================
-- 模块注册
-- ============================================================================

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_ENCOUNTER_JOURNAL",
  settingsIntroKey = "MODULE_ENCOUNTER_JOURNAL_INTRO",
  settingsOrder = 50,

  OnModuleLoad = function()
    registerIntegration()
  end,

  OnModuleEnable = function()
    setLockoutUpdateEventEnabled(true)
    DetailEnhancer:refresh()
    MountFilter:syncCheckbox()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  OnEnabledSettingChanged = function(enabled)
    local loc = Toolbox.L or {}
    local msgKey = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(loc[msgKey] or "%s", loc.MODULE_ENCOUNTER_JOURNAL or MODULE_ID))
    setLockoutUpdateEventEnabled(enabled)
    if enabled then
      RequestRaidInfo()
      DetailEnhancer:refresh()
    else
      RefreshScheduler:cancel()
      LockoutOverlay:clearAllFrames()
    end
    MountFilter:syncCheckbox()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
    DetailEnhancer:refresh()
    MountFilter:syncCheckbox()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  RegisterSettings = function(box)
    local loc = Toolbox.L or {}
    local moduleDb = getModuleDb()
    local yOffset = 0

    -- 坐骑筛选设置
    local mountFilterCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    mountFilterCheck:SetPoint("TOPLEFT", 20, yOffset)
    mountFilterCheck.Text:SetText(loc.DRD_MOUNT_FILTER_ENABLED or "在冒险指南中筛选坐骑")
    mountFilterCheck:SetChecked(moduleDb.mountFilterEnabled ~= false)
    mountFilterCheck:SetScript("OnClick", function(self)
      moduleDb.mountFilterEnabled = self:GetChecked()
      MountFilter:syncCheckbox()
      if type(_G.EncounterJournal_ListInstances) == "function" then
        pcall(_G.EncounterJournal_ListInstances)
      end
    end)
    yOffset = yOffset - 36

    -- CD 叠加设置
    local lockoutOverlayCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    lockoutOverlayCheck:SetPoint("TOPLEFT", 20, yOffset)
    lockoutOverlayCheck.Text:SetText(loc.EJ_LOCKOUT_OVERLAY_LABEL or "在冒险指南中显示副本 CD")
    lockoutOverlayCheck:SetChecked(moduleDb.lockoutOverlayEnabled ~= false)
    lockoutOverlayCheck:SetScript("OnClick", function(self)
      moduleDb.lockoutOverlayEnabled = self:GetChecked() and true or false
      if moduleDb.lockoutOverlayEnabled == false then
        LockoutOverlay:clearAllFrames()
      end
      RefreshScheduler:schedule("settings_change")
    end)
    yOffset = yOffset - 36

    box.realHeight = math.abs(yOffset) + 8
  end,
})
