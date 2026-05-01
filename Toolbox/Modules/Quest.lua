--[[
  quest 模块（quest）。
  职责：
    1. 提供独立任务界面宿主 Frame，并托管任务视图刷新。
    2. 管理任务相关设置与 Quest Inspector 工具区。
    3. 监听任务完成事件，维护“最近完成”数据。
]]

local Internal = Toolbox.QuestInternal -- quest 模块内部命名空间
local MODULE_ID = Internal.MODULE_ID -- 模块 ID
local Runtime = Internal.Runtime -- 运行时适配器
local CreateFrame = Internal.CreateFrame -- 统一建帧入口

local questEventFrame = nil -- quest 模块事件 Frame
local questHostFrame = nil -- quest 主界面根 Frame

local questInspectorUiState = {
  requestToken = 0,
  resultText = nil,
}

local function getModuleDb()
  return Internal.GetModuleDb()
end

local function getQuestView()
  return Internal.QuestlineTreeView
end

--- 让 quest 宿主框复用 mover 模块的自建窗体拖动与位置记忆。
---@param hostFrame Frame|nil quest 宿主框
local function registerQuestFrameDrag(hostFrame)
  if not hostFrame or not Toolbox or not Toolbox.Mover or type(Toolbox.Mover.RegisterFrame) ~= "function" then
    return
  end
  local dragRegion = hostFrame.TitleContainer or hostFrame -- 标题栏拖动命中区
  Toolbox.Mover.RegisterFrame(hostFrame, "ToolboxQuestFrame", {
    dragRegion = dragRegion,
  })
end

--- 归一化“最近完成”上限输入值。
---@param rawValue string|number|nil
---@return number
local function normalizeRecentCompletedLimit(rawValue)
  local numericValue = tonumber(rawValue) -- 输入对应的数字值
  if type(numericValue) ~= "number" then
    return 10
  end
  numericValue = math.floor(numericValue)
  if numericValue < 1 then
    return 1
  end
  if numericValue > 30 then
    return 30
  end
  return numericValue
end

--- 确保 quest 主界面已创建。
---@return Frame
local function ensureQuestHostFrame()
  if questHostFrame and questHostFrame.SetShown then
    return questHostFrame
  end

  local existingFrame = _G.ToolboxQuestFrame -- 已存在的 quest 主界面
  if existingFrame then
    questHostFrame = existingFrame
  else
    questHostFrame = CreateFrame("Frame", "ToolboxQuestFrame", UIParent, "PortraitFrameTemplate") -- quest 主界面
    questHostFrame:SetSize(980, 700)
    questHostFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local localeTable = Toolbox.L or {} -- 本地化文案
    if questHostFrame.SetTitle then
      questHostFrame:SetTitle(localeTable.MODULE_QUEST or "Quest")
    end
    if questHostFrame.SetPortraitToAsset then
      questHostFrame:SetPortraitToAsset([[Interface\QuestFrame\UI-QuestLog-BookIcon]])
    end
    questHostFrame:Hide()
  end

  if questHostFrame and not questHostFrame._toolboxQuestHooksBound then
    questHostFrame._toolboxQuestHooksBound = true
    questHostFrame:SetScript("OnShow", function()
      local questView = getQuestView() -- 任务视图对象
      if type(questView) == "table" and type(questView.setSelected) == "function" then
        questView:setSelected(true, true)
      end
      if type(questView) == "table" and type(questView.refresh) == "function" then
        questView:refresh()
      end
    end)
    questHostFrame:SetScript("OnHide", function()
      local questView = getQuestView() -- 任务视图对象
      if type(questView) == "table" and type(questView.setSelected) == "function" then
        questView:setSelected(false, true)
      end
    end)
  end

  registerQuestFrameDrag(questHostFrame)

  return questHostFrame
end

--- 打开 quest 主界面。
local function openQuestMainFrame()
  local moduleDb = getModuleDb() -- 模块存档
  if moduleDb.enabled == false then
    if Toolbox.SettingsHost and type(Toolbox.SettingsHost.OpenToModulePage) == "function" then
      Toolbox.SettingsHost:OpenToModulePage(MODULE_ID)
    end
    return
  end

  local hostFrame = ensureQuestHostFrame() -- quest 主界面
  hostFrame:Show()
end

--- 关闭 quest 主界面。
local function closeQuestMainFrame()
  if questHostFrame and questHostFrame.Hide then
    questHostFrame:Hide()
  end
