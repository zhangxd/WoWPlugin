--[[
  冒险指南增强模块（encounter_journal）。
  本文件仅保留模块注册、事件入口、调度器与设置页等组装层逻辑。
  具体实现已拆分到 Modules/EncounterJournal/*.lua 私有文件。
]]

local Internal = Toolbox.EncounterJournalInternal -- 冒险指南内部命名空间
local MODULE_ID = Internal.MODULE_ID
local Runtime = Internal.Runtime
local CreateFrame = Internal.CreateFrame
local microTooltipAppendState = Internal.microTooltipAppendState
local scrollBoxCache = Internal.scrollBoxCache

local MountFilter = Internal.MountFilter
local DetailEnhancer = Internal.DetailEnhancer
local QuestlineTreeView = Internal.QuestlineTreeView
local LockoutOverlay = Internal.LockoutOverlay

local function getModuleDb()
  return Internal.GetModuleDb()
end

local function isModuleEnabled()
  return Internal.IsModuleEnabled()
end

local function getEncounterInfoFrame()
  return Internal.GetEncounterInfoFrame()
end

local function refreshAll()
  MountFilter = Internal.MountFilter
  DetailEnhancer = Internal.DetailEnhancer
  QuestlineTreeView = Internal.QuestlineTreeView
  LockoutOverlay = Internal.LockoutOverlay
  MountFilter:createUI()
  DetailEnhancer:refresh()
  QuestlineTreeView:refresh()
  MountFilter:updateVisibility()
  MountFilter:applyFilter()
  LockoutOverlay:updateFrames()
  LockoutOverlay:hookTooltips()
end

local function getRootTabHiddenIdsTable()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.rootTabHiddenIds) ~= "table" then
    moduleDb.rootTabHiddenIds = {}
  end
  return moduleDb.rootTabHiddenIds
end

local function buildDefaultRootTabOrderIds()
  return QuestlineTreeView:buildDefaultRootTabOrderIds()
end

local function buildEffectiveRootTabOrderIds()
  return QuestlineTreeView:buildEffectiveRootTabOrderIds()
end

-- ============================================================================
-- 微型菜单「冒险手册」按钮 Tooltip 增补（右下角菜单排）
-- ============================================================================

local microButtonTooltipHooked = false

--- 获取冒险手册微型菜单按钮（Retail 主路径为 EJMicroButton，旧名仅作兜底）。
---@return Button|nil
local function getAdventureGuideMicroButton()
  local microButton = _G.EJMicroButton -- Retail 微型菜单按钮全局名
  if not microButton then
    microButton = _G.EncounterJournalMicroButton -- 历史命名兜底
  end
  return microButton
end

--- 向当前冒险手册微型按钮 tooltip 追加副本 CD 摘要（带一次悬停去重）。
local function appendAdventureGuideMicroButtonLockoutLines()
  if not isModuleEnabled() then
    return
  end
  if not GameTooltip or not GameTooltip.AddLine then
    return
  end
  if microTooltipAppendState[GameTooltip] == true then
    return
  end
  microTooltipAppendState[GameTooltip] = true

  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local sectionTitle = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE or "Current lockouts" -- 标题文案
  local emptyText = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_EMPTY or "No saved instance lockouts." -- 空态文案
  local moreFormat = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_MORE_FMT or "+%d more..." -- 溢出计数文案

  Runtime.TooltipAddLine(GameTooltip, " ")
  Runtime.TooltipAddLine(GameTooltip, sectionTitle, 1, 0.82, 0.2)

  if not Toolbox.EJ or type(Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines) ~= "function" then
    Runtime.TooltipAddLine(GameTooltip, emptyText, 0.75, 0.75, 0.75, true)
    return
  end

  local lineList, overflowCount = Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(8) -- 锁定摘要行与溢出数量
  if type(lineList) ~= "table" or #lineList == 0 then
    Runtime.TooltipAddLine(GameTooltip, emptyText, 0.75, 0.75, 0.75, true)
    return
  end

  for _, lineText in ipairs(lineList) do
    Runtime.TooltipAddLine(GameTooltip, lineText, 0.82, 0.88, 1, true)
  end
  if type(overflowCount) == "number" and overflowCount > 0 then
    Runtime.TooltipAddLine(GameTooltip, string.format(moreFormat, overflowCount), 0.6, 0.6, 0.6, true)
  end
end

--- 若当前 tooltip 正在显示冒险手册微型按钮提示，则重建一次（用于 UPDATE_INSTANCE_INFO 回刷）。
local function refreshAdventureGuideMicroButtonTooltipIfOwned()
  local microButton = getAdventureGuideMicroButton() -- 冒险手册微型菜单按钮
  if not microButton then
    return
  end
  if not GameTooltip or not GameTooltip.IsOwned or not GameTooltip:IsOwned(microButton) then
    return
  end
  if GameTooltip then
    microTooltipAppendState[GameTooltip] = nil
  end
  local onEnterHandler = microButton.GetScript and microButton:GetScript("OnEnter") -- 微型按钮 OnEnter 脚本
  if type(onEnterHandler) == "function" then
    pcall(onEnterHandler, microButton)
    appendAdventureGuideMicroButtonLockoutLines()
    Runtime.TooltipShow(GameTooltip)
    return
  end
  appendAdventureGuideMicroButtonLockoutLines()
  Runtime.TooltipShow(GameTooltip)
end

--- 在右下角微型菜单的冒险手册按钮 tooltip 末尾追加当前角色副本 CD 摘要。
local function hookAdventureGuideMicroButtonTooltip()
  local microButton = getAdventureGuideMicroButton() -- 冒险手册微型菜单按钮
  if not microButton then
    return
  end

  if not microButtonTooltipHooked and microButton.HookScript then
    microButtonTooltipHooked = true
    microButton:HookScript("OnEnter", function()
      pcall(function()
        if type(RequestRaidInfo) == "function" then
          pcall(RequestRaidInfo)
        end
        if GameTooltip then
          microTooltipAppendState[GameTooltip] = nil
        end
        appendAdventureGuideMicroButtonLockoutLines()
        Runtime.TooltipShow(GameTooltip)
      end)
    end)
    microButton:HookScript("OnLeave", function()
      if GameTooltip then
        microTooltipAppendState[GameTooltip] = nil
      end
    end)
  end

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
  local currentToken = self.token -- 当前调度令牌

  local timerHandle = Runtime.NewTimer(delay, function()
    if self.token ~= currentToken then
      return
    end
    self.timer = nil
    self:execute()
  end)
  if timerHandle then
    self.timer = timerHandle
    return
  end

  local afterScheduled = false -- 延时任务是否已调度
  Runtime.After(delay, function()
    afterScheduled = true
    if self.token ~= currentToken then
      return
    end
    self.timer = nil
    self:execute()
  end)
  if afterScheduled then
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
local detailInfoOnShowHooked = false

local function hookDetailInfoOnShow()
  if detailInfoOnShowHooked then
    return
  end
  local infoFrame = getEncounterInfoFrame() -- 详情信息面板
  if not infoFrame or not infoFrame.HookScript then
    return
  end
  detailInfoOnShowHooked = true
  infoFrame:HookScript("OnShow", function()
    RefreshScheduler:schedule("detail_info_show")
  end)
end

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
        QuestlineTreeView.pendingNativeSelection = true
        if QuestlineTreeView.selected then
          QuestlineTreeView.selected = false
        end
        Runtime.After(0, function()
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
        hookDetailInfoOnShow()
      end)
    end)
  end
  if hooksecurefunc and type(_G.EncounterJournal_DisplayEncounter) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_DisplayEncounter", function()
        RefreshScheduler:schedule("detail_display")
        hookDetailInfoOnShow()
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
        hookDetailInfoOnShow()
        -- 页签顺序/显隐在 OnShow 当帧先应用，避免首帧出现默认顺序闪烁。
        if isModuleEnabled() then
          MountFilter:createUI()
          MountFilter:updateVisibility()
          QuestlineTreeView:refresh()
        end
        RefreshScheduler:schedule("frame_show")
      end)
    end)
  end

  hookDetailInfoOnShow()

  -- Hook 4: 右下角微型菜单的冒险手册按钮 tooltip
  hookAdventureGuideMicroButtonTooltip()
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

local function refreshAfterHookInit()
  -- hook 安装后无条件执行一次统一刷新，消除首次打开时序差异。
  local refreshSuccess, refreshError = pcall(refreshAll) -- 统一刷新执行结果
  if not refreshSuccess and getModuleDb().debug then
    print("Toolbox EncounterJournal post-hook refresh error:", refreshError)
  end
end

local function registerIntegration()
  if eventFrame then return end

  eventFrame = CreateFrame("Frame", "ToolboxEncounterJournalHost")
  eventFrame:RegisterEvent("ADDON_LOADED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("QUEST_TURNED_IN")
  setLockoutUpdateEventEnabled(isModuleEnabled())

  eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then
      self:UnregisterEvent("ADDON_LOADED")
      initHooks()
      refreshAfterHookInit()
      RequestRaidInfo()
    elseif event == "UPDATE_INSTANCE_INFO" then
      refreshAdventureGuideMicroButtonTooltipIfOwned()
      if isModuleEnabled() then
        RefreshScheduler:schedule("lockout_update")
      end
    elseif event == "PLAYER_ENTERING_WORLD" then
      self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      RequestRaidInfo()
      hookAdventureGuideMicroButtonTooltip()
    elseif event == "QUEST_TURNED_IN" then
      local questID = type(name) == "number" and name or nil -- 已完成任务 ID
      if isModuleEnabled() and type(questID) == "number" and questID > 0 then
        QuestlineTreeView:recordRecentlyCompletedQuest(questID)
      end
    end
  end)

  -- 如果 EJ 已加载，立即初始化
  if Runtime.IsAddOnLoaded("Blizzard_EncounterJournal") then
    initHooks()
    refreshAfterHookInit()
  end

  RequestRaidInfo()
end

local function exposeTestHooksIfNeeded()
  local testingEnabled = false -- 是否测试模式
  if type(Runtime.IsTesting) == "function" and Runtime.IsTesting() == true then
    testingEnabled = true
  elseif Runtime.__isTesting == true then
    testingEnabled = true
  end
  if not testingEnabled then
    return
  end

  Toolbox.TestHooks = Toolbox.TestHooks or {} -- 测试 hook 容器
  Toolbox.TestHooks.EncounterJournal = {
    appendAdventureGuideMicroButtonLockoutLines = appendAdventureGuideMicroButtonLockoutLines,
    refreshAdventureGuideMicroButtonTooltipIfOwned = refreshAdventureGuideMicroButtonTooltipIfOwned,
    hookAdventureGuideMicroButtonTooltip = hookAdventureGuideMicroButtonTooltip,
    getEventFrame = function()
      return eventFrame
    end,
    getRefreshScheduler = function()
      return RefreshScheduler
    end,
    getQuestlineTreeView = function()
      return QuestlineTreeView
    end,
    resetInternalState = function()
      if eventFrame and eventFrame.UnregisterEvent then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")
        eventFrame:UnregisterEvent("QUEST_TURNED_IN")
      end
      eventFrame = nil
      microButtonTooltipHooked = false
      hooked = false
      detailInfoOnShowHooked = false
      RefreshScheduler:cancel()
      RefreshScheduler.token = 0
      RefreshScheduler.timer = nil
    end,
  }
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
    exposeTestHooksIfNeeded()
    registerIntegration()
  end,

  OnModuleEnable = function()
    setLockoutUpdateEventEnabled(true)
    DetailEnhancer:refresh()
    QuestlineTreeView:refresh()
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
      QuestlineTreeView:refresh()
    else
      RefreshScheduler:cancel()
      QuestlineTreeView:setSelected(false)
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
    QuestlineTreeView:setSelected(false)
    QuestlineTreeView:refresh()
    MountFilter:syncCheckbox()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  RegisterSettings = function(box)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local moduleDb = getModuleDb() -- 模块存档
    local yOffset = 0 -- 当前纵向游标

    -- 坐骑筛选设置
    local mountFilterCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 坐骑筛选复选框
    mountFilterCheck:SetPoint("TOPLEFT", 20, yOffset)
    mountFilterCheck.Text:SetText(localeTable.DRD_MOUNT_FILTER_ENABLED or "在冒险指南中筛选坐骑")
    mountFilterCheck:SetChecked(moduleDb.mountFilterEnabled ~= false)
    mountFilterCheck:SetScript("OnClick", function(checkButton)
      moduleDb.mountFilterEnabled = checkButton:GetChecked()
      MountFilter:syncCheckbox()
      if type(_G.EncounterJournal_ListInstances) == "function" then
        pcall(_G.EncounterJournal_ListInstances)
      end
    end)
    yOffset = yOffset - 36

    -- CD 叠加设置
    local lockoutOverlayCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- CD 叠加复选框
    lockoutOverlayCheck:SetPoint("TOPLEFT", 20, yOffset)
    lockoutOverlayCheck.Text:SetText(localeTable.EJ_LOCKOUT_OVERLAY_LABEL or "在冒险指南中显示副本 CD")
    lockoutOverlayCheck:SetChecked(moduleDb.lockoutOverlayEnabled ~= false)
    lockoutOverlayCheck:SetScript("OnClick", function(checkButton)
      moduleDb.lockoutOverlayEnabled = checkButton:GetChecked() and true or false
      if moduleDb.lockoutOverlayEnabled == false then
        LockoutOverlay:clearAllFrames()
      end
      RefreshScheduler:schedule("settings_change")
    end)
    yOffset = yOffset - 36

    -- 任务页签设置
    local questlineTreeCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 任务页签总开关
    questlineTreeCheck:SetPoint("TOPLEFT", 20, yOffset)
    questlineTreeCheck.Text:SetText(localeTable.EJ_QUESTLINE_TREE_LABEL or "任务")
    questlineTreeCheck:SetChecked(moduleDb.questlineTreeEnabled ~= false)
    questlineTreeCheck:SetScript("OnClick", function(checkButton)
      moduleDb.questlineTreeEnabled = checkButton:GetChecked() and true or false
      if moduleDb.questlineTreeEnabled ~= true then
        QuestlineTreeView:setSelected(false)
      end
      RefreshScheduler:schedule("settings_change")
    end)
    yOffset = yOffset - 36

    local skinPresetLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 任务页签皮肤标签
    skinPresetLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    skinPresetLabel:SetWidth(168)
    skinPresetLabel:SetJustifyH("LEFT")
    skinPresetLabel:SetText(localeTable.EJ_QUEST_SKIN_STYLE_LABEL or "任务页签皮肤")

    local skinPresetDropdown = CreateFrame("Frame", nil, box, "UIDropDownMenuTemplate") -- 任务页签皮肤下拉
    skinPresetDropdown:SetPoint("TOPLEFT", box, "TOPLEFT", 170, yOffset - 2)
    UIDropDownMenu_SetWidth(skinPresetDropdown, 240)
    UIDropDownMenu_JustifyText(skinPresetDropdown, "LEFT")

    local skinPresetOptions = {
      { value = "default", label = localeTable.EJ_QUEST_SKIN_STYLE_DEFAULT or "接近暴雪原生" },
      { value = "archive", label = localeTable.EJ_QUEST_SKIN_STYLE_ARCHIVE or "古典档案馆（推荐）" },
      { value = "contrast", label = localeTable.EJ_QUEST_SKIN_STYLE_CONTRAST or "高对比" },
    }

    local function normalizeSkinPresetValue(value)
      if value == "default" or value == "archive" or value == "contrast" then
        return value
      end
      return "archive"
    end

    local function getSkinPresetLabel(value)
      local normalizedValue = normalizeSkinPresetValue(value) -- 归一化后的皮肤值
      for _, optionEntry in ipairs(skinPresetOptions) do
        if optionEntry.value == normalizedValue then
          return optionEntry.label
        end
      end
      return normalizedValue
    end

    local function refreshSkinPresetDropdownText()
      moduleDb.questNavSkinPreset = normalizeSkinPresetValue(moduleDb.questNavSkinPreset)
      UIDropDownMenu_SetText(skinPresetDropdown, getSkinPresetLabel(moduleDb.questNavSkinPreset))
    end

    UIDropDownMenu_Initialize(skinPresetDropdown, function(_, level)
      if level and level > 1 then
        return
      end
      for _, optionEntry in ipairs(skinPresetOptions) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = optionEntry.label
        info.func = function()
          moduleDb.questNavSkinPreset = optionEntry.value
          refreshSkinPresetDropdownText()
          QuestlineTreeView:refresh()
          RefreshScheduler:schedule("settings_change")
          CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    refreshSkinPresetDropdownText()
    yOffset = yOffset - 34

    local skinPresetHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 任务页签皮肤说明
    skinPresetHint:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    skinPresetHint:SetWidth(560)
    skinPresetHint:SetJustifyH("LEFT")
    skinPresetHint:SetText(localeTable.EJ_QUEST_SKIN_STYLE_HINT or "仅影响 Toolbox 任务页签自定义界面。")
    yOffset = yOffset - math.max(24, math.ceil((skinPresetHint:GetStringHeight() or 14) + 8))

    local function normalizeRecentCompletedMaxValue(value)
      local normalizedValue = tonumber(value) or 10 -- 归一化后的最近完成上限
      normalizedValue = math.floor(normalizedValue)
      if normalizedValue < 1 then
        normalizedValue = 1
      elseif normalizedValue > 30 then
        normalizedValue = 30
      end
      return normalizedValue
    end

    moduleDb.questRecentCompletedMax = normalizeRecentCompletedMaxValue(moduleDb.questRecentCompletedMax)

    local recentCompletedLimitLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 最近完成数量标签
    recentCompletedLimitLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    recentCompletedLimitLabel:SetText(localeTable.EJ_QUEST_RECENT_COMPLETED_LIMIT_LABEL or "最近完成任务保留条数")
    yOffset = yOffset - 24

    local recentCompletedLimitSlider = nil -- 最近完成数量滑条
    local sliderCreated, sliderObject = pcall(CreateFrame, "Slider", nil, box, "OptionsSliderTemplate")
    if sliderCreated and sliderObject then
      recentCompletedLimitSlider = sliderObject
    else
      recentCompletedLimitSlider = CreateFrame("Slider", nil, box, "UISliderTemplate")
    end
    recentCompletedLimitSlider:SetPoint("TOPLEFT", box, "TOPLEFT", 24, yOffset)
    recentCompletedLimitSlider:SetWidth(220)
    recentCompletedLimitSlider:SetMinMaxValues(1, 30)
    recentCompletedLimitSlider:SetValueStep(1)
    if recentCompletedLimitSlider.SetObeyStepOnDrag then
      recentCompletedLimitSlider:SetObeyStepOnDrag(true)
    end
    if recentCompletedLimitSlider.Low and recentCompletedLimitSlider.Low.SetText then
      recentCompletedLimitSlider.Low:SetText("1")
    end
    if recentCompletedLimitSlider.High and recentCompletedLimitSlider.High.SetText then
      recentCompletedLimitSlider.High:SetText("30")
    end
    if recentCompletedLimitSlider.Text and recentCompletedLimitSlider.Text.SetText then
      recentCompletedLimitSlider.Text:SetText("")
    end

    local recentCompletedLimitValueText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 最近完成数量值
    recentCompletedLimitValueText:SetPoint("LEFT", recentCompletedLimitSlider, "RIGHT", 12, 0)
    recentCompletedLimitValueText:SetJustifyH("LEFT")

    local isSyncingRecentCompletedSlider = false -- 是否正在同步滑条值
    local function refreshRecentCompletedLimitValueText()
      recentCompletedLimitValueText:SetText(tostring(moduleDb.questRecentCompletedMax or 10))
    end
    recentCompletedLimitSlider:SetScript("OnValueChanged", function(slider, rawValue)
      if isSyncingRecentCompletedSlider then
        return
      end
      local normalizedValue = normalizeRecentCompletedMaxValue(rawValue) -- 归一化后的滑条值
      if slider.GetValue and slider:GetValue() ~= normalizedValue then
        isSyncingRecentCompletedSlider = true
        slider:SetValue(normalizedValue)
        isSyncingRecentCompletedSlider = false
      end
      if moduleDb.questRecentCompletedMax ~= normalizedValue then
        moduleDb.questRecentCompletedMax = normalizedValue
        QuestlineTreeView:trimRecentCompletedQuestRecords()
        QuestlineTreeView:refresh()
        RefreshScheduler:schedule("settings_change")
      end
      refreshRecentCompletedLimitValueText()
    end)

    isSyncingRecentCompletedSlider = true
    recentCompletedLimitSlider:SetValue(moduleDb.questRecentCompletedMax)
    isSyncingRecentCompletedSlider = false
    refreshRecentCompletedLimitValueText()
    yOffset = yOffset - 38

    local recentCompletedLimitHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 最近完成数量说明
    recentCompletedLimitHint:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    recentCompletedLimitHint:SetWidth(560)
    recentCompletedLimitHint:SetJustifyH("LEFT")
    recentCompletedLimitHint:SetText(localeTable.EJ_QUEST_RECENT_COMPLETED_LIMIT_HINT or "最近完成任务列表仅记录插件启用后通过交任务事件采集的数据。")
    yOffset = yOffset - math.max(24, math.ceil((recentCompletedLimitHint:GetStringHeight() or 14) + 8))

    yOffset = yOffset - 8

    local rootTabSectionTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 根页签设置标题
    rootTabSectionTitle:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    rootTabSectionTitle:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_TITLE or "冒险指南主页页签排序")
    yOffset = yOffset - 22

    local rootTabSectionHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 根页签设置说明
    rootTabSectionHint:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    rootTabSectionHint:SetWidth(560)
    rootTabSectionHint:SetJustifyH("LEFT")
    rootTabSectionHint:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_HINT or "左键拖动每行可调整顺序。可见性开关会立即生效；隐藏项仍会保留在列表中。")
    yOffset = yOffset - math.max(28, math.ceil((rootTabSectionHint:GetStringHeight() or 16) + 8))

    local rootTabListPanelHeight = 220 -- 页签列表容器高度
    local rootTabListPanel = CreateFrame("Frame", nil, box, "BackdropTemplate") -- 页签列表容器
    rootTabListPanel:SetSize(560, rootTabListPanelHeight)
    rootTabListPanel:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    rootTabListPanel:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    rootTabListPanel:SetBackdropColor(0.06, 0.06, 0.08, 0.65)
    rootTabListPanel:SetBackdropBorderColor(0.24, 0.24, 0.3, 0.9)

    local rootTabListScrollFrame = CreateFrame("ScrollFrame", nil, rootTabListPanel, "UIPanelScrollFrameTemplate") -- 页签列表滚动容器
    rootTabListScrollFrame:SetPoint("TOPLEFT", rootTabListPanel, "TOPLEFT", 8, -8)
    rootTabListScrollFrame:SetPoint("BOTTOMRIGHT", rootTabListPanel, "BOTTOMRIGHT", -28, 8)

    local rootTabListChild = CreateFrame("Frame", nil, rootTabListScrollFrame) -- 页签列表滚动子容器
    rootTabListChild:SetSize(520, 1)
    rootTabListScrollFrame:SetScrollChild(rootTabListChild)

    local rootTabOrderIdsForSettings = buildEffectiveRootTabOrderIds() -- 设置页编辑中的页签顺序
    local rowFrameList = {} -- 设置页行框体列表
    local refreshRootTabRows = nil -- 行重建函数（前向声明）
    local dragPreviewFrame = nil -- 拖拽跟随预览框体
    local dragPreviewText = nil -- 拖拽跟随预览文本

    local function notifyRootTabSettingsChanged()
      QuestlineTreeView:refresh()
      RefreshScheduler:schedule("settings_change")
    end

    local function persistRootTabOrderIds()
      moduleDb.rootTabOrderIds = moduleDb.rootTabOrderIds or {}
      local targetOrderIds = moduleDb.rootTabOrderIds -- 模块存档顺序表
      wipe(targetOrderIds)
      for _, rootTabId in ipairs(rootTabOrderIdsForSettings) do
        targetOrderIds[#targetOrderIds + 1] = rootTabId
      end
    end

    local function clearRootTabRowFrames()
      for _, rowFrame in ipairs(rowFrameList) do
        rowFrame:Hide()
        rowFrame:SetParent(nil)
      end
      wipe(rowFrameList)
      if dragPreviewFrame then
        dragPreviewFrame:Hide()
      end
    end

    local function moveRootTabByIndex(sourceIndex, targetIndex)
      local rowCount = #rootTabOrderIdsForSettings -- 当前行数
      if type(sourceIndex) ~= "number" or type(targetIndex) ~= "number" then
        return
      end
      if sourceIndex < 1 or sourceIndex > rowCount or targetIndex < 1 or targetIndex > rowCount then
        return
      end
      if sourceIndex == targetIndex then
        return
      end
      local movedRootTabId = table.remove(rootTabOrderIdsForSettings, sourceIndex) -- 被移动的页签 ID
      table.insert(rootTabOrderIdsForSettings, targetIndex, movedRootTabId)
      persistRootTabOrderIds()
      if refreshRootTabRows then
        refreshRootTabRows()
      end
      notifyRootTabSettingsChanged()
    end

    local function ensureDragPreviewFrame()
      if dragPreviewFrame then
        return
      end
      dragPreviewFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      dragPreviewFrame:SetSize(180, 28)
      dragPreviewFrame:SetFrameStrata("TOOLTIP")
      dragPreviewFrame:SetFrameLevel(200)
      dragPreviewFrame:EnableMouse(false)
      dragPreviewFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
      })
      dragPreviewFrame:SetBackdropColor(0.1, 0.1, 0.14, 0.72)
      dragPreviewFrame:SetBackdropBorderColor(0.95, 0.82, 0.2, 0.9)

      dragPreviewText = dragPreviewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      dragPreviewText:SetPoint("LEFT", dragPreviewFrame, "LEFT", 8, 0)
      dragPreviewText:SetPoint("RIGHT", dragPreviewFrame, "RIGHT", -8, 0)
      dragPreviewText:SetJustifyH("LEFT")
      dragPreviewText:SetWordWrap(false)
      dragPreviewFrame:Hide()
    end

    local function updateDragPreviewPosition()
      if not dragPreviewFrame or not dragPreviewFrame.IsShown or not dragPreviewFrame:IsShown() then
        return
      end
      local parentScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1 -- UIParent 缩放
      if type(parentScale) ~= "number" or parentScale <= 0 then
        parentScale = 1
      end
      local cursorPosX, cursorPosY = GetCursorPosition() -- 当前鼠标位置
      local anchorX = (cursorPosX / parentScale) + 14 -- 预览框锚点 X
      local anchorY = (cursorPosY / parentScale) - 10 -- 预览框锚点 Y
      dragPreviewFrame:ClearAllPoints()
      dragPreviewFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", anchorX, anchorY)
    end

    local function showDragPreview(labelText)
      ensureDragPreviewFrame()
      local safeLabelText = type(labelText) == "string" and labelText or "" -- 预览显示文本
      dragPreviewText:SetText(safeLabelText)
      local textWidth = dragPreviewText.GetStringWidth and dragPreviewText:GetStringWidth() or 120 -- 文本宽度
      dragPreviewFrame:SetWidth(math.max(140, math.min(360, textWidth + 20)))
      dragPreviewFrame:SetAlpha(0.72)
      dragPreviewFrame:Show()
      updateDragPreviewPosition()
    end

    local function hideDragPreview()
      if dragPreviewFrame then
        dragPreviewFrame:Hide()
      end
    end

    refreshRootTabRows = function()
      clearRootTabRowFrames()

      local rowHeight = 28 -- 单行高度
      local rowGap = 6 -- 行间距
      local displayNameById = QuestlineTreeView:buildRootTabDisplayNameById(rootTabOrderIdsForSettings) -- 页签名映射
      local rootTabHiddenIds = getRootTabHiddenIdsTable() -- 页签隐藏配置

      for rowIndex, rootTabId in ipairs(rootTabOrderIdsForSettings) do
        local currentRowIndex = rowIndex -- 当前行索引（用于闭包捕获）
        local currentRootTabId = rootTabId -- 当前行页签 ID（用于闭包捕获）
        local rowFrame = CreateFrame("Button", nil, rootTabListChild, "BackdropTemplate") -- 页签设置行
        rowFrame:SetSize(516, rowHeight)
        rowFrame:SetPoint("TOPLEFT", rootTabListChild, "TOPLEFT", 0, -((currentRowIndex - 1) * (rowHeight + rowGap)))
        rowFrame:SetBackdrop({
          bgFile = "Interface\\Buttons\\WHITE8X8",
          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
          tile = true,
          tileSize = 8,
          edgeSize = 8,
          insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        rowFrame:SetBackdropColor(0.1, 0.1, 0.14, 0.55)
        rowFrame:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.65)
        rowFrame:RegisterForDrag("LeftButton")
        rowFrame:RegisterForClicks("LeftButtonDown")

        local dragHandleText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 拖拽手柄文案
        dragHandleText:SetPoint("LEFT", rowFrame, "LEFT", 8, 0)
        dragHandleText:SetText("|||")

        local rowNameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 页签名称文本
        rowNameText:SetPoint("LEFT", rowFrame, "LEFT", 28, 0)
        rowNameText:SetPoint("RIGHT", rowFrame, "RIGHT", -138, 0)
        rowNameText:SetJustifyH("LEFT")
        rowNameText:SetWordWrap(false)
        rowNameText:SetText(displayNameById[currentRootTabId] or tostring(currentRootTabId))

        local visibleCheck = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate") -- 可见性复选框
        visibleCheck:SetPoint("RIGHT", rowFrame, "RIGHT", -112, 0)
        if visibleCheck.Text and visibleCheck.Text.SetText then
          visibleCheck.Text:SetText("")
        end
        visibleCheck:SetChecked(rootTabHiddenIds[currentRootTabId] ~= true)
        visibleCheck:SetScript("OnClick", function(checkButton)
          local visibleChecked = checkButton:GetChecked() == true -- 目标可见性
          rootTabHiddenIds[currentRootTabId] = visibleChecked and nil or true
          notifyRootTabSettingsChanged()
        end)

        local visibleLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 显示开关标签
        visibleLabel:SetPoint("LEFT", visibleCheck, "RIGHT", 0, 0)
        visibleLabel:SetWidth(24)
        visibleLabel:SetJustifyH("LEFT")
        visibleLabel:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_VISIBLE or "显")

        local moveUpButton = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate") -- 上移按钮
        moveUpButton:SetSize(36, 20)
        moveUpButton:SetPoint("RIGHT", rowFrame, "RIGHT", -44, 0)
        moveUpButton:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_MOVE_UP or "Up")
        moveUpButton:SetScript("OnClick", function()
          moveRootTabByIndex(currentRowIndex, currentRowIndex - 1)
        end)

        local moveDownButton = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate") -- 下移按钮
        moveDownButton:SetSize(36, 20)
        moveDownButton:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        moveDownButton:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_MOVE_DOWN or "Dn")
        moveDownButton:SetScript("OnClick", function()
          moveRootTabByIndex(currentRowIndex, currentRowIndex + 1)
        end)

        local function resolveDropRowIndex()
          local childTop = rootTabListChild:GetTop() -- 列表子容器顶部坐标
          local childScale = rootTabListChild:GetEffectiveScale() or 1 -- 列表子容器缩放
          local scrollOffset = rootTabListScrollFrame.GetVerticalScroll and rootTabListScrollFrame:GetVerticalScroll() or 0 -- 当前滚动偏移
          local _, cursorY = GetCursorPosition()
          if type(childTop) ~= "number" or type(cursorY) ~= "number" or childScale <= 0 then
            return nil
          end
          local localOffsetY = (childTop - (cursorY / childScale)) + (scrollOffset or 0) -- 光标相对列表顶部偏移
          local estimatedIndex = math.floor((localOffsetY + rowGap) / (rowHeight + rowGap)) + 1 -- 估算落点行号
          if estimatedIndex < 1 then
            estimatedIndex = 1
          end
          if estimatedIndex > #rootTabOrderIdsForSettings then
            estimatedIndex = #rootTabOrderIdsForSettings
          end
          return estimatedIndex
        end

        rowFrame:SetScript("OnMouseDown", function(dragRowFrame, mouseButton)
          if mouseButton ~= "LeftButton" then
            return
          end
          if visibleCheck:IsMouseOver() or moveUpButton:IsMouseOver() or moveDownButton:IsMouseOver() then
            return
          end
          dragRowFrame._toolboxDragSourceIndex = currentRowIndex
          dragRowFrame:SetAlpha(0.45)
          dragRowFrame:SetBackdropBorderColor(0.95, 0.82, 0.2, 0.95)
          showDragPreview(rowNameText:GetText())
          dragRowFrame:SetScript("OnUpdate", function(updateFrame)
            if IsMouseButtonDown("LeftButton") then
              updateDragPreviewPosition()
              return
            end
            updateFrame:SetScript("OnUpdate", nil)
            updateFrame:SetAlpha(1)
            updateFrame:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.65)
            hideDragPreview()
            local sourceIndex = updateFrame._toolboxDragSourceIndex -- 拖拽源索引
            updateFrame._toolboxDragSourceIndex = nil
            local dropRowIndex = resolveDropRowIndex() -- 拖拽落点索引
            if type(sourceIndex) == "number"
              and type(dropRowIndex) == "number"
              and dropRowIndex ~= sourceIndex
            then
              moveRootTabByIndex(sourceIndex, dropRowIndex)
            end
          end)
        end)

        rowFrameList[#rowFrameList + 1] = rowFrame
      end

      local listHeight = #rootTabOrderIdsForSettings * (rowHeight + rowGap) -- 列表总高度
      rootTabListChild:SetSize(520, math.max(1, listHeight))
    end

    refreshRootTabRows()

    yOffset = yOffset - rootTabListPanelHeight - 12

    local resetRootTabOrderButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate") -- 恢复默认顺序按钮
    resetRootTabOrderButton:SetSize(180, 22)
    resetRootTabOrderButton:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
    resetRootTabOrderButton:SetText(localeTable.EJ_ROOT_TAB_SETTINGS_RESET_ORDER or "恢复默认顺序")
    resetRootTabOrderButton:SetScript("OnClick", function()
      local defaultOrderIds = buildDefaultRootTabOrderIds() -- 当前客户端可用的默认顺序
      local defaultTabIdSet = {} -- 默认页签 ID 集合
      local extraTabIdList = {} -- 非默认页签 ID 列表
      for _, defaultRootTabId in ipairs(defaultOrderIds) do
        defaultTabIdSet[defaultRootTabId] = true
      end
      for _, rootTabId in ipairs(rootTabOrderIdsForSettings) do
        if not defaultTabIdSet[rootTabId] then
          extraTabIdList[#extraTabIdList + 1] = rootTabId
        end
      end
      wipe(rootTabOrderIdsForSettings)
      for _, defaultRootTabId in ipairs(defaultOrderIds) do
        rootTabOrderIdsForSettings[#rootTabOrderIdsForSettings + 1] = defaultRootTabId
      end
      for _, extraRootTabId in ipairs(extraTabIdList) do
        rootTabOrderIdsForSettings[#rootTabOrderIdsForSettings + 1] = extraRootTabId
      end
      persistRootTabOrderIds()
      refreshRootTabRows()
      notifyRootTabSettingsChanged()
    end)

    yOffset = yOffset - 30

    box.realHeight = math.abs(yOffset) + 8
  end,
})
