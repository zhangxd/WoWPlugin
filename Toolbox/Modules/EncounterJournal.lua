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
    GameTooltip._ToolboxSkipAnchorOverride = true
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
    GameTooltip._ToolboxSkipAnchorOverride = nil
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
    GameTooltip._ToolboxSkipAnchorOverride = true
    Runtime.TooltipSetOwner(GameTooltip, btn, "ANCHOR_RIGHT")
    Runtime.TooltipClear(GameTooltip)
    Runtime.TooltipSetText(GameTooltip, loc.EJ_DETAIL_MOUNT_ONLY_LABEL or "")
    Runtime.TooltipAddLine(GameTooltip, loc.EJ_DETAIL_MOUNT_ONLY_HINT or "", 1, 1, 1, true)
    Runtime.TooltipShow(GameTooltip)
  end)
  check:SetScript("OnLeave", function()
    GameTooltip._ToolboxSkipAnchorOverride = nil
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
  viewButtons = {},
  typeModeButton = nil,
  rowHeight = 18,
  selected = false,
  selectedView = "status",
  selectedKind = "map",
  selectedTypeID = nil,
  selectedMapID = nil,
  selectedQuestLineID = nil,
  selectedQuestID = nil,
  typeListMode = "tree",
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

function QuestlineTreeView:ensureSelectionPathExpanded()
  local collapseState = getQuestlineCollapsedTable() -- 折叠状态表
  if type(self.selectedMapID) == "number" and (self.selectedKind == "questline" or self.selectedKind == "quest") then
    setTreeNodeCollapsed(collapseState, "map:" .. tostring(self.selectedMapID), false)
  end
  if type(self.selectedQuestLineID) == "number" and self.selectedKind == "quest" then
    setTreeNodeCollapsed(collapseState, "questline:" .. tostring(self.selectedQuestLineID), false)
  end
end

function QuestlineTreeView:saveSelection()
  local moduleDb = getModuleDb() -- 模块存档
  local selectionTable = ensureSelectionTable() -- 旧版选中状态持久化对象
  moduleDb.questViewMode = type(self.selectedView) == "string" and self.selectedView or "status"
  moduleDb.questViewSelectedMapID = type(self.selectedMapID) == "number" and self.selectedMapID or 0
  moduleDb.questViewSelectedTypeID = type(self.selectedTypeID) == "number" and self.selectedTypeID or 0
  moduleDb.questViewSelectedQuestLineID = type(self.selectedQuestLineID) == "number" and self.selectedQuestLineID or 0
  moduleDb.questViewSelectedQuestID = type(self.selectedQuestID) == "number" and self.selectedQuestID or 0

  selectionTable.selectedKind = self.selectedKind
  selectionTable.selectedMapID = self.selectedMapID
  selectionTable.selectedTypeID = self.selectedTypeID
  selectionTable.selectedQuestLineID = self.selectedQuestLineID
  selectionTable.selectedQuestID = self.selectedQuestID
end

function QuestlineTreeView:loadSelection()
  local moduleDb = getModuleDb() -- 模块存档
  local selectionTable = ensureSelectionTable() -- 旧版选中状态持久化对象
  self.selectedView = type(moduleDb.questViewMode) == "string" and moduleDb.questViewMode or "status"
  self.selectedMapID = normalizeSelectionID(moduleDb.questViewSelectedMapID)
  self.selectedTypeID = normalizeSelectionID(moduleDb.questViewSelectedTypeID or selectionTable.selectedTypeID)
  self.selectedQuestLineID = normalizeSelectionID(moduleDb.questViewSelectedQuestLineID)
  self.selectedQuestID = normalizeSelectionID(moduleDb.questViewSelectedQuestID)

  if self.selectedQuestID ~= nil then
    self.selectedKind = "quest"
  elseif self.selectedView == "type" and self.selectedTypeID ~= nil then
    self.selectedKind = "type"
  elseif self.selectedQuestLineID ~= nil then
    self.selectedKind = "questline"
  elseif self.selectedMapID ~= nil then
    self.selectedKind = "map"
  else
    self.selectedKind = self.selectedView == "type" and "type" or "map"
  end
end

function QuestlineTreeView:setViewMode(viewMode)
  if viewMode ~= "status" and viewMode ~= "type" and viewMode ~= "map" then
    return
  end
  self.selectedView = viewMode
  if viewMode == "type" then
    if type(self.selectedTypeID) ~= "number" then
      self.selectedKind = "type"
    end
  else
    if self.selectedKind == "type" then
      self.selectedKind = "map"
    end
  end
  self:saveSelection()
  self:applyContentLayout()
  self:render()
end

local function resolveDefaultMapID(questTabModel, selectedView)
  local mapList = questTabModel and questTabModel.maps or nil -- 地图列表
  if type(mapList) ~= "table" or #mapList == 0 then
    return nil
  end

  if selectedView == "status" then
    local currentMapID = getCurrentPlayerMapID() -- 当前角色所在地图 ID
    if type(currentMapID) == "number" and questTabModel.mapByID and type(questTabModel.mapByID[currentMapID]) == "table" then
      return currentMapID
    end
  end

  return mapList[1] and mapList[1].id or nil
end

local function resolveTypeEntryID(typeEntry)
  if type(typeEntry) == "number" then
    return typeEntry
  end
  if type(typeEntry) == "table" and type(typeEntry.id) == "number" then
    return typeEntry.id
  end
  return nil
end

local function resolveTypeEntryName(typeEntry)
  if type(typeEntry) == "table" and type(typeEntry.name) == "string" and typeEntry.name ~= "" then
    return typeEntry.name
  end

  local typeID = resolveTypeEntryID(typeEntry) -- 当前类型 ID
  if type(typeID) == "number"
    and Toolbox.Questlines
    and type(Toolbox.Questlines.GetQuestTypeLabel) == "function"
  then
    return Toolbox.Questlines.GetQuestTypeLabel(typeID)
  end
  return nil
end

local function listContainsTypeID(typeList, typeID)
  if type(typeList) ~= "table" or type(typeID) ~= "number" then
    return false
  end

  for _, typeEntry in ipairs(typeList) do
    if resolveTypeEntryID(typeEntry) == typeID then
      return true
    end
  end
  return false
end

local function getFirstTypeID(typeList)
  if type(typeList) ~= "table" then
    return nil
  end

  for _, typeEntry in ipairs(typeList) do
    local typeID = resolveTypeEntryID(typeEntry) -- 当前类型 ID
    if type(typeID) == "number" then
      return typeID
    end
  end
  return nil
end

local function findTypeEntryByID(typeList, typeID)
  if type(typeList) ~= "table" or type(typeID) ~= "number" then
    return nil
  end

  for _, typeEntry in ipairs(typeList) do
    if resolveTypeEntryID(typeEntry) == typeID then
      return typeEntry
    end
  end
  return nil
end

function QuestlineTreeView:resolveSelectionWithModel(questTabModel)
  local mapList = questTabModel and questTabModel.maps or nil -- 地图列表
  if type(mapList) ~= "table" or #mapList == 0 then
    self.selectedKind = self.selectedView == "type" and "type" or "map"
    self.selectedTypeID = nil
    self.selectedMapID = nil
    self.selectedQuestLineID = nil
    self.selectedQuestID = nil
    return
  end

  if self.selectedView == "status" then
    local currentQuestList = collectStatusQuestEntries(questTabModel) -- 状态视图当前任务集合
    if #currentQuestList == 0 then
      self.selectedKind = "quest"
      self.selectedMapID = nil
      self.selectedQuestLineID = nil
      self.selectedQuestID = nil
      return
    end

    local selectedQuestEntry = findStatusQuestEntryByID(currentQuestList, self.selectedQuestID) -- 当前选中任务
    if type(selectedQuestEntry) ~= "table" then
      selectedQuestEntry = currentQuestList[1]
    end

    self.selectedKind = "quest"
    self.selectedMapID = selectedQuestEntry.mapID
    self.selectedQuestLineID = selectedQuestEntry.questLineID
    self.selectedQuestID = selectedQuestEntry.questID
    return
  elseif self.selectedView == "type" then
    local typeIndexModel = nil -- 类型索引模型
    local typeIndexError = nil -- 类型索引查询错误
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTypeIndex) == "function" then
      typeIndexModel, typeIndexError = Toolbox.Questlines.GetQuestTypeIndex()
    end
    local typeList = typeIndexModel and typeIndexModel.typeList or {} -- 类型列表
    if #typeList == 0 then
      self.selectedKind = "type"
      self.selectedTypeID = nil
      self.selectedQuestLineID = nil
      self.selectedQuestID = nil
      return
    end

    if not listContainsTypeID(typeList, self.selectedTypeID) then
      self.selectedTypeID = getFirstTypeID(typeList)
      self.selectedMapID = nil
      self.selectedQuestLineID = nil
      self.selectedQuestID = nil
      self.selectedKind = "type"
    end

    local validTypeMapList = typeIndexModel and typeIndexModel.typeToMapIDs and typeIndexModel.typeToMapIDs[self.selectedTypeID] or nil -- 当前类型地图列表
    if type(self.selectedMapID) == "number" and not listContainsNumber(validTypeMapList, self.selectedMapID) then
      self.selectedMapID = nil
      if self.selectedKind == "map" then
        self.selectedKind = "type"
      end
    end

    if self.selectedKind == "questline" then
      local questLineEntry = questTabModel.questLineByID and questTabModel.questLineByID[self.selectedQuestLineID] or nil -- 任务线对象
      local validQuestLineList = typeIndexModel and typeIndexModel.typeToQuestLineIDs and typeIndexModel.typeToQuestLineIDs[self.selectedTypeID] or nil -- 当前类型任务线列表
      if typeIndexError or type(questLineEntry) ~= "table" or not listContainsNumber(validQuestLineList, self.selectedQuestLineID) then
        self.selectedKind = "type"
        self.selectedQuestLineID = nil
      else
        self.selectedMapID = questLineEntry.UiMapID
      end
    elseif self.selectedKind == "quest" then
      local detailObject = nil -- 任务详情对象
      local detailError = nil -- 任务详情查询错误
      if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestDetailByID) == "function" and type(self.selectedQuestID) == "number" then
        detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(self.selectedQuestID)
      end
      if detailError or type(detailObject) ~= "table" or detailObject.typeID ~= self.selectedTypeID then
        self.selectedKind = "type"
        self.selectedQuestLineID = nil
        self.selectedQuestID = nil
      else
        self.selectedQuestLineID = detailObject.questLineID
        self.selectedMapID = detailObject.UiMapID
      end
    elseif self.selectedKind ~= "map" and self.selectedKind ~= "type" then
      self.selectedKind = "type"
    end
  else
    local mapEntry = nil -- 当前选中的地图对象
    if type(self.selectedMapID) == "number" and questTabModel.mapByID then
      mapEntry = questTabModel.mapByID[self.selectedMapID]
    end
    if type(mapEntry) ~= "table" then
      self.selectedMapID = resolveDefaultMapID(questTabModel, self.selectedView)
      self.selectedKind = "map"
      self.selectedQuestLineID = nil
      self.selectedQuestID = nil
    end

    if self.selectedKind == "questline" then
      local questLineEntry = questTabModel.questLineByID and questTabModel.questLineByID[self.selectedQuestLineID] or nil -- 任务线对象
      if type(questLineEntry) ~= "table" or questLineEntry.UiMapID ~= self.selectedMapID then
        self.selectedKind = "map"
        self.selectedQuestLineID = nil
      end
    elseif self.selectedKind == "quest" then
      local detailObject = nil -- 任务详情对象
      local detailError = nil -- 任务详情查询错误
      if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestDetailByID) == "function" and type(self.selectedQuestID) == "number" then
        detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(self.selectedQuestID)
      end
      if detailError or type(detailObject) ~= "table" then
        self.selectedKind = "map"
        self.selectedQuestLineID = nil
        self.selectedQuestID = nil
      else
        self.selectedQuestLineID = detailObject.questLineID
        self.selectedMapID = detailObject.UiMapID
      end
    else
      self.selectedKind = "map"
    end
  end
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

