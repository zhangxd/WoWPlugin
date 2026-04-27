--[[
  鍐掗櫓鎸囧崡澧炲己妯″潡锛坋ncounter_journal锛夈€?
  鏈枃浠朵粎淇濈暀妯″潡娉ㄥ唽銆佷簨浠跺叆鍙ｃ€佽皟搴﹀櫒涓庤缃〉绛夌粍瑁呭眰閫昏緫銆?
  鍏蜂綋瀹炵幇宸叉媶鍒嗗埌 Modules/EncounterJournal/*.lua 绉佹湁鏂囦欢銆?
]]

local Internal = Toolbox.EncounterJournalInternal -- 鍐掗櫓鎸囧崡鍐呴儴鍛藉悕绌洪棿
local MODULE_ID = Internal.MODULE_ID
local Runtime = Internal.Runtime
local CreateFrame = Internal.CreateFrame
local microTooltipAppendState = Internal.microTooltipAppendState
local scrollBoxCache = Internal.scrollBoxCache

local MountFilter = Internal.MountFilter
local DetailEnhancer = Internal.DetailEnhancer
local LockoutOverlay = Internal.LockoutOverlay
local ListNavigationPin = Internal.ListNavigationPin

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
  LockoutOverlay = Internal.LockoutOverlay
  ListNavigationPin = Internal.ListNavigationPin
  MountFilter:createUI()
  DetailEnhancer:refresh()
  MountFilter:updateVisibility()
  MountFilter:applyFilter()
  ListNavigationPin:updateFrames()
  LockoutOverlay:updateFrames()
  LockoutOverlay:hookTooltips()
end

-- ============================================================================
-- 寰瀷鑿滃崟銆屽啋闄╂墜鍐屻€嶆寜閽?Tooltip 澧炶ˉ锛堝彸涓嬭鑿滃崟鎺掞級
-- ============================================================================

local microButtonTooltipHooked = false

--- 鑾峰彇鍐掗櫓鎵嬪唽寰瀷鑿滃崟鎸夐挳锛圧etail 涓昏矾寰勪负 EJMicroButton锛屾棫鍚嶄粎浣滃厹搴曪級銆?
---@return Button|nil
local function getAdventureGuideMicroButton()
  local microButton = _G.EJMicroButton -- Retail 寰瀷鑿滃崟鎸夐挳鍏ㄥ眬鍚?
  if not microButton then
    microButton = _G.EncounterJournalMicroButton -- 鍘嗗彶鍛藉悕鍏滃簳
  end
  return microButton
end

--- 鍚戝綋鍓嶅啋闄╂墜鍐屽井鍨嬫寜閽?tooltip 杩藉姞鍓湰 CD 鎽樿锛堝甫涓€娆℃偓鍋滃幓閲嶏級銆?
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

  local localeTable = Toolbox.L or {} -- 鏈湴鍖栧瓧绗︿覆琛?
  local sectionTitle = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE or "Current lockouts" -- 鏍囬鏂囨
  local emptyText = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_EMPTY or "No saved instance lockouts." -- 绌烘€佹枃妗?
  local moreFormat = localeTable.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_MORE_FMT or "+%d more..." -- 婧㈠嚭璁℃暟鏂囨

  Runtime.TooltipAddLine(GameTooltip, " ")
  Runtime.TooltipAddLine(GameTooltip, sectionTitle, 1, 0.82, 0.2)

  if not Toolbox.EJ or type(Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines) ~= "function" then
    Runtime.TooltipAddLine(GameTooltip, emptyText, 0.75, 0.75, 0.75, true)
    return
  end

  local lineList, overflowCount = Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(8) -- 閿佸畾鎽樿琛屼笌婧㈠嚭鏁伴噺
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

--- 鑻ュ綋鍓?tooltip 姝ｅ湪鏄剧ず鍐掗櫓鎵嬪唽寰瀷鎸夐挳鎻愮ず锛屽垯閲嶅缓涓€娆★紙鐢ㄤ簬 UPDATE_INSTANCE_INFO 鍥炲埛锛夈€?
local function refreshAdventureGuideMicroButtonTooltipIfOwned()
  local microButton = getAdventureGuideMicroButton() -- 鍐掗櫓鎵嬪唽寰瀷鑿滃崟鎸夐挳
  if not microButton then
    return
  end
  if not GameTooltip or not GameTooltip.IsOwned or not GameTooltip:IsOwned(microButton) then
    return
  end
  if GameTooltip then
    microTooltipAppendState[GameTooltip] = nil
  end
  local onEnterHandler = microButton.GetScript and microButton:GetScript("OnEnter") -- 寰瀷鎸夐挳 OnEnter 鑴氭湰
  if type(onEnterHandler) == "function" then
    pcall(onEnterHandler, microButton)
    appendAdventureGuideMicroButtonLockoutLines()
    Runtime.TooltipShow(GameTooltip)
    return
  end
  appendAdventureGuideMicroButtonLockoutLines()
  Runtime.TooltipShow(GameTooltip)
end

--- 鍦ㄥ彸涓嬭寰瀷鑿滃崟鐨勫啋闄╂墜鍐屾寜閽?tooltip 鏈熬杩藉姞褰撳墠瑙掕壊鍓湰 CD 鎽樿銆?
local function hookAdventureGuideMicroButtonTooltip()
  local microButton = getAdventureGuideMicroButton() -- 鍐掗櫓鎵嬪唽寰瀷鑿滃崟鎸夐挳
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

--- 鍒锋柊璋冨害鍣紙闃叉姈锛?
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
  local currentToken = self.token -- 褰撳墠璋冨害浠ょ墝

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

  local afterScheduled = false -- 寤舵椂浠诲姟鏄惁宸茶皟搴?
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

--- Hook 绠＄悊鍣紙鍙?Hook 涓€娆★級
local hooked = false
local detailInfoOnShowHooked = false

local function hookDetailInfoOnShow()
  if detailInfoOnShowHooked then
    return
  end
  local infoFrame = getEncounterInfoFrame() -- 璇︽儏淇℃伅闈㈡澘
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

  -- Hook 1: 鍒楄〃鍒锋柊
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

  -- Hook 1.5: 璇︽儏椤垫垬鍒╁搧鏇存柊锛堢敤浜庘€滀粎鍧愰獞鈥濈瓫閫夛級
  if hooksecurefunc and type(_G.EncounterJournal_LootUpdate) == "function" then
    pcall(function()
      hooksecurefunc("EncounterJournal_LootUpdate", function()
        RefreshScheduler:schedule("detail_loot_update")
      end)
    end)
  end

  -- Hook 2: 鏍囩鍒囨崲锛堢敤浜庡埛鏂板垪琛ㄧ紦瀛橈級
  if hooksecurefunc and type(_G.EJ_ContentTab_Select) == "function" then
    pcall(function()
      hooksecurefunc("EJ_ContentTab_Select", function()
        Runtime.After(0, function()
          scrollBoxCache.ref = nil
          scrollBoxCache.lastUpdate = 0
          RefreshScheduler:schedule("tab_change")
        end)
      end)
    end)
  end

  -- Hook 2.5: 璇︽儏椤靛垏鎹㈠疄渚?棣栭
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

  -- Hook 2.6: 鍙充晶闅惧害鍒囨崲锛堟爣棰樺悗鈥滈噸缃細xxxx鈥濋渶涓庡綋鍓嶉毦搴﹀尮閰嶏級
  if hooksecurefunc and type(_G.EJ_SetDifficulty) == "function" then
    pcall(function()
      hooksecurefunc("EJ_SetDifficulty", function()
        RefreshScheduler:schedule("detail_difficulty")
      end)
    end)
  end

  -- Hook 3: 涓绘鏋舵樉绀?
  local ej = _G.EncounterJournal
  if ej and ej.HookScript then
    pcall(function()
      ej:HookScript("OnShow", function()
        RequestRaidInfo()
        hookDetailInfoOnShow()
        -- 椤电椤哄簭/鏄鹃殣鍦?OnShow 褰撳抚鍏堝簲鐢紝閬垮厤棣栧抚鍑虹幇榛樿椤哄簭闂儊銆?
        if isModuleEnabled() then
          MountFilter:createUI()
          MountFilter:updateVisibility()
        end
        RefreshScheduler:schedule("frame_show")
      end)
    end)
  end

  hookDetailInfoOnShow()

  -- Hook 4: 鍙充笅瑙掑井鍨嬭彍鍗曠殑鍐掗櫓鎵嬪唽鎸夐挳 tooltip
  hookAdventureGuideMicroButtonTooltip()
end

--- 浜嬩欢绠＄悊鍣?
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
  -- hook 瀹夎鍚庢棤鏉′欢鎵ц涓€娆＄粺涓€鍒锋柊锛屾秷闄ら娆℃墦寮€鏃跺簭宸紓銆?
  local refreshSuccess, refreshError = pcall(refreshAll) -- 缁熶竴鍒锋柊鎵ц缁撴灉
  if not refreshSuccess and getModuleDb().debug then
    print("Toolbox EncounterJournal post-hook refresh error:", refreshError)
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
    end
  end)

  -- 若 EJ 已加载，提前注销一次性 ADDON_LOADED 监听，避免常驻。
  if Runtime.IsAddOnLoaded("Blizzard_EncounterJournal") then
    eventFrame:UnregisterEvent("ADDON_LOADED")
  end

  -- 濡傛灉 EJ 宸插姞杞斤紝绔嬪嵆鍒濆鍖?
  if Runtime.IsAddOnLoaded("Blizzard_EncounterJournal") then
    initHooks()
    refreshAfterHookInit()
  end

  RequestRaidInfo()
end

local function exposeTestHooksIfNeeded()
  local testingEnabled = false -- 鏄惁娴嬭瘯妯″紡
  if type(Runtime.IsTesting) == "function" and Runtime.IsTesting() == true then
    testingEnabled = true
  elseif Runtime.__isTesting == true then
    testingEnabled = true
  end
  if not testingEnabled then
    return
  end

  Toolbox.TestHooks = Toolbox.TestHooks or {} -- 娴嬭瘯 hook 瀹瑰櫒
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
    resetInternalState = function()
      if eventFrame and eventFrame.UnregisterEvent then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")
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
-- 妯″潡娉ㄥ唽
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
    MountFilter:syncCheckbox()
    ListNavigationPin:updateFrames()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  OnEnabledSettingChanged = function(enabled)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local msgKey = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT" -- 提示键
    Toolbox.Chat.PrintAddonMessage(string.format(localeTable[msgKey] or "%s", localeTable.MODULE_ENCOUNTER_JOURNAL or MODULE_ID))
    setLockoutUpdateEventEnabled(enabled)
    if enabled then
      RequestRaidInfo()
      DetailEnhancer:refresh()
    else
      RefreshScheduler:cancel()
      ListNavigationPin:clearInteractionState()
      LockoutOverlay:clearAllFrames()
      ListNavigationPin:clearAllFrames()
    end
    MountFilter:syncCheckbox()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
    ListNavigationPin:clearInteractionState()
    DetailEnhancer:refresh()
    MountFilter:syncCheckbox()
    ListNavigationPin:updateFrames()
    if type(_G.EncounterJournal_ListInstances) == "function" then
      pcall(_G.EncounterJournal_ListInstances)
    end
  end,

  RegisterSettings = function(box)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local moduleDb = getModuleDb() -- 模块存档
    local yOffset = 0 -- 当前纵向游标

    local mountFilterCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 坐骑筛选开关
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

    local lockoutOverlayCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 锁定叠加开关
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

    local pinAlwaysVisibleCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 图钉常驻显示开关
    pinAlwaysVisibleCheck:SetPoint("TOPLEFT", 20, yOffset)
    pinAlwaysVisibleCheck.Text:SetText(localeTable.EJ_LIST_PIN_ALWAYS_VISIBLE_LABEL or "定位图标常驻显示")
    pinAlwaysVisibleCheck:SetChecked(moduleDb.listPinAlwaysVisible == true)
    pinAlwaysVisibleCheck:SetScript("OnClick", function(checkButton)
      moduleDb.listPinAlwaysVisible = checkButton:GetChecked() and true or false
      ListNavigationPin:updateFrames()
    end)
    yOffset = yOffset - 36

    local detailMountOnlyCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 详情页仅坐骑开关
    detailMountOnlyCheck:SetPoint("TOPLEFT", 20, yOffset)
    detailMountOnlyCheck.Text:SetText(localeTable.EJ_DETAIL_MOUNT_ONLY_LABEL or "详情页仅显示坐骑")
    detailMountOnlyCheck:SetChecked(moduleDb.detailMountOnlyEnabled == true)
    detailMountOnlyCheck:SetScript("OnClick", function(checkButton)
      moduleDb.detailMountOnlyEnabled = checkButton:GetChecked() and true or false
      DetailEnhancer:refresh()
    end)
    yOffset = yOffset - 36

    box.realHeight = math.abs(yOffset) + 12
  end,
})
