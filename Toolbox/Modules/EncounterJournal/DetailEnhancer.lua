--[[
  冒险指南详情增强与列表“仅坐骑”筛选私有实现。
]]

local Internal = Toolbox.EncounterJournalInternal -- 冒险指南内部命名空间
local Runtime = Internal.Runtime
local CreateFrame = Internal.CreateFrame

local function getModuleDb()
  return Internal.GetModuleDb()
end

local function isModuleEnabled()
  return Internal.IsModuleEnabled()
end

local function isMountFilterChecked()
  return Internal.IsMountFilterChecked()
end

local function getCurrentScrollBox()
  return Internal.GetCurrentScrollBox()
end

local function getJournalInstanceID(elementData)
  return Internal.GetJournalInstanceID(elementData)
end

local function formatResetTime(seconds)
  return Internal.FormatResetTime(seconds)
end

local function getEncounterInfoFrame()
  return Internal.GetEncounterInfoFrame()
end

local MountFilter = {
  checkButton = nil,
  label = nil,
}

--- 检查是否应显示坐骑筛选 UI
---@return boolean
local function shouldShowMountFilterUI()
  local ej = _G.EncounterJournal
  local instSel = ej and ej.instanceSelect
  if not instSel then return false end
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
  if not instSel then return end
  local anchorTarget = instSel.ExpansionDropdown or instSel -- 按钮锚点目标（优先资料片下拉）

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
    if Toolbox.Tooltip and Toolbox.Tooltip.SetSkipAnchorOverride then
      Toolbox.Tooltip.SetSkipAnchorOverride(GameTooltip, true)
    end
    Runtime.TooltipSetOwner(GameTooltip, btn, "ANCHOR_RIGHT")
    Runtime.TooltipClear(GameTooltip)
    if not isModuleEnabled() then
      Runtime.TooltipSetText(GameTooltip, loc.EJ_MOUNT_FILTER_LABEL or "")
      Runtime.TooltipAddLine(GameTooltip, loc.EJ_MOUNT_FILTER_SETTINGS_DEPENDENCY_DISABLED or "", 1, 0.2, 0.2, true)
    else
      Runtime.TooltipSetText(GameTooltip, loc.EJ_MOUNT_FILTER_HINT or "")
    end
    Runtime.TooltipShow(GameTooltip)
  end)
  checkBtn:SetScript("OnLeave", function()
    if Toolbox.Tooltip and Toolbox.Tooltip.SetSkipAnchorOverride then
      Toolbox.Tooltip.SetSkipAnchorOverride(GameTooltip, false)
    end
    Runtime.TooltipHide(GameTooltip)
  end)

  local anchorSuccess = pcall(function() checkBtn:SetPoint("RIGHT", anchorTarget, "LEFT", -8, 0) end)
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

local function getCurrentDetailJournalInstanceID()
  if type(EJ_GetCurrentInstance) ~= "function" then
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local fallbackInstanceID = encounterJournalFrame and encounterJournalFrame.instanceID -- 当前界面记录的副本 ID
    if type(fallbackInstanceID) == "number" and fallbackInstanceID > 0 then
      return fallbackInstanceID
    end
    return nil
  end
  local ok, journalInstanceID = pcall(EJ_GetCurrentInstance)
  if ok and type(journalInstanceID) == "number" and journalInstanceID > 0 then
    return journalInstanceID
  end

  local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
  local fallbackInstanceID = encounterJournalFrame and encounterJournalFrame.instanceID -- 当前界面记录的副本 ID
  if type(fallbackInstanceID) == "number" and fallbackInstanceID > 0 then
    return fallbackInstanceID
  end

  return nil
end

local function isEncounterDetailVisible()
  local infoFrame = getEncounterInfoFrame() -- 详情信息面板
  if infoFrame and infoFrame.IsShown then
    local infoSuccess, infoShown = pcall(function() return infoFrame:IsShown() end)
    if infoSuccess and infoShown == true then
      return true
    end
  end

  local ej = _G.EncounterJournal
  local encounterFrame = ej and ej.encounter
  if encounterFrame and encounterFrame.IsShown then
    local encounterSuccess, encounterShown = pcall(function() return encounterFrame:IsShown() end)
    if encounterSuccess and encounterShown == true then
      return true
    end
  end

  return false
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

local function getDetailInstanceTitleControl()
  local info = getEncounterInfoFrame() -- 详情信息面板
  if not info then
    return nil
  end
  return info.InstanceTitle or info.instanceTitle or _G.EncounterJournalEncounterFrameInfoInstanceTitle
end