function QuestlineTreeView:buildQuestlineTreeRows(questTabModel)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local rowList = {} -- 左侧树行列表
  local collapseState = getQuestlineCollapsedTable() -- 折叠状态表
  self:ensureSelectionPathExpanded()

  local mapList = questTabModel and questTabModel.maps
  if type(mapList) ~= "table" or #mapList == 0 then
    return rowList
  end

  for _, mapEntry in ipairs(mapList) do
    local mapID = mapEntry.id -- 当前地图 ID
    local mapCollapseKey = "map:" .. tostring(mapID or "0")
    local mapCollapsed = isTreeNodeCollapsed(collapseState, mapCollapseKey)
    local mapPrefix = mapCollapsed and "+" or "-"
    local mapSelected = self.selectedKind == "map" and self.selectedMapID == mapID
    local mapText = string.format("%s %s", mapPrefix, mapEntry.name or ("Map #" .. tostring(mapID or "?")))
    if (not mapCollapsed or mapSelected)
      and Toolbox.Questlines
      and type(Toolbox.Questlines.GetMapProgress) == "function"
    then
      local mapProgress, progressError = Toolbox.Questlines.GetMapProgress(mapID) -- 地图进度
      if not progressError then
        local progressText = formatProgressText(mapProgress, localeTable) -- 地图进度文本
        if type(progressText) == "string" then
          mapText = string.format("%s (%s)", mapText, progressText)
        end
      end
    end
    rowList[#rowList + 1] = { -- 地图行
      indent = 0,
      text = mapText,
      kind = "map",
      selected = mapSelected,
      toggle = true,
      collapseKey = mapCollapseKey,
      selectKind = "map",
      mapID = mapID,
    }

    if not mapCollapsed then
      local questLineList = mapEntry.questLines or {} -- 地图下任务线列表
      for _, questLineEntry in ipairs(questLineList) do
        local questLineID = questLineEntry.id -- 当前任务线 ID
        local questLineCollapseKey = "questline:" .. tostring(questLineID or "0") -- 任务线折叠键
        local questLineCollapsed = isTreeNodeCollapsed(collapseState, questLineCollapseKey) -- 任务线折叠状态
        local questLinePrefix = questLineCollapsed and "+" or "-" -- 任务线展开前缀
        local questLineSelected = self.selectedKind == "questline" and self.selectedQuestLineID == questLineID
        local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineID or "?")) -- 当前任务线显示名
        local questLineText = string.format("%s %s", questLinePrefix, questLineName)
        if (not questLineCollapsed or questLineSelected)
          and Toolbox.Questlines
          and type(Toolbox.Questlines.GetQuestLineProgress) == "function"
        then
          local progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineID) -- 任务线进度
          if not progressError then
            local progressText = formatProgressText(progressInfo, localeTable) -- 任务线进度文本
            if type(progressText) == "string" then
              questLineText = string.format("%s (%s)", questLineText, progressText)
            end
          end
        end
        rowList[#rowList + 1] = {
          indent = 1,
          text = questLineText,
          kind = "questline",
          selected = questLineSelected,
          toggle = true,
          collapseKey = questLineCollapseKey,
          selectKind = "questline",
          mapID = mapID,
          questLineID = questLineID,
        }
        if not questLineCollapsed then
          local questList = nil -- 当前任务线任务列表
          local queryListError = nil -- 当前任务线任务查询错误
          if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
            questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineID)
          end
          if not queryListError and type(questList) == "table" then
            for _, questEntry in ipairs(questList) do
              local questID = questEntry.id -- 当前任务 ID
              local questSelected = self.selectedKind == "quest" and self.selectedQuestID == questID -- 任务是否选中
              rowList[#rowList + 1] = {
                indent = 2,
                text = string.format("%s %s", formatQuestStatusPrefix(questEntry.status), questEntry.name or ("Quest #" .. tostring(questID or "?"))),
                kind = "quest",
                status = questEntry.status,
                selected = questSelected,
                toggle = false,
                selectKind = "quest",
                mapID = mapID,
                questLineID = questLineID,
                questID = questID,
              }
            end
          end
        end
      end
    end
  end

  return rowList
end

local function appendQuestRowsForQuestLine(rightRows, questList)
  for _, questEntry in ipairs(questList or {}) do
    local questID = questEntry.id -- 当前任务 ID
    local questText = string.format("%s %s", formatQuestStatusPrefix(questEntry.status), questEntry.name or ("Quest #" .. tostring(questID or "?")))
    rightRows[#rightRows + 1] = {
      text = questText,
      questID = questID,
      status = questEntry.status,
      selected = QuestlineTreeView.selectedQuestID == questID,
      onClick = function()
        QuestlineTreeView.selectedKind = "quest"
        QuestlineTreeView.selectedQuestID = questID
        QuestlineTreeView.selectedQuestLineID = QuestlineTreeView.selectedQuestLineID or nil
      end,
    }
  end
end

local function collectQuestEntriesForMapSelection(questTabModel, selectedKind, selectedMapID, selectedQuestLineID)
  if selectedKind == "questline" and type(selectedQuestLineID) == "number" then
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
      local questList, errorObject = Toolbox.Questlines.GetQuestListByQuestLineID(selectedQuestLineID) -- 当前任务线任务列表
      if not errorObject and type(questList) == "table" then
        return questList
      end
    end
    return {}
  end

  local mapEntry = type(selectedMapID) == "number" and questTabModel.mapByID and questTabModel.mapByID[selectedMapID] or nil -- 当前地图
  if type(mapEntry) ~= "table" then
    return {}
  end

  local questList = {} -- 当前地图任务列表
  for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
      local questLineList, errorObject = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 当前任务线任务列表
      if not errorObject and type(questLineList) == "table" then
        for _, questEntry in ipairs(questLineList) do
          questList[#questList + 1] = questEntry
        end
      end
    end
  end
  return questList
end

local function isQuestCurrentForStatusView(questEntry)
  if type(questEntry) ~= "table" then
    return false
  end
  if questEntry.readyForTurnIn == true then
    return true
  end
  return questEntry.status == "active"
end

local function buildStatusQuestPriority(questEntry)
  if type(questEntry) ~= "table" then
    return 99
  end
  if questEntry.readyForTurnIn == true then
    return 1
  end
  if questEntry.status == "active" then
    return 2
  end
  return 99
end

collectStatusQuestEntries = function(questTabModel)
  local resultList = {} -- 状态视图当前任务列表
  local orderIndex = 0 -- 原始顺序索引
  local usedCurrentQuestApi = false -- 是否已使用 Quest Log 当前任务 API

  if Toolbox.Questlines and type(Toolbox.Questlines.GetCurrentQuestLogEntries) == "function" then
    local currentQuestList, errorObject = Toolbox.Questlines.GetCurrentQuestLogEntries() -- 当前任务日志任务列表
    if not errorObject and type(currentQuestList) == "table" then
      usedCurrentQuestApi = true
      for _, questEntry in ipairs(currentQuestList) do
        if isQuestCurrentForStatusView(questEntry) then
          orderIndex = orderIndex + 1
          resultList[#resultList + 1] = {
            questID = questEntry.questID,
            questName = questEntry.name,
            questLineID = questEntry.questLineID,
            questLineName = questEntry.questLineName,
            mapID = questEntry.UiMapID,
            status = questEntry.status,
            readyForTurnIn = questEntry.readyForTurnIn == true,
            orderIndex = orderIndex,
          }
        end
      end
    end
  end

  if not usedCurrentQuestApi then
    for _, mapEntry in ipairs((questTabModel and questTabModel.maps) or {}) do
      local mapID = mapEntry.id -- 当前地图 ID
      for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
        local questLineID = questLineEntry.id -- 当前任务线 ID
        local questList = nil -- 当前任务线任务列表
        local queryListError = nil -- 当前任务线任务查询错误
        if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
          questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineID)
        end
        if not queryListError and type(questList) == "table" then
          for _, questEntry in ipairs(questList) do
            if isQuestCurrentForStatusView(questEntry) then
              orderIndex = orderIndex + 1
              resultList[#resultList + 1] = {
                questID = questEntry.id,
                questName = questEntry.name,
                questLineID = questLineID,
                questLineName = resolveQuestLineDisplayName(questLineEntry),
                mapID = mapID,
                status = questEntry.status,
                readyForTurnIn = questEntry.readyForTurnIn == true,
                orderIndex = orderIndex,
              }
            end
          end
        end
      end
    end
  end

  table.sort(resultList, function(leftEntry, rightEntry)
    local leftPriority = buildStatusQuestPriority(leftEntry) -- 左侧任务优先级
    local rightPriority = buildStatusQuestPriority(rightEntry) -- 右侧任务优先级
    if leftPriority ~= rightPriority then
      return leftPriority < rightPriority
    end
    return (leftEntry.orderIndex or 0) < (rightEntry.orderIndex or 0)
  end)

  return resultList
