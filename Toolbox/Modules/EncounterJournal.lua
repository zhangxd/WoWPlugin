--[[
  冒险指南增强模块（encounter_journal）。
  功能：
    1. 「仅坐骑」复选框筛选：post-hook EncounterJournal_ListInstances，从 DataProvider 移除不含坐骑的条目。
    2. 副本 CD 叠加显示：列表条目内嵌剩余重置时间；鼠标悬停 tooltip 显示首领进度详情。
    3. 详情页任务页签：在冒险手册详情页内显示离线任务线树（与 EJ 副本 ID 解耦）。
  数据来源：
    - 坐骑掉落：Toolbox.Data.MountDrops（Data/InstanceDrops_Mount.lua）
    - 锁定查询：Toolbox.EJ.GetAllLockoutsForInstance / GetKilledBosses（Core/EncounterJournal.lua）
    - 任务树：Toolbox.Questlines.GetQuestTabModel（Core/API/QuestlineProgress.lua）
  存档键：ToolboxDB.modules.encounter_journal
]]

local MODULE_ID = "encounter_journal"
local Runtime = Toolbox.Runtime -- 运行时适配入口
local CreateFrame = Runtime.CreateFrame -- Frame 创建函数
local microTooltipAppendState = setmetatable({}, { __mode = "k" }) -- tooltip 追加状态表

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

local function isQuestlineTreeEnabled()
  local moduleDb = getModuleDb() -- 模块存档
  return isModuleEnabled() and moduleDb.questlineTreeEnabled ~= false
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
  local instId = elementData.instanceID or elementData.journalInstanceID
  if type(instId) == "number" then return instId end
  local nested = elementData.data or elementData.elementData or elementData.node
  if type(nested) == "table" and nested ~= elementData then
    local nestedId = nested.instanceID or nested.journalInstanceID
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

local function getDetailLootContainer()
  local info = getEncounterInfoFrame()
  if not info then
    return nil
  end
  return info.LootContainer or info.lootContainer
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
    if Toolbox.Tooltip and Toolbox.Tooltip.SetSkipAnchorOverride then
      Toolbox.Tooltip.SetSkipAnchorOverride(GameTooltip, true)
    end
    Runtime.TooltipSetOwner(GameTooltip, btn, "ANCHOR_RIGHT")
    Runtime.TooltipClear(GameTooltip)
    Runtime.TooltipSetText(GameTooltip, loc.EJ_DETAIL_MOUNT_ONLY_LABEL or "")
    Runtime.TooltipAddLine(GameTooltip, loc.EJ_DETAIL_MOUNT_ONLY_HINT or "", 1, 1, 1, true)
    Runtime.TooltipShow(GameTooltip)
  end)
  check:SetScript("OnLeave", function()
    if Toolbox.Tooltip and Toolbox.Tooltip.SetSkipAnchorOverride then
      Toolbox.Tooltip.SetSkipAnchorOverride(GameTooltip, false)
    end
    Runtime.TooltipHide(GameTooltip)
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
-- 任务页签视图（冒险手册主页底部内容页签层级）
-- ============================================================================

local QuestlineTreeView = {
  tabButton = nil,
  panelFrame = nil,
  headerFrame = nil,
  contentFrame = nil,
  leftTree = nil,
  rightContent = nil,
  scrollFrame = nil,
  scrollChild = nil,
  emptyText = nil,
  rowButtons = {},
  rightScrollFrame = nil,
  rightScrollChild = nil,
  rightRowButtons = {},
  rightTitle = nil,
  detailText = nil,
  rowHeight = 18,
  selected = false,
  selectedExpansionID = nil,
  selectedModeKey = "map_questline",
  selectedMapID = nil,
  selectedTypeKey = "",
  expandedQuestLineID = nil,
  selectedQuestID = nil,
  hostJournalFrame = nil,
  hookedNativeTabs = setmetatable({}, {__mode = "k"}),
  wasShowingPanel = false,
  activeRootState = "native",
  nativeTabBeforeQuest = nil,
  pendingNativeSelection = false,
}

local function getQuestlineCollapsedTable()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.questlineTreeCollapsed) ~= "table" then
    moduleDb.questlineTreeCollapsed = {}
  end
  return moduleDb.questlineTreeCollapsed
end

local QUEST_ROOT_TAB_ID = 203 -- 任务根页签 ID（自定义）
local DUNGEON_ROOT_TAB_ID = 4 -- 地下城根页签 ID
local RAID_ROOT_TAB_ID = 5 -- 团队副本根页签 ID

local buildDefaultRootTabOrderIds -- 默认根页签顺序构建函数（前向声明）

local function getRootTabHiddenIdsTable()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.rootTabHiddenIds) ~= "table" then
    moduleDb.rootTabHiddenIds = {}
  end
  return moduleDb.rootTabHiddenIds
end

local function getConfiguredRootTabOrderIds()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.rootTabOrderIds) ~= "table" then
    moduleDb.rootTabOrderIds = {}
  end
  return moduleDb.rootTabOrderIds
end