local function getVisibleTitleTextWidth(titleControl)
  if not titleControl then
    return 0
  end
  local stringWidth = 0 -- 标题文本宽度
  if titleControl.GetStringWidth then
    local stringWidthSuccess, widthValue = pcall(function() return titleControl:GetStringWidth() end)
    if stringWidthSuccess and type(widthValue) == "number" and widthValue > 0 then
      stringWidth = widthValue
    end
  end
  if titleControl.GetWidth then
    local controlWidthSuccess, controlWidth = pcall(function() return titleControl:GetWidth() end)
    if controlWidthSuccess and type(controlWidth) == "number" and controlWidth > 0 and stringWidth > controlWidth then
      stringWidth = controlWidth
    end
  end
  return stringWidth
end

local function isDetailInstanceTitleVisible()
  local titleControl = getDetailInstanceTitleControl() -- 副本标题控件
  if not titleControl or not titleControl.IsShown then
    return false
  end
  local shownSuccess, shownValue = pcall(function() return titleControl:IsShown() end)
  return shownSuccess and shownValue == true
end

local function pickFallbackLockout(lockoutList)
  if type(lockoutList) ~= "table" or #lockoutList == 0 then
    return nil
  end

  local chosenLockout = nil -- 回退锁定记录
  for _, lockoutEntry in ipairs(lockoutList) do
    if type(lockoutEntry) == "table" and (lockoutEntry.resetTime or 0) > 0 then
      if not chosenLockout or (lockoutEntry.resetTime or math.huge) < (chosenLockout.resetTime or math.huge) then
        chosenLockout = lockoutEntry
      end
    end
  end

  return chosenLockout or lockoutList[1]
end

local function resolveDetailLockout(journalInstanceID, difficultyID)
  local lockoutInfo = nil -- 当前难度锁定信息
  if Toolbox.EJ and Toolbox.EJ.GetLockoutForInstanceAndDifficulty then
    lockoutInfo = Toolbox.EJ.GetLockoutForInstanceAndDifficulty(journalInstanceID, difficultyID)
  end
  if lockoutInfo then
    return lockoutInfo
  end

  -- 当前难度未命中时，回退到该副本已有锁定（优先最近重置）。
  if Toolbox.EJ and Toolbox.EJ.GetAllLockoutsForInstance then
    local allLockouts = Toolbox.EJ.GetAllLockoutsForInstance(journalInstanceID)
    return pickFallbackLockout(allLockouts)
  end

  return nil
end

local DetailEnhancer = {
  lockoutLabel = nil,
}

function DetailEnhancer:isMountOnlyEnabled()
  return getModuleDb().detailMountOnlyEnabled == true
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

  self.lockoutLabel = label
  self:refreshLockoutLabelAnchor()
end

function DetailEnhancer:refreshLockoutLabelAnchor()
  if not self.lockoutLabel then
    return
  end

  local info = getEncounterInfoFrame() -- 详情信息面板
  if not info then
    return
  end

  local label = self.lockoutLabel -- 重置时间标签
  local titleAnchor = getDetailInstanceTitleControl() -- 副本名称锚点（右侧详情区标题）
  local difficultyControl = getDetailDifficultyControl() -- 难度控件锚点

  if label.ClearAllPoints then
    label:ClearAllPoints()
  end
  if titleAnchor and titleAnchor.SetPoint then
    local textWidth = getVisibleTitleTextWidth(titleAnchor) -- 副本标题可见文本宽度
    label:SetPoint("LEFT", titleAnchor, "LEFT", textWidth + 8, 0)
  elseif difficultyControl and difficultyControl.SetPoint then
    label:SetPoint("RIGHT", difficultyControl, "LEFT", -12, 0)
  else
    label:SetPoint("TOPLEFT", info, "TOPLEFT", 180, -10)
  end
end

function DetailEnhancer:updateVisibility()
  local detailShown = isEncounterDetailVisible()
  local instanceTitleShown = isDetailInstanceTitleVisible()
  if self.lockoutLabel then
    self:refreshLockoutLabelAnchor()
    self.lockoutLabel:SetShown(detailShown and instanceTitleShown and isModuleEnabled())
  end
end

function DetailEnhancer:updateLockoutLabel()
  if not self.lockoutLabel then
    return
  end
  if not isEncounterDetailVisible() or not isModuleEnabled() or not isDetailInstanceTitleVisible() then
    self.lockoutLabel:SetText("")
    return
  end

  local loc = Toolbox.L or {}
  local journalInstanceID = getCurrentDetailJournalInstanceID()
  local difficultyID = Toolbox.EJ.GetSelectedDifficultyID and Toolbox.EJ.GetSelectedDifficultyID() or nil
  local lockout = resolveDetailLockout(journalInstanceID, difficultyID) -- 展示用锁定信息
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
  self:ensureLockoutLabel()
  -- 详情页右侧“仅坐骑”按钮已移除，避免与列表筛选入口重复。
  self:updateVisibility()
  self:updateLockoutLabel()
  self:applyMountOnlyFilter()
end

Internal.MountFilter = MountFilter
Internal.DetailEnhancer = DetailEnhancer