end

findStatusQuestEntryByID = function(questEntryList, questID)
  if type(questID) ~= "number" then
    return nil
  end
  for _, questEntry in ipairs(questEntryList or {}) do
    if questEntry.questID == questID then
      return questEntry
    end
  end
  return nil
end

function QuestlineTreeView:buildStatusViewRows(questTabModel)
  local rightRows = {} -- 状态视图右侧任务线行
  if type(self.selectedQuestLineID) ~= "number" then
    return rightRows
  end

  local questList = nil -- 当前任务线任务列表
  local queryListError = nil -- 当前任务线任务查询错误
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
    questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(self.selectedQuestLineID)
  end
  if not queryListError and type(questList) == "table" then
    appendQuestRowsForQuestLine(rightRows, questList)
  end
  return rightRows
end

function QuestlineTreeView:buildStatusQuestRows(questTabModel)
  local rowList = {} -- 状态视图左侧任务行
  for _, questEntry in ipairs(collectStatusQuestEntries(questTabModel)) do
    local questID = questEntry.questID -- 当前任务 ID
    rowList[#rowList + 1] = {
      indent = 0,
      text = string.format("%s %s", formatQuestStatusPrefix(questEntry.status), questEntry.questName or ("Quest #" .. tostring(questID or "?"))),
      kind = "quest",
      selected = self.selectedKind == "quest" and self.selectedQuestID == questID,
      toggle = false,
      selectKind = "quest",
      mapID = questEntry.mapID,
      questLineID = questEntry.questLineID,
      questID = questID,
    }
  end
  return rowList
end

local function buildQuestLineListForType(questTabModel, typeIndexModel, typeID, mapID)
  local resultList = {} -- 类型过滤后的任务线列表
  local questLineIDList = typeIndexModel and typeIndexModel.typeToQuestLineIDs and typeIndexModel.typeToQuestLineIDs[typeID] or {} -- 当前类型任务线 ID 列表
  for _, questLineID in ipairs(questLineIDList or {}) do
    local questLineEntry = questTabModel.questLineByID and questTabModel.questLineByID[questLineID] or nil -- 当前任务线
    if type(questLineEntry) == "table" and (type(mapID) ~= "number" or mapID == questLineEntry.UiMapID) then
      resultList[#resultList + 1] = questLineEntry
    end
  end
  return resultList
end

function QuestlineTreeView:buildTypeViewRows(questTabModel)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local rightRows = {} -- 类型视图行
  local typeIndexModel = nil -- 类型索引模型
  local typeIndexError = nil -- 类型索引查询错误
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTypeIndex) == "function" then
    typeIndexModel, typeIndexError = Toolbox.Questlines.GetQuestTypeIndex()
  end
  local typeList = typeIndexModel and typeIndexModel.typeList or {}
  if #typeList == 0 then
    rightRows[#rightRows + 1] = {
      text = localeTable.EJ_QUEST_TYPE_EMPTY or "当前没有可解析的任务类型。",
    }
    return rightRows
  end

  if self.typeListMode == "list" and type(self.selectedTypeID) == "number" then
    local questLineList = buildQuestLineListForType(questTabModel, typeIndexModel, self.selectedTypeID, self.selectedMapID) -- 当前类型任务线列表
    if type(self.selectedMapID) == "number" and questTabModel.mapByID and type(questTabModel.mapByID[self.selectedMapID]) == "table" then
      rightRows[#rightRows + 1] = {
        text = questTabModel.mapByID[self.selectedMapID].name or ("Map #" .. tostring(self.selectedMapID)),
      }
    end
    for _, questLineEntry in ipairs(questLineList) do
      local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")) -- 当前任务线显示名
      if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
        local questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 当前任务线任务列表
        if not queryListError and type(questList) == "table" then
          for _, questEntry in ipairs(questList) do
            if questEntry.typeID == self.selectedTypeID then
              local questID = questEntry.id -- 当前任务 ID
              rightRows[#rightRows + 1] = {
                text = string.format("%s [%s] %s", formatQuestStatusPrefix(questEntry.status), questLineName, questEntry.name or ("Quest #" .. tostring(questID or "?"))),
                questID = questID,
                status = questEntry.status,
                selected = self.selectedKind == "quest" and self.selectedQuestID == questID,
                onClick = function()
                  self.selectedKind = "quest"
                  self.selectedQuestID = questID
                  self.selectedQuestLineID = questLineEntry.id
                  self.selectedMapID = questLineEntry.UiMapID
                end,
              }
            end
          end
        end
      end
    end
    if #rightRows == 0 then
      rightRows[#rightRows + 1] = {
        text = localeTable.EJ_QUEST_FILTER_EMPTY or "当前筛选下没有可显示的任务。",
      }
    end
    return rightRows
  end

  for _, typeEntry in ipairs(typeList) do
    local typeID = resolveTypeEntryID(typeEntry) -- 当前类型 ID
    local typeLabel = resolveTypeEntryName(typeEntry) or ("Type #" .. tostring(typeID or "?")) -- 类型展示名
    if type(typeID) == "number" then
      local isSelectedType = self.selectedTypeID == typeID -- 是否当前选中类型
      rightRows[#rightRows + 1] = {
        text = string.format("%s %s", isSelectedType and "-" or "+", typeLabel),
        onClick = function()
          self.selectedTypeID = typeID
          self.selectedKind = "type"
          self.selectedMapID = nil
          self.selectedQuestLineID = nil
          self.selectedQuestID = nil
        end,
      }

      if isSelectedType then
        local typeMapList = typeIndexModel and typeIndexModel.typeToMapIDs and typeIndexModel.typeToMapIDs[typeID] or {} -- 当前类型地图列表
        if type(typeMapList) == "table" and #typeMapList > 0 then
          for _, mapID in ipairs(typeMapList) do
            local mapEntry = questTabModel.mapByID and questTabModel.mapByID[mapID] or nil -- 当前地图
            local mapText = (mapEntry and mapEntry.name) or ("Map #" .. tostring(mapID or "?"))
            local mapSelected = self.selectedMapID == mapID -- 地图是否选中
            rightRows[#rightRows + 1] = {
              text = string.format("  %s %s", mapSelected and "-" or "+", mapText),
              onClick = function()
                self.selectedTypeID = typeID
                self.selectedKind = "map"
                self.selectedMapID = mapID
                self.selectedQuestLineID = nil
                self.selectedQuestID = nil
              end,
            }

            if mapSelected then
              for _, questLineEntry in ipairs(buildQuestLineListForType(questTabModel, typeIndexModel, typeID, mapID)) do
                local questLineSelected = self.selectedQuestLineID == questLineEntry.id -- 当前任务线是否选中
                local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")) -- 当前任务线显示名
                rightRows[#rightRows + 1] = {
                  text = string.format("    %s %s", questLineSelected and "-" or "+", questLineName),
                  onClick = function()
                    self.selectedTypeID = typeID
                    self.selectedKind = "questline"
                    self.selectedMapID = mapID
                    self.selectedQuestLineID = questLineEntry.id
                    self.selectedQuestID = nil
                  end,
                }

                if questLineSelected then
                  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
                    local questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 当前任务线任务列表
                    if not queryListError and type(questList) == "table" then
                      for _, questEntry in ipairs(questList) do
                        if questEntry.typeID == typeID then
                          local questID = questEntry.id -- 当前任务 ID
                          rightRows[#rightRows + 1] = {
                            text = string.format("      %s %s", formatQuestStatusPrefix(questEntry.status), questEntry.name or ("Quest #" .. tostring(questID or "?"))),
                            questID = questID,
                            status = questEntry.status,
                            selected = self.selectedKind == "quest" and self.selectedQuestID == questID,
                            onClick = function()
                              self.selectedTypeID = typeID
                              self.selectedKind = "quest"
                              self.selectedMapID = mapID
                              self.selectedQuestLineID = questLineEntry.id
                              self.selectedQuestID = questID
                            end,
                          }
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        else
          for _, questLineEntry in ipairs(buildQuestLineListForType(questTabModel, typeIndexModel, typeID, nil)) do
            local questLineSelected = self.selectedQuestLineID == questLineEntry.id -- 当前任务线是否选中
            local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")) -- 当前任务线显示名
            rightRows[#rightRows + 1] = {
              text = string.format("  %s %s", questLineSelected and "-" or "+", questLineName),
              onClick = function()
                self.selectedTypeID = typeID
                self.selectedKind = "questline"
                self.selectedMapID = nil
                self.selectedQuestLineID = questLineEntry.id
                self.selectedQuestID = nil
              end,
            }

            if questLineSelected then
              if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
                local questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 当前任务线任务列表
                if not queryListError and type(questList) == "table" then
                  for _, questEntry in ipairs(questList) do
                    if questEntry.typeID == typeID then
                      local questID = questEntry.id -- 当前任务 ID
                      rightRows[#rightRows + 1] = {
                        text = string.format("    %s %s", formatQuestStatusPrefix(questEntry.status), questEntry.name or ("Quest #" .. tostring(questID or "?"))),
                        questID = questID,
                        status = questEntry.status,
                        selected = self.selectedKind == "quest" and self.selectedQuestID == questID,
                        onClick = function()
                          self.selectedTypeID = typeID
                          self.selectedKind = "quest"
                          self.selectedMapID = nil
                          self.selectedQuestLineID = questLineEntry.id
                          self.selectedQuestID = questID
                        end,
                      }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return rightRows
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

