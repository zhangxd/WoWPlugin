--[[
  quest 模块任务视图私有实现。
]]

local Internal = Toolbox.QuestInternal -- quest 模块内部命名空间
local Runtime = Internal.Runtime
local CreateFrame = Internal.CreateFrame

local function getModuleDb()
  return Internal.GetModuleDb()
end

local function isQuestlineTreeEnabled()
  return Internal.IsQuestlineTreeEnabled()
end

local function normalizeSelectionID(value)
  if type(value) == "number" and value > 0 then
    return value
  end
  return nil
end

local QuestlineTreeView = {
  tabButton = nil,
  panelFrame = nil,
  leftTree = nil,
  rightContent = nil,
  modeTabButtonByKey = {},
  scrollFrame = nil,
  scrollChild = nil,
  emptyText = nil,
  rowButtons = {},
  rightScrollFrame = nil,
  rightScrollChild = nil,
  rightRowButtons = {},
  rightTitle = nil,
  activeLogCurrentPanel = nil,
  activeLogCurrentTitle = nil,
  activeLogCurrentScrollFrame = nil,
  activeLogCurrentScrollChild = nil,
  activeLogCurrentRowButtons = {},
  activeLogRecentPanel = nil,
  activeLogRecentTitle = nil,
  activeLogRecentScrollFrame = nil,
  activeLogRecentScrollChild = nil,
  activeLogRecentRowButtons = {},
  activeLogRecentToggleButton = nil,
  activeLogRecentCollapsed = false,
  rowHeight = 21,
  selected = false,
  selectedExpansionID = nil,
  selectedModeKey = "active_log",
  selectedMapID = nil,
  selectedTypeKey = "",
  searchText = "",
  expandedQuestLineID = nil,
  selectedQuestID = nil,
  hostJournalFrame = nil,
  hookedNativeTabs = setmetatable({}, {__mode = "k"}),
  wasShowingPanel = false,
  activeRootState = "native",
  nativeTabBeforeQuest = nil,
  pendingNativeSelection = false,
}

local VIEW_STYLE = {
  leftPanelWidth = 244,
  leftRowGap = 2,
  rightRowGap = 2,
  expansionExtraHeight = 2,
  modeTabHeight = 22,
  modeTabGap = 8,
  activeLogPanelGap = 8,
  activeLogRecentRatio = 0.25,
}

local function getQuestlineCollapsedTable()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.questlineTreeCollapsed) ~= "table" then
    moduleDb.questlineTreeCollapsed = {}
  end
  return moduleDb.questlineTreeCollapsed
end

local RECENT_COMPLETED_MIN = 1 -- 最近完成最小保留条数
local RECENT_COMPLETED_MAX = 30 -- 最近完成最大保留条数
local RECENT_COMPLETED_DEFAULT = 10 -- 最近完成默认保留条数

local function normalizeRecentCompletedMaxValue(rawValue)
  if type(rawValue) ~= "number" then
    return RECENT_COMPLETED_DEFAULT
  end
  local normalizedValue = math.floor(rawValue) -- 归一化后的条数
  if normalizedValue < RECENT_COMPLETED_MIN then
    return RECENT_COMPLETED_MIN
  end
  if normalizedValue > RECENT_COMPLETED_MAX then
    return RECENT_COMPLETED_MAX
  end
  return normalizedValue
end

local function getRecentCompletedQuestMaxValue()
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questRecentCompletedMax = normalizeRecentCompletedMaxValue(moduleDb.questRecentCompletedMax)
  return moduleDb.questRecentCompletedMax
end

local function getRecentCompletedQuestList()
  local moduleDb = getModuleDb() -- 模块存档
  if type(moduleDb.questRecentCompletedList) ~= "table" then
    moduleDb.questRecentCompletedList = {}
  end
  return moduleDb.questRecentCompletedList
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
  -- 独立 quest 模块只依赖自身宿主 Frame，不主动拉起冒险手册插件。
  return _G.ToolboxQuestFrame ~= nil
end

local function isStandaloneQuestHost(hostFrame)
  return hostFrame ~= nil and hostFrame == _G.ToolboxQuestFrame
end

buildDefaultRootTabOrderIds = function()
  ensureEncounterJournalAddonLoaded()

  local defaultOrderIds = {} -- 默认顺序（按 ID）
  local addedTabIdSet = {} -- 已纳入默认顺序的页签 ID 集合
  local journalFrame = _G.ToolboxQuestFrame -- quest 模块根面板
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
    return "[OK]"
  end
  if statusText == "ready" then
    return "[!]"
  end
  if statusText == "active" then
    return "[>]"
  end
  return "[ ]"
end

local function getQuestStatusTextColor(statusText)
  if statusText == "completed" then
    return 0.2, 0.8, 0.2
  end
  if statusText == "ready" then
    return 1.0, 0.82, 0.18
  end
  if statusText == "active" then
    return 0.35, 0.85, 1
  end
  return nil
end

local function isTreeNodeCollapsed(collapseState, collapseKey)
  if type(collapseState) ~= "table" or type(collapseKey) ~= "string" then
    return false
  end
  return collapseState[collapseKey] == true
end

local function setTreeNodeCollapsed(collapseState, collapseKey, collapsed)
  if type(collapseState) ~= "table" or type(collapseKey) ~= "string" then
    return
  end
  if collapsed == true then
    collapseState[collapseKey] = true
  else
    collapseState[collapseKey] = nil
  end
end

local function buildExpansionCollapseKey(expansionID)
  return "expansion:" .. tostring(expansionID or "")
end

local function buildModeCollapseKey(expansionID, modeKey)
  return "mode:" .. tostring(expansionID or "") .. ":" .. tostring(modeKey or "")
end

local function normalizeSearchText(rawText)
  if type(rawText) ~= "string" then
    return ""
  end
  local trimmedText = rawText:gsub("^%s+", ""):gsub("%s+$", "") -- 去除首尾空白
  if trimmedText == "" then
    return ""
  end
  return string.lower(trimmedText)
end

local function textContainsKeyword(sourceText, keyword)
  if type(keyword) ~= "string" or keyword == "" then
    return true
  end
  if type(sourceText) ~= "string" or sourceText == "" then
    return false
  end
  return string.find(string.lower(sourceText), keyword, 1, true) ~= nil
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

local function formatCompletedAtText(completedAt)
  if type(completedAt) ~= "number" or completedAt <= 0 then
    return ""
  end
  if type(date) ~= "function" then
    return tostring(completedAt)
  end
  local formatSuccess, formattedText = pcall(date, "%m-%d %H:%M", completedAt) -- 完成时间显示文本
  if formatSuccess and type(formattedText) == "string" and formattedText ~= "" then
    return formattedText
  end
  return tostring(completedAt)
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

local function buildBreadcrumbButtonWidth(textValue)
  local textLength = #(tostring(textValue or "")) -- 文本长度
  return math.max(56, textLength * 9 + 18)
end

local function applyBreadcrumbButtonState(buttonObject, crumbEntry, crumbIndex, crumbCount)
  if not buttonObject then
    return
  end

  if type(crumbEntry.onClick) == "function" and crumbIndex < crumbCount then
    buttonObject:SetEnabled(true)
    buttonObject:SetScript("OnClick", function()
      crumbEntry.onClick()
    end)
  else
    buttonObject:SetEnabled(false)
    buttonObject:SetScript("OnClick", nil)
  end
end