end

--- 切换 quest 主界面显示状态。
local function toggleQuestMainFrame()
  local moduleDb = getModuleDb() -- 模块存档
  if moduleDb.enabled == false then
    if Toolbox.SettingsHost and type(Toolbox.SettingsHost.OpenToModulePage) == "function" then
      Toolbox.SettingsHost:OpenToModulePage(MODULE_ID)
    end
    return
  end

  local hostFrame = ensureQuestHostFrame() -- quest 主界面
  if hostFrame.IsShown and hostFrame:IsShown() then
    closeQuestMainFrame()
  else
    openQuestMainFrame()
  end
end

Toolbox.Quest = Toolbox.Quest or {}

--- 打开 quest 主界面。
function Toolbox.Quest.OpenMainFrame()
  openQuestMainFrame()
end

--- 切换 quest 主界面显示状态。
function Toolbox.Quest.ToggleMainFrame()
  toggleQuestMainFrame()
end

--- 返回任务详情查询页键名。
---@return string
local function getQuestInspectorPageKey()
  local settingsHost = Toolbox and Toolbox.SettingsHost or nil -- 设置页宿主
  if settingsHost and type(settingsHost.GetModulePageKey) == "function" then
    return settingsHost:GetModulePageKey(MODULE_ID)
  end
  return "quest"
end

--- 解析 QuestID 输入文本。
---@param rawValue string|number|nil
---@return number|nil
local function normalizeQuestInspectorQuestID(rawValue)
  local numericValue = tonumber(rawValue) -- 输入对应的数字值
  if type(numericValue) ~= "number" then
    return nil
  end
  numericValue = math.floor(numericValue)
  if numericValue <= 0 then
    return nil
  end
  return numericValue
end