function QuestlineTreeView:syncViewButtons()
  local localeTable = Toolbox.L or {} -- 本地化文案
  local buttonConfigList = {
    { key = "status", text = localeTable.EJ_QUEST_VIEW_STATUS or "状态" },
    { key = "type", text = localeTable.EJ_QUEST_VIEW_TYPE or "类型" },
    { key = "map", text = localeTable.EJ_QUEST_VIEW_MAP or "地图" },
  }
  for _, configEntry in ipairs(buttonConfigList) do
    local buttonObject = self.viewButtons[configEntry.key] -- 当前视图按钮
    if buttonObject and buttonObject.SetText then
      buttonObject:SetText(configEntry.text)
      buttonObject:SetEnabled(self.selectedView ~= configEntry.key)
    end
  end
end

function QuestlineTreeView:syncTypeModeButton()
  if not self.typeModeButton then
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  local isTreeMode = self.typeListMode == "tree" -- 当前是否树形模式
  self.typeModeButton:SetShown(self.selectedView == "type")
  self.typeModeButton:SetText(isTreeMode and (localeTable.EJ_QUEST_VIEW_TYPE_LIST or "列表") or (localeTable.EJ_QUEST_VIEW_TYPE_TREE or "树形"))
end

function QuestlineTreeView:applyContentLayout()
  if not self.panelFrame or not self.headerFrame or not self.leftTree or not self.rightContent then
    return
  end

  self.headerFrame:ClearAllPoints()
  self.headerFrame:SetPoint("TOPLEFT", self.panelFrame, "TOPLEFT", 8, -8)
  self.headerFrame:SetPoint("TOPRIGHT", self.panelFrame, "TOPRIGHT", -8, -8)
  self.headerFrame:SetHeight(24)

  if self.selectedView == "type" then
    self.leftTree:Hide()
    self.rightContent:ClearAllPoints()
    self.rightContent:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, -6)
    self.rightContent:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -8, 8)
  else
    self.leftTree:Show()
    self.leftTree:ClearAllPoints()
    self.leftTree:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, -6)
    self.leftTree:SetPoint("BOTTOMLEFT", self.panelFrame, "BOTTOMLEFT", 8, 8)
    self.leftTree:SetWidth(260)

    self.rightContent:ClearAllPoints()
    self.rightContent:SetPoint("TOPLEFT", self.leftTree, "TOPRIGHT", 6, 0)
    self.rightContent:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -8, 8)
  end

  self:syncViewButtons()
  self:syncTypeModeButton()
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

function QuestlineTreeView:getOrCreateRowButton(rowIndex)
  local rowButton = self.rowButtons[rowIndex] -- 指定索引行按钮
  if rowButton then
    return rowButton
  end

  rowButton = CreateFrame("Button", nil, self.scrollChild)
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local highlightTexture = rowButton:GetHighlightTexture() -- 行高亮贴图
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

    if rowData.toggle == true and type(rowData.collapseKey) == "string" then
      local collapseState = getQuestlineCollapsedTable() -- 折叠状态表
      setTreeNodeCollapsed(
        collapseState,
        rowData.collapseKey,
        not isTreeNodeCollapsed(collapseState, rowData.collapseKey)
      )
    end

    if type(rowData.selectKind) == "string" then
      self.selectedKind = rowData.selectKind
    if type(rowData.mapID) == "number" then
      self.selectedMapID = rowData.mapID
    elseif self.selectedKind == "map" or self.selectedKind == "quest" then
      self.selectedMapID = nil
    end
      if type(rowData.typeID) == "number" then
        self.selectedTypeID = rowData.typeID
      end
    if type(rowData.questLineID) == "number" then
      self.selectedQuestLineID = rowData.questLineID
    elseif self.selectedKind == "quest" then
      self.selectedQuestLineID = nil
    elseif self.selectedKind ~= "questline" then
      self.selectedQuestLineID = nil
    end
      if self.selectedKind == "quest" and type(rowData.questID) == "number" then
        self.selectedQuestID = rowData.questID
      else
        self.selectedQuestID = nil
      end
      self:saveSelection()
    end

    self:render()
  end)

  self.rowButtons[rowIndex] = rowButton
  return rowButton
end

function QuestlineTreeView:getOrCreateRightRowButton(rowIndex)
  local rowButton = self.rightRowButtons[rowIndex] -- 右侧指定索引行按钮
  if rowButton then
    return rowButton
  end

  rowButton = CreateFrame("Button", nil, self.rightScrollChild)
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local highlightTexture = rowButton:GetHighlightTexture() -- 行高亮贴图
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
    local rowData = button.rowData -- 右侧当前行数据
    if type(rowData) ~= "table" or type(rowData.onClick) ~= "function" then
      return
    end
    rowData.onClick()
    self:saveSelection()
    self:render()
  end)

  self.rightRowButtons[rowIndex] = rowButton
  return rowButton
end

function QuestlineTreeView:renderRightRows(rowDataList)
  if not self.rightScrollFrame or not self.rightScrollChild then
    return
  end

  if type(rowDataList) ~= "table" or #rowDataList == 0 then
    self:hideAllRightRows()
    self.rightScrollFrame:Hide()
    return
  end

  self.rightScrollFrame:Show()
  local scrollWidth = self.rightScrollFrame:GetWidth() -- 右侧滚动区宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 260
  end
  local rowWidth = math.max(140, scrollWidth - 24) -- 行宽（预留滚动条）
  local rowOffsetY = 6 -- 顶部留白
  local rowIndex = 0 -- 渲染行计数

  for _, rowData in ipairs(rowDataList) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRightRowButton(rowIndex) -- 当前右侧行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", self.rightScrollChild, "TOPLEFT", 6, -((rowIndex - 1) * self.rowHeight + rowOffsetY))
    rowButton:SetWidth(rowWidth)
    rowButton:SetHeight(self.rowHeight)
    rowButton.rowFont:SetText(rowData.text or "")
    if rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
    else
      local redValue, greenValue, blueValue = getQuestStatusTextColor(rowData.status)
      if type(redValue) == "number" and type(greenValue) == "number" and type(blueValue) == "number" then
        rowButton.rowFont:SetTextColor(redValue, greenValue, blueValue)
      else
        rowButton.rowFont:SetTextColor(1, 1, 1)
      end
    end
    rowButton:EnableMouse(type(rowData.onClick) == "function")
    rowButton:Show()
  end

  for hideIndex = rowIndex + 1, #self.rightRowButtons do
    self.rightRowButtons[hideIndex]:Hide()
  end

  local contentHeight = rowIndex * self.rowHeight + rowOffsetY + 4 -- 总内容高度
  local frameHeight = self.rightScrollFrame:GetHeight() -- 当前滚动框高度
  if type(frameHeight) == "number" and frameHeight > 0 then
    contentHeight = math.max(contentHeight, frameHeight + 2)
  end
  self.rightScrollChild:SetSize(rowWidth, contentHeight)
  self.rightScrollFrame:SetVerticalScroll(0)
end