local function syncNavBarBreadcrumbButtons(viewObject, breadcrumbList)
  if not viewObject or not viewObject.breadcrumbFrame then
    return false
  end

  viewObject.breadcrumbButtons = viewObject.breadcrumbButtons or {}
  local previousButton = nil -- 上一个导航按钮
  for crumbIndex, crumbEntry in ipairs(breadcrumbList) do
    local buttonObject = viewObject.breadcrumbButtons[crumbIndex] -- 当前导航按钮
    if not buttonObject then
      local createSuccess, createdButton = pcall(CreateFrame, "Button", nil, viewObject.breadcrumbFrame, "NavButtonTemplate") -- NavBar 按钮模板
      if not createSuccess or not createdButton then
        return false
      end
      buttonObject = createdButton
      viewObject.breadcrumbButtons[crumbIndex] = buttonObject
    end

    buttonObject:SetText(tostring(crumbEntry.text or ""))
    buttonObject:SetWidth(buildBreadcrumbButtonWidth(crumbEntry.text))
    buttonObject:ClearAllPoints()
    if previousButton then
      buttonObject:SetPoint("LEFT", previousButton, "RIGHT", 2, 0)
    else
      buttonObject:SetPoint("TOPLEFT", viewObject.breadcrumbFrame, "TOPLEFT", 0, 0)
    end
    applyBreadcrumbButtonState(buttonObject, crumbEntry, crumbIndex, #breadcrumbList)
    buttonObject:Show()
    previousButton = buttonObject
  end

  for hideIndex = #breadcrumbList + 1, #viewObject.breadcrumbButtons do
    viewObject.breadcrumbButtons[hideIndex]:Hide()
  end
  return true
end

local function syncFallbackBreadcrumbButtons(viewObject, breadcrumbList)
  if not viewObject or not viewObject.breadcrumbFrame then
    return
  end

  viewObject.breadcrumbButtons = viewObject.breadcrumbButtons or {}
  local previousButton = nil -- 上一个 breadcrumb 按钮
  for crumbIndex, crumbEntry in ipairs(breadcrumbList) do
    local buttonObject = viewObject.breadcrumbButtons[crumbIndex] -- 当前 breadcrumb 按钮
    if not buttonObject then
      buttonObject = CreateFrame("Button", nil, viewObject.breadcrumbFrame, "UIPanelButtonTemplate")
      buttonObject:SetHeight(18)
      viewObject.breadcrumbButtons[crumbIndex] = buttonObject
    end
    buttonObject:SetText(tostring(crumbEntry.text or ""))
    buttonObject:SetWidth(math.max(72, (buttonObject.GetText and #(buttonObject:GetText() or "") or 8) * 10))
    buttonObject:ClearAllPoints()
    if previousButton then
      buttonObject:SetPoint("LEFT", previousButton, "RIGHT", 4, 0)
    else
      buttonObject:SetPoint("TOPLEFT", viewObject.breadcrumbFrame, "TOPLEFT", 0, 0)
    end
    applyBreadcrumbButtonState(buttonObject, crumbEntry, crumbIndex, #breadcrumbList)
    buttonObject:Show()
    previousButton = buttonObject
  end

  for hideIndex = #breadcrumbList + 1, #viewObject.breadcrumbButtons do
    viewObject.breadcrumbButtons[hideIndex]:Hide()
  end
end


function QuestlineTreeView:syncTabLabel()
  if isStandaloneQuestHost(self.hostJournalFrame) then
    if self.tabButton and self.tabButton.Hide then
      self.tabButton:Hide()
    end
    return
  end
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
  if isStandaloneQuestHost(self.hostJournalFrame) then
    return
  end
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

function QuestlineTreeView:hideRowButtonList(rowButtonList)
  for _, rowButton in ipairs(rowButtonList or {}) do
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

function QuestlineTreeView:buildDefaultRootTabOrderIds()
  return buildDefaultRootTabOrderIds()
end

function QuestlineTreeView:buildEffectiveRootTabOrderIds()
  return buildEffectiveRootTabOrderIds()
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
  if isStandaloneQuestHost(self.hostJournalFrame) then
    if self.tabButton and self.tabButton.Hide then
      self.tabButton:Hide()
    end
    return
  end
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
  if modeKey == "active_log" then
    return "active_log"
  end
  return "map_questline"
end

local function getActiveLogRootText(localeTable)
  return localeTable.QUEST_VIEW_TAB_ACTIVE or "当前任务"
end

local function getQuestlineRootText(localeTable)
  return localeTable.QUEST_VIEW_TAB_QUESTLINE or "任务线"
end

local function getRecentCompletedToggleText(localeTable, collapsed)
  if collapsed == true then
    return localeTable.QUEST_VIEW_RECENT_TOGGLE_EXPAND or "展开历史完成"
  end
  return localeTable.QUEST_VIEW_RECENT_TOGGLE_COLLAPSE or "折叠历史完成"
end

local function setModeTabSelected(tabButton, selected)
  if not tabButton then
    return
  end
  if selected == true then
    if type(PanelTemplates_SelectTab) == "function" then
      pcall(PanelTemplates_SelectTab, tabButton)
    elseif tabButton.LockHighlight then
      tabButton:LockHighlight()
    end
  else
    if type(PanelTemplates_DeselectTab) == "function" then
      pcall(PanelTemplates_DeselectTab, tabButton)
    elseif tabButton.UnlockHighlight then
      tabButton:UnlockHighlight()
    end
  end
end

local function getMapNameByID(uiMapID)
  if type(uiMapID) == "number" and type(C_Map) == "table" and type(C_Map.GetMapInfo) == "function" then
    local success, mapInfo = pcall(C_Map.GetMapInfo, uiMapID) -- 安全查询地图信息
    if success and type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
      return mapInfo.name
    end
  end
  return "Map #" .. tostring(uiMapID or "?")
end

function QuestlineTreeView:loadSelection()
  local moduleDb = getModuleDb() -- 模块存档
  self.selectedExpansionID = normalizeSelectionID(moduleDb.questNavExpansionID)
  self.selectedModeKey = normalizeQuestNavModeKey(moduleDb.questNavModeKey)
  self.selectedMapID = normalizeSelectionID(moduleDb.questNavSelectedMapID)
  self.selectedTypeKey = ""
  self.searchText = type(moduleDb.questNavSearchText) == "string" and moduleDb.questNavSearchText or ""
  self.expandedQuestLineID = normalizeSelectionID(moduleDb.questNavExpandedQuestLineID)
  if self.selectedModeKey == "active_log" then
    self.expandedQuestLineID = nil
  end
  self.activeLogRecentCollapsed = false
  self:trimRecentCompletedQuestRecords()
  self.selectedQuestID = nil
end

function QuestlineTreeView:saveSelection()
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questNavExpansionID = type(self.selectedExpansionID) == "number" and self.selectedExpansionID or 0
  moduleDb.questNavModeKey = normalizeQuestNavModeKey(self.selectedModeKey)
  moduleDb.questNavSelectedMapID = type(self.selectedMapID) == "number" and self.selectedMapID or 0
  moduleDb.questNavSelectedTypeKey = ""
  moduleDb.questNavSearchText = type(self.searchText) == "string" and self.searchText or ""
  moduleDb.questNavExpandedQuestLineID = type(self.expandedQuestLineID) == "number" and self.expandedQuestLineID or 0
end

function QuestlineTreeView:trimRecentCompletedQuestRecords()
  local recentCompletedList = getRecentCompletedQuestList() -- 最近完成任务列表
  local maxCount = getRecentCompletedQuestMaxValue() -- 当前最大保留条数
  local uniqueQuestIdSet = {} -- 去重索引
  local normalizedRecentList = {} -- 归一化后的列表
  for _, recentEntry in ipairs(recentCompletedList) do
    local questID = type(recentEntry) == "table" and recentEntry.questID or nil -- 当前任务 ID
    if type(questID) == "number" and questID > 0 and uniqueQuestIdSet[questID] ~= true then
      uniqueQuestIdSet[questID] = true
      normalizedRecentList[#normalizedRecentList + 1] = {
        questID = questID,
        questName = type(recentEntry.questName) == "string" and recentEntry.questName or "",
        completedAt = type(recentEntry.completedAt) == "number" and recentEntry.completedAt or 0,
      }
      if #normalizedRecentList >= maxCount then
        break
      end
    end
  end
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questRecentCompletedList = normalizedRecentList
end

function QuestlineTreeView:recordRecentlyCompletedQuest(questID, completedAt)
  if type(questID) ~= "number" or questID <= 0 then
    return
  end
  local moduleDb = getModuleDb() -- 模块存档
  moduleDb.questRecentCompletedMax = normalizeRecentCompletedMaxValue(moduleDb.questRecentCompletedMax)
  local recentCompletedList = getRecentCompletedQuestList() -- 最近完成任务列表
  local questName = nil -- 任务显示名
  if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
    local questTitle = C_QuestLog.GetTitleForQuestID(questID) -- 任务标题
    if type(questTitle) == "string" and questTitle ~= "" then
      questName = questTitle
    end
  end
  if type(questName) ~= "string" or questName == "" then
    questName = "Quest #" .. tostring(questID)
  end
  local completedTimestamp = type(completedAt) == "number" and completedAt or 0 -- 完成时间戳
  if completedTimestamp <= 0 then
    if type(GetServerTime) == "function" then
      completedTimestamp = GetServerTime()
    elseif type(time) == "function" then
      completedTimestamp = time()
    end
  end
  for index = #recentCompletedList, 1, -1 do
    local recentEntry = recentCompletedList[index] -- 当前遍历条目
    if type(recentEntry) == "table" and recentEntry.questID == questID then
      table.remove(recentCompletedList, index)
    end
  end
  table.insert(recentCompletedList, 1, {
    questID = questID,
    questName = questName,
    completedAt = completedTimestamp,
  })
  self:trimRecentCompletedQuestRecords()
  if self.selected == true and self.selectedModeKey == "active_log" then
    self:render()
  end
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

  if self.selectedModeKey == "map_questline" then
    local mapMode = expansionEntry.modeByKey and expansionEntry.modeByKey.map_questline or nil -- 地图任务线模式
    local hasSelectedMap = false -- 当前地图是否存在
    local hasSelectedQuestLine = false -- 当前直接任务线是否存在
    for _, mapEntry in ipairs(mapMode and mapMode.entries or {}) do
      if mapEntry.kind == "map" and mapEntry.id == self.selectedMapID then
        hasSelectedMap = true
        break
      end
      if mapEntry.kind == "questline" and mapEntry.id == self.expandedQuestLineID and self.selectedMapID == nil then
        hasSelectedQuestLine = true
      end
    end
    if not hasSelectedMap and not hasSelectedQuestLine then
      if type(self.selectedMapID) == "number" or type(self.expandedQuestLineID) == "number" then
        local firstEntry = mapMode and mapMode.entries and mapMode.entries[1] or nil -- 默认子项
        if type(firstEntry) == "table" and firstEntry.kind == "questline" then
          self.selectedMapID = nil
          self.expandedQuestLineID = firstEntry.id
        else
          self.selectedMapID = firstEntry and firstEntry.id or nil
          self.expandedQuestLineID = nil
        end
      end
    end
    self.selectedTypeKey = ""
  else
    self.selectedMapID = nil
    self.selectedTypeKey = ""
    self.expandedQuestLineID = nil
  end

  return expansionEntry
end

function QuestlineTreeView:buildLeftTreeRows(navigationModel)
  local rowDataList = {} -- 左侧树行
  local expansionList = navigationModel and navigationModel.expansionList or {} -- 资料片列表
  local expansionByID = navigationModel and navigationModel.expansionByID or {} -- 资料片索引
  local collapseState = getQuestlineCollapsedTable() -- 左树折叠状态
  for _, expansionSummary in ipairs(expansionList) do
    local expansionSelected = self.selectedExpansionID == expansionSummary.id -- 资料片是否选中
    local expansionCollapseKey = buildExpansionCollapseKey(expansionSummary.id) -- 资料片折叠键
    local expansionCollapsed = isTreeNodeCollapsed(collapseState, expansionCollapseKey) -- 资料片是否折叠
    rowDataList[#rowDataList + 1] = {
      kind = "expansion",
      text = string.format("%s %s", expansionCollapsed and "[+]" or "[-]", tostring(expansionSummary.name or "")),
      selected = expansionSelected,
      expansionID = expansionSummary.id,
      collapseKey = expansionCollapseKey,
      collapsed = expansionCollapsed,
    }
    if expansionSelected and not expansionCollapsed then
      local expansionEntry = expansionByID[expansionSummary.id] -- 当前资料片对象
      local mapMode = expansionEntry and expansionEntry.modeByKey and expansionEntry.modeByKey.map_questline or nil -- 地图任务线模式
      for _, childEntry in ipairs(mapMode and mapMode.entries or {}) do
        local childKind = childEntry.kind -- 导航子项类型
        if type(childKind) ~= "string" or childKind == "" then
          childKind = "map"
        end
        rowDataList[#rowDataList + 1] = {
          kind = childKind,
          text = childEntry.name,
          selected = (childKind == "map" and self.selectedMapID == childEntry.id)
            or (childKind == "questline" and self.selectedMapID == nil and self.expandedQuestLineID == childEntry.id),
          expansionID = expansionSummary.id,
          mapID = childKind == "map" and childEntry.id or nil,
          questLineID = childKind == "questline" and childEntry.id or nil,
        }
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
  rowButton = CreateFrame("Button", nil, self.scrollChild, "BackdropTemplate")
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  rowButton:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  rowButton:SetBackdropColor(0.12, 0.1, 0.07, 0.68)
  rowButton:SetBackdropBorderColor(0.45, 0.36, 0.19, 0.55)
  local highlightTexture = rowButton:GetHighlightTexture() -- 高亮贴图
  if highlightTexture and highlightTexture.SetBlendMode then
    highlightTexture:SetBlendMode("ADD")
  end
  local rowFont = rowButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rowFont:SetPoint("LEFT", rowButton, "LEFT", 8, 0)
  rowFont:SetPoint("RIGHT", rowButton, "RIGHT", -6, 0)
  rowFont:SetJustifyH("LEFT")
  rowFont:SetJustifyV("MIDDLE")
  rowButton.rowFont = rowFont
  rowButton:SetScript("OnClick", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" then
      return
    end

    local collapseState = getQuestlineCollapsedTable() -- 左树折叠状态
    if rowData.kind == "expansion" and type(rowData.expansionID) == "number" then
      local collapseKey = rowData.collapseKey -- 当前资料片折叠键
      if self.selectedExpansionID == rowData.expansionID and type(collapseKey) == "string" then
        setTreeNodeCollapsed(collapseState, collapseKey, not isTreeNodeCollapsed(collapseState, collapseKey))
      else
        self.selectedExpansionID = rowData.expansionID
        self.selectedModeKey = "map_questline"
        self.selectedMapID = nil
        self.selectedTypeKey = ""
        self.expandedQuestLineID = nil
        if type(collapseKey) == "string" then
          setTreeNodeCollapsed(collapseState, collapseKey, false)
        end
      end
    elseif rowData.kind == "map" and type(rowData.mapID) == "number" then
      self.selectedModeKey = "map_questline"
      self.selectedMapID = rowData.mapID
      self.selectedTypeKey = ""
      self.expandedQuestLineID = nil
    elseif rowData.kind == "questline" and type(rowData.questLineID) == "number" then
      self.selectedModeKey = "map_questline"
      self.selectedMapID = nil
      self.selectedTypeKey = ""
      self.expandedQuestLineID = rowData.questLineID
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

function QuestlineTreeView:getOrCreateRightRowButton(rowIndex, rowButtonList, scrollChild)
  local buttonList = type(rowButtonList) == "table" and rowButtonList or self.rightRowButtons -- 目标按钮缓存
  local targetScrollChild = scrollChild or self.rightScrollChild -- 目标滚动子容器
  local rowButton = buttonList[rowIndex] -- 主区行按钮
  if rowButton then
    return rowButton
  end
  rowButton = CreateFrame("Button", nil, targetScrollChild, "BackdropTemplate")
  rowButton:SetHeight(self.rowHeight)
  rowButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  rowButton:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  rowButton:SetBackdropColor(0.09, 0.09, 0.11, 0.75)
  rowButton:SetBackdropBorderColor(0.28, 0.28, 0.3, 0.65)
  local progressTexture = rowButton:CreateTexture(nil, "BACKGROUND") -- 进度底色
  progressTexture:SetColorTexture(0.85, 0.64, 0.2, 0.2)
  progressTexture:SetPoint("TOPLEFT", rowButton, "TOPLEFT", 2, -2)
  progressTexture:SetPoint("BOTTOMLEFT", rowButton, "BOTTOMLEFT", 2, 2)
  progressTexture:SetWidth(0)
  progressTexture:Hide()
  rowButton.progressTexture = progressTexture
  local highlightTexture = rowButton:GetHighlightTexture() -- 高亮贴图
  if highlightTexture and highlightTexture.SetBlendMode then
    highlightTexture:SetBlendMode("ADD")
  end
  local rowFont = rowButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rowFont:SetPoint("LEFT", rowButton, "LEFT", 8, 0)
  rowFont:SetPoint("RIGHT", rowButton, "RIGHT", -128, 0)
  rowFont:SetJustifyH("LEFT")
  rowFont:SetJustifyV("MIDDLE")
  rowButton.rowFont = rowFont
  local rowMetaFont = rowButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall") -- 行右侧信息
  rowMetaFont:SetPoint("RIGHT", rowButton, "RIGHT", -8, 0)
  rowMetaFont:SetWidth(118)
  rowMetaFont:SetJustifyH("RIGHT")
  rowMetaFont:SetJustifyV("MIDDLE")
  rowMetaFont:SetText("")
  rowButton.rowMetaFont = rowMetaFont
  rowButton:SetScript("OnEnter", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) ~= "table" or (rowData.kind ~= "quest" and rowData.kind ~= "recent_quest") then
      return
    end
    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(rowData.questID) -- 任务详情
    if not detailError then
      buildQuestTooltip(detailObject, Toolbox.L or {})
    end
  end)
  rowButton:SetScript("OnLeave", function(button)
    local rowData = button.rowData -- 当前行数据
    if type(rowData) == "table"
      and (rowData.kind == "quest" or rowData.kind == "recent_quest")
      and GameTooltip
      and GameTooltip.Hide
    then
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
    if (rowData.kind == "quest" or rowData.kind == "recent_quest") and type(rowData.questID) == "number" then
      self.selectedQuestID = rowData.questID
      if Toolbox.Questlines and type(Toolbox.Questlines.RequestAndDumpQuestDetailsToChat) == "function" then
        Toolbox.Questlines.RequestAndDumpQuestDetailsToChat(rowData.questID)
      end
      self:showQuestDetailPopup(rowData.questID)
    end
  end)
  buttonList[rowIndex] = rowButton
  return rowButton
end

local function buildQuestStatusKey(statusText, readyForTurnIn)
  if readyForTurnIn == true then
    return "ready"
  end
  if statusText == "completed" then
    return "completed"
  end
  if statusText == "active" then
    return "active"
  end
  return "pending"
end

local function getQuestStatusRank(statusKey)
  if statusKey == "ready" then
    return 1
  end
  if statusKey == "active" then
    return 2
  end
  if statusKey == "pending" then
    return 3
  end
  return 4
end

local function buildQuestlineMetaText(progressInfo, localeTable)
  if type(progressInfo) ~= "table" then
    return ""
  end
  if type(progressInfo.nextQuestName) == "string" and progressInfo.nextQuestName ~= "" and progressInfo.isCompleted ~= true then
    return string.format(localeTable.EJ_QUEST_NEXT_STEP_FMT or "Next: %s", progressInfo.nextQuestName)
  end
  if progressInfo.isCompleted == true then
    return localeTable.EJ_QUEST_STATUS_COMPLETED or "Completed"
  end
  return ""
end

function QuestlineTreeView:buildMainRowsForMap()
  local rowDataList = {} -- 地图模式主区行
  local localeTable = Toolbox.L or {} -- 本地化文案
  local searchKeyword = normalizeSearchText(self.searchText) -- 搜索关键词
  local questLineList = nil -- 当前主区任务线列表
  if type(self.selectedMapID) == "number" then
    local errorObject = nil -- 地图查询错误
    questLineList, errorObject = Toolbox.Questlines.GetQuestLinesForMap(self.selectedMapID, self.selectedExpansionID) -- 当前资料片地图下任务线
    if errorObject then
      return {}, errorObject
    end
  elseif type(self.expandedQuestLineID) == "number" then
    local questTabModel, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
    if errorObject then
      return {}, errorObject
    end
    local questLineEntry = questTabModel and questTabModel.questLineByID and questTabModel.questLineByID[self.expandedQuestLineID] or nil -- 当前直接任务线
    if type(questLineEntry) == "table" then
      questLineList = { questLineEntry }
    else
      questLineList = {}
    end
  else
    questLineList = {}
  end

  for _, questLineEntry in ipairs(questLineList or {}) do
    local questLineID = questLineEntry.id -- 当前任务线 ID
    local questLineName = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(questLineID or "?")) -- 任务线显示名
    local progressInfo, progressError = Toolbox.Questlines.GetQuestLineProgress(questLineID) -- 任务线进度
    local progressText = not progressError and formatProgressText(progressInfo, localeTable) or nil -- 进度文本
    local shouldQueryQuestList = self.expandedQuestLineID == questLineID or searchKeyword ~= "" -- 是否需要查询任务列表
    local questList = nil -- 任务线下任务列表
    if shouldQueryQuestList then
      local listError = nil -- 任务列表查询错误
      questList, listError = Toolbox.Questlines.GetQuestListByQuestLineID(questLineID)
      if listError then
        return {}, listError
      end
    end

    local matchQuestRows = {} -- 搜索命中的任务行
    local hasQuestMatch = false -- 当前任务线是否命中任务名
    for _, questEntry in ipairs(questList or {}) do
      local questName = tostring(questEntry.name or ("Quest #" .. tostring(questEntry.id or "?"))) -- 任务显示名
      local questMatched = searchKeyword == "" or textContainsKeyword(questName, searchKeyword) -- 任务名是否匹配搜索
      if questMatched then
        hasQuestMatch = true
        local statusKey = buildQuestStatusKey(questEntry.status, questEntry.readyForTurnIn) -- 任务状态键
        matchQuestRows[#matchQuestRows + 1] = {
          kind = "quest",
          text = questName,
          questID = questEntry.id,
          status = statusKey,
          readyForTurnIn = questEntry.readyForTurnIn,
          selected = self.selectedQuestID == questEntry.id,
        }
      end
    end

    local questLineMatched = searchKeyword == "" or textContainsKeyword(questLineName, searchKeyword) -- 任务线名是否匹配搜索
    if searchKeyword == "" or questLineMatched or hasQuestMatch then
      local shouldExpand = self.expandedQuestLineID == questLineID or (searchKeyword ~= "" and hasQuestMatch) -- 当前任务线是否展开
      local linePrefix = shouldExpand and "[-]" or "[+]" -- 展开前缀
      local lineText = string.format("%s %s", linePrefix, questLineName) -- 任务线主文本
      if type(progressText) == "string" then
        lineText = string.format("%s  %s", lineText, progressText)
      end
      if type(questLineEntry.questCount) == "number" then
        lineText = string.format("%s · " .. (localeTable.EJ_QUEST_CARD_QUEST_COUNT_FMT or "%d quests"), lineText, questLineEntry.questCount)
      end

      rowDataList[#rowDataList + 1] = {
        kind = "questline",
        text = lineText,
        questLineID = questLineID,
        selected = shouldExpand,
        progressInfo = progressInfo,
        metaText = buildQuestlineMetaText(progressInfo, localeTable),
      }

      if shouldExpand then
        for _, questRow in ipairs(matchQuestRows) do
          rowDataList[#rowDataList + 1] = questRow
        end
      end
    end
  end

  return rowDataList, nil
end

function QuestlineTreeView:buildRecentCompletedRows()
  local rowDataList = {} -- 最近完成行
  local searchKeyword = normalizeSearchText(self.searchText) -- 搜索关键词
  local localeTable = Toolbox.L or {} -- 本地化文案
  local recentCompletedList = getRecentCompletedQuestList() -- 最近完成任务列表
  local recentMatchCount = 0 -- 最近完成命中条数
  for _, recentEntry in ipairs(recentCompletedList) do
    local recentQuestName = tostring(recentEntry.questName or ("Quest #" .. tostring(recentEntry.questID or "?"))) -- 最近完成任务显示名
    if searchKeyword == "" or textContainsKeyword(recentQuestName, searchKeyword) then
      recentMatchCount = recentMatchCount + 1
      rowDataList[#rowDataList + 1] = {
        kind = "recent_quest",
        text = recentQuestName,
        questID = recentEntry.questID,
        status = "completed",
        readyForTurnIn = false,
        selected = self.selectedQuestID == recentEntry.questID,
        metaText = formatCompletedAtText(recentEntry.completedAt),
      }
    end
  end
  if recentMatchCount == 0 then
    rowDataList[#rowDataList + 1] = {
      kind = "section_empty",
      text = localeTable.EJ_QUEST_RECENT_COMPLETED_EMPTY or "No recently completed quests.",
    }
  end
  return rowDataList, nil
end

function QuestlineTreeView:buildCurrentQuestRows()
  local rowDataList = {} -- 当前任务行
  local searchKeyword = normalizeSearchText(self.searchText) -- 搜索关键词
  local localeTable = Toolbox.L or {} -- 本地化文案
  local questEntryList, errorObject = Toolbox.Questlines.GetCurrentQuestLogEntries() -- 当前任务日志条目
  if errorObject then
    return {}, errorObject
  end

  local activeQuestRows = {} -- 当前任务行列表
  for _, questEntry in ipairs(questEntryList or {}) do
    local questName = tostring(questEntry.name or ("Quest #" .. tostring(questEntry.questID or "?"))) -- 任务显示名
    if searchKeyword == "" or textContainsKeyword(questName, searchKeyword) then
      activeQuestRows[#activeQuestRows + 1] = {
        kind = "quest",
        text = questName,
        questID = questEntry.questID,
        status = buildQuestStatusKey(questEntry.status, questEntry.readyForTurnIn),
        readyForTurnIn = questEntry.readyForTurnIn,
        selected = self.selectedQuestID == questEntry.questID,
      }
    end
  end

  table.sort(activeQuestRows, function(leftRow, rightRow)
    local leftRank = getQuestStatusRank(leftRow.status) -- 左侧状态排序权重
    local rightRank = getQuestStatusRank(rightRow.status) -- 右侧状态排序权重
    if leftRank ~= rightRank then
      return leftRank < rightRank
    end
    return tostring(leftRow.text or "") < tostring(rightRow.text or "")
  end)

  if #activeQuestRows == 0 then
    rowDataList[#rowDataList + 1] = {
      kind = "section_empty",
      text = localeTable.EJ_QUEST_ACTIVE_EMPTY or "No active quests in the quest log.",
    }
  else
    for _, activeQuestRow in ipairs(activeQuestRows) do
      rowDataList[#rowDataList + 1] = activeQuestRow
    end
  end

  return rowDataList, nil
end

function QuestlineTreeView:renderLeftRows(rowDataList)
  local scrollWidth = self.scrollFrame:GetWidth() -- 左树宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 230
  end
  local rowWidth = math.max(150, scrollWidth - 24) -- 行宽
  local rowOffsetY = 6 -- 顶部留白
  local currentOffsetY = rowOffsetY -- 当前累计偏移
  local rowIndex = 0 -- 行索引
  for _, rowData in ipairs(rowDataList or {}) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRowButton(rowIndex) -- 当前左树行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 6, -currentOffsetY)
    rowButton:SetWidth(rowWidth)
    local rowHeight = rowData.kind == "expansion" and (self.rowHeight + VIEW_STYLE.expansionExtraHeight) or self.rowHeight -- 当前行高度
    rowButton:SetHeight(rowHeight)
    local indentLevel = 0 -- 缩进层级
    if rowData.kind == "map" or rowData.kind == "questline" then
      indentLevel = 1
    end
    rowButton.rowFont:SetText(string.rep("  ", indentLevel) .. tostring(rowData.text or ""))
    if rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
      rowButton:SetBackdropBorderColor(0.86, 0.68, 0.28, 0.95)
      rowButton:SetBackdropColor(0.2, 0.16, 0.1, 0.88)
    elseif rowData.kind == "expansion" then
      rowButton.rowFont:SetTextColor(1.0, 0.9, 0.68)
      rowButton:SetBackdropBorderColor(0.48, 0.4, 0.24, 0.65)
      rowButton:SetBackdropColor(0.14, 0.11, 0.08, 0.78)
    elseif rowData.kind == "mode" then
      rowButton.rowFont:SetTextColor(0.9, 0.85, 0.72)
      rowButton:SetBackdropBorderColor(0.34, 0.3, 0.22, 0.55)
      rowButton:SetBackdropColor(0.11, 0.1, 0.09, 0.7)
    else
      rowButton.rowFont:SetTextColor(1, 1, 1)
      rowButton:SetBackdropBorderColor(0.3, 0.3, 0.32, 0.5)
      rowButton:SetBackdropColor(0.1, 0.1, 0.12, 0.68)
    end
    rowButton:Show()
    currentOffsetY = currentOffsetY + rowHeight + VIEW_STYLE.leftRowGap
  end
  for hideIndex = rowIndex + 1, #self.rowButtons do
    self.rowButtons[hideIndex]:Hide()
  end
  local contentHeight = math.max(currentOffsetY + 4, 10) -- 左树内容高度
  self.scrollChild:SetSize(rowWidth, contentHeight)
  return contentHeight
end

function QuestlineTreeView:renderRowList(scrollFrame, scrollChild, rowButtonList, rowDataList)
  local scrollWidth = scrollFrame:GetWidth() -- 主区宽度
  if type(scrollWidth) ~= "number" or scrollWidth <= 0 then
    scrollWidth = 520
  end
  local rowWidth = math.max(200, scrollWidth - 24) -- 行宽
  local rowOffsetY = 6 -- 顶部留白
  local currentOffsetY = rowOffsetY -- 当前累计偏移
  local rowIndex = 0 -- 行索引

  for _, rowData in ipairs(rowDataList or {}) do
    rowIndex = rowIndex + 1
    local rowButton = self:getOrCreateRightRowButton(rowIndex, rowButtonList, scrollChild) -- 当前主区行按钮
    rowButton.rowData = rowData
    rowButton:ClearAllPoints()
    rowButton:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -currentOffsetY)
    rowButton:SetWidth(rowWidth)
    local rowHeight = rowData.kind == "questline" and (self.rowHeight + 1) or self.rowHeight -- 当前行高度
    rowButton:SetHeight(rowHeight)

    local indentLevel = (rowData.kind == "quest" or rowData.kind == "recent_quest") and 1 or 0 -- 任务缩进
    local statusPrefix = (rowData.kind == "quest" or rowData.kind == "recent_quest")
      and formatQuestStatusPrefix(rowData.status)
      or "" -- 任务状态前缀
    if statusPrefix ~= "" then
      rowButton.rowFont:SetText(string.rep("  ", indentLevel) .. statusPrefix .. " " .. tostring(rowData.text or ""))
    else
      rowButton.rowFont:SetText(string.rep("  ", indentLevel) .. tostring(rowData.text or ""))
    end

    if rowData.kind == "section_header" then
      rowButton.rowFont:SetTextColor(1.0, 0.9, 0.68)
      rowButton:SetBackdropBorderColor(0.5, 0.4, 0.22, 0.7)
      rowButton:SetBackdropColor(0.15, 0.11, 0.07, 0.78)
    elseif rowData.kind == "section_empty" then
      rowButton.rowFont:SetTextColor(0.7, 0.7, 0.74)
      rowButton:SetBackdropBorderColor(0.32, 0.32, 0.34, 0.46)
      rowButton:SetBackdropColor(0.09, 0.09, 0.11, 0.62)
    elseif rowData.selected == true then
      rowButton.rowFont:SetTextColor(0.35, 0.85, 1)
      rowButton:SetBackdropBorderColor(0.86, 0.68, 0.28, 0.95)
      rowButton:SetBackdropColor(0.2, 0.16, 0.1, 0.88)
    else
      local colorR, colorG, colorB = getQuestStatusTextColor(rowData.status) -- 状态文本颜色
      if type(colorR) == "number" then
        rowButton.rowFont:SetTextColor(colorR, colorG, colorB)
      else
        rowButton.rowFont:SetTextColor(1, 1, 1)
      end
      if rowData.kind == "questline" then
        rowButton:SetBackdropBorderColor(0.52, 0.4, 0.2, 0.82)
        rowButton:SetBackdropColor(0.13, 0.1, 0.08, 0.82)
      else
        rowButton:SetBackdropBorderColor(0.3, 0.3, 0.34, 0.52)
        rowButton:SetBackdropColor(0.1, 0.1, 0.12, 0.7)
      end
    end

    if rowButton.rowMetaFont then
      local metaText = rowData.kind == "section_header" and "" or tostring(rowData.metaText or "")
      rowButton.rowMetaFont:SetText(metaText)
      if rowData.kind == "questline" then
        rowButton.rowMetaFont:SetTextColor(0.95, 0.88, 0.6)
      elseif rowData.kind == "recent_quest" then
        rowButton.rowMetaFont:SetTextColor(0.88, 0.82, 0.65)
      else
        rowButton.rowMetaFont:SetTextColor(0.72, 0.72, 0.76)
      end
    end

    if rowButton.progressTexture then
      local progressInfo = rowData.progressInfo -- 当前行进度信息
      local totalCount = type(progressInfo) == "table" and tonumber(progressInfo.total) or nil -- 总任务数
      local completedCount = type(progressInfo) == "table" and tonumber(progressInfo.completed) or nil -- 已完成数
      if rowData.kind == "questline" and type(totalCount) == "number" and totalCount > 0 and type(completedCount) == "number" then
        local ratio = math.max(0, math.min(1, completedCount / totalCount)) -- 进度比例
        rowButton.progressTexture:SetWidth(math.max(0, (rowWidth - 4) * ratio))
        rowButton.progressTexture:Show()
      else
        rowButton.progressTexture:Hide()
      end
    end

    rowButton:Show()
    currentOffsetY = currentOffsetY + rowHeight + VIEW_STYLE.rightRowGap
  end

  for hideIndex = rowIndex + 1, #rowButtonList do
    rowButtonList[hideIndex]:Hide()
  end

  local contentHeight = math.max(currentOffsetY + 4, 10) -- 主区内容高度
  scrollChild:SetSize(rowWidth, contentHeight)
  scrollFrame:SetShown(rowIndex > 0)
  return contentHeight
end

function QuestlineTreeView:renderRightRows(rowDataList)
  return self:renderRowList(self.rightScrollFrame, self.rightScrollChild, self.rightRowButtons, rowDataList)
end

function QuestlineTreeView:updateActiveLogPanelTitles(currentRows, recentRows)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local currentCount = 0 -- 当前任务条数
  local recentCount = 0 -- 最近完成条数

  for _, rowData in ipairs(currentRows or {}) do
    if type(rowData) == "table" and rowData.kind == "quest" then
      currentCount = currentCount + 1
    end
  end
  for _, rowData in ipairs(recentRows or {}) do
    if type(rowData) == "table" and rowData.kind == "recent_quest" then
      recentCount = recentCount + 1
    end
  end

  if self.activeLogCurrentTitle then
    self.activeLogCurrentTitle:SetText(string.format(
      localeTable.EJ_QUEST_ACTIVE_SECTION_COUNT_FMT or "Current Quests (%d)",
      currentCount
    ))
  end
  if self.activeLogRecentTitle then
    self.activeLogRecentTitle:SetText(string.format(
      localeTable.EJ_QUEST_RECENT_COMPLETED_COUNT_FMT or "Recently Completed (%d)",
      recentCount
    ))
  end
  if self.activeLogRecentToggleButton then
    self.activeLogRecentToggleButton:SetText(getRecentCompletedToggleText(localeTable, self.activeLogRecentCollapsed))
  end
end

function QuestlineTreeView:renderActiveLogPanels()
  local currentRows, currentError = self:buildCurrentQuestRows() -- 当前任务行
  if currentError then
    return nil, currentError
  end
  local recentRows, recentError = self:buildRecentCompletedRows() -- 最近完成行
  if recentError then
    return nil, recentError
  end

  self:updateActiveLogPanelTitles(currentRows, recentRows)
  local currentHeight = self:renderRowList(
    self.activeLogCurrentScrollFrame,
    self.activeLogCurrentScrollChild,
    self.activeLogCurrentRowButtons,
    currentRows
  ) -- 当前任务区内容高度

  if self.activeLogRecentCollapsed == true then
    if self.activeLogRecentScrollFrame then
      self.activeLogRecentScrollFrame:Hide()
    end
    if self.activeLogRecentScrollChild then
      self.activeLogRecentScrollChild:SetSize(10, 10)
    end
    self:hideRowButtonList(self.activeLogRecentRowButtons)
    return {
      currentHeight = currentHeight,
      recentHeight = 0,
      currentRows = currentRows,
      recentRows = recentRows,
    }, nil
  end

  local recentHeight = self:renderRowList(
    self.activeLogRecentScrollFrame,
    self.activeLogRecentScrollChild,
    self.activeLogRecentRowButtons,
    recentRows
  ) -- 最近完成区内容高度

  return {
    currentHeight = currentHeight,
    recentHeight = recentHeight,
    currentRows = currentRows,
    recentRows = recentRows,
  }, nil
end

function QuestlineTreeView:hideQuestDetailPopup()
  if self.detailPopupFrame then
    self.detailPopupFrame:Hide()
  end
  if self.detailPopupActiveButton then
    self.detailPopupActiveButton:Hide()
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
    self.detailPopupJumpButton.expansionID = detailObject.questLineExpansionID
    self.detailPopupJumpButton:SetShown(canJump)
    self.detailPopupJumpButton:SetText(localeTable.EJ_QUEST_JUMP_TO_QUESTLINE or "跳转到对应地图/任务线")
  end
  if self.detailPopupActiveButton then
    self.detailPopupActiveButton.questID = detailObject.questID
    self.detailPopupActiveButton:SetText(localeTable.EJ_QUEST_ACTION_OPEN_ACTIVE or "Open in Active View")
    self.detailPopupActiveButton:Show()
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
  local breadcrumbList = {} -- 当前路径段

  if self.selectedModeKey == "active_log" then
    breadcrumbList[#breadcrumbList + 1] = {
      text = getActiveLogRootText(localeTable),
    }
  elseif type(expansionEntry) == "table" then
    breadcrumbList[#breadcrumbList + 1] = {
      text = getQuestlineRootText(localeTable),
      onClick = function()
        self.selectedModeKey = "map_questline"
        self.selectedMapID = nil
        self.expandedQuestLineID = nil
        self.selectedQuestID = nil
        self:hideQuestDetailPopup()
        self:saveSelection()
        self:render()
      end,
    }
    breadcrumbList[#breadcrumbList + 1] = {
      text = tostring(expansionEntry.name or ""),
      onClick = function()
        self.selectedModeKey = "map_questline"
        self.expandedQuestLineID = nil
        self.selectedMapID = nil
        self:hideQuestDetailPopup()
        self:saveSelection()
        self:render()
      end,
    }
    if type(self.selectedMapID) == "number" then
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
        local mapID = type(questLineEntry.UiMapID) == "number" and questLineEntry.UiMapID
          or type(questLineEntry.PrimaryUiMapID) == "number" and questLineEntry.PrimaryUiMapID
          or nil -- 任务线所属地图 ID
        if type(self.selectedMapID) ~= "number" and type(mapID) == "number" then
          breadcrumbList[#breadcrumbList + 1] = {
            text = getMapNameByID(mapID),
            onClick = function()
              self.selectedMapID = mapID
              self.expandedQuestLineID = nil
              self:hideQuestDetailPopup()
              self:saveSelection()
              self:render()
            end,
          }
        end
        breadcrumbList[#breadcrumbList + 1] = {
          text = resolveQuestLineDisplayName(questLineEntry) or ("QuestLine #" .. tostring(self.expandedQuestLineID)),
        }
      end
    end
  else
    breadcrumbList[#breadcrumbList + 1] = {
      text = getQuestlineRootText(localeTable),
    }
  end

  if self.breadcrumbFrame and self.breadcrumbFrame.templateName == "NavBarTemplate" then
    if syncNavBarBreadcrumbButtons(self, breadcrumbList) then
      return
    end
  end
  syncFallbackBreadcrumbButtons(self, breadcrumbList)
end

function QuestlineTreeView:applyContentLayout()
  if not self.panelFrame or not self.leftTree or not self.rightContent then
    return
  end
  local activeModeKey = normalizeQuestNavModeKey(self.selectedModeKey) -- 当前激活视图
  if self.modeTabButtonByKey.active_log then
    self.modeTabButtonByKey.active_log:ClearAllPoints()
    self.modeTabButtonByKey.active_log:SetPoint("TOPLEFT", self.hostJournalFrame or self.panelFrame, "BOTTOMLEFT", 14, 2)
    setModeTabSelected(self.modeTabButtonByKey.active_log, activeModeKey == "active_log")
    self.modeTabButtonByKey.active_log:Show()
  end
  if self.modeTabButtonByKey.map_questline then
    self.modeTabButtonByKey.map_questline:ClearAllPoints()
    if self.modeTabButtonByKey.active_log then
      self.modeTabButtonByKey.map_questline:SetPoint("LEFT", self.modeTabButtonByKey.active_log, "RIGHT", VIEW_STYLE.modeTabGap, 0)
    else
      self.modeTabButtonByKey.map_questline:SetPoint("TOPLEFT", self.hostJournalFrame or self.panelFrame, "BOTTOMLEFT", 126, 2)
    end
    setModeTabSelected(self.modeTabButtonByKey.map_questline, activeModeKey == "map_questline")
    self.modeTabButtonByKey.map_questline:Show()
  end

  self.rightContent:ClearAllPoints()
  if activeModeKey == "active_log" then
    self.leftTree:Hide()
    self.scrollFrame:Hide()
    self.rightContent:SetPoint("TOPLEFT", self.panelFrame, "TOPLEFT", 8, -8)
    self.rightContent:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -8, 8)
  else
    self.leftTree:ClearAllPoints()
    self.leftTree:SetPoint("TOPLEFT", self.panelFrame, "TOPLEFT", 8, -8)
    self.leftTree:SetPoint("BOTTOMLEFT", self.panelFrame, "BOTTOMLEFT", 8, 8)
    self.leftTree:SetWidth(VIEW_STYLE.leftPanelWidth)
    self.leftTree:Show()
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", self.leftTree, "TOPLEFT", 6, -6)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.leftTree, "BOTTOMRIGHT", -28, 6)
    self.scrollFrame:Show()
    self.rightContent:SetPoint("TOPLEFT", self.leftTree, "TOPRIGHT", 6, 0)
    self.rightContent:SetPoint("BOTTOMRIGHT", self.panelFrame, "BOTTOMRIGHT", -8, 8)
  end
  self.rightContent:Show()
  if self.searchBoxFrame then
    self.searchBoxFrame:ClearAllPoints()
    self.searchBoxFrame:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -8)
    self.searchBoxFrame:SetSize(184, 22)
  end
  if self.breadcrumbFrame then
    self.breadcrumbFrame:ClearAllPoints()
    self.breadcrumbFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 8, -8)
    if self.searchBoxFrame then
      self.breadcrumbFrame:SetPoint("TOPRIGHT", self.searchBoxFrame, "TOPLEFT", -10, 0)
    else
      self.breadcrumbFrame:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -8)
    end
    self.breadcrumbFrame:SetHeight(28)
  end
  if self.searchBox then
    self.searchBox:ClearAllPoints()
    if self.searchBoxFrame then
      self.searchBox:SetPoint("TOPLEFT", self.searchBoxFrame, "TOPLEFT", 4, -1)
      self.searchBox:SetPoint("BOTTOMRIGHT", self.searchBoxFrame, "BOTTOMRIGHT", -4, 1)
    else
      self.searchBox:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -8)
      self.searchBox:SetSize(184, 20)
    end
  end
  if self.rightTitle then
    self.rightTitle:ClearAllPoints()
    self.rightTitle:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -42)
    self.rightTitle:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -206, -42)
  end
  if self.rightHeaderDivider then
    self.rightHeaderDivider:ClearAllPoints()
    self.rightHeaderDivider:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -60)
    self.rightHeaderDivider:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -60)
    self.rightHeaderDivider:SetHeight(1)
  end

  if activeModeKey == "active_log" then
    local contentHeight = self.rightContent.GetHeight and self.rightContent:GetHeight() or 0 -- 当前内容区高度
    if type(contentHeight) ~= "number" or contentHeight <= 0 then
      contentHeight = 520
    end
    local bodyHeight = math.max(220, contentHeight - 90) -- 头部以下可用高度
    local recentHeight = self.activeLogRecentCollapsed == true and 0 or math.floor(bodyHeight * VIEW_STYLE.activeLogRecentRatio) -- 历史完成面板高度
    local currentHeight = self.activeLogRecentCollapsed == true and bodyHeight or math.max(140, bodyHeight - recentHeight - VIEW_STYLE.activeLogPanelGap) -- 当前任务面板高度

    self:hideAllRightRows()
    if self.rightTitle then
      self.rightTitle:Hide()
    end
    if self.rightScrollFrame then
      self.rightScrollFrame:Hide()
    end

    if self.activeLogRecentToggleButton then
      self.activeLogRecentToggleButton:ClearAllPoints()
      self.activeLogRecentToggleButton:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -42)
      self.activeLogRecentToggleButton:Show()
    end

    if self.activeLogCurrentPanel then
      self.activeLogCurrentPanel:ClearAllPoints()
      self.activeLogCurrentPanel:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -68)
      self.activeLogCurrentPanel:SetPoint("TOPRIGHT", self.rightContent, "TOPRIGHT", -10, -68)
      self.activeLogCurrentPanel:SetHeight(currentHeight)
      self.activeLogCurrentPanel:Show()
    end
    if self.activeLogCurrentTitle then
      self.activeLogCurrentTitle:ClearAllPoints()
      self.activeLogCurrentTitle:SetPoint("TOPLEFT", self.activeLogCurrentPanel, "TOPLEFT", 10, -10)
      self.activeLogCurrentTitle:SetPoint("TOPRIGHT", self.activeLogCurrentPanel, "TOPRIGHT", -10, -10)
      self.activeLogCurrentTitle:Show()
    end
    if self.activeLogCurrentScrollFrame then
      self.activeLogCurrentScrollFrame:ClearAllPoints()
      self.activeLogCurrentScrollFrame:SetPoint("TOPLEFT", self.activeLogCurrentPanel, "TOPLEFT", 8, -32)
      self.activeLogCurrentScrollFrame:SetPoint("BOTTOMRIGHT", self.activeLogCurrentPanel, "BOTTOMRIGHT", -26, 8)
      self.activeLogCurrentScrollFrame:Show()
    end

    if self.activeLogRecentPanel then
      if self.activeLogRecentCollapsed == true then
        self.activeLogRecentPanel:Hide()
      else
        self.activeLogRecentPanel:ClearAllPoints()
        self.activeLogRecentPanel:SetPoint("TOPLEFT", self.activeLogCurrentPanel, "BOTTOMLEFT", 0, -VIEW_STYLE.activeLogPanelGap)
        self.activeLogRecentPanel:SetPoint("TOPRIGHT", self.activeLogCurrentPanel, "BOTTOMRIGHT", 0, -VIEW_STYLE.activeLogPanelGap)
        self.activeLogRecentPanel:SetHeight(recentHeight)
        self.activeLogRecentPanel:Show()
      end
    end
    if self.activeLogRecentTitle then
      if self.activeLogRecentCollapsed == true then
        self.activeLogRecentTitle:Hide()
      else
        self.activeLogRecentTitle:ClearAllPoints()
        self.activeLogRecentTitle:SetPoint("TOPLEFT", self.activeLogRecentPanel, "TOPLEFT", 10, -10)
        self.activeLogRecentTitle:SetPoint("TOPRIGHT", self.activeLogRecentPanel, "TOPRIGHT", -10, -10)
        self.activeLogRecentTitle:Show()
      end
    end
    if self.activeLogRecentScrollFrame then
      if self.activeLogRecentCollapsed == true then
        self.activeLogRecentScrollFrame:Hide()
      else
        self.activeLogRecentScrollFrame:ClearAllPoints()
        self.activeLogRecentScrollFrame:SetPoint("TOPLEFT", self.activeLogRecentPanel, "TOPLEFT", 8, -32)
        self.activeLogRecentScrollFrame:SetPoint("BOTTOMRIGHT", self.activeLogRecentPanel, "BOTTOMRIGHT", -26, 8)
        self.activeLogRecentScrollFrame:Show()
      end
    end
  else
    if self.rightTitle then
      self.rightTitle:Show()
    end
    if self.rightScrollFrame then
      self.rightScrollFrame:ClearAllPoints()
      self.rightScrollFrame:SetPoint("TOPLEFT", self.rightContent, "TOPLEFT", 10, -68)
      self.rightScrollFrame:SetPoint("BOTTOMRIGHT", self.rightContent, "BOTTOMRIGHT", -26, 10)
      self.rightScrollFrame:Show()
    end
    if self.activeLogCurrentPanel then
      self.activeLogCurrentPanel:Hide()
    end
    if self.activeLogRecentPanel then
      self.activeLogRecentPanel:Hide()
    end
    if self.activeLogRecentToggleButton then
      self.activeLogRecentToggleButton:Hide()
    end
    self:hideRowButtonList(self.activeLogCurrentRowButtons)
    self:hideRowButtonList(self.activeLogRecentRowButtons)
  end