local function buildEffectiveRootTabOrderIds()
  local configuredOrderIds = getConfiguredRootTabOrderIds() -- 用户配置的顺序（ID）
  local defaultOrderIds = buildDefaultRootTabOrderIds and buildDefaultRootTabOrderIds() or {} -- 运行时默认顺序（ID）
  local effectiveOrderIds = {} -- 生效顺序结果（ID）
  local addedTabIdSet = {} -- 去重记录

  for _, rawTabId in ipairs(configuredOrderIds) do
    local normalizedTabId = tonumber(rawTabId) -- 规范化后的页签 ID
    if type(normalizedTabId) == "number" and normalizedTabId > 0 and not addedTabIdSet[normalizedTabId] then
      effectiveOrderIds[#effectiveOrderIds + 1] = normalizedTabId
      addedTabIdSet[normalizedTabId] = true
    end
  end

  for _, defaultTabId in ipairs(defaultOrderIds) do
    if not addedTabIdSet[defaultTabId] then
      effectiveOrderIds[#effectiveOrderIds + 1] = defaultTabId
      addedTabIdSet[defaultTabId] = true
    end
  end

  if not addedTabIdSet[QUEST_ROOT_TAB_ID] then
    effectiveOrderIds[#effectiveOrderIds + 1] = QUEST_ROOT_TAB_ID
    addedTabIdSet[QUEST_ROOT_TAB_ID] = true
  end

  return effectiveOrderIds
end

local function ensureEncounterJournalAddonLoaded()
  local addonName = "Blizzard_EncounterJournal" -- 冒险手册插件名
  if Runtime.IsAddOnLoaded(addonName) then
    return true
  end
  if Runtime.LoadAddOn(addonName) then
    return true
  end
  return _G.EncounterJournal ~= nil
end

buildDefaultRootTabOrderIds = function()
  ensureEncounterJournalAddonLoaded()

  local defaultOrderIds = {} -- 默认顺序（按 ID）
  local addedTabIdSet = {} -- 已纳入默认顺序的页签 ID 集合
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  local nativeTabs = journalFrame and journalFrame.Tabs -- 原生根页签数组

  local function appendTabId(rootTabId)
    if type(rootTabId) ~= "number" or rootTabId <= 0 then
      return
    end
    if rootTabId == QUEST_ROOT_TAB_ID or addedTabIdSet[rootTabId] then
      return
    end
    defaultOrderIds[#defaultOrderIds + 1] = rootTabId
    addedTabIdSet[rootTabId] = true
  end

  if type(nativeTabs) == "table" then
    for _, rootTabButton in ipairs(nativeTabs) do
      if rootTabButton and rootTabButton.GetID then
        appendTabId(rootTabButton:GetID())
      end
    end
  end

  if #defaultOrderIds == 0 then
    return { QUEST_ROOT_TAB_ID }
  end

  local questInsertAfterIndex = nil -- 任务页签插入基准索引
  for orderIndex, rootTabId in ipairs(defaultOrderIds) do
    if rootTabId == RAID_ROOT_TAB_ID then
      questInsertAfterIndex = orderIndex
      break
    end
  end
  if type(questInsertAfterIndex) ~= "number" then
    for orderIndex, rootTabId in ipairs(defaultOrderIds) do
      if rootTabId == DUNGEON_ROOT_TAB_ID then
        questInsertAfterIndex = orderIndex
        break
      end
    end
  end

  if type(questInsertAfterIndex) == "number" then
    table.insert(defaultOrderIds, questInsertAfterIndex + 1, QUEST_ROOT_TAB_ID)
  else
    defaultOrderIds[#defaultOrderIds + 1] = QUEST_ROOT_TAB_ID
  end

  return defaultOrderIds
end

local function getRootTabFallbackName(rootTabId)
  local localeTable = Toolbox.L or {} -- 本地化文案
  if rootTabId == QUEST_ROOT_TAB_ID then
    return localeTable.EJ_QUESTLINE_TREE_LABEL or "任务"
  end
  local unknownFormat = localeTable.EJ_ROOT_TAB_NAME_UNKNOWN_FMT or "Tab #%d" -- 未解析页签名格式
  if type(rootTabId) == "number" then
    return string.format(unknownFormat, rootTabId)
  end
  return tostring(rootTabId or "")
end

local function formatQuestStatusPrefix(statusText)
  if statusText == "completed" then
    return "✓"
  end
  if statusText == "active" then
    return "▶"
  end
  return "○"
end

local function getQuestStatusTextColor(statusText)
  if statusText == "completed" then
    return 0.2, 0.8, 0.2
  end
  return nil
end

local function ensureSelectionTable()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.questlineTreeSelection) ~= "table" then
    moduleDb.questlineTreeSelection = {}
  end
  return moduleDb.questlineTreeSelection
end

local function normalizeSelectionID(value)
  if type(value) == "number" and value > 0 then
    return value
  end
  return nil
end

local collectStatusQuestEntries = nil -- 状态视图当前任务集合构造器
local findStatusQuestEntryByID = nil -- 状态视图任务查询器

local function getCurrentPlayerMapID()
  if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then
    return nil
  end
  local success, mapID = pcall(C_Map.GetBestMapForUnit, "player") -- 当前角色所在地图
  if success and type(mapID) == "number" and mapID > 0 then
    return mapID
  end
  return nil
end

local function listContainsNumber(valueList, targetValue)
  if type(valueList) ~= "table" or type(targetValue) ~= "number" then
    return false
  end
  for _, value in ipairs(valueList) do
    if value == targetValue then
      return true
    end
  end
  return false
end

local function isTreeNodeCollapsed(collapseState, collapseKey)
  if type(collapseState) ~= "table" or type(collapseKey) ~= "string" then
    return true
  end
  return collapseState[collapseKey] ~= false
end

local function setTreeNodeCollapsed(collapseState, collapseKey, collapsed)
  if type(collapseState) ~= "table" or type(collapseKey) ~= "string" then
    return
  end
  collapseState[collapseKey] = collapsed == true
end

--- 读取滚动框当前垂直偏移
---@param scrollFrame table|nil 滚动框
---@return number scrollOffset 当前滚动偏移
local function readVerticalScrollOffset(scrollFrame)
  if not scrollFrame or type(scrollFrame.GetVerticalScroll) ~= "function" then
    return 0
  end

  local scrollOffset = tonumber(scrollFrame:GetVerticalScroll()) or 0 -- 当前垂直偏移
  return math.max(0, scrollOffset)
end

--- 在重排内容后恢复滚动位置，并按内容高度裁剪边界
---@param scrollFrame table|nil 滚动框
---@param scrollOffset number 期望恢复的偏移
---@param contentHeight number 当前内容高度
local function restoreVerticalScrollOffset(scrollFrame, scrollOffset, contentHeight)
  if not scrollFrame or type(scrollFrame.SetVerticalScroll) ~= "function" then
    return
  end

  local restoredOffset = math.max(0, tonumber(scrollOffset) or 0) -- 归一化后的滚动偏移
  local frameHeight = type(scrollFrame.GetHeight) == "function" and tonumber(scrollFrame:GetHeight()) or nil -- 滚动框高度
  local normalizedContentHeight = tonumber(contentHeight) or 0 -- 内容总高度
  if type(frameHeight) == "number" and frameHeight > 0 and normalizedContentHeight > frameHeight then
    local maxOffset = math.max(0, normalizedContentHeight - frameHeight) -- 当前内容允许的最大偏移
    restoredOffset = math.min(restoredOffset, maxOffset)
  end

  scrollFrame:SetVerticalScroll(restoredOffset)
end

local function formatProgressText(progressInfo, localeTable)
  if type(progressInfo) ~= "table" then
    return nil
  end
  return string.format(
    localeTable.EJ_QUESTLINE_PROGRESS_FMT or "%d/%d",
    progressInfo.completed or 0,
    progressInfo.total or 0
  )
end

local function resolveQuestLineDisplayName(questLineEntry)
  if type(questLineEntry) ~= "table" then
    return nil
  end

  local questLineID = type(questLineEntry.id) == "number" and questLineEntry.id or nil -- 当前任务线 ID
  if type(questLineID) == "number"
    and Toolbox.Questlines
    and type(Toolbox.Questlines.GetQuestLineDisplayName) == "function"
  then
    local displayName, errorObject = Toolbox.Questlines.GetQuestLineDisplayName(questLineID) -- 任务线显示名
    if not errorObject and type(displayName) == "string" and displayName ~= "" then
      return displayName
    end
  end

  if type(questLineEntry.name) == "string" and questLineEntry.name ~= "" then
    return questLineEntry.name
  end
  return nil
end


function QuestlineTreeView:syncTabLabel()
  if not self.tabButton or not self.tabButton.SetText then
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  self.tabButton:SetText(localeTable.EJ_QUESTLINE_TREE_LABEL or "任务")
  if type(PanelTemplates_TabResize) == "function" then
    pcall(PanelTemplates_TabResize, self.tabButton, 0)
  end
  if self.tabButton.Text and self.tabButton.Text.SetPoint then
    self.tabButton.Text:ClearAllPoints()
    self.tabButton.Text:SetPoint("CENTER", self.tabButton, "CENTER", 0, -1)
  end
end


function QuestlineTreeView:hookVanillaTabsOnce()
  if not self.hostJournalFrame then
    return
  end
  local nativeTabList = self:getNativeRootTabs(true) -- 原生根页签列表（含隐藏）
  for _, childButton in ipairs(nativeTabList) do
    if childButton ~= self.tabButton
      and childButton
      and childButton.GetObjectType
      and childButton:GetObjectType() == "Button"
      and childButton.GetID
      and type(childButton:GetID()) == "number"
      and childButton.HookScript
      and not self.hookedNativeTabs[childButton]
    then
      self.hookedNativeTabs[childButton] = true
      childButton:HookScript("OnClick", function()
        self.pendingNativeSelection = true
        self.selected = false
        self:updateVisibility()
      end)
    end
  end
end

function QuestlineTreeView:setTabVisualSelected(selected)
  if not self.tabButton then
    return
  end
  if selected then
    if type(PanelTemplates_SelectTab) == "function" then
      pcall(PanelTemplates_SelectTab, self.tabButton)
    elseif self.tabButton.LockHighlight then
      self.tabButton:LockHighlight()
    end
  else
    if type(PanelTemplates_DeselectTab) == "function" then
      pcall(PanelTemplates_DeselectTab, self.tabButton)
    elseif self.tabButton.UnlockHighlight then
      self.tabButton:UnlockHighlight()
    end
  end
end

function QuestlineTreeView:hideAllRows()
  for _, rowButton in ipairs(self.rowButtons) do
    rowButton:Hide()
  end
end

function QuestlineTreeView:hideAllRightRows()
  for _, rowButton in ipairs(self.rightRowButtons) do
    rowButton:Hide()
  end
end

function QuestlineTreeView:setSelected(selected)
  if selected == true and self.selected ~= true and self.hostJournalFrame and type(self.hostJournalFrame.selectedTab) == "number" then
    self.nativeTabBeforeQuest = self.hostJournalFrame.selectedTab -- 进入任务页前的原生页签 ID
  end
  self.selected = selected == true
  self:updateVisibility()
end

function QuestlineTreeView:getNativeRootTabs(includeHidden)
  local nativeTabList = {} -- 原生根页签数组
  local journalFrame = self.hostJournalFrame -- 冒险手册根面板
  if journalFrame and type(journalFrame.Tabs) == "table" then
    for _, rootTabButton in ipairs(journalFrame.Tabs) do
      if rootTabButton and rootTabButton ~= self.tabButton then
        local shouldInclude = includeHidden == true -- 是否纳入当前页签
        if not shouldInclude and rootTabButton.IsShown then
          local shownSuccess, isShown = pcall(function() return rootTabButton:IsShown() end)
          shouldInclude = shownSuccess and isShown == true
        end
        if shouldInclude then
          nativeTabList[#nativeTabList + 1] = rootTabButton
        end
      end
    end
  end
  return nativeTabList
end

function QuestlineTreeView:getRaidRootTab()
  local nativeTabList = self:getNativeRootTabs(true) -- 原生根页签列表（含隐藏）
  for _, rootTabButton in ipairs(nativeTabList) do
    local rootTabId = self:resolveNativeRootTabId(rootTabButton) -- 当前根页签 ID
    if rootTabId == RAID_ROOT_TAB_ID then
      return rootTabButton
    end
  end
  return nil
end

function QuestlineTreeView:resolveNativeRootTabId(rootTabButton)
  if not rootTabButton or not rootTabButton.GetID then
    return nil
  end
  local rootTabId = rootTabButton:GetID() -- 根页签 ID
  if type(rootTabId) == "number" and rootTabId > 0 then
    return rootTabId
  end
  return nil
end

function QuestlineTreeView:readRootTabDisplayName(rootTabButton)
  if not rootTabButton then
    return ""
  end
  if rootTabButton.GetText then
    local buttonText = rootTabButton:GetText() -- 页签主文本
    if type(buttonText) == "string" and buttonText ~= "" then
      return buttonText
    end
  end
  local textRegion = rootTabButton.Text -- 页签文本区域
  if textRegion and textRegion.GetText then
    local regionText = textRegion:GetText() -- 页签文本区域内容
    if type(regionText) == "string" then
      return regionText
    end
  end
  local rootTabId = self:resolveNativeRootTabId(rootTabButton) -- 根页签 ID
  return type(rootTabId) == "number" and tostring(rootTabId) or ""
end

function QuestlineTreeView:buildRootTabDisplayNameById(rootTabOrderIds)
  local displayNameById = {} -- 页签显示名映射（按 ID）
  local sourceTabOrderIds = rootTabOrderIds -- 传入顺序列表
  if type(sourceTabOrderIds) ~= "table" or #sourceTabOrderIds == 0 then
    sourceTabOrderIds = buildEffectiveRootTabOrderIds()
  end

  ensureEncounterJournalAddonLoaded()

  for _, rootTabId in ipairs(sourceTabOrderIds) do
    if type(rootTabId) == "number" and rootTabId > 0 then
      displayNameById[rootTabId] = getRootTabFallbackName(rootTabId)
    end
  end
  displayNameById[QUEST_ROOT_TAB_ID] = getRootTabFallbackName(QUEST_ROOT_TAB_ID)

  self:ensureWidgets()
  local nativeRootTabList = self:getNativeRootTabs(true) -- 原生根页签（含隐藏）
  for _, rootTabButton in ipairs(nativeRootTabList) do
    local rootTabId = self:resolveNativeRootTabId(rootTabButton) -- 页签 ID
    local displayName = self:readRootTabDisplayName(rootTabButton) -- 动态页签名
    if type(rootTabId) == "number" and type(displayName) == "string" and displayName ~= "" then
      displayNameById[rootTabId] = displayName
    end
  end

  return displayNameById
end

function QuestlineTreeView:setNativeRootTabShown(rootTabButton, shouldShow)
  if not rootTabButton then
    return
  end
  local rootTabID = rootTabButton.GetID and rootTabButton:GetID() or nil -- 根页签 ID
  if type(rootTabID) == "number"
    and self.hostJournalFrame
    and type(PanelTemplates_ShowTab) == "function"
    and type(PanelTemplates_HideTab) == "function"
  then
    if shouldShow then
      pcall(PanelTemplates_ShowTab, self.hostJournalFrame, rootTabID)
    else
      pcall(PanelTemplates_HideTab, self.hostJournalFrame, rootTabID)
    end
    return
  end
  if shouldShow then
    rootTabButton:Show()
  else
    rootTabButton:Hide()
  end
end

function QuestlineTreeView:deselectAllNativeTabs()
  local nativeTabList = self:getNativeRootTabs(true) -- 原生根页签列表（含隐藏）
  for _, rootTabButton in ipairs(nativeTabList) do
    if rootTabButton and rootTabButton ~= self.tabButton then
      if rootTabButton and rootTabButton.GetID then
        if type(PanelTemplates_DeselectTab) == "function" then
          pcall(PanelTemplates_DeselectTab, rootTabButton)
        end
      end
    end
  end
end

function QuestlineTreeView:hideNativeRootChrome()
  if not self.hostJournalFrame then
    return
  end
  local navBar = self.hostJournalFrame.navBar -- 顶部导航条
  if navBar and navBar.Hide then
    navBar:Hide()
  end
  local searchBox = self.hostJournalFrame.searchBox -- 右上搜索框
  if searchBox and searchBox.Hide then
    searchBox:Hide()
  end
  local journeysFrame = self.hostJournalFrame.JourneysFrame -- Journeys 独立内容面板
  if journeysFrame and journeysFrame.Hide then
    journeysFrame:Hide()
  end
  if type(EncounterJournal_HideGreatVaultButton) == "function" then
    pcall(EncounterJournal_HideGreatVaultButton)
  end
end

function QuestlineTreeView:restoreNativeRootTab()
  if not self.hostJournalFrame or type(EJ_ContentTab_Select) ~= "function" then
    return
  end
  local restoreTabId = self.hostJournalFrame.selectedTab -- 恢复目标页签 ID（优先当前原生状态）
  if type(restoreTabId) ~= "number" then
    restoreTabId = self.nativeTabBeforeQuest
  end
  if type(restoreTabId) ~= "number" then
    restoreTabId = RAID_ROOT_TAB_ID
  end
  if type(restoreTabId) == "number" then
    pcall(EJ_ContentTab_Select, restoreTabId)
  end
end

local rootStateStrategies = {
  quest = function(view)
    if type(view.nativeTabBeforeQuest) ~= "number"
      and view.hostJournalFrame
      and type(view.hostJournalFrame.selectedTab) == "number"
    then
      view.nativeTabBeforeQuest = view.hostJournalFrame.selectedTab -- 首次进入任务页签时记录原生页签
    end
    if type(EJ_HideNonInstancePanels) == "function" then
      pcall(EJ_HideNonInstancePanels)
    end
    view:hideNativeRootChrome()
    view:render()
    view.panelFrame:Show()
    view:deselectAllNativeTabs()
    if view.hostJournalFrame then
      local instanceSelect = view.hostJournalFrame.instanceSelect -- 副本列表容器
      local encounterFrame = view.hostJournalFrame.encounter -- 首领详情容器
      if instanceSelect and instanceSelect.Hide then
        instanceSelect:Hide()
      end
      if encounterFrame and encounterFrame.Hide then
        encounterFrame:Hide()
      end
    end
  end,
  native = function(view, stateContext)
    view.panelFrame:Hide()
    if stateContext and stateContext.shouldRestoreNative then
      view:restoreNativeRootTab()
    end
    view.nativeTabBeforeQuest = nil
  end,
}

function QuestlineTreeView:resolveRootState(canShow)
  if canShow and self.selected then
    return "quest"
  end
  return "native"
end

function QuestlineTreeView:applyRootState(rootState, stateContext)
  local strategy = rootStateStrategies[rootState] -- 根状态策略
  if not strategy then
    return
  end
  strategy(self, stateContext)
  self.activeRootState = rootState
end

function QuestlineTreeView:layoutRootTabs()
  if not self.tabButton or not self.hostJournalFrame then
    return
  end

  local allNativeTabList = self:getNativeRootTabs(true) -- 全量原生页签（含隐藏）
  if #allNativeTabList == 0 then
    self.tabButton:ClearAllPoints()
    self.tabButton:SetPoint("BOTTOMLEFT", self.hostJournalFrame, "BOTTOMLEFT", 110, 3)
    return
  end

  local rootTabHiddenIds = getRootTabHiddenIdsTable() -- 用户隐藏配置（按 ID）
  local effectiveRootTabOrderIds = buildEffectiveRootTabOrderIds() -- 生效顺序配置（按 ID）
  local visibleNativeEntryById = {} -- 可见原生页签 ID 映射
  local visibleNativeTabList = {} -- 可见原生页签顺序列表

  for _, rootTabButton in ipairs(allNativeTabList) do
    local rootTabId = self:resolveNativeRootTabId(rootTabButton) -- 当前页签 ID
    local rootTabName = self:readRootTabDisplayName(rootTabButton) -- 当前页签名（动态读取）
    local hiddenByConfig = type(rootTabId) == "number" and rootTabHiddenIds[rootTabId] == true -- 是否被配置隐藏
    local shouldShow = not hiddenByConfig -- 最终可见性（由配置显隐控制）
    self:setNativeRootTabShown(rootTabButton, shouldShow)
    if shouldShow then
      local entry = {
        id = rootTabId,
        name = rootTabName,
        button = rootTabButton,
      }
      visibleNativeTabList[#visibleNativeTabList + 1] = entry
      if type(rootTabId) == "number" and not visibleNativeEntryById[rootTabId] then
        visibleNativeEntryById[rootTabId] = entry
      end
    end
  end

  local orderedTabList = {} -- 最终重排后的显示页签
  local addedTabSet = {} -- 已添加页签集合
  local shouldShowQuestTab = isQuestlineTreeEnabled() and rootTabHiddenIds[QUEST_ROOT_TAB_ID] ~= true -- 任务页签是否可见

  self.tabButton:SetShown(shouldShowQuestTab)

  local function appendRootTab(rootTabButton)
    if not rootTabButton or addedTabSet[rootTabButton] then
      return
    end
    orderedTabList[#orderedTabList + 1] = rootTabButton
    addedTabSet[rootTabButton] = true
  end

  for _, rootTabId in ipairs(effectiveRootTabOrderIds) do
    if rootTabId == QUEST_ROOT_TAB_ID then
      if shouldShowQuestTab then
        appendRootTab(self.tabButton)
      end
    else
      local nativeEntry = visibleNativeEntryById[rootTabId] -- 对应原生页签
      appendRootTab(nativeEntry and nativeEntry.button or nil)
    end
  end

  for _, nativeEntry in ipairs(visibleNativeTabList) do
    appendRootTab(nativeEntry.button)
  end

  if shouldShowQuestTab then
    appendRootTab(self.tabButton)
  end

  if #orderedTabList == 0 then
    self.tabButton:Hide()
    return
  end

  local previousTab = nil -- 上一个已锚定页签
  for _, rootTabButton in ipairs(orderedTabList) do
    rootTabButton:ClearAllPoints()
    if previousTab then
      rootTabButton:SetPoint("LEFT", previousTab, "RIGHT", 3, 0)
    else
      rootTabButton:SetPoint("TOPLEFT", self.hostJournalFrame, "BOTTOMLEFT", 11, 2)
    end
    previousTab = rootTabButton
  end
end

local function normalizeQuestNavModeKey(modeKey)
  if modeKey == "quest_type" then
    return "quest_type"
  end
  return "map_questline"
end

function QuestlineTreeView:loadSelection()
  local moduleDb = getModuleDb() -- 模块存档
  self.selectedExpansionID = normalizeSelectionID(moduleDb.questNavExpansionID)
  self.selectedModeKey = normalizeQuestNavModeKey(moduleDb.questNavModeKey)
  self.selectedMapID = normalizeSelectionID(moduleDb.questNavSelectedMapID)
  self.selectedTypeKey = type(moduleDb.questNavSelectedTypeKey) == "string" and moduleDb.questNavSelectedTypeKey or ""
  self.expandedQuestLineID = normalizeSelectionID(moduleDb.questNavExpandedQuestLineID)
  if self.selectedModeKey == "quest_type" then
    self.expandedQuestLineID = nil
  end
  self.selectedQuestID = nil
end

function QuestlineTreeView:saveSelection()
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questNavExpansionID = type(self.selectedExpansionID) == "number" and self.selectedExpansionID or 0
  moduleDb.questNavModeKey = normalizeQuestNavModeKey(self.selectedModeKey)
  moduleDb.questNavSelectedMapID = type(self.selectedMapID) == "number" and self.selectedMapID or 0
  moduleDb.questNavSelectedTypeKey = type(self.selectedTypeKey) == "string" and self.selectedTypeKey or ""
  moduleDb.questNavExpandedQuestLineID = type(self.expandedQuestLineID) == "number" and self.expandedQuestLineID or 0
end

function QuestlineTreeView:resolveNavigationDefaults(navigationModel)
  local expansionList = navigationModel and navigationModel.expansionList or {} -- 资料片列表
  local expansionByID = navigationModel and navigationModel.expansionByID or {} -- 资料片索引
  if type(self.selectedExpansionID) ~= "number" or type(expansionByID[self.selectedExpansionID]) ~= "table" then
    self.selectedExpansionID = expansionList[1] and expansionList[1].id or nil
  end

  local expansionEntry = type(self.selectedExpansionID) == "number" and expansionByID[self.selectedExpansionID] or nil -- 当前资料片
  if type(expansionEntry) ~= "table" then
    self.selectedMapID = nil
    self.selectedTypeKey = ""
    self.expandedQuestLineID = nil
    return nil
  end

  self.selectedModeKey = normalizeQuestNavModeKey(self.selectedModeKey)
  local modeByKey = expansionEntry.modeByKey or {} -- 模式索引
  if type(modeByKey[self.selectedModeKey]) ~= "table" then
    self.selectedModeKey = "map_questline"
  end

  if self.selectedModeKey == "map_questline" then
    local mapMode = modeByKey.map_questline -- 地图模式
    local hasSelectedMap = false -- 当前地图是否存在
    for _, mapEntry in ipairs(mapMode and mapMode.entries or {}) do
      if mapEntry.id == self.selectedMapID then
        hasSelectedMap = true
        break
      end
    end
    if not hasSelectedMap then
      self.selectedMapID = mapMode and mapMode.entries and mapMode.entries[1] and mapMode.entries[1].id or nil
    end
    self.selectedTypeKey = ""
  else
    local typeMode = modeByKey.quest_type -- 类型模式
    local hasSelectedType = false -- 当前类型是否存在
    for _, typeEntry in ipairs(typeMode and typeMode.entries or {}) do
      if tostring(typeEntry.id) == self.selectedTypeKey then
        hasSelectedType = true
        break
      end
    end
    if not hasSelectedType then
      self.selectedTypeKey = typeMode and typeMode.entries and typeMode.entries[1] and tostring(typeMode.entries[1].id) or ""
    end
    self.selectedMapID = nil
    self.expandedQuestLineID = nil
  end

  return expansionEntry
end

function QuestlineTreeView:buildLeftTreeRows(navigationModel)
  local rowDataList = {} -- 左侧树行
  local expansionList = navigationModel and navigationModel.expansionList or {} -- 资料片列表
  local expansionByID = navigationModel and navigationModel.expansionByID or {} -- 资料片索引
  for _, expansionSummary in ipairs(expansionList) do
    local expansionSelected = self.selectedExpansionID == expansionSummary.id -- 资料片是否选中
    rowDataList[#rowDataList + 1] = {
      kind = "expansion",
      text = expansionSummary.name,
      selected = expansionSelected,
      expansionID = expansionSummary.id,
    }
    if expansionSelected then
      local expansionEntry = expansionByID[expansionSummary.id] -- 当前资料片对象
      for _, modeEntry in ipairs(expansionEntry and expansionEntry.modes or {}) do
        local modeSelected = self.selectedModeKey == modeEntry.key -- 模式是否选中
        rowDataList[#rowDataList + 1] = {
          kind = "mode",
          text = modeEntry.name,
          selected = modeSelected,
          expansionID = expansionSummary.id,
          modeKey = modeEntry.key,
        }
        if modeSelected then
          for _, childEntry in ipairs(modeEntry.entries or {}) do
            local childKind = childEntry.kind -- 导航子项类型
            if type(childKind) ~= "string" or childKind == "" then
              childKind = modeEntry.key == "quest_type" and "type_group" or "map"
            end
            rowDataList[#rowDataList + 1] = {
              kind = childKind,
              text = childEntry.name,
              selected = (childKind == "map" and self.selectedMapID == childEntry.id)
                or (childKind == "type_group" and self.selectedTypeKey == tostring(childEntry.id)),
              expansionID = expansionSummary.id,
              modeKey = modeEntry.key,
              mapID = childKind == "map" and childEntry.id or nil,
              typeKey = childKind == "type_group" and tostring(childEntry.id) or nil,
            }
          end
        end
      end
    end
  end
  return rowDataList
end

function QuestlineTreeView:getOrCreateRowButton(rowIndex)
  local rowButton = self.rowButtons[rowIndex] -- 左树行按钮
  if rowButton then
    return rowButton
  end
  rowButton = CreateFrame("Button", nil, self.scrollChild)
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local highlightTexture = rowButton:GetHighlightTexture() -- 高亮贴图
  if highlightTexture and highlightTexture.SetBlendMode then
    highlightTexture:SetBlendMode("ADD")
  end
  local rowFont = rowButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rowFont:SetPoint("LEFT", rowButton, "LEFT", 2, 0)
  rowFont:SetPoint("RIGHT", rowButton, "RIGHT", -6, 0)
  rowFont:SetJustifyH("LEFT")
  rowFont:SetJustifyV("MIDDLE")
  rowButton.rowFont = rowFont
  rowButton:SetScript("OnClick", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" then
      return
    end
    if rowData.kind == "expansion" and type(rowData.expansionID) == "number" then
      self.selectedExpansionID = rowData.expansionID
      self.selectedModeKey = "map_questline"
      self.selectedMapID = nil
      self.selectedTypeKey = ""
      self.expandedQuestLineID = nil
    elseif rowData.kind == "mode" and type(rowData.modeKey) == "string" then
      self.selectedModeKey = normalizeQuestNavModeKey(rowData.modeKey)
      self.selectedMapID = nil
      self.selectedTypeKey = ""
      self.expandedQuestLineID = nil
    elseif rowData.kind == "map" and type(rowData.mapID) == "number" then
      self.selectedModeKey = "map_questline"
      self.selectedMapID = rowData.mapID
      self.selectedTypeKey = ""
      self.expandedQuestLineID = nil
    elseif rowData.kind == "type_group" and type(rowData.typeKey) == "string" then
      self.selectedModeKey = "quest_type"
      self.selectedTypeKey = rowData.typeKey
      self.selectedMapID = nil
      self.expandedQuestLineID = nil
    end
    self:hideQuestDetailPopup()
    self:saveSelection()
    self:render()
  end)
  self.rowButtons[rowIndex] = rowButton
  return rowButton
end

local function buildQuestTooltip(detailObject, localeTable)
  if type(detailObject) ~= "table" or not GameTooltip then
    return
  end

  GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:SetText(tostring(detailObject.name or ("Quest #" .. tostring(detailObject.questID or "?"))))
  if type(detailObject.questLineName) == "string" and detailObject.questLineName ~= "" then
    GameTooltip:AddLine(tostring(detailObject.questLineName))
  end
  if type(detailObject.UiMapID) == "number" then
    GameTooltip:AddLine(string.format("Map: %s", tostring(detailObject.UiMapID)))
  end
  if type(detailObject.status) == "string" then
    GameTooltip:AddLine(string.format("Status: %s", tostring(detailObject.status)))
  end
  if type(detailObject.typeID) == "number" then
    GameTooltip:AddLine(string.format("%s: %s", localeTable.EJ_QUEST_VIEW_TYPE or "类型", tostring(detailObject.typeID)))
  end
  GameTooltip:Show()
end

local function buildQuestDetailLines(detailObject, localeTable)
  local detailLines = {} -- 弹框详情文本行
  if type(detailObject) ~= "table" then
    detailLines[#detailLines + 1] = localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。"
    return detailLines
  end

  detailLines[#detailLines + 1] = string.format("ID: %s", tostring(detailObject.questID or ""))
  detailLines[#detailLines + 1] = string.format("%s: %s", localeTable.EJ_QUESTLINE_TREE_LABEL or "任务", tostring(detailObject.name or ""))
  if type(detailObject.questLineName) == "string" and detailObject.questLineName ~= "" then
    detailLines[#detailLines + 1] = string.format("%s: %s", localeTable.EJ_QUESTLINE_LIST_TITLE or "任务线", detailObject.questLineName)
  end
  if type(detailObject.UiMapID) == "number" then
    detailLines[#detailLines + 1] = string.format("Map: %s", tostring(detailObject.UiMapID))
  end
  if type(detailObject.typeID) == "number" then
    detailLines[#detailLines + 1] = string.format("%s: %s", localeTable.EJ_QUEST_VIEW_TYPE or "类型", tostring(detailObject.typeID))
  end
  if type(detailObject.prerequisiteQuestIDs) == "table" and #detailObject.prerequisiteQuestIDs > 0 then
    detailLines[#detailLines + 1] = "Prerequisite: " .. table.concat(detailObject.prerequisiteQuestIDs, ", ")
  end
  if type(detailObject.nextQuestIDs) == "table" and #detailObject.nextQuestIDs > 0 then
    detailLines[#detailLines + 1] = "Next: " .. table.concat(detailObject.nextQuestIDs, ", ")
  end
  return detailLines
end

function QuestlineTreeView:getOrCreateRightRowButton(rowIndex)
  local rowButton = self.rightRowButtons[rowIndex] -- 主区行按钮
  if rowButton then
    return rowButton
  end
  rowButton = CreateFrame("Button", nil, self.rightScrollChild)
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local highlightTexture = rowButton:GetHighlightTexture() -- 高亮贴图
  if highlightTexture and highlightTexture.SetBlendMode then
    highlightTexture:SetBlendMode("ADD")
  end
  local rowFont = rowButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rowFont:SetPoint("LEFT", rowButton, "LEFT", 2, 0)
  rowFont:SetPoint("RIGHT", rowButton, "RIGHT", -6, 0)
  rowFont:SetJustifyH("LEFT")
  rowFont:SetJustifyV("MIDDLE")
  rowButton.rowFont = rowFont
  rowButton:SetScript("OnEnter", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" or rowData.kind ~= "quest" then
      return
    end
    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(rowData.questID) -- 任务详情
    if not detailError then
      buildQuestTooltip(detailObject, Toolbox.L or {})
    end
  end)
  rowButton:SetScript("OnLeave", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) == "table" and rowData.kind == "quest" and GameTooltip and GameTooltip.Hide then
      GameTooltip:Hide()
    end
  end)
  rowButton:SetScript("OnClick", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" then
      return
    end
    if rowData.kind == "questline" and type(rowData.questLineID) == "number" then
      if self.expandedQuestLineID == rowData.questLineID then
        self.expandedQuestLineID = nil
      else
        self.expandedQuestLineID = rowData.questLineID
      end
      self:hideQuestDetailPopup()
      self:saveSelection()
      self:render()
      return
    end
    if rowData.kind == "quest" and type(rowData.questID) == "number" then
      self.selectedQuestID = rowData.questID
      self:showQuestDetailPopup(rowData.questID)
    end
  end)
  self.rightRowButtons[rowIndex] = rowButton
  return rowButton
end

function QuestlineTreeView:buildMainRowsForMap()
  local rowDataList = {} -- 地图模式主区行
  local localeTable = Toolbox.L or {} -- 本地化文案
  local questLineList, errorObject = Toolbox.Questlines.GetQuestLinesForMap(self.selectedMapID) -- 地图下任务线
  if errorObject then
    return {}, errorObject
  end
  for _, questLineEntry in ipairs(questLineList or {}) do
    local progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineEntry.id) -- 任务线进度
    local progressText = not progressError and formatProgressText(progressInfo, localeTable) or nil -- 进度文本
    local prefix = self.expandedQuestLineID == questLineEntry.id and "[-]" or "[+]" -- 展开前缀
    local lineText = string.format("%s %s", prefix, resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")))
    if type(progressText) == "string" then
      lineText = string.format("%s  %s", lineText, progressText)
    end
    if type(questLineEntry.questCount) == "number" then
      lineText = string.format("%s · %d个任务", lineText, questLineEntry.questCount)
    end
    rowDataList[#rowDataList + 1] = {
      kind = "questline",
      text = lineText,
      questLineID = questLineEntry.id,
      selected = self.expandedQuestLineID == questLineEntry.id,
    }
    if self.expandedQuestLineID == questLineEntry.id then
      local questList, listError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 任务列表
      if listError then
        return {}, listError
      end
      for _, questEntry in ipairs(questList or {}) do
        rowDataList[#rowDataList + 1] = {
          kind = "quest",
          text = tostring(questEntry.name or ("Quest #" .. tostring(questEntry.id or "?"))),
          questID = questEntry.id,
          status = questEntry.status,
        }
      end
    end
  end
  return rowDataList, nil
end

function QuestlineTreeView:buildMainRowsForType()
  local rowDataList = {} -- 类型模式主区行
  local questList, errorObject = Toolbox.Questlines.GetTasksForTypeGroup(self.selectedExpansionID, self.selectedTypeKey) -- 类型任务列表
  if errorObject then
    return {}, errorObject
  end
  for _, questEntry in ipairs(questList or {}) do
    rowDataList[#rowDataList + 1] = {
      kind = "quest",
      text = tostring(questEntry.name or ("Quest #" .. tostring(questEntry.id or "?"))),
      questID = questEntry.id,
      status = questEntry.status,
    }
  end
  return rowDataList, nil
end

function QuestlineTreeView:renderLeftRows(rowDataList)
  local scrollWidth = self.scrollFrame:GetWidth() -- 左树宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 230
  end
  local rowWidth = math.max(140, scrollWidth - 24) -- 行宽
  local rowOffsetY = 6 -- 顶部留白
  local rowIndex = 0 -- 行索引
  for _, rowData in ipairs(rowDataList or {}) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRowButton(rowIndex) -- 当前左树行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 6, -((rowIndex - 1) * self.rowHeight + rowOffsetY))
    rowButton:SetWidth(rowWidth)
    rowButton:SetHeight(self.rowHeight)
    local indentLevel = 0 -- 缩进层级
    if rowData.kind == "mode" then
      indentLevel = 1
    elseif rowData.kind == "map" or rowData.kind == "type_group" then
      indentLevel = 2
    end
    rowButton.rowFont:SetText(string.rep("  ", indentLevel) .. tostring(rowData.text or ""))
    if rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
    else
      rowButton.rowFont:SetTextColor(1, 1, 1)
    end
    rowButton:Show()
  end
  for hideIndex = rowIndex + 1, #self.rowButtons do
    self.rowButtons[hideIndex]:Hide()
  end
  self.scrollChild:SetSize(rowWidth, math.max(rowIndex * self.rowHeight + rowOffsetY + 4, 10))
end

function QuestlineTreeView:renderRightRows(rowDataList)
  local scrollWidth = self.rightScrollFrame:GetWidth() -- 主区宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 520
  end
  local rowWidth = math.max(180, scrollWidth - 24) -- 行宽
  local rowOffsetY = 6 -- 顶部留白
  local rowIndex = 0 -- 行索引
  for _, rowData in ipairs(rowDataList or {}) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRightRowButton(rowIndex) -- 当前主区行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", self.rightScrollChild, "TOPLEFT", 6, -((rowIndex - 1) * self.rowHeight + rowOffsetY))
    rowButton:SetWidth(rowWidth)
    rowButton:SetHeight(self.rowHeight)
    local indentLevel = rowData.kind == "quest" and 1 or 0 -- 任务缩进
    rowButton.rowFont:SetText(string.rep("  ", indentLevel) .. tostring(rowData.text or ""))
    if rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
    elseif rowData.status == "completed" then
      rowButton.rowFont:SetTextColor(0.2, 0.8, 0.2)
    else
      rowButton.rowFont:SetTextColor(1, 1, 1)
    end
    rowButton:Show()
  end
  for hideIndex = rowIndex + 1, #self.rightRowButtons do
    self.rightRowButtons[hideIndex]:Hide()
  end
  self.rightScrollChild:SetSize(rowWidth, math.max(rowIndex * self.rowHeight + rowOffsetY + 4, 10))
  self.rightScrollFrame:SetShown(rowIndex > 0)
end

function QuestlineTreeView:hideQuestDetailPopup()
  if self.detailPopupFrame then
    self.detailPopupFrame:Hide()
  end
end

function QuestlineTreeView:showQuestDetailPopup(questID)
  local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(questID) -- 任务详情
  if detailError or type(detailObject) ~= "table" then
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  if self.detailPopupTitle then
    self.detailPopupTitle:SetText(localeTable.EJ_QUEST_DETAIL_TITLE or "任务详情")
  end
  if self.detailPopupText then
    self.detailPopupText:SetText(table.concat(buildQuestDetailLines(detailObject, localeTable), "\n"))
  end
  if self.detailPopupJumpButton then
    local canJump = type(detailObject.questLineID) == "number" and type(detailObject.UiMapID) == "number" -- 是否可回跳
    self.detailPopupJumpButton.questLineID = detailObject.questLineID
    self.detailPopupJumpButton.mapID = detailObject.UiMapID
    self.detailPopupJumpButton:SetShown(canJump)
    self.detailPopupJumpButton:SetText(localeTable.EJ_QUEST_JUMP_TO_QUESTLINE or "跳转到对应地图/任务线")
  end
  if self.detailPopupFrame then
    self.detailPopupFrame:Show()
  end
end



-- ============================================================================
-- 任务页签 breadcrumb 最终覆盖定义
-- ============================================================================

function QuestlineTreeView:syncBreadcrumb(expansionEntry)
  local localeTable = Toolbox.L or {} -- 本地化文案
  self.breadcrumbButtons = self.breadcrumbButtons or {}
  local breadcrumbList = {} -- 当前路径段

  if type(expansionEntry) == "table" then
    breadcrumbList[#breadcrumbList + 1] = {
      text = tostring(expansionEntry.name or ""),
      onClick = function()
        self.expandedQuestLineID = nil
        self:hideQuestDetailPopup()
        self:saveSelection()
        self:render()
      end,
    }
  end

  if self.selectedModeKey == "quest_type" then
    breadcrumbList[#breadcrumbList + 1] = {
      text = localeTable.EJ_QUEST_NAV_MODE_QUEST_TYPE or "任务类型",
      onClick = function()
        self.selectedTypeKey = ""
        self:hideQuestDetailPopup()
        self:saveSelection()
        self:render()
      end,
    }
    if type(self.selectedTypeKey) == "string" and self.selectedTypeKey ~= "" and type(expansionEntry) == "table" then
      local typeMode = expansionEntry.modeByKey and expansionEntry.modeByKey.quest_type or nil -- 类型模式
      for _, typeEntry in ipairs(typeMode and typeMode.entries or {}) do
        if tostring(typeEntry.id) == self.selectedTypeKey then
          breadcrumbList[#breadcrumbList + 1] = {
            text = tostring(typeEntry.name or ""),
          }
          break
        end
      end
    end
  else
    breadcrumbList[#breadcrumbList + 1] = {
      text = localeTable.EJ_QUEST_NAV_MODE_MAP_QUESTLINE or "地图任务线",
      onClick = function()
        self.selectedMapID = nil
        self.expandedQuestLineID = nil
        self:hideQuestDetailPopup()
        self:saveSelection()
        self:render()
      end,
    }
    if type(self.selectedMapID) == "number" and type(expansionEntry) == "table" then
      local mapMode = expansionEntry.modeByKey and expansionEntry.modeByKey.map_questline or nil -- 地图模式
      for _, mapEntry in ipairs(mapMode and mapMode.entries or {}) do
        if mapEntry.id == self.selectedMapID then
          breadcrumbList[#breadcrumbList + 1] = {
            text = tostring(mapEntry.name or ""),
            onClick = function()
              self.expandedQuestLineID = nil
              self:hideQuestDetailPopup()
              self:saveSelection()
              self:render()
            end,
          }
          break
        end
      end
    end
    if type(self.expandedQuestLineID) == "number" and Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTabModel) == "function" then
      local questTabModel = select(1, Toolbox.Questlines.GetQuestTabModel()) -- 任务页签模型
      local questLineEntry = questTabModel and questTabModel.questLineByID and questTabModel.questLineByID[self.expandedQuestLineID] or nil -- 当前任务线
      if type(questLineEntry) ~= "table" and type(self.selectedMapID) == "number" and Toolbox.Questlines and type(Toolbox.Questlines.GetQuestLinesForMap) == "function" then
        local questLineList = select(1, Toolbox.Questlines.GetQuestLinesForMap(self.selectedMapID)) -- 当前地图任务线列表
        for _, currentQuestLineEntry in ipairs(questLineList or {}) do
          if type(currentQuestLineEntry) == "table" and currentQuestLineEntry.id == self.expandedQuestLineID then
            questLineEntry = currentQuestLineEntry
            break
          end
        end
      end
      if type(questLineEntry) == "table" then
        breadcrumbList[#breadcrumbList + 1] = {
          text = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(self.expandedQuestLineID)),
        }
      end
    end
  end

  local previousButton = nil -- 上一个 breadcrumb 按钮
  for crumbIndex, crumbEntry in ipairs(breadcrumbList) do
    local buttonObject = self.breadcrumbButtons[crumbIndex] -- 当前 breadcrumb 按钮
    if not buttonObject then
      buttonObject = CreateFrame("Button", nil, self.rightContent, "UIPanelButtonTemplate")
      buttonObject:SetHeight(18)
      self.breadcrumbButtons[crumbIndex] = buttonObject
    end
    buttonObject:SetText(tostring(crumbEntry.text or ""))
    buttonObject:SetWidth(math.max(72, (buttonObject.GetText and #(buttonObject:GetText() or "") or 8) * 10))
    buttonObject:ClearAllPoints()
    if previousButton then
      buttonObject:SetPoint("LEFT", previousButton, "RIGHT", 4, 0)
    else
      buttonObject:SetPoint("TOPLEFT", self.breadcrumbFrame, "TOPLEFT", 0, 0)
    end
    if type(crumbEntry.onClick) == "function" and crumbIndex < #breadcrumbList then
      buttonObject:SetEnabled(true)
      buttonObject:SetScript("OnClick", function()
        crumbEntry.onClick()
      end)
    else
      buttonObject:SetEnabled(false)
      buttonObject:SetScript("OnClick", nil)
    end
    buttonObject:Show()
    previousButton = buttonObject
  end
  for hideIndex = #breadcrumbList + 1, #self.breadcrumbButtons do
    self.breadcrumbButtons[hideIndex]:Hide()
  end
end

function QuestlineTreeView:applyContentLayout()
  if not self.panelFrame or not self.leftTree or not self.rightContent then
    return
  end
  self.leftTree:ClearAllPoints()
  self.leftTree:SetPoint("TOPLEFT", self.panelFrame, "TOPLEFT", 8, -8)
  self.leftTree:SetPoint("BOTTOMLEFT", self.panelFrame, "BOTTOMLEFT", 8, 8)
  self.leftTree:SetWidth(220)
  self.scrollFrame:ClearAllPoints()
  self.scrollFrame:SetPoint("TOPLEFT", self.leftTree, "TOPLEFT", 6, -6)
  self.scrollFrame:SetPoint("BOTTOMRIGHT", self.leftTree, "BOTTOMRIGHT", -28, 6)
  self.rightContent:ClearAllPoints()
  self.rightContent:SetPoint("TOPLEFT", self.leftTree, "TOPRIGHT", 6, 0)
  self.rightContent:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -8, 8)
  if self.breadcrumbFrame then
    self.breadcrumbFrame:ClearAllPoints()
    self.breadcrumbFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -10)
    self.breadcrumbFrame:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -10)
    self.breadcrumbFrame:SetHeight(18)
  end
  if self.rightScrollFrame then
    self.rightScrollFrame:ClearAllPoints()
    self.rightScrollFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -34)
    self.rightScrollFrame:SetPoint("BOTTOMRIGHT", self.rightContent, "BOTTOMRIGHT", -26, 10)
  end
end

function QuestlineTreeView:render()
  if not self.scrollFrame or not self.rightScrollFrame or not self.emptyText then
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  local navigationModel, queryError = Toolbox.Questlines.GetQuestNavigationModel() -- 导航模型
  if queryError then
    self:hideAllRows()
    self:hideAllRightRows()
    self.rightScrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end
  local expansionEntry = self:resolveNavigationDefaults(navigationModel or {}) -- 当前资料片
  local leftRows = self:buildLeftTreeRows(navigationModel or {}) -- 左树行
  local mainRows, mainError = self.selectedModeKey == "quest_type" and self:buildMainRowsForType() or self:buildMainRowsForMap() -- 主区行
  if mainError then
    self:hideAllRows()
    self:hideAllRightRows()
    self.rightScrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end
  self:renderLeftRows(leftRows)
  self:renderRightRows(mainRows)
  self:syncBreadcrumb(expansionEntry)
  self.emptyText:SetShown(#leftRows == 0 and #mainRows == 0)
  if self.emptyText:IsShown() then
    self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
  end
  if self.rightTitle then
    self.rightTitle:SetText("")
  end
end

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame
  self.breadcrumbButtons = self.breadcrumbButtons or {}
  if self.tabButton
    and self.panelFrame
    and self.leftTree
    and self.rightContent
    and self.scrollFrame
    and self.scrollChild
    and self.rightScrollFrame
    and self.rightScrollChild
    and self.emptyText
    and self.detailPopupFrame
    and self.detailPopupJumpButton
    and self.breadcrumbFrame
  then
    self:loadSelection()
    self:layoutRootTabs()
    self:syncTabLabel()
    self:applyContentLayout()
    self:hookVanillaTabsOnce()
    return
  end
  if not self.tabButton then
    local tabButton = CreateFrame("Button", "ToolboxEJQuestlineTab", journalFrame, "PanelTabButtonTemplate")
    tabButton:SetID(QUEST_ROOT_TAB_ID)
    tabButton:SetScript("OnClick", function()
      self:setSelected(true)
    end)
    self.tabButton = tabButton
    self:layoutRootTabs()
  end
  if not self.panelFrame then
    local panelFrame = CreateFrame("Frame", "ToolboxEJQuestlinePanel", journalFrame, "InsetFrameTemplate3")
    local instanceSelect = journalFrame.instanceSelect -- 主内容区
    if instanceSelect then
      panelFrame:SetPoint("TOPLEFT", instanceSelect, "TOPLEFT", 0, 0)
      panelFrame:SetPoint("BOTTOMRIGHT", instanceSelect, "BOTTOMRIGHT", 0, 0)
    else
      panelFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 45, -83)
      panelFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -34, 36)
    end
    panelFrame:Hide()
    self.panelFrame = panelFrame
  end
  if not self.leftTree then
    self.leftTree = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
  end
  if not self.rightContent then
    self.rightContent = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
  end
  if not self.scrollFrame then
    self.scrollFrame = CreateFrame("ScrollFrame", "ToolboxEJQuestlineScrollFrame", self.leftTree, "UIPanelScrollFrameTemplate")
  end
  if not self.scrollChild then
    local scrollChild = CreateFrame("Frame", "ToolboxEJQuestlineScrollChild", self.scrollFrame)
    scrollChild:SetSize(180, 32)
    self.scrollChild = scrollChild
  end
  if self.scrollFrame:GetScrollChild() ~= self.scrollChild then
    self.scrollFrame:SetScrollChild(self.scrollChild)
  end
  if not self.rightTitle then
    local rightTitle = self.rightContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightTitle:SetJustifyH("LEFT")
    self.rightTitle = rightTitle
  end
  if not self.breadcrumbFrame then
    self.breadcrumbFrame = CreateFrame("Frame", nil, self.rightContent)
  end
  if not self.rightScrollFrame then
    self.rightScrollFrame = CreateFrame("ScrollFrame", nil, self.rightContent, "UIPanelScrollFrameTemplate")
  end
  if not self.rightScrollChild then
    local rightScrollChild = CreateFrame("Frame", nil, self.rightScrollFrame)
    rightScrollChild:SetSize(200, 32)
    self.rightScrollChild = rightScrollChild
  end
  if self.rightScrollFrame:GetScrollChild() ~= self.rightScrollChild then
    self.rightScrollFrame:SetScrollChild(self.rightScrollChild)
  end
  if not self.emptyText then
    local emptyText = self.panelFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", self.panelFrame, "CENTER", 0, 0)
    emptyText:SetWidth(360)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetJustifyV("MIDDLE")
    emptyText:SetWordWrap(true)
    self.emptyText = emptyText
  end
  if not self.detailPopupFrame then
    local popupFrame = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
    popupFrame:SetPoint("CENTER", self.panelFrame, "CENTER", 0, 0)
    popupFrame:SetSize(360, 220)
    popupFrame:Hide()
    self.detailPopupFrame = popupFrame
  end
  if not self.detailPopupTitle then
    local popupTitle = self.detailPopupFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    popupTitle:SetPoint("TOPLEFT", self.detailPopupFrame, "TOPLEFT", 12, -12)
    popupTitle:SetPoint("TOPRIGHT", self.detailPopupFrame, "TOPRIGHT", -12, -12)
    popupTitle:SetJustifyH("LEFT")
    self.detailPopupTitle = popupTitle
  end
  if not self.detailPopupText then
    local popupText = self.detailPopupFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    popupText:SetPoint("TOPLEFT", self.detailPopupFrame, "TOPLEFT", 12, -38)
    popupText:SetPoint("BOTTOMRIGHT", self.detailPopupFrame, "BOTTOMRIGHT", -12, 40)
    popupText:SetJustifyH("LEFT")
    popupText:SetJustifyV("TOP")
    popupText:SetWordWrap(true)
    self.detailPopupText = popupText
  end
  if not self.detailPopupJumpButton then
    local jumpButton = CreateFrame("Button", nil, self.detailPopupFrame, "UIPanelButtonTemplate")
    jumpButton:SetSize(180, 20)
    jumpButton:SetPoint("BOTTOMLEFT", self.detailPopupFrame, "BOTTOMLEFT", 12, 12)
    jumpButton:SetScript("OnClick", function(button)
      if type(button.mapID) == "number" then
        self.selectedModeKey = "map_questline"
        self.selectedMapID = button.mapID
      end
      if type(button.questLineID) == "number" then
        self.expandedQuestLineID = button.questLineID
      end
      self.selectedTypeKey = ""
      self:hideQuestDetailPopup()
      self:saveSelection()
      self:render()
    end)
    jumpButton:Hide()
    self.detailPopupJumpButton = jumpButton
  end
  self:loadSelection()
  self:syncTabLabel()
  self:applyContentLayout()
  self:hookVanillaTabsOnce()
end

function QuestlineTreeView:updateVisibility()
  if not self.tabButton or not self.panelFrame then
    return
  end

  self:layoutRootTabs()
  self:applyContentLayout()

  local journalShown = self.hostJournalFrame and self.hostJournalFrame.IsShown and self.hostJournalFrame:IsShown() or false -- 冒险手册显示状态
  local treeEnabled = isQuestlineTreeEnabled() -- 模块+设置开关状态
  local canShow = treeEnabled and journalShown -- 模块可用且主框体可见
  local rootTabHiddenIds = getRootTabHiddenIdsTable() -- 页签隐藏配置（按 ID）
  local questTabVisibleByLayout = rootTabHiddenIds[QUEST_ROOT_TAB_ID] ~= true -- 任务页签在布局中可见
  local canShowQuestTab = canShow and questTabVisibleByLayout -- 任务页签可见性

  if not canShowQuestTab then
    self.selected = false
  end
  self.tabButton:SetShown(canShowQuestTab)
  self:setTabVisualSelected(canShowQuestTab and self.selected)

  local previousRootState = self.activeRootState or "native" -- 上一轮根状态
  local currentRootState = self:resolveRootState(canShowQuestTab) -- 目标根状态
  local shouldRestoreNative = previousRootState == "quest"
    and currentRootState == "native"
    and not self.pendingNativeSelection -- 是否需要主动恢复原生页签
  self:applyRootState(currentRootState, {
    shouldRestoreNative = shouldRestoreNative,
  })
  self.pendingNativeSelection = false
  self.wasShowingPanel = currentRootState == "quest"
end

function QuestlineTreeView:refresh()
  self:ensureWidgets()
  self:updateVisibility()
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
  if type(Toolbox.EJ.IsRaidOrDungeonInstanceListTab) ~= "function" then
    self:clearAllFrames()
    return
  end
  if Toolbox.EJ.IsRaidOrDungeonInstanceListTab() ~= true then
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
        if type(Toolbox.EJ.IsRaidOrDungeonInstanceListTab) ~= "function" then return end
        if Toolbox.EJ.IsRaidOrDungeonInstanceListTab() ~= true then return end
        local success, elementData = pcall(function() return self:GetElementData() end)
        if not success or not elementData then return end
        local jid = getJournalInstanceID(elementData)
        if not jid then return end

        local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(jid)
        if #lockouts == 0 then return end

        local loc = Toolbox.L or {}
        Runtime.TooltipAddLine(GameTooltip, " ")
        for _, lockout in ipairs(lockouts) do
          local timeStr = formatResetTime(lockout.resetTime or 0)
          local resetLabel = string.format(loc.EJ_LOCKOUT_RESET_FMT or "%s - Resets in: %s",
            lockout.difficultyName or "", timeStr)
          if lockout.isExtended then
            resetLabel = resetLabel .. " " .. (loc.EJ_LOCKOUT_EXTENDED or "(Extended)")
          end
          Runtime.TooltipAddLine(GameTooltip, resetLabel, 1, 0.8, 0)
          if lockout.isRaid and (lockout.numEncounters or 0) > 0 then
            local progressLabel = string.format(loc.EJ_LOCKOUT_PROGRESS_FMT or "Progress: %d / %d bosses",
              lockout.encounterProgress or 0, lockout.numEncounters or 0)
            Runtime.TooltipAddLine(GameTooltip, progressLabel, 0.8, 0.8, 0.8)
            local killed = Toolbox.EJ.GetKilledBosses(jid)
            for _, boss in ipairs(killed) do
              Runtime.TooltipAddLine(GameTooltip, "  " .. (boss.name or ""), 0.6, 0.6, 0.6)
            end
          end
        end
        Runtime.TooltipShow(GameTooltip)
      end)
    end)
  end)
end

-- ============================================================================
-- 事件驱动架构
-- ============================================================================

--- 统一刷新入口
local function refreshAll()
  MountFilter:createUI()
  DetailEnhancer:refresh()
  QuestlineTreeView:refresh()
  MountFilter:updateVisibility()
  MountFilter:applyFilter()
  LockoutOverlay:updateFrames()
  LockoutOverlay:hookTooltips()
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