function QuestlineTreeView:render()
  if not self.scrollFrame or not self.scrollChild or not self.emptyText then
    return
  end

  local leftScrollOffset = readVerticalScrollOffset(self.scrollFrame) -- 左树当前滚动位置
  local localeTable = Toolbox.L or {} -- 本地化文案
  local questTabModel = nil -- 任务页签模型
  local queryError = nil -- 查询错误对象
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTabModel) == "function" then
    questTabModel, queryError = Toolbox.Questlines.GetQuestTabModel()
  end

  if queryError then
    self:hideAllRows()
    self:hideAllRightRows()
    if self.rightScrollFrame then
      self.rightScrollFrame:Hide()
    end
    if self.detailText then
      self.detailText:Hide()
    end
    self.scrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end

  self:resolveSelectionWithModel(questTabModel)
  self:saveSelection()

  if self.selectedView == "type" then
    self:hideAllRows()
    self.scrollFrame:Hide()
    self.emptyText:Hide()
  else
    local rowDataList = nil -- 左侧列表行数据
    if self.selectedView == "status" then
      rowDataList = self:buildStatusQuestRows(questTabModel)
    else
      rowDataList = self:buildQuestlineTreeRows(questTabModel)
    end
    if #rowDataList == 0 then
      self:hideAllRows()
      self:hideAllRightRows()
      if self.rightScrollFrame then
        self.rightScrollFrame:Hide()
      end
      if self.detailText then
        self.detailText:Hide()
      end
      self.scrollFrame:Hide()
      self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
      self.emptyText:Show()
      return
    end

    self.emptyText:Hide()
    self.scrollFrame:Show()
    local scrollWidth = self.scrollFrame:GetWidth() -- 滚动视图区宽度
    if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
      scrollWidth = 380
    end
    local rowWidth = math.max(140, scrollWidth - 24) -- 行宽（预留滚动条）
    local rowOffsetY = 6 -- 顶部留白
    local rowIndex = 0 -- 渲染行计数

    for _, rowData in ipairs(rowDataList) do
      rowIndex = rowIndex + 1
      local rowButton = self:getOrCreateRowButton(rowIndex) -- 当前行按钮
      rowButton.rowData = rowData
      rowButton:ClearAllPoints()
      rowButton:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 6, -((rowIndex - 1) * self.rowHeight + rowOffsetY))
    rowButton:SetWidth(rowWidth)
    rowButton:SetHeight(self.rowHeight)
    rowButton.rowFont:SetText(string.rep("  ", rowData.indent or 0) .. (rowData.text or ""))
    if rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
    elseif rowData.status == "completed" then
      rowButton:EnableMouse(true)
      rowButton.rowFont:SetTextColor(0.2, 0.8, 0.2)
    elseif rowData.toggle == true then
      rowButton:EnableMouse(true)
      rowButton.rowFont:SetTextColor(1, 0.82, 0.2)
      else
        rowButton:EnableMouse(true)
        rowButton.rowFont:SetTextColor(1, 1, 1)
      end
      rowButton:Show()
    end

    for hideIndex = rowIndex + 1, #self.rowButtons do
      self.rowButtons[hideIndex]:Hide()
    end

    local contentHeight = rowIndex * self.rowHeight + rowOffsetY + 4 -- 总内容高度
    local frameHeight = self.scrollFrame:GetHeight() -- 当前滚动框高度
    if type(frameHeight) == "number" and frameHeight > 0 then
      contentHeight = math.max(contentHeight, frameHeight + 2)
    end
    self.scrollChild:SetSize(rowWidth, contentHeight)
    restoreVerticalScrollOffset(self.scrollFrame, leftScrollOffset, contentHeight)
  end

  local rightRows = {} -- 右侧列表行
  if self.detailText then
    self.detailText:Hide()
  end

  if self.selectedKind == "quest"
    and type(self.selectedQuestID) == "number"
    and (self.selectedView ~= "status" or type(self.selectedQuestLineID) ~= "number")
  then
    local detailObject = nil -- 任务详情对象
    local detailError = nil -- 任务详情错误
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestDetailByID) == "function" then
      detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(self.selectedQuestID)
    end
    if detailError then
      if self.detailText then
        self.detailText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
        self.detailText:Show()
      end
      self:hideAllRightRows()
      if self.rightScrollFrame then
        self.rightScrollFrame:Hide()
      end
    elseif type(detailObject) == "table" and self.detailText then
      local detailLines = {} -- 任务详情文本行
      detailLines[#detailLines + 1] = (localeTable.EJ_QUEST_DETAIL_TITLE or "任务详情")
      detailLines[#detailLines + 1] = string.format("ID: %s", tostring(detailObject.questID or ""))
      detailLines[#detailLines + 1] = string.format("%s: %s", localeTable.EJ_QUESTLINE_TREE_LABEL or "任务", tostring(detailObject.name or ""))
      detailLines[#detailLines + 1] = string.format("Map: %s", tostring(detailObject.UiMapID or ""))
      if type(detailObject.startNpcID) == "number" then
        detailLines[#detailLines + 1] = string.format("Start NPC: %d", detailObject.startNpcID)
      end
      if type(detailObject.turnInNpcID) == "number" then
        detailLines[#detailLines + 1] = string.format("Turn In NPC: %d", detailObject.turnInNpcID)
      end
      if type(detailObject.prerequisiteQuestIDs) == "table" and #detailObject.prerequisiteQuestIDs > 0 then
        detailLines[#detailLines + 1] = "Prerequisite: " .. table.concat(detailObject.prerequisiteQuestIDs, ", ")
      end
      if type(detailObject.nextQuestIDs) == "table" and #detailObject.nextQuestIDs > 0 then
        detailLines[#detailLines + 1] = "Next: " .. table.concat(detailObject.nextQuestIDs, ", ")
      end
      self.detailText:SetText(table.concat(detailLines, "\n"))
      self.detailText:Show()
      self:hideAllRightRows()
      if self.rightScrollFrame then
        self.rightScrollFrame:Hide()
      end
      if self.rightTitle then
        self.rightTitle:SetText(localeTable.EJ_QUEST_DETAIL_TITLE or "任务详情")
      end
    end
    return
  end

  if self.selectedView == "status" then
    rightRows = self:buildStatusViewRows(questTabModel)
    if self.rightTitle then
      local questLineEntry = type(self.selectedQuestLineID) == "number" and questTabModel.questLineByID and questTabModel.questLineByID[self.selectedQuestLineID] or nil -- 当前任务线对象
      local questLineName = resolveQuestLineDisplayName(questLineEntry) -- 当前任务线显示名
      if type(questLineName) == "string" and questLineName ~= "" then
        self.rightTitle:SetText(questLineName)
      else
        self.rightTitle:SetText(localeTable.EJ_QUEST_VIEW_STATUS or "状态")
      end
    end
  elseif self.selectedView == "type" then
    rightRows = self:buildTypeViewRows(questTabModel)
    if self.rightTitle then
      local typeIndexModel = nil -- 类型索引模型
      local selectedTypeEntry = nil -- 当前选中类型对象
      local selectedTypeName = nil -- 当前选中类型名称
      if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTypeIndex) == "function" then
        typeIndexModel = Toolbox.Questlines.GetQuestTypeIndex()
      end
      selectedTypeEntry = findTypeEntryByID(typeIndexModel and typeIndexModel.typeList or nil, self.selectedTypeID)
      selectedTypeName = resolveTypeEntryName(selectedTypeEntry)
      if type(selectedTypeName) == "string" and selectedTypeName ~= "" then
        self.rightTitle:SetText(selectedTypeName)
      elseif type(self.selectedTypeID) == "number" and Toolbox.Questlines and type(Toolbox.Questlines.GetQuestTypeLabel) == "function" then
        self.rightTitle:SetText(Toolbox.Questlines.GetQuestTypeLabel(self.selectedTypeID))
      else
        self.rightTitle:SetText(localeTable.EJ_QUEST_VIEW_TYPE or "类型")
      end
    end
  elseif self.selectedKind == "questline" and type(self.selectedQuestLineID) == "number" then
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
      local questList = nil -- 任务列表
      local queryListError = nil -- 任务列表查询错误
      questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(self.selectedQuestLineID)
      if not queryListError and type(questList) == "table" then
        appendQuestRowsForQuestLine(rightRows, questList)
      end
    end
    if self.rightTitle then
      self.rightTitle:SetText(localeTable.EJ_QUEST_TASK_LIST_TITLE or "任务列表")
    end
  else
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestLinesForSelection) == "function" then
      local questLineList = nil -- 任务线列表
      local queryListError = nil -- 任务线查询错误
      questLineList, queryListError = Toolbox.Questlines.GetQuestLinesForSelection(
        self.selectedKind,
        self.selectedMapID
      )
      if not queryListError and type(questLineList) == "table" then
        for _, questLineEntry in ipairs(questLineList) do
          local progressInfo = nil -- 任务线进度
          local progressError = nil -- 任务线进度查询错误
          local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")) -- 当前任务线显示名
          if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestLineProgress) == "function" then
            progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineEntry.id)
          end
          local progressText = formatProgressText(progressInfo, localeTable) or "0/0" -- 任务线进度文本
          local questCount = tonumber(questLineEntry.questCount) or 0 -- 任务数量
          rightRows[#rightRows + 1] = {
            text = string.format("%s  (%s · %d)", questLineName, progressText, questCount),
            onClick = function()
              self.selectedKind = "questline"
              self.selectedQuestLineID = questLineEntry.id
              self.selectedMapID = questLineEntry.UiMapID
            end,
          }
        end
      end
    end
    if self.rightTitle then
      self.rightTitle:SetText(localeTable.EJ_QUEST_VIEW_MAP or (localeTable.EJ_QUESTLINE_LIST_TITLE or "任务线列表"))
    end
  end

  self:renderRightRows(rightRows)
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

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame

  if self.tabButton
    and self.panelFrame
    and self.headerFrame
    and self.leftTree
    and self.rightContent
    and self.scrollFrame
    and self.scrollChild
    and self.rightScrollFrame
    and self.rightScrollChild
    and self.emptyText
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
    local instanceSelect = journalFrame.instanceSelect -- 地下城/团队副本主内容区
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

  if not self.headerFrame then
    local headerFrame = CreateFrame("Frame", nil, self.panelFrame)
    self.headerFrame = headerFrame
  end

  if not self.leftTree then
    local leftTree = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
    leftTree:SetWidth(260)
    self.leftTree = leftTree
  end

  if not self.rightContent then
    local rightContent = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
    self.rightContent = rightContent
  end

  if not self.scrollFrame then
    local scrollFrame = CreateFrame("ScrollFrame", "ToolboxEJQuestlineScrollFrame", self.leftTree, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", self.leftTree, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", self.leftTree, "BOTTOMRIGHT", -28, 6)
    self.scrollFrame = scrollFrame
  end

  if not self.scrollChild then
    local scrollChild = CreateFrame("Frame", "ToolboxEJQuestlineScrollChild", self.scrollFrame)
    scrollChild:SetSize(200, 32)
    self.scrollChild = scrollChild
  end

  if self.scrollFrame and self.scrollChild and self.scrollFrame:GetScrollChild() ~= self.scrollChild then
    self.scrollFrame:SetScrollChild(self.scrollChild)
  end

  if not self.rightTitle then
    local rightTitle = self.rightContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightTitle:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -10)
    rightTitle:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -10)
    rightTitle:SetJustifyH("LEFT")
    rightTitle:SetText((Toolbox.L or {}).EJ_QUESTLINE_LIST_TITLE or "任务线列表")
    self.rightTitle = rightTitle
  end

  if not self.rightScrollFrame then
    local rightScrollFrame = CreateFrame("ScrollFrame", nil, self.rightContent, "UIPanelScrollFrameTemplate")
    rightScrollFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -30)
    rightScrollFrame:SetPoint("BOTTOMRIGHT", self.rightContent, "BOTTOMRIGHT", -26, 10)
    self.rightScrollFrame = rightScrollFrame
  end

  if not self.rightScrollChild then
    local rightScrollChild = CreateFrame("Frame", nil, self.rightScrollFrame)
    rightScrollChild:SetSize(200, 32)
    self.rightScrollChild = rightScrollChild
  end

  if self.rightScrollFrame and self.rightScrollChild and self.rightScrollFrame:GetScrollChild() ~= self.rightScrollChild then
    self.rightScrollFrame:SetScrollChild(self.rightScrollChild)
  end

  if not self.detailText then
    local detailText = self.rightContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -34)
    detailText:SetPoint("BOTTOMRIGHT", self.rightContent, "BOTTOMRIGHT", -10, 10)
    detailText:SetJustifyH("LEFT")
    detailText:SetJustifyV("TOP")
    detailText:SetWordWrap(true)
    detailText:Hide()
    self.detailText = detailText
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

  if type(next(self.viewButtons)) ~= "table" and not self.viewButtons.status then
    local buttonConfigList = {
      { key = "status", offsetX = 0 },
      { key = "type", offsetX = 68 },
      { key = "map", offsetX = 136 },
    }
    for _, configEntry in ipairs(buttonConfigList) do
      local buttonObject = CreateFrame("Button", nil, self.headerFrame, "UIPanelButtonTemplate")
      buttonObject:SetSize(62, 20)
      buttonObject:SetPoint("TOPLEFT", self.headerFrame, "TOPLEFT", configEntry.offsetX, 0)
      buttonObject:SetScript("OnClick", function()
        self:setViewMode(configEntry.key)
      end)
      self.viewButtons[configEntry.key] = buttonObject
    end
  end

  if not self.typeModeButton then
    local typeModeButton = CreateFrame("Button", nil, self.headerFrame, "UIPanelButtonTemplate")
    typeModeButton:SetSize(54, 20)
    typeModeButton:SetPoint("TOPRIGHT", self.headerFrame, "TOPRIGHT", 0, 0)
    typeModeButton:SetScript("OnClick", function()
      self.typeListMode = self.typeListMode == "tree" and "list" or "tree"
      self:syncTypeModeButton()
      self:render()
    end)
    self.typeModeButton = typeModeButton
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
-- 任务页签左树导航（资料片 -> 地图任务线/任务类型）
-- ============================================================================

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

  self.selectedModeKey = normalizeQuestNavModeKey(self.selectedModeKey)
  local expansionEntry = type(self.selectedExpansionID) == "number" and expansionByID[self.selectedExpansionID] or nil -- 当前资料片
  if type(expansionEntry) ~= "table" then
    self.selectedMapID = nil
    self.selectedTypeKey = ""
    self.expandedQuestLineID = nil
    return nil
  end

  local modeByKey = expansionEntry.modeByKey or {} -- 模式索引
  if type(modeByKey[self.selectedModeKey]) ~= "table" then
    self.selectedModeKey = "map_questline"
  end

  if self.selectedModeKey == "map_questline" then
    local modeEntry = modeByKey.map_questline -- 地图模式
    local firstMapEntry = modeEntry and modeEntry.entries and modeEntry.entries[1] or nil -- 首个地图
    local hasSelectedMap = false -- 当前地图是否存在
    for _, mapEntry in ipairs(modeEntry and modeEntry.entries or {}) do
      if mapEntry.id == self.selectedMapID then
        hasSelectedMap = true
        break
      end
    end
    if not hasSelectedMap then
      self.selectedMapID = firstMapEntry and firstMapEntry.id or nil
    end
    self.selectedTypeKey = ""
  else
    local modeEntry = modeByKey.quest_type -- 类型模式
    local firstTypeEntry = modeEntry and modeEntry.entries and modeEntry.entries[1] or nil -- 首个类型
    local hasSelectedType = false -- 当前类型是否存在
    for _, typeEntry in ipairs(modeEntry and modeEntry.entries or {}) do
      if tostring(typeEntry.id) == self.selectedTypeKey then
        hasSelectedType = true
        break
      end
    end
    if not hasSelectedType then
      self.selectedTypeKey = firstTypeEntry and tostring(firstTypeEntry.id) or ""
    end
    self.selectedMapID = nil
    self.expandedQuestLineID = nil
  end

  return expansionEntry