end

function QuestlineTreeView:render()
  if not self.scrollFrame or not self.rightScrollFrame or not self.emptyText then
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  local leftScrollOffset = readVerticalScrollOffset(self.scrollFrame) -- 左树滚动偏移
  local rightScrollOffset = readVerticalScrollOffset(self.rightScrollFrame) -- 主区滚动偏移
  local navigationModel, queryError = Toolbox.Questlines.GetQuestNavigationModel() -- 导航模型
  if queryError then
    self:hideAllRows()
    self:hideAllRightRows()
    self:hideRowButtonList(self.activeLogCurrentRowButtons)
    self:hideRowButtonList(self.activeLogRecentRowButtons)
    self.rightScrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end
  local expansionEntry = self:resolveNavigationDefaults(navigationModel or {}) -- 当前资料片
  self:applyContentLayout()
  self:syncBreadcrumb(expansionEntry)

  if self.selectedModeKey == "active_log" then
    local activeLayoutState, activeError = self:renderActiveLogPanels() -- 当前任务布局状态
    if activeError then
      self:hideAllRows()
      self:hideAllRightRows()
      self:hideRowButtonList(self.activeLogCurrentRowButtons)
      self:hideRowButtonList(self.activeLogRecentRowButtons)
      self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
      self.emptyText:Show()
      return
    end
    self:hideAllRows()
    self:hideAllRightRows()
    restoreVerticalScrollOffset(
      self.activeLogCurrentScrollFrame,
      readVerticalScrollOffset(self.activeLogCurrentScrollFrame),
      activeLayoutState.currentHeight
    )
    if self.activeLogRecentCollapsed ~= true then
      restoreVerticalScrollOffset(
        self.activeLogRecentScrollFrame,
        readVerticalScrollOffset(self.activeLogRecentScrollFrame),
        activeLayoutState.recentHeight
      )
    end
    local hasAnyActiveRow = false -- 当前任务视图是否有内容
    for _, rowData in ipairs(activeLayoutState.currentRows or {}) do
      if type(rowData) == "table" and rowData.kind ~= "section_empty" then
        hasAnyActiveRow = true
        break
      end
    end
    if not hasAnyActiveRow then
      for _, rowData in ipairs(activeLayoutState.recentRows or {}) do
        if type(rowData) == "table" and rowData.kind ~= "section_empty" then
          hasAnyActiveRow = true
          break
        end
      end
    end
    self.emptyText:SetShown(not hasAnyActiveRow)
    if self.emptyText:IsShown() then
      self.emptyText:SetText(localeTable.EJ_QUEST_ACTIVE_EMPTY or "No active quests in the quest log.")
    end
    return
  end

  local leftRows = self:buildLeftTreeRows(navigationModel or {}) -- 左树行
  local mainRows, mainError = self:buildMainRowsForMap() -- 主区行与错误
  if mainError then
    self:hideAllRows()
    self:hideAllRightRows()
    self.rightScrollFrame:Hide()
    self.emptyText:SetText(localeTable.EJ_QUEST_DATA_INVALID or "任务数据无效。")
    self.emptyText:Show()
    return
  end
  local leftContentHeight = self:renderLeftRows(leftRows) -- 左树内容高度
  local rightContentHeight = self:renderRightRows(mainRows) -- 主区内容高度
  restoreVerticalScrollOffset(self.scrollFrame, leftScrollOffset, leftContentHeight)
  restoreVerticalScrollOffset(self.rightScrollFrame, rightScrollOffset, rightContentHeight)
  self:hideRowButtonList(self.activeLogCurrentRowButtons)
  self:hideRowButtonList(self.activeLogRecentRowButtons)
  self.emptyText:SetShown(#leftRows == 0 and #mainRows == 0)
  if self.emptyText:IsShown() then
    self.emptyText:SetText(localeTable.EJ_QUESTLINE_TREE_EMPTY or "当前暂无任务线数据。")
  end
  if self.rightTitle then
    local titleText = localeTable.EJ_QUESTLINE_LIST_TITLE or "Questlines" -- 主区标题文本
    local titleCount = #mainRows -- 标题计数
    for _, rowData in ipairs(mainRows) do
      if type(rowData) ~= "table" or rowData.kind ~= "questline" then
        titleCount = titleCount - 1
      end
    end
    self.rightTitle:SetText(string.format("%s (%d)", titleText, titleCount))
  end
end

function QuestlineTreeView:ensureWidgets()
  local journalFrame = _G.ToolboxQuestFrame -- quest 模块根面板
  if not journalFrame then
    return
  end
  self.hostJournalFrame = journalFrame
  self.breadcrumbButtons = self.breadcrumbButtons or {}
  self.modeTabButtonByKey = self.modeTabButtonByKey or {}
  if self.tabButton
    and self.panelFrame
    and self.modeTabButtonByKey.active_log
    and self.modeTabButtonByKey.map_questline
    and self.leftTree
    and self.rightContent
    and self.scrollFrame
    and self.scrollChild
    and self.rightScrollFrame
    and self.rightScrollChild
    and self.activeLogCurrentPanel
    and self.activeLogCurrentScrollFrame
    and self.activeLogCurrentScrollChild
    and self.activeLogRecentPanel
    and self.activeLogRecentScrollFrame
    and self.activeLogRecentScrollChild
    and self.activeLogRecentToggleButton
    and self.emptyText
    and self.detailPopupFrame
    and self.detailPopupJumpButton
    and self.detailPopupActiveButton
    and self.detailPopupCloseButton
    and self.breadcrumbFrame
    and self.searchBox
    and self.searchBoxFrame
    and self.rightHeaderDivider
  then
    self:loadSelection()
    if self.searchBox then
      self.searchBox:SetText(self.searchText or "")
    end
    if self.searchPlaceholder then
      local localeTable = Toolbox.L or {} -- 本地化文案
      self.searchPlaceholder:SetText(localeTable.EJ_QUEST_SEARCH_PLACEHOLDER or "Search questlines / quests...")
      self.searchPlaceholder:SetShown((self.searchText or "") == "")
    end
    local localeTable = Toolbox.L or {} -- 本地化文案
    if self.modeTabButtonByKey.active_log then
      self.modeTabButtonByKey.active_log:SetText(getActiveLogRootText(localeTable))
      self.modeTabButtonByKey.active_log:SetWidth(108)
    end
    if self.modeTabButtonByKey.map_questline then
      self.modeTabButtonByKey.map_questline:SetText(getQuestlineRootText(localeTable))
      self.modeTabButtonByKey.map_questline:SetWidth(92)
    end
    if self.activeLogRecentToggleButton then
      self.activeLogRecentToggleButton:SetText(getRecentCompletedToggleText(localeTable, self.activeLogRecentCollapsed))
      self.activeLogRecentToggleButton:SetWidth(108)
    end
    self:layoutRootTabs()
    self:syncTabLabel()
    self:applyContentLayout()
    self:hookVanillaTabsOnce()
    return
  end
  if not self.tabButton then
    local tabButton = CreateFrame("Button", "ToolboxQuestRootTab", journalFrame, "PanelTabButtonTemplate")
    tabButton:SetID(QUEST_ROOT_TAB_ID)
    tabButton:SetScript("OnClick", function()
      self:setSelected(true)
    end)
    self.tabButton = tabButton
    self:layoutRootTabs()
  end
  if not self.panelFrame then
    local panelFrame = CreateFrame("Frame", "ToolboxQuestMainPanel", journalFrame, "InsetFrameTemplate")
    local instanceSelect = journalFrame.instanceSelect -- 主内容区
    if instanceSelect then
      panelFrame:SetPoint("TOPLEFT", instanceSelect, "TOPLEFT", 0, 0)
      panelFrame:SetPoint("BOTTOMRIGHT", instanceSelect, "BOTTOMRIGHT", 0, 0)
    else
      panelFrame:SetPoint("TOPLEFT", journalFrame, "TOPLEFT", 4, -60)
      panelFrame:SetPoint("BOTTOMRIGHT", journalFrame, "BOTTOMRIGHT", -4, 5)
    end
    panelFrame:Hide()
    self.panelFrame = panelFrame
  end
  if not self.modeTabButtonByKey.active_log then
    local activeButton = CreateFrame("Button", nil, journalFrame, "PanelTabButtonTemplate") -- 当前任务视图页签
    activeButton:SetHeight(VIEW_STYLE.modeTabHeight)
    activeButton:SetScript("OnClick", function()
      self.selectedModeKey = "active_log"
      self.selectedMapID = nil
      self.expandedQuestLineID = nil
      self.selectedQuestID = nil
      self:hideQuestDetailPopup()
      self:saveSelection()
      self:render()
    end)
    self.modeTabButtonByKey.active_log = activeButton
  end
  if not self.modeTabButtonByKey.map_questline then
    local mapButton = CreateFrame("Button", nil, journalFrame, "PanelTabButtonTemplate") -- 任务线视图页签
    mapButton:SetHeight(VIEW_STYLE.modeTabHeight)
    mapButton:SetScript("OnClick", function()
      self.selectedModeKey = "map_questline"
      self.selectedQuestID = nil
      self:hideQuestDetailPopup()
      self:saveSelection()
      self:render()
    end)
    self.modeTabButtonByKey.map_questline = mapButton
  end
  if not self.leftTree then
    self.leftTree = CreateFrame("Frame", nil, self.panelFrame)
  end
  if not self.rightContent then
    self.rightContent = CreateFrame("Frame", nil, self.panelFrame)
  end
  if not self.scrollFrame then
    self.scrollFrame = CreateFrame("ScrollFrame", "ToolboxQuestLeftScrollFrame", self.leftTree, "UIPanelScrollFrameTemplate")
  end
  if not self.scrollChild then
    local scrollChild = CreateFrame("Frame", "ToolboxQuestLeftScrollChild", self.scrollFrame)
    scrollChild:SetSize(180, 32)
    self.scrollChild = scrollChild
  end
  if self.scrollFrame:GetScrollChild() ~= self.scrollChild then
    self.scrollFrame:SetScrollChild(self.scrollChild)
  end
  if not self.rightTitle then
    local rightTitle = self.rightContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightTitle:SetJustifyH("LEFT")
    rightTitle:SetTextColor(1.0, 0.9, 0.68)
    self.rightTitle = rightTitle
  end
  if not self.rightHeaderDivider then
    local dividerTexture = self.rightContent:CreateTexture(nil, "ARTWORK")
    dividerTexture:SetColorTexture(0.6, 0.48, 0.24, 0.5)
    self.rightHeaderDivider = dividerTexture
  end
  if not self.breadcrumbFrame then
    local createSuccess, breadcrumbFrame = pcall(CreateFrame, "Frame", nil, self.rightContent, "NavBarTemplate") -- 冒险指南同款 NavBar 容器
    if createSuccess and breadcrumbFrame then
      self.breadcrumbFrame = breadcrumbFrame
    else
      self.breadcrumbFrame = CreateFrame("Frame", nil, self.rightContent)
    end
  end
  if not self.searchBoxFrame then
    local searchBoxFrame = CreateFrame("Frame", nil, self.rightContent, "BackdropTemplate")
    searchBoxFrame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    searchBoxFrame:SetBackdropColor(0.1, 0.08, 0.06, 1)
    searchBoxFrame:SetBackdropBorderColor(0.58, 0.47, 0.25, 1)
    self.searchBoxFrame = searchBoxFrame
  end
  if not self.searchBox then
    local searchBox = CreateFrame("EditBox", nil, self.rightContent, "InputBoxTemplate")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(80)
    searchBox:SetHeight(20)
    searchBox:SetTextInsets(0, 0, 0, 0)
    searchBox:SetScript("OnEscapePressed", function(editBox)
      editBox:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(editBox)
      editBox:ClearFocus()
    end)
    searchBox:SetScript("OnTextChanged", function(editBox, userInput)
      local currentText = editBox:GetText() or "" -- 当前输入文本
      if self.searchPlaceholder then
        self.searchPlaceholder:SetShown(currentText == "" and not editBox:HasFocus())
      end
      self.searchText = currentText
      if userInput then
        self:saveSelection()
        self:render()
      end
    end)
    searchBox:SetScript("OnEditFocusGained", function(editBox)
      if self.searchPlaceholder then
        self.searchPlaceholder:Hide()
      end
    end)
    searchBox:SetScript("OnEditFocusLost", function(editBox)
      if self.searchPlaceholder then
        self.searchPlaceholder:SetShown((editBox:GetText() or "") == "")
      end
    end)
    self.searchBox = searchBox
  end
  if not self.searchPlaceholder then
    local placeholderText = self.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholderText:SetPoint("LEFT", self.searchBox, "LEFT", 6, 0)
    placeholderText:SetPoint("RIGHT", self.searchBox, "RIGHT", -6, 0)
    placeholderText:SetJustifyH("LEFT")
    self.searchPlaceholder = placeholderText
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
  if not self.activeLogCurrentPanel then
    self.activeLogCurrentPanel = CreateFrame("Frame", nil, self.rightContent)
  end
  if not self.activeLogCurrentTitle then
    local currentTitle = self.activeLogCurrentPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight") -- 当前任务区标题
    currentTitle:SetJustifyH("LEFT")
    currentTitle:SetTextColor(1.0, 0.9, 0.68)
    self.activeLogCurrentTitle = currentTitle
  end
  if not self.activeLogCurrentScrollFrame then
    self.activeLogCurrentScrollFrame = CreateFrame("ScrollFrame", nil, self.activeLogCurrentPanel, "UIPanelScrollFrameTemplate")
  end
  if not self.activeLogCurrentScrollChild then
    local currentScrollChild = CreateFrame("Frame", nil, self.activeLogCurrentScrollFrame)
    currentScrollChild:SetSize(200, 32)
    self.activeLogCurrentScrollChild = currentScrollChild
  end
  if self.activeLogCurrentScrollFrame:GetScrollChild() ~= self.activeLogCurrentScrollChild then
    self.activeLogCurrentScrollFrame:SetScrollChild(self.activeLogCurrentScrollChild)
  end
  if not self.activeLogRecentPanel then
    self.activeLogRecentPanel = CreateFrame("Frame", nil, self.rightContent)
  end
  if not self.activeLogRecentTitle then
    local recentTitle = self.activeLogRecentPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight") -- 最近完成区标题
    recentTitle:SetJustifyH("LEFT")
    recentTitle:SetTextColor(1.0, 0.9, 0.68)
    self.activeLogRecentTitle = recentTitle
  end
  if not self.activeLogRecentToggleButton then
    local toggleButton = CreateFrame("Button", nil, self.rightContent, "UIPanelButtonTemplate") -- 最近完成折叠按钮
    toggleButton:SetHeight(18)
    toggleButton:SetScript("OnClick", function()
      self.activeLogRecentCollapsed = self.activeLogRecentCollapsed ~= true
      self:hideQuestDetailPopup()
      self:applyContentLayout()
      self:render()
    end)
    self.activeLogRecentToggleButton = toggleButton
  end
  if not self.activeLogRecentScrollFrame then
    self.activeLogRecentScrollFrame = CreateFrame("ScrollFrame", nil, self.activeLogRecentPanel, "UIPanelScrollFrameTemplate")
  end
  if not self.activeLogRecentScrollChild then
    local recentScrollChild = CreateFrame("Frame", nil, self.activeLogRecentScrollFrame)
    recentScrollChild:SetSize(200, 32)
    self.activeLogRecentScrollChild = recentScrollChild
  end
  if self.activeLogRecentScrollFrame:GetScrollChild() ~= self.activeLogRecentScrollChild then
    self.activeLogRecentScrollFrame:SetScrollChild(self.activeLogRecentScrollChild)
  end
  if self.activeLogCurrentPanel and self.activeLogCurrentPanel.SetBackdropColor then
    self.activeLogCurrentPanel:SetBackdropColor(0.09, 0.09, 0.11, 1)
    if self.activeLogCurrentPanel.SetBackdropBorderColor then
      self.activeLogCurrentPanel:SetBackdropBorderColor(0.38, 0.34, 0.28, 1)
    end
  end
  if self.activeLogRecentPanel and self.activeLogRecentPanel.SetBackdropColor then
    self.activeLogRecentPanel:SetBackdropColor(0.09, 0.09, 0.11, 1)
    if self.activeLogRecentPanel.SetBackdropBorderColor then
      self.activeLogRecentPanel:SetBackdropBorderColor(0.38, 0.34, 0.28, 1)
    end
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
    popupFrame:SetFrameStrata("DIALOG")
    popupFrame:SetFrameLevel(120)
    popupFrame:Hide()
    self.detailPopupFrame = popupFrame
  end
  if self.detailPopupFrame and self.detailPopupFrame.SetBackdropColor then
    self.detailPopupFrame:SetBackdropColor(0.09, 0.08, 0.06, 0.96)
    if self.detailPopupFrame.SetBackdropBorderColor then
      self.detailPopupFrame:SetBackdropBorderColor(0.72, 0.58, 0.3, 0.92)
    end
  end
  if not self.detailPopupTitleBar then
    local titleBarTexture = self.detailPopupFrame:CreateTexture(nil, "BACKGROUND")
    titleBarTexture:SetColorTexture(0.32, 0.24, 0.12, 0.58)
    titleBarTexture:SetPoint("TOPLEFT", self.detailPopupFrame, "TOPLEFT", 6, -6)
    titleBarTexture:SetPoint("TOPRIGHT", self.detailPopupFrame, "TOPRIGHT", -6, -6)
    titleBarTexture:SetHeight(24)
    self.detailPopupTitleBar = titleBarTexture
  end
  if not self.detailPopupTitle then
    local popupTitle = self.detailPopupFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    popupTitle:SetPoint("TOPLEFT", self.detailPopupFrame, "TOPLEFT", 14, -12)
    popupTitle:SetPoint("TOPRIGHT", self.detailPopupFrame, "TOPRIGHT", -40, -12)
    popupTitle:SetJustifyH("LEFT")
    popupTitle:SetTextColor(1.0, 0.9, 0.68)
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
      if type(button.expansionID) == "number" then
        self.selectedExpansionID = button.expansionID
      end
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
  if not self.detailPopupActiveButton then
    local activeButton = CreateFrame("Button", nil, self.detailPopupFrame, "UIPanelButtonTemplate")
    activeButton:SetSize(164, 20)
    activeButton:SetPoint("BOTTOMRIGHT", self.detailPopupFrame, "BOTTOMRIGHT", -12, 12)
    activeButton:SetScript("OnClick", function(button)
      self.selectedModeKey = "active_log"
      self.selectedQuestID = button.questID
      self:hideQuestDetailPopup()
      self:saveSelection()
      self:render()
    end)
    activeButton:Hide()
    self.detailPopupActiveButton = activeButton
  end
  if not self.detailPopupCloseButton then
    local closeButton = CreateFrame("Button", nil, self.detailPopupFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", self.detailPopupFrame, "TOPRIGHT", -6, -6)
    closeButton:SetScript("OnClick", function()
      self:hideQuestDetailPopup()
    end)
    self.detailPopupCloseButton = closeButton
  end
  self:loadSelection()
  if self.searchBox then
    self.searchBox:SetText(self.searchText or "")
  end
  if self.searchPlaceholder then
    local localeTable = Toolbox.L or {} -- 本地化文案
    self.searchPlaceholder:SetText(localeTable.EJ_QUEST_SEARCH_PLACEHOLDER or "Search questlines / quests...")
    self.searchPlaceholder:SetShown((self.searchText or "") == "")
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  if self.modeTabButtonByKey.active_log then
    self.modeTabButtonByKey.active_log:SetText(getActiveLogRootText(localeTable))
    self.modeTabButtonByKey.active_log:SetWidth(108)
  end
  if self.modeTabButtonByKey.map_questline then
    self.modeTabButtonByKey.map_questline:SetText(getQuestlineRootText(localeTable))
    self.modeTabButtonByKey.map_questline:SetWidth(92)
  end
  if self.activeLogRecentToggleButton then
    self.activeLogRecentToggleButton:SetText(getRecentCompletedToggleText(localeTable, self.activeLogRecentCollapsed))
    self.activeLogRecentToggleButton:SetWidth(108)
  end
  self:syncTabLabel()
  self:applyContentLayout()
  self:hookVanillaTabsOnce()
end

function QuestlineTreeView:updateVisibility()
  if not self.panelFrame then
    return
  end

  if isStandaloneQuestHost(self.hostJournalFrame) then
    local hostShown = self.hostJournalFrame and self.hostJournalFrame.IsShown and self.hostJournalFrame:IsShown() or false -- 主界面显示状态
    local shouldShowPanel = isQuestlineTreeEnabled() and hostShown and self.selected == true -- 是否显示 quest 主内容
    self:applyContentLayout()
    if self.tabButton and self.tabButton.Hide then
      self.tabButton:Hide()
    end
    if shouldShowPanel then
      self.panelFrame:Show()
      self.activeRootState = "quest"
      self:render()
    else
      self.panelFrame:Hide()
      self.activeRootState = "native"
    end
    return
  end

  if not self.tabButton then
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

--- 返回 quest 模块底部分页签模式键顺序。
---@return string[]
function QuestlineTreeView:getBottomTabModeKeys()
  return {
    "active_log",
    "map_questline",
  }
end

Internal.QuestlineTreeView = QuestlineTreeView