--- 构建任务详情查询页展示文本。
---@param localeTable table 本地化文案
---@param loadStateText string|nil 加载状态
---@param snapshotObject table|nil 任务详情快照
---@return string
local function buildQuestInspectorResultText(localeTable, loadStateText, snapshotObject)
  local lineList = {} -- 结果文本行列表
  lineList[#lineList + 1] = string.format("loadState: %s", tostring(loadStateText or "ready"))

  if type(snapshotObject) == "table" and type(snapshotObject.flatLines) == "table" and #snapshotObject.flatLines > 0 then
    for _, messageText in ipairs(snapshotObject.flatLines) do
      lineList[#lineList + 1] = messageText
    end
    return table.concat(lineList, "\n")
  end

  lineList[#lineList + 1] = localeTable.EJ_QUEST_INSPECTOR_FAILED or "Quest data load failed or no runtime data is available."
  return table.concat(lineList, "\n")
end

--- 触发任务详情查询并在设置页结果区回填文本。
---@param questID number 任务 ID
local function requestQuestInspectorSnapshot(questID)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local moduleDb = getModuleDb() -- 模块存档
  local pageKey = getQuestInspectorPageKey() -- 查询页键名
  local settingsHost = Toolbox and Toolbox.SettingsHost or nil -- 设置页宿主

  local function rebuildInspectorPage()
    if settingsHost and type(settingsHost.BuildPage) == "function" then
      settingsHost:BuildPage(pageKey)
    end
  end

  moduleDb.questInspectorLastQuestID = questID
  questInspectorUiState.requestToken = (questInspectorUiState.requestToken or 0) + 1
  local currentToken = questInspectorUiState.requestToken -- 当前请求令牌
  questInspectorUiState.resultText = localeTable.EJ_QUEST_INSPECTOR_LOADING or "Loading quest data..."
  rebuildInspectorPage()

  if not Toolbox.Questlines or type(Toolbox.Questlines.RequestQuestInspectorSnapshot) ~= "function" then
    questInspectorUiState.resultText = localeTable.EJ_QUEST_INSPECTOR_FAILED or "Quest data load failed or no runtime data is available."
    rebuildInspectorPage()
    return
  end

  local accepted, stateText, snapshotObject = Toolbox.Questlines.RequestQuestInspectorSnapshot(
    questID,
    function(_, loadedStateText, loadedSnapshotObject)
      if questInspectorUiState.requestToken ~= currentToken then
        return
      end
      questInspectorUiState.resultText = buildQuestInspectorResultText(localeTable, loadedStateText, loadedSnapshotObject)
      rebuildInspectorPage()
    end
  )

  if not accepted then
    questInspectorUiState.resultText = localeTable.EJ_QUEST_INSPECTOR_FAILED or "Quest data load failed or no runtime data is available."
  elseif stateText == "ready" then
    questInspectorUiState.resultText = buildQuestInspectorResultText(localeTable, stateText, snapshotObject)
  else
    questInspectorUiState.resultText = localeTable.EJ_QUEST_INSPECTOR_LOADING or "Loading quest data..."
  end
  rebuildInspectorPage()
end

--- 构建任务页中的 Quest Inspector 低频工具区。
---@param box Frame 子页面容器
---@return number
local function buildQuestInspectorSettingsPage(box)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local moduleDb = getModuleDb() -- 模块存档
  local yOffset = 0 -- 当前纵向游标

  local inputLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 输入框标签
  inputLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
  inputLabel:SetText(localeTable.EJ_QUEST_INSPECTOR_INPUT_LABEL or "QuestID")
  yOffset = yOffset - 24

  local questIDEditBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate") -- QuestID 输入框
  questIDEditBox:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
  questIDEditBox:SetSize(200, 24)
  questIDEditBox:SetAutoFocus(false)
  questIDEditBox:SetMaxLetters(12)
  if type(moduleDb.questInspectorLastQuestID) == "number" and moduleDb.questInspectorLastQuestID > 0 then
    questIDEditBox:SetText(tostring(moduleDb.questInspectorLastQuestID))
  else
    questIDEditBox:SetText("")
  end
  questIDEditBox:SetScript("OnEscapePressed", function(editBox)
    editBox:ClearFocus()
  end)

  local function submitQuestInspectorQuery()
    local questID = normalizeQuestInspectorQuestID(questIDEditBox:GetText()) -- 当前输入的任务 ID
    if not questID then
      questInspectorUiState.resultText = localeTable.EJ_QUEST_INSPECTOR_INVALID_ID or "Please input a valid QuestID."
      if Toolbox.SettingsHost and type(Toolbox.SettingsHost.BuildPage) == "function" then
        Toolbox.SettingsHost:BuildPage(getQuestInspectorPageKey())
      end
      return
    end
    requestQuestInspectorSnapshot(questID)
  end

  questIDEditBox:SetScript("OnEnterPressed", function(editBox)
    editBox:ClearFocus()
    submitQuestInspectorQuery()
  end)

  local queryButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate") -- 查询按钮
  queryButton:SetSize(120, 22)
  queryButton:SetPoint("LEFT", questIDEditBox, "RIGHT", 12, 0)
  queryButton:SetText(localeTable.EJ_QUEST_INSPECTOR_QUERY_BUTTON or "Inspect")
  queryButton:SetScript("OnClick", submitQuestInspectorQuery)

  yOffset = yOffset - 42

  local resultTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 结果区标题
  resultTitle:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
  resultTitle:SetText(localeTable.EJ_QUEST_INSPECTOR_RESULT_TITLE or "Result")
  yOffset = yOffset - 24

  local resultFrame = CreateFrame("Frame", nil, box, "BackdropTemplate") -- 结果区底板
  resultFrame:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
  resultFrame:SetSize(560, 420)
  if resultFrame.SetBackdrop then
    resultFrame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    resultFrame:SetBackdropColor(0.08, 0.08, 0.1, 0.82)
    resultFrame:SetBackdropBorderColor(0.35, 0.35, 0.38, 0.75)
  end

  local resultScrollFrame = CreateFrame("ScrollFrame", nil, resultFrame, "UIPanelScrollFrameTemplate") -- 结果滚动框
  resultScrollFrame:SetPoint("TOPLEFT", resultFrame, "TOPLEFT", 8, -8)
  resultScrollFrame:SetPoint("BOTTOMRIGHT", resultFrame, "BOTTOMRIGHT", -28, 8)

  local resultEditBox = CreateFrame("EditBox", nil, resultScrollFrame) -- 结果文本框
  resultEditBox:SetMultiLine(true)
  if resultEditBox.SetFontObject and ChatFontNormal then
    resultEditBox:SetFontObject(ChatFontNormal)
  end
  resultEditBox:SetWidth(500)
  resultEditBox:SetHeight(2000)
  resultEditBox:SetAutoFocus(false)
  resultEditBox:SetTextInsets(6, 6, 6, 6)
  resultEditBox:SetScript("OnEscapePressed", function(editBox)
    editBox:ClearFocus()
  end)
  resultEditBox:SetText(questInspectorUiState.resultText or (localeTable.EJ_QUEST_INSPECTOR_EMPTY or "Input a QuestID and click Inspect."))
  resultScrollFrame:SetScrollChild(resultEditBox)

  yOffset = yOffset - 436
  local blockHeight = math.abs(yOffset) + 20 -- Inspector 内容块最终高度
  box:SetHeight(blockHeight)
  box.realHeight = blockHeight
  return blockHeight
end

local function setQuestTurnInEventEnabled(enabled)
  if not questEventFrame then
    return
  end
  if enabled then
    questEventFrame:RegisterEvent("QUEST_TURNED_IN")
  else
    questEventFrame:UnregisterEvent("QUEST_TURNED_IN")
  end
end

local function registerIntegration()
  if questEventFrame then
    return
  end

  questEventFrame = CreateFrame("Frame", "ToolboxQuestHost") -- quest 事件主 Frame
  setQuestTurnInEventEnabled(Internal.IsModuleEnabled())
  questEventFrame:SetScript("OnEvent", function(_, eventName, ...)
    if eventName ~= "QUEST_TURNED_IN" then
      return
    end
    local questID = ... -- 完成事件任务 ID
    if type(questID) ~= "number" or questID <= 0 then
      return
    end
    local questView = getQuestView() -- 任务视图对象
    if type(questView) == "table" and type(questView.recordRecentlyCompletedQuest) == "function" then
      questView:recordRecentlyCompletedQuest(questID)
    end
  end)
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

  local function collectBreadcrumbTextList()
    local questView = getQuestView() -- 任务视图对象
    local breadcrumbTextList = {} -- breadcrumb 文本列表
    if type(questView) ~= "table" or type(questView.breadcrumbButtons) ~= "table" then
      return breadcrumbTextList
    end
    for _, buttonObject in ipairs(questView.breadcrumbButtons) do
      if buttonObject and (not buttonObject.IsShown or buttonObject:IsShown()) and buttonObject.GetText then
        breadcrumbTextList[#breadcrumbTextList + 1] = tostring(buttonObject:GetText() or "")
      end
    end
    return breadcrumbTextList
  end

  Toolbox.TestHooks = Toolbox.TestHooks or {} -- 测试 hook 容器
  Toolbox.TestHooks.Quest = {
    getView = function()
      return getQuestView()
    end,
    getBottomTabModeKeys = function()
      local questView = getQuestView() -- 任务视图对象
      if type(questView) == "table" and type(questView.getBottomTabModeKeys) == "function" then
        return questView:getBottomTabModeKeys()
      end
      return {}
    end,
    getBreadcrumbTextList = function()
      return collectBreadcrumbTextList()
    end,
    getHostFrame = function()
      return questHostFrame
    end,
    resetInternalState = function()
      if questEventFrame and questEventFrame.UnregisterEvent then
        questEventFrame:UnregisterEvent("QUEST_TURNED_IN")
      end
      questEventFrame = nil
      if questHostFrame and questHostFrame.Hide then
        questHostFrame:Hide()
      end
      questHostFrame = nil
    end,
  }
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_QUEST",
  settingsIntroKey = "MODULE_QUEST_INTRO",
  settingsOrder = 55,

  OnModuleLoad = function()
    ensureQuestHostFrame()
    registerIntegration()
    exposeTestHooksIfNeeded()
  end,

  OnModuleEnable = function()
    local questView = getQuestView() -- 任务视图对象
    if type(questView) == "table" and type(questView.refresh) == "function" then
      questView:refresh()
    end
  end,

  OnEnabledSettingChanged = function(enabled)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local messageKey = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT" -- 提示键
    Toolbox.Chat.PrintAddonMessage(string.format(localeTable[messageKey] or "%s", localeTable.MODULE_QUEST or MODULE_ID))

    setQuestTurnInEventEnabled(enabled)
    if not enabled then
      closeQuestMainFrame()
      return
    end

    local questView = getQuestView() -- 任务视图对象
    if type(questView) == "table" and type(questView.refresh) == "function" then
      questView:refresh()
    end
  end,

  OnDebugSettingChanged = function(enabled)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local messageKey = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT" -- 提示键
    Toolbox.Chat.PrintAddonMessage(string.format(localeTable[messageKey] or "%s", localeTable.MODULE_QUEST or MODULE_ID))
  end,

  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
    local questView = getQuestView() -- 任务视图对象
    if type(questView) == "table" and type(questView.loadSelection) == "function" then
      questView:loadSelection()
    end
    if type(questView) == "table" and type(questView.refresh) == "function" then
      questView:refresh()
    end
  end,

  RegisterSettings = function(box)
    local localeTable = Toolbox.L or {} -- 本地化文案
    local moduleDb = getModuleDb() -- 模块存档
    box:AddActionRow({
      label = localeTable.MINIMAP_FLYOUT_QUEST or "任务",
      buttonText = localeTable.MINIMAP_FLYOUT_QUEST or "任务",
      onClick = function()
        openQuestMainFrame()
      end,
    })

    box:AddToggleRow({
      label = localeTable.EJ_QUESTLINE_TREE_LABEL or "任务",
      getValue = function()
        return moduleDb.questlineTreeEnabled ~= false
      end,
      setValue = function(value)
        moduleDb.questlineTreeEnabled = value == true
      end,
      afterChange = function()
        local questView = getQuestView() -- 任务视图对象
        if type(questView) == "table" and type(questView.refresh) == "function" then
          questView:refresh()
        end
      end,
    })

    box:AddCustomBlock(function(blockFrame)
      local yOffset = 0 -- 最近完成设置块纵向游标

      local recentLabel = blockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 最近完成上限标签
      recentLabel:SetPoint("TOPLEFT", blockFrame, "TOPLEFT", 20, yOffset)
      recentLabel:SetText(localeTable.EJ_QUEST_RECENT_COMPLETED_LIMIT_LABEL or "Recent completed limit")
      yOffset = yOffset - 24

      local recentInput = CreateFrame("EditBox", nil, blockFrame, "InputBoxTemplate") -- 最近完成上限输入框
      recentInput:SetPoint("TOPLEFT", blockFrame, "TOPLEFT", 20, yOffset)
      recentInput:SetSize(120, 24)
      recentInput:SetAutoFocus(false)
      recentInput:SetMaxLetters(3)
      recentInput:SetText(tostring(normalizeRecentCompletedLimit(moduleDb.questRecentCompletedMax)))
      recentInput:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
      end)

      local applyButton = CreateFrame("Button", nil, blockFrame, "UIPanelButtonTemplate") -- 应用上限按钮
      applyButton:SetSize(80, 22)
      applyButton:SetPoint("LEFT", recentInput, "RIGHT", 12, 0)
      applyButton:SetText(localeTable.MINIMAP_FLYOUT_SETTING_APPLY or "Apply")
      applyButton:SetScript("OnClick", function()
        moduleDb.questRecentCompletedMax = normalizeRecentCompletedLimit(recentInput:GetText())
        recentInput:SetText(tostring(moduleDb.questRecentCompletedMax))
        local questView = getQuestView() -- 任务视图对象
        if type(questView) == "table" and type(questView.trimRecentCompletedQuestRecords) == "function" then
          questView:trimRecentCompletedQuestRecords()
        end
        if type(questView) == "table" and type(questView.refresh) == "function" then
          questView:refresh()
        end
      end)
      yOffset = yOffset - 36

      local hintText = blockFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 提示文本
      hintText:SetPoint("TOPLEFT", blockFrame, "TOPLEFT", 20, yOffset)
      hintText:SetWidth(560)
      hintText:SetJustifyH("LEFT")
      hintText:SetText(localeTable.EJ_QUEST_RECENT_COMPLETED_LIMIT_HINT or "")
      yOffset = yOffset - math.max(28, math.ceil((hintText:GetStringHeight() or 0) + 8))

      local blockHeight = math.abs(yOffset) + 4 -- 最近完成设置块最终高度
      blockFrame:SetHeight(blockHeight)
      blockFrame.realHeight = blockHeight
      return blockHeight
    end)

    box:AddSectionHeader({
      title = localeTable.EJ_QUEST_INSPECTOR_PAGE_TITLE or "Quest Inspector",
      description = localeTable.EJ_QUEST_INSPECTOR_PAGE_INTRO or "",
    })

    box:AddCustomBlock(function(blockFrame)
      return buildQuestInspectorSettingsPage(blockFrame)
    end)
  end,
})