end

function QuestlineTreeView:buildLeftTreeRows(navigationModel)
  local rowDataList = {} -- 左侧树行数据
  local expansionList = navigationModel and navigationModel.expansionList or {} -- 资料片列表
  local expansionByID = navigationModel and navigationModel.expansionByID or {} -- 资料片索引

  for _, expansionEntry in ipairs(expansionList) do
    local expansionSelected = self.selectedExpansionID == expansionEntry.id -- 资料片是否选中
    rowDataList[#rowDataList + 1] = {
      kind = "expansion",
      text = tostring(expansionEntry.name or ""),
      selected = expansionSelected,
      expansionID = expansionEntry.id,
    }
    if expansionSelected then
      local fullExpansionEntry = expansionByID[expansionEntry.id] -- 完整资料片对象
      for _, modeEntry in ipairs(fullExpansionEntry and fullExpansionEntry.modes or {}) do
        local modeSelected = self.selectedModeKey == modeEntry.key -- 模式是否选中
        rowDataList[#rowDataList + 1] = {
          kind = "mode",
          text = tostring(modeEntry.name or ""),
          selected = modeSelected,
          expansionID = expansionEntry.id,
          modeKey = modeEntry.key,
        }
        if modeSelected then
          for _, childEntry in ipairs(modeEntry.entries or {}) do
            rowDataList[#rowDataList + 1] = {
              kind = childEntry.kind,
              text = tostring(childEntry.name or ""),
              selected = (childEntry.kind == "map" and self.selectedMapID == childEntry.id)
                or (childEntry.kind == "type_group" and self.selectedTypeKey == tostring(childEntry.id)),
              expansionID = expansionEntry.id,
              modeKey = modeEntry.key,
              mapID = childEntry.kind == "map" and childEntry.id or nil,
              typeKey = childEntry.kind == "type_group" and tostring(childEntry.id) or nil,
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
    local rowData = button.rowData -- 当前左树行数据
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
      self.selectedExpansionID = rowData.expansionID
      self.selectedModeKey = normalizeQuestNavModeKey(rowData.modeKey)
      self.expandedQuestLineID = nil
    elseif rowData.kind == "map" and type(rowData.mapID) == "number" then
      self.selectedExpansionID = rowData.expansionID
      self.selectedModeKey = "map_questline"
      self.selectedMapID = rowData.mapID
      self.expandedQuestLineID = nil
      self.selectedTypeKey = ""
    elseif rowData.kind == "type_group" and type(rowData.typeKey) == "string" then
      self.selectedExpansionID = rowData.expansionID
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
    local rowData = button.rowData -- 当前主区行数据
    if type(rowData) ~= "table" or rowData.kind ~= "quest" then
      return
    end
    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(rowData.questID) -- 当前任务详情
    if not detailError then
      buildQuestTooltip(detailObject, Toolbox.L or {})
    end
  end)
  rowButton:SetScript("OnLeave", function(button)
    local rowData = button.rowData -- 当前主区行数据
    if type(rowData) == "table" and rowData.kind == "quest" and GameTooltip and GameTooltip.Hide then
      GameTooltip:Hide()
    end
  end)
  rowButton:SetScript("OnClick", function(button)
    local rowData = button.rowData -- 当前主区行数据
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
  local questLineList, errorObject = Toolbox.Questlines.GetQuestLinesForMap(self.selectedMapID) -- 当前地图任务线列表
  if errorObject then
    return {}, errorObject
  end

  for _, questLineEntry in ipairs(questLineList or {}) do
    local progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineEntry.id) -- 当前任务线进度
    local progressText = not progressError and formatProgressText(progressInfo, localeTable) or nil -- 任务线进度文本
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
      local questList, listError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineEntry.id) -- 当前任务线任务列表
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
  local questList, errorObject = Toolbox.Questlines.GetTasksForTypeGroup(self.selectedExpansionID, self.selectedTypeKey) -- 当前类型任务列表
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
  local scrollWidth = self.scrollFrame:GetWidth() -- 左树滚动宽度
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

  local contentHeight = rowIndex * self.rowHeight + rowOffsetY + 4 -- 内容高度
  self.scrollChild:SetSize(rowWidth, math.max(contentHeight, 10))
end

function QuestlineTreeView:renderRightRows(rowDataList)
  if not self.rightScrollFrame or not self.rightScrollChild then
    return
  end
  local scrollWidth = self.rightScrollFrame:GetWidth() -- 主区滚动宽度
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
    local indentLevel = rowData.kind == "quest" and 1 or 0 -- 主区缩进层级
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

  local contentHeight = rowIndex * self.rowHeight + rowOffsetY + 4 -- 内容高度
  self.rightScrollChild:SetSize(rowWidth, math.max(contentHeight, 10))
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
    self.detailPopupJumpButton:SetText((localeTable.EJ_QUEST_JUMP_TO_QUESTLINE or "跳转到对应地图/任务线"))
  end
  if self.detailPopupFrame then
    self.detailPopupFrame:Show()
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

  if self.rightTitle then
    self.rightTitle:ClearAllPoints()
    self.rightTitle:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -10)
    self.rightTitle:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -10)
  end
  if self.rightScrollFrame then
    self.rightScrollFrame:ClearAllPoints()
    self.rightScrollFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -30)
    self.rightScrollFrame:SetPoint("BOTTOMRIGHT", self.rightContent, "BOTTOMRIGHT", -26, 10)
  end
end

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame

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
    local instanceSelect = journalFrame.instanceSelect -- 地下城/团队副本主内容区
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
    local leftTree = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
    self.leftTree = leftTree
  end
  if not self.rightContent then
    local rightContent = CreateFrame("Frame", nil, self.panelFrame, "InsetFrameTemplate3")
    self.rightContent = rightContent
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
    self.rightTitle = self.rightContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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

  local expansionEntry = self:resolveNavigationDefaults(navigationModel or {}) -- 当前资料片对象
  local leftRows = self:buildLeftTreeRows(navigationModel or {}) -- 左树行
  local mainRows = {} -- 主区行
  local mainError = nil -- 主区错误
  if self.selectedModeKey == "quest_type" then
    mainRows, mainError = self:buildMainRowsForType()
  else
    mainRows, mainError = self:buildMainRowsForMap()
  end

  if mainError then
    self:hideAllRows()
    self:hideAllRightRows()
    self.rightScrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end

  self.emptyText:SetShown(#leftRows == 0 and #mainRows == 0)
  if self.emptyText:IsShown() then
    self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
  end

  self:renderLeftRows(leftRows)
  self:renderRightRows(mainRows)
  if self.rightTitle then
    if self.selectedModeKey == "quest_type" then
      self.rightTitle:SetText((expansionEntry and expansionEntry.name or "") .. " / " .. ((localeTable.EJ_QUEST_NAV_MODE_QUEST_TYPE or "任务类型")))
    else
      self.rightTitle:SetText((expansionEntry and expansionEntry.name or "") .. " / " .. ((localeTable.EJ_QUEST_NAV_MODE_MAP_QUESTLINE or "地图任务线")))
    end
  end
end

-- ============================================================================
-- 任务页签导航重构（资料片 -> 分类 -> 任务线 -> 任务）
-- ============================================================================

local function normalizeQuestNavCategoryKey(categoryKey)
  if categoryKey == "type" then
    return "type"
  end
  return "map"
end

local function isQuestLinePresentInGroupList(groupList, questLineID)
  if type(questLineID) ~= "number" then
    return false
  end
  for _, groupEntry in ipairs(groupList or {}) do
    for _, questLineEntry in ipairs(groupEntry.questLines or {}) do
      if type(questLineEntry) == "table" and questLineEntry.id == questLineID then
        return true
      end
    end
  end
  return false
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

function QuestlineTreeView:loadSelection()
  local moduleDb = getModuleDb() -- 模块存档
  self.selectedExpansionID = normalizeSelectionID(moduleDb.questNavExpansionID)
  self.selectedCategoryKey = normalizeQuestNavCategoryKey(moduleDb.questNavCategoryKey)
  self.selectedQuestLineID = normalizeSelectionID(moduleDb.questNavSelectedQuestLineID)
  self.selectedQuestID = nil
end

function QuestlineTreeView:saveSelection()
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questNavExpansionID = type(self.selectedExpansionID) == "number" and self.selectedExpansionID or 0
  moduleDb.questNavCategoryKey = normalizeQuestNavCategoryKey(self.selectedCategoryKey)
  moduleDb.questNavSelectedQuestLineID = type(self.selectedQuestLineID) == "number" and self.selectedQuestLineID or 0
end

function QuestlineTreeView:setExpansionID(expansionID)
  if type(expansionID) ~= "number" then
    return
  end
  self.selectedExpansionID = expansionID
  self.selectedQuestLineID = nil
  self:hideQuestDetailPopup()
  self:saveSelection()
  self:render()
end

function QuestlineTreeView:setCategoryKey(categoryKey)
  self.selectedCategoryKey = normalizeQuestNavCategoryKey(categoryKey)
  self.selectedQuestLineID = nil
  self:hideQuestDetailPopup()
  self:saveSelection()
  self:render()
end

function QuestlineTreeView:getActiveNavigationGroupList(navigationModel)
  local expansionList = navigationModel and navigationModel.expansionList or nil -- 资料片列表
  local expansionByID = navigationModel and navigationModel.expansionByID or nil -- 资料片索引
  if type(expansionList) ~= "table" or #expansionList == 0 or type(expansionByID) ~= "table" then
    self.selectedExpansionID = nil
    self.selectedQuestLineID = nil
    return nil, {}
  end

  if type(self.selectedExpansionID) ~= "number" or type(expansionByID[self.selectedExpansionID]) ~= "table" then
    self.selectedExpansionID = expansionList[1] and expansionList[1].id or nil
  end
  self.selectedCategoryKey = normalizeQuestNavCategoryKey(self.selectedCategoryKey)

  local expansionEntry = type(self.selectedExpansionID) == "number" and expansionByID[self.selectedExpansionID] or nil -- 当前资料片对象
  if type(expansionEntry) ~= "table" then
    self.selectedQuestLineID = nil
    return nil, {}
  end

  local groupList = expansionEntry.categoryGroups and expansionEntry.categoryGroups[self.selectedCategoryKey] or {} -- 当前分类分组列表
  if type(groupList) ~= "table" then
    groupList = {}
  end
  if type(self.selectedQuestLineID) == "number" and not isQuestLinePresentInGroupList(groupList, self.selectedQuestLineID) then
    self.selectedQuestLineID = nil
  end
  return expansionEntry, groupList
end

function QuestlineTreeView:syncExpansionButtons(navigationModel)
  self.expansionButtons = self.expansionButtons or {}
  local expansionList = navigationModel and navigationModel.expansionList or {} -- 资料片列表
  local previousButton = nil -- 上一个按钮
  for expansionIndex, expansionEntry in ipairs(expansionList) do
    local buttonObject = self.expansionButtons[expansionIndex] -- 当前资料片按钮
    if not buttonObject then
      buttonObject = CreateFrame("Button", nil, self.expansionNavFrame, "UIPanelButtonTemplate")
      buttonObject:SetSize(86, 20)
      buttonObject:SetScript("OnClick", function(button)
        local buttonExpansionID = button.expansionID -- 当前按钮资料片 ID
        self:setExpansionID(buttonExpansionID)
      end)
      self.expansionButtons[expansionIndex] = buttonObject
    end
    buttonObject.expansionID = expansionEntry.id
    buttonObject:SetText(expansionEntry.name or tostring(expansionEntry.id or ""))
    buttonObject:ClearAllPoints()
    if previousButton then
      buttonObject:SetPoint("LEFT", previousButton, "RIGHT", 4, 0)
    else
      buttonObject:SetPoint("TOPLEFT", self.expansionNavFrame, "TOPLEFT", 0, 0)
    end
    buttonObject:SetShown(true)
    previousButton = buttonObject
  end

  for hideIndex = #expansionList + 1, #self.expansionButtons do
    self.expansionButtons[hideIndex]:Hide()
  end
end

function QuestlineTreeView:syncCategoryButtons()
  self.categoryButtons = self.categoryButtons or {}
  local localeTable = Toolbox.L or {} -- 本地化文案
  local buttonConfigList = {
    { key = "map", text = localeTable.EJ_QUEST_VIEW_MAP or "地图", offsetX = 0 },
    { key = "type", text = localeTable.EJ_QUEST_VIEW_TYPE or "类型", offsetX = 72 },
  }
  for _, configEntry in ipairs(buttonConfigList) do
    local buttonObject = self.categoryButtons[configEntry.key] -- 分类按钮
    if not buttonObject then
      buttonObject = CreateFrame("Button", nil, self.categoryNavFrame, "UIPanelButtonTemplate")
      buttonObject:SetSize(64, 20)
      buttonObject:SetScript("OnClick", function()
        self:setCategoryKey(configEntry.key)
      end)
      self.categoryButtons[configEntry.key] = buttonObject
    end
    buttonObject:SetText(configEntry.text)
    buttonObject:ClearAllPoints()
    buttonObject:SetPoint("TOPLEFT", self.categoryNavFrame, "TOPLEFT", configEntry.offsetX, 0)
    buttonObject:SetShown(true)
  end
end

function QuestlineTreeView:applyContentLayout()
  if not self.panelFrame or not self.headerFrame or not self.scrollFrame then
    return
  end

  self.headerFrame:ClearAllPoints()
  self.headerFrame:SetPoint("TOPLEFT", self.panelFrame, "TOPLEFT", 8, -8)
  self.headerFrame:SetPoint("TOPRIGHT", self.panelFrame, "TOPRIGHT", -8, -8)
  self.headerFrame:SetHeight(48)

  if self.expansionNavFrame then
    self.expansionNavFrame:ClearAllPoints()
    self.expansionNavFrame:SetPoint("TOPLEFT", self.headerFrame, "TOPLEFT", 0, 0)
    self.expansionNavFrame:SetPoint("TOPRIGHT", self.headerFrame, "TOPRIGHT", 0, 0)
    self.expansionNavFrame:SetHeight(20)
  end
  if self.categoryNavFrame then
    self.categoryNavFrame:ClearAllPoints()
    self.categoryNavFrame:SetPoint("TOPLEFT", self.headerFrame, "TOPLEFT", 0, -24)
    self.categoryNavFrame:SetPoint("TOPRIGHT", self.headerFrame, "TOPRIGHT", 0, -24)
    self.categoryNavFrame:SetHeight(20)
  end

  self.scrollFrame:ClearAllPoints()
  self.scrollFrame:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, -6)
  self.scrollFrame:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -24, 8)
end

function QuestlineTreeView:getOrCreateRowButton(rowIndex)
  local rowButton = self.rowButtons[rowIndex] -- 指定索引行按钮
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

  rowButton:SetScript("OnEnter", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" or rowData.kind ~= "quest" then
      return
    end
    local detailObject = nil -- 当前任务详情对象
    local detailError = nil -- 当前任务详情错误
    if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestDetailByID) == "function" then
      detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(rowData.questID)
    end
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
      self.selectedQuestLineID = rowData.questLineID
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

  self.rowButtons[rowIndex] = rowButton
  return rowButton
end

function QuestlineTreeView:buildQuestlineGroupRows(groupList)
  local rowDataList = {} -- 主视图任务线行
  local localeTable = Toolbox.L or {} -- 本地化文案
  for _, groupEntry in ipairs(groupList or {}) do
    rowDataList[#rowDataList + 1] = {
      kind = "group",
      text = groupEntry.name or "",
    }
    for _, questLineEntry in ipairs(groupEntry.questLines or {}) do
      local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineEntry.id or "?")) -- 当前任务线显示名
      local questLineText = questLineName -- 当前任务线文本
      if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestLineProgress) == "function" then
        local progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineEntry.id) -- 任务线进度
        if not progressError then
          local progressText = formatProgressText(progressInfo, localeTable) -- 任务线进度文本
          if type(progressText) == "string" then
            questLineText = string.format("%s (%s)", questLineText, progressText)
          end
        end
      end
      rowDataList[#rowDataList + 1] = {
        kind = "questline",
        text = questLineText,
        questLineID = questLineEntry.id,
        selected = self.selectedQuestLineID == questLineEntry.id,
      }
    end
  end
  return rowDataList
end

function QuestlineTreeView:buildQuestRows()
  local rowDataList = {} -- 任务列表行
  if type(self.selectedQuestLineID) ~= "number" then
    return rowDataList, nil
  end

  local questList = nil -- 当前任务线任务列表
  local queryListError = nil -- 任务列表查询错误
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestListByQuestLineID) == "function" then
    questList, queryListError = Toolbox.Questlines.GetQuestListByQuestLineID(self.selectedQuestLineID)
  end
  if queryListError then
    return rowDataList, queryListError
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

function QuestlineTreeView:renderRowList(rowDataList)
  local scrollWidth = self.scrollFrame:GetWidth() -- 列表滚动宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 520
  end
  local rowWidth = math.max(180, scrollWidth - 24) -- 行宽
  local rowOffsetY = 6 -- 顶部留白
  local rowIndex = 0 -- 行索引

  for _, rowData in ipairs(rowDataList or {}) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRowButton(rowIndex) -- 当前行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 6, -((rowIndex - 1) * self.rowHeight + rowOffsetY))
    rowButton:SetWidth(rowWidth)
    rowButton:SetHeight(self.rowHeight)
    rowButton.rowFont:SetText(rowData.text or "")
    if rowData.kind == "group" then
      rowButton.rowFont:SetTextColor(1, 0.82, 0.2)
    elseif rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
    elseif rowData.status == "completed" then
      rowButton.rowFont:SetTextColor(0.2, 0.8, 0.2)
    else
      rowButton.rowFont:SetTextColor(1, 1, 1)
    end
    rowButton:EnableMouse(rowData.kind == "questline" or rowData.kind == "quest")
    rowButton:Show()
  end

  for hideIndex = rowIndex + 1, #self.rowButtons do
    self.rowButtons[hideIndex]:Hide()
  end

  local contentHeight = rowIndex * self.rowHeight + rowOffsetY + 4 -- 内容高度
  local frameHeight = self.scrollFrame:GetHeight() -- 滚动框高度
  if type(frameHeight) == "number" and frameHeight > 0 then
    contentHeight = math.max(contentHeight, frameHeight + 2)
  end
  self.scrollChild:SetSize(rowWidth, contentHeight)
end

function QuestlineTreeView:hideQuestDetailPopup()
  if self.detailPopupFrame then
    self.detailPopupFrame:Hide()
  end
end

function QuestlineTreeView:showQuestDetailPopup(questID)
  local detailObject = nil -- 当前任务详情对象
  local detailError = nil -- 当前任务详情错误
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestDetailByID) == "function" then
    detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(questID)
  end
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
  if self.detailPopupFrame then
    self.detailPopupFrame:Show()
  end
end

function QuestlineTreeView:render()
  if not self.scrollFrame or not self.scrollChild or not self.emptyText then
    return
  end

  local scrollOffset = readVerticalScrollOffset(self.scrollFrame) -- 当前滚动位置
  local localeTable = Toolbox.L or {} -- 本地化文案
  local navigationModel = nil -- 任务导航模型
  local queryError = nil -- 导航查询错误
  if Toolbox.Questlines and type(Toolbox.Questlines.GetQuestNavigationModel) == "function" then
    navigationModel, queryError = Toolbox.Questlines.GetQuestNavigationModel()
  end
  if queryError then
    self:hideAllRows()
    self.scrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    self:hideQuestDetailPopup()
    return
  end

  local expansionEntry, groupList = self:getActiveNavigationGroupList(navigationModel or {}) -- 当前导航分组
  self:syncExpansionButtons(navigationModel or { expansionList = {} })
  self:syncCategoryButtons()
  self:saveSelection()

  local rowDataList = nil -- 主视图行数据
  local rowError = nil -- 主视图错误
  if type(self.selectedQuestLineID) == "number" then
    rowDataList, rowError = self:buildQuestRows()
  else
    rowDataList = self:buildQuestlineGroupRows(groupList)
  end

  if rowError then
    self:hideAllRows()
    self.scrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    self:hideQuestDetailPopup()
    return
  end

  if type(rowDataList) ~= "table" or #rowDataList == 0 then
    self:hideAllRows()
    self.scrollFrame:Hide()
    if type(self.selectedQuestLineID) == "number" then
      self.emptyText:SetText(localeTable.EJ_QUEST_FILTER_EMPTY or "当前筛选下没有可显示的任务。")
    elseif type(expansionEntry) ~= "table" then
      self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
    else
      self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
    end
    self.emptyText:Show()
    self:hideQuestDetailPopup()
    return
  end

  self.emptyText:Hide()
  self.scrollFrame:Show()
  self:renderRowList(rowDataList)
  restoreVerticalScrollOffset(self.scrollFrame, scrollOffset, self.scrollChild:GetHeight())
end

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame
  self.expansionButtons = self.expansionButtons or {}
  self.categoryButtons = self.categoryButtons or {}

  if self.tabButton
    and self.panelFrame
    and self.headerFrame
    and self.expansionNavFrame
    and self.categoryNavFrame
    and self.scrollFrame
    and self.scrollChild
    and self.emptyText
    and self.detailPopupFrame
    and self.detailPopupText
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
    local instanceSelect = journalFrame.instanceSelect -- 地下城/团队副本主内容区
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

  if not self.headerFrame then
    self.headerFrame = CreateFrame("Frame", nil, self.panelFrame)
  end
  if not self.expansionNavFrame then
    self.expansionNavFrame = CreateFrame("Frame", nil, self.headerFrame)
  end
  if not self.categoryNavFrame then
    self.categoryNavFrame = CreateFrame("Frame", nil, self.headerFrame)
  end

  if not self.scrollFrame then
    local scrollFrame = CreateFrame("ScrollFrame", "ToolboxEJQuestlineScrollFrame", self.panelFrame, "UIPanelScrollFrameTemplate")
    self.scrollFrame = scrollFrame
  end
  if not self.scrollChild then
    local scrollChild = CreateFrame("Frame", "ToolboxEJQuestlineScrollChild", self.scrollFrame)
    scrollChild:SetSize(200, 32)
    self.scrollChild = scrollChild
  end
  if self.scrollFrame and self.scrollChild and self.scrollFrame:GetScrollChild() ~= self.scrollChild then
    self.scrollFrame:SetScrollChild(self.scrollChild)
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
    popupText:SetPoint("TOPLEFT", self.detailPopupFrame, "TOPLEFT", 12, -36)
    popupText:SetPoint("BOTTOMRIGHT", self.detailPopupFrame, "BOTTOMRIGHT", -12, 12)
    popupText:SetJustifyH("LEFT")
    popupText:SetJustifyV("TOP")
    popupText:SetWordWrap(true)
    self.detailPopupText = popupText
  end

  self:loadSelection()
  self:syncTabLabel()
  self:applyContentLayout()
  self:hookVanillaTabsOnce()
end

-- ============================================================================
-- 任务页签最终覆盖定义（左侧资料片树 + 两个子入口）
-- ============================================================================

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
            rowDataList[#rowDataList + 1] = {
              kind = childEntry.kind,
              text = childEntry.name,
              selected = (childEntry.kind == "map" and self.selectedMapID == childEntry.id)
                or (childEntry.kind == "type_group" and self.selectedTypeKey == tostring(childEntry.id)),
              expansionID = expansionSummary.id,
              modeKey = modeEntry.key,
              mapID = childEntry.kind == "map" and childEntry.id or nil,
              typeKey = childEntry.kind == "type_group" and tostring(childEntry.id) or nil,
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
  if self.rightTitle then
    self.rightTitle:ClearAllPoints()
    self.rightTitle:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -10)
    self.rightTitle:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -10)
  end
  if self.rightScrollFrame then
    self.rightScrollFrame:ClearAllPoints()
    self.rightScrollFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -30)
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
  self.emptyText:SetShown(#leftRows == 0 and #mainRows == 0)
  if self.emptyText:IsShown() then
    self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
  end
  if self.rightTitle then
    local modeText = self.selectedModeKey == "quest_type" and (localeTable.EJ_QUEST_NAV_MODE_QUEST_TYPE or "任务类型") or (localeTable.EJ_QUEST_NAV_MODE_MAP_QUESTLINE or "地图任务线")
    self.rightTitle:SetText((expansionEntry and expansionEntry.name or "") .. " / " .. modeText)
  end
end

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame
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
  if GameTooltip._toolboxEJMicroLockoutsAdded then
    return
  end
  GameTooltip._toolboxEJMicroLockoutsAdded = true

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
  GameTooltip._toolboxEJMicroLockoutsAdded = nil
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
          GameTooltip._toolboxEJMicroLockoutsAdded = nil
        end
        appendAdventureGuideMicroButtonLockoutLines()
        Runtime.TooltipShow(GameTooltip)
      end)
    end)
    microButton:HookScript("OnLeave", function()
      if GameTooltip then
        GameTooltip._toolboxEJMicroLockoutsAdded = nil
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
