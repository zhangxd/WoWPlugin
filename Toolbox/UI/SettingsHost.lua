--[[
  正式服 Settings 宿主：注册 Toolbox 根类目与 6 个叶子设置页。
  宿主负责把多个模块页组合进“通用 / 界面 / 地图 / 任务 / 冒险手册 / 关于”，并统一默认打开规则。
  `/toolbox`、ESC 菜单按钮与小地图按钮都优先回到上次停留叶子页；首次打开回退到“通用”。
  战斗中暴雪 `Settings.OpenToCategory` 不可靠：用独立宿主（全屏半透明遮罩 + Dialog 风格底板）托起 Canvas，脱战后仍走系统设置。
  非战斗打开设置前会 `HideUIPanel(GameMenuFrame)`，避免关闭设置后仍显示 ESC 菜单。
  勿缓存 `Toolbox.L`；语言切换后会重建所有页面内容。
]]

Toolbox.SettingsHost = Toolbox.SettingsHost or {}

local PANEL_WIDTH = 700
local PANEL_HEIGHT = 920
local SCROLL_CHILD_WIDTH = 640
local MODULE_BOX_WIDTH = 604
local DEFAULT_LEAF_PAGE_KEY = "general" -- 默认打开的叶子页键名
local SETTINGS_ROW_LABEL_WIDTH = 340
local SETTINGS_ROW_TEXT_WIDTH = 360
local SETTINGS_ROW_CONTROL_LEFT = 390
local SETTINGS_ROW_BUTTON_WIDTH = 92
local SETTINGS_BOX_BOTTOM_PADDING = 8
local SETTINGS_BOX_MIN_HEIGHT = 8
--- 战斗内独立展示时相对裸 `UIParent` 居中略缩小，贴近系统设置窗口内嵌 Canvas 的观感（可按实机再调）。
local STANDALONE_PANEL_SCALE = 0.82
local MODULE_LEAF_KEY_MAP = {
  chat_notify = "general",
  minimap_button = "general",
  mover = "interface",
  tooltip_anchor = "interface",
  navigation = "map",
  quest = "quest",
  encounter_journal = "encounter_journal",
}

local function sanitizePageName(value)
  return tostring(value or "Page"):gsub("[^%w_]", "_")
end

local function createCanvasPanel(frameName)
  local panel = CreateFrame("Frame", frameName, UIParent) -- 叶子页面板
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:Hide()

  local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate") -- 页面滚动框
  scrollFrame:SetPoint("TOPLEFT", 8, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

  local childFrame = CreateFrame("Frame", nil, scrollFrame) -- 页面滚动内容根节点
  childFrame:SetSize(SCROLL_CHILD_WIDTH, 800)
  scrollFrame:SetScrollChild(childFrame)

  panel._toolboxScroll = scrollFrame
  panel._toolboxChild = childFrame
  return panel
end

local function resetCanvasPanel(panel)
  local scrollFrame = panel._toolboxScroll -- 页面滚动框
  local oldChild = panel._toolboxChild -- 旧内容节点
  if oldChild then
    oldChild:SetParent(nil)
    oldChild:Hide()
  end

  local childFrame = CreateFrame("Frame", nil, scrollFrame) -- 新内容节点
  childFrame:SetSize(SCROLL_CHILD_WIDTH, 800)
  scrollFrame:SetScrollChild(childFrame)
  panel._toolboxChild = childFrame
  if scrollFrame.SetVerticalScroll then
    scrollFrame:SetVerticalScroll(0)
  end
  return childFrame
end

local function collectSettingsModules()
  local moduleList = {} -- 带设置页的模块列表
  for _, moduleObject in ipairs(Toolbox.ModuleRegistry:GetSorted()) do
    if moduleObject.RegisterSettings then
      moduleList[#moduleList + 1] = moduleObject
    end
  end

  table.sort(moduleList, function(leftModule, rightModule)
    local leftOrder = tonumber(leftModule.settingsOrder) or 9999 -- 左侧排序值
    local rightOrder = tonumber(rightModule.settingsOrder) or 9999 -- 右侧排序值
    if leftOrder ~= rightOrder then
      return leftOrder < rightOrder
    end
    return tostring(leftModule.id) < tostring(rightModule.id)
  end)

  return moduleList
end

local function getModuleTitle(moduleObject)
  local localeTable = Toolbox.L or {} -- 本地化文案
  if moduleObject.nameKey and localeTable[moduleObject.nameKey] then
    return localeTable[moduleObject.nameKey]
  end
  if moduleObject.name then
    return moduleObject.name
  end
  return moduleObject.id
end

local function getModuleIntro(moduleObject)
  local localeTable = Toolbox.L or {} -- 本地化文案
  if moduleObject.settingsIntroKey and localeTable[moduleObject.settingsIntroKey] then
    return localeTable[moduleObject.settingsIntroKey]
  end
  return ""
end

local function getPageTitle(pageObject)
  local localeTable = Toolbox.L or {} -- 本地化文案
  if pageObject.titleKey and localeTable[pageObject.titleKey] then
    return localeTable[pageObject.titleKey]
  end
  if pageObject.titleText then
    return pageObject.titleText
  end
  if pageObject.module then
    return getModuleTitle(pageObject.module)
  end
  return pageObject.key
end

local function getPageIntro(pageObject)
  local localeTable = Toolbox.L or {} -- 本地化文案
  if pageObject.introKey and localeTable[pageObject.introKey] then
    return localeTable[pageObject.introKey]
  end
  if type(pageObject.introText) == "string" then
    return pageObject.introText
  end
  if pageObject.module then
    return getModuleIntro(pageObject.module)
  end
  return ""
end

local function applyModuleCallbacks(moduleObject)
  local moduleDb = Toolbox.Config.GetModule(moduleObject.id) -- 模块存档
  if moduleObject.OnEnabledSettingChanged then
    moduleObject.OnEnabledSettingChanged(moduleDb.enabled ~= false)
  end
  if moduleObject.OnDebugSettingChanged then
    moduleObject.OnDebugSettingChanged(moduleDb.debug == true)
  end
end

local function getChoiceOptions(optionList)
  if type(optionList) ~= "table" then
    return {}
  end
  return optionList
end

local function normalizeChoiceValue(currentValue, optionList, defaultValue)
  local choiceList = getChoiceOptions(optionList) -- 选项列表
  for _, optionObject in ipairs(choiceList) do
    if optionObject and optionObject.value == currentValue then
      return currentValue, false
    end
  end

  if defaultValue ~= nil then
    for _, optionObject in ipairs(choiceList) do
      if optionObject and optionObject.value == defaultValue then
        return defaultValue, true
      end
    end
  end

  local firstOption = choiceList[1] -- 首项兜底
  if firstOption ~= nil then
    return firstOption.value, true
  end
  return defaultValue, true
end

local function normalizeToggleValue(currentValue, defaultValue)
  if type(currentValue) == "boolean" then
    return currentValue, false
  end
  if defaultValue ~= nil then
    return defaultValue == true, true
  end
  if currentValue == nil then
    return false, true
  end
  return currentValue == true, true
end

local function setFontStringTextColor(fontString, isEnabled)
  if not fontString or not fontString.SetTextColor then
    return
  end
  if isEnabled == false then
    fontString:SetTextColor(0.55, 0.55, 0.55)
  else
    fontString:SetTextColor(1, 1, 1)
  end
end

local function triggerBoxRefresh(boxFrame, options)
  local refreshMode = type(options) == "table" and options.refreshMode or nil -- 刷新模式
  if refreshMode == "page" then
    boxFrame:RequestPageRebuild()
  elseif refreshMode == "all_pages" then
    Toolbox.SettingsHost:RefreshAllPages()
  elseif refreshMode == "none" then
    return
  else
    boxFrame:RequestLocalRefresh()
  end
end

local function anchorInset(frameObject, parentObject, insetValue)
  if not frameObject or not parentObject then
    return
  end
  local insetAmount = tonumber(insetValue) or 0 -- 统一内缩值
  frameObject:ClearAllPoints()
  frameObject:SetPoint("TOPLEFT", parentObject, "TOPLEFT", insetAmount, -insetAmount)
  frameObject:SetPoint("BOTTOMRIGHT", parentObject, "BOTTOMRIGHT", -insetAmount, insetAmount)
end

local function setObjectShown(frameObject, shouldShow)
  if not frameObject then
    return
  end
  if shouldShow then
    frameObject:Show()
  else
    frameObject:Hide()
  end
end

local function setControlLabelText(controlObject, textValue)
  if controlObject and controlObject._toolboxLabel and controlObject._toolboxLabel.SetText then
    controlObject._toolboxLabel:SetText(textValue or "")
  end
  if controlObject and controlObject.SetText then
    controlObject:SetText(textValue or "")
  end
end

local function getChoiceCurrentValue(rowOptions, choiceList)
  local currentValue = type(rowOptions.getValue) == "function" and rowOptions.getValue() or rowOptions.value -- 当前取值
  local normalizedValue, wasNormalized = normalizeChoiceValue(currentValue, choiceList, rowOptions.defaultValue) -- 归一后的取值
  if wasNormalized and normalizedValue ~= nil and type(rowOptions.setValue) == "function" then
    rowOptions.setValue(normalizedValue)
  end
  return normalizedValue
end

local function findChoiceIndex(choiceList, currentValue)
  for indexNumber, optionObject in ipairs(choiceList or {}) do
    if optionObject and optionObject.value == currentValue then
      return indexNumber
    end
  end
  return nil
end

local function getChoiceOption(choiceList, currentValue)
  local currentIndex = findChoiceIndex(choiceList, currentValue) or 1 -- 当前索引
  return choiceList[currentIndex], currentIndex
end

local function setDropdownDisplayText(dropdownButton, textValue)
  if not dropdownButton then
    return
  end
  if type(dropdownButton.SetDefaultText) == "function" then
    dropdownButton:SetDefaultText(textValue or "")
  end
  if type(dropdownButton.OverrideText) == "function" then
    dropdownButton:OverrideText(textValue or "")
  elseif type(dropdownButton.SetText) == "function" then
    dropdownButton:SetText(textValue or "")
  end
end

local function ensureDropdownWithButtonsControl(parentFrame, dropdownWidth)
  local widthValue = tonumber(dropdownWidth) or 170 -- 中间下拉框宽度
  local controlObject = nil -- 下拉+步进组合控件
  local createdWithTemplate = false -- 是否成功使用原生模板
  local okFlag, frameObject = pcall(function()
    return CreateFrame("Frame", nil, parentFrame, "SettingsDropdownWithButtonsTemplate")
  end)
  if okFlag and frameObject then
    controlObject = frameObject
    createdWithTemplate = true
  else
    controlObject = CreateFrame("Frame", nil, parentFrame)
  end

  controlObject.templateName = createdWithTemplate and "SettingsDropdownWithButtonsTemplate" or controlObject.templateName
  controlObject:SetSize(widthValue + 70, 32)

  if not controlObject.Dropdown then
    local dropdownButton = CreateFrame("Button", nil, controlObject) -- 兜底下拉按钮
    dropdownButton:RegisterForClicks("LeftButtonUp")
    controlObject.Dropdown = dropdownButton
  end
  if not controlObject.IncrementButton then
    local incrementButton = CreateFrame("Button", nil, controlObject) -- 兜底右箭头
    incrementButton:RegisterForClicks("LeftButtonUp")
    controlObject.IncrementButton = incrementButton
  end
  if not controlObject.DecrementButton then
    local decrementButton = CreateFrame("Button", nil, controlObject) -- 兜底左箭头
    decrementButton:RegisterForClicks("LeftButtonUp")
    controlObject.DecrementButton = decrementButton
  end

  if controlObject.Dropdown.ClearAllPoints and controlObject.Dropdown.SetPoint then
    controlObject.Dropdown:ClearAllPoints()
    controlObject.Dropdown:SetPoint("LEFT", controlObject, "LEFT", 32, 0)
  end
  if controlObject.Dropdown.SetWidth then
    controlObject.Dropdown:SetWidth(widthValue)
  end
  if controlObject.Dropdown.SetHeight then
    controlObject.Dropdown:SetHeight(28)
  end

  if controlObject.IncrementButton.ClearAllPoints and controlObject.IncrementButton.SetPoint then
    controlObject.IncrementButton:ClearAllPoints()
    controlObject.IncrementButton:SetPoint("LEFT", controlObject.Dropdown, "RIGHT", 4, 0)
  end
  if controlObject.DecrementButton.ClearAllPoints and controlObject.DecrementButton.SetPoint then
    controlObject.DecrementButton:ClearAllPoints()
    controlObject.DecrementButton:SetPoint("RIGHT", controlObject.Dropdown, "LEFT", -5, 0)
  end
  if controlObject.IncrementButton.SetSize then
    controlObject.IncrementButton:SetSize(28, 28)
  end
  if controlObject.DecrementButton.SetSize then
    controlObject.DecrementButton:SetSize(28, 28)
  end

  if type(controlObject.SetSteppersShown) ~= "function" then
    function controlObject:SetSteppersShown(isShown)
      setObjectShown(self.IncrementButton, isShown ~= false)
      setObjectShown(self.DecrementButton, isShown ~= false)
    end
  end
  if type(controlObject.SetSteppersEnabled) ~= "function" then
    function controlObject:SetSteppersEnabled(canDecrement, canIncrement)
      if self.DecrementButton and self.DecrementButton.SetEnabled then
        self.DecrementButton:SetEnabled(canDecrement == true)
      end
      if self.IncrementButton and self.IncrementButton.SetEnabled then
        self.IncrementButton:SetEnabled(canIncrement == true)
      end
    end
  end

  return controlObject
end

local function createSurfaceControl(parentFrame, frameType)
  local controlObject = CreateFrame(frameType or "Button", nil, parentFrame) -- 通用表面控件
  local borderTexture = controlObject:CreateTexture(nil, "BORDER") -- 外边框贴图
  borderTexture:SetAllPoints()
  borderTexture:SetColorTexture(0.27, 0.31, 0.4, 1)
  controlObject._toolboxBorderTexture = borderTexture

  local backgroundTexture = controlObject:CreateTexture(nil, "BACKGROUND") -- 主背景贴图
  anchorInset(backgroundTexture, controlObject, 1)
  backgroundTexture:SetColorTexture(0.09, 0.11, 0.16, 0.96)
  controlObject._toolboxBackgroundTexture = backgroundTexture

  local accentTexture = controlObject:CreateTexture(nil, "ARTWORK") -- 选中高亮贴图
  anchorInset(accentTexture, controlObject, 1)
  accentTexture:SetColorTexture(0.21, 0.45, 0.82, 0.36)
  accentTexture:Hide()
  controlObject._toolboxAccentTexture = accentTexture

  local labelText = controlObject:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 控件标签文本
  labelText:SetPoint("CENTER", controlObject, "CENTER", 0, 0)
  labelText:SetJustifyH("CENTER")
  controlObject._toolboxLabel = labelText
  return controlObject
end

local function applySurfaceControlState(controlObject, isEnabled, isSelected, isOpen)
  if not controlObject then
    return
  end
  local borderTexture = controlObject._toolboxBorderTexture -- 控件边框贴图
  local backgroundTexture = controlObject._toolboxBackgroundTexture -- 控件背景贴图
  local accentTexture = controlObject._toolboxAccentTexture -- 控件高亮贴图
  local labelText = controlObject._toolboxLabel -- 控件标签文本

  if borderTexture and borderTexture.SetColorTexture then
    if isEnabled == false then
      borderTexture:SetColorTexture(0.2, 0.22, 0.28, 1)
    elseif isSelected or isOpen then
      borderTexture:SetColorTexture(0.46, 0.63, 0.95, 1)
    else
      borderTexture:SetColorTexture(0.27, 0.31, 0.4, 1)
    end
  end

  if backgroundTexture and backgroundTexture.SetColorTexture then
    if isEnabled == false then
      backgroundTexture:SetColorTexture(0.08, 0.09, 0.12, 0.82)
    elseif isSelected or isOpen then
      backgroundTexture:SetColorTexture(0.14, 0.2, 0.33, 0.96)
    else
      backgroundTexture:SetColorTexture(0.09, 0.11, 0.16, 0.96)
    end
  end

  if accentTexture then
    setObjectShown(accentTexture, isEnabled ~= false and (isSelected or isOpen))
  end

  if labelText and labelText.SetTextColor then
    if isEnabled == false then
      labelText:SetTextColor(0.5, 0.52, 0.58)
    elseif isSelected or isOpen then
      labelText:SetTextColor(0.96, 0.97, 1)
    else
      labelText:SetTextColor(0.86, 0.88, 0.93)
    end
  end
end

local function createCheckboxControl(parentFrame)
  local okFlag, nativeCheckbox = pcall(function()
    return CreateFrame("CheckButton", nil, parentFrame, "SettingsCheckboxTemplate")
  end)
  if okFlag and nativeCheckbox then
    return nativeCheckbox
  end

  local checkButton = CreateFrame("CheckButton", nil, parentFrame) -- 自绘勾选控件
  checkButton:RegisterForClicks("LeftButtonUp")

  local borderTexture = checkButton:CreateTexture(nil, "BORDER") -- 勾选框边框
  borderTexture:SetAllPoints()
  borderTexture:SetColorTexture(0.27, 0.31, 0.4, 1)
  checkButton._toolboxBorderTexture = borderTexture

  local backgroundTexture = checkButton:CreateTexture(nil, "BACKGROUND") -- 勾选框底色
  anchorInset(backgroundTexture, checkButton, 1)
  backgroundTexture:SetColorTexture(0.09, 0.11, 0.16, 0.96)
  checkButton._toolboxBackgroundTexture = backgroundTexture

  local checkTexture = checkButton:CreateTexture(nil, "ARTWORK") -- 勾选标记贴图
  anchorInset(checkTexture, checkButton, 3)
  checkTexture:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  checkTexture:Hide()
  checkButton._toolboxCheckTexture = checkTexture
  return checkButton
end

local function applyCheckboxState(checkButton, isEnabled, isChecked)
  if not checkButton then
    return
  end
  local borderTexture = checkButton._toolboxBorderTexture -- 勾选框边框
  local backgroundTexture = checkButton._toolboxBackgroundTexture -- 勾选框底色
  local checkTexture = checkButton._toolboxCheckTexture -- 勾选标记贴图
  local inlineLabel = checkButton._toolboxInlineLabel -- 行内标签文本

  if borderTexture and borderTexture.SetColorTexture then
    if isEnabled == false then
      borderTexture:SetColorTexture(0.2, 0.22, 0.28, 1)
    elseif isChecked then
      borderTexture:SetColorTexture(0.46, 0.63, 0.95, 1)
    else
      borderTexture:SetColorTexture(0.27, 0.31, 0.4, 1)
    end
  end

  if backgroundTexture and backgroundTexture.SetColorTexture then
    if isEnabled == false then
      backgroundTexture:SetColorTexture(0.08, 0.09, 0.12, 0.82)
    elseif isChecked then
      backgroundTexture:SetColorTexture(0.13, 0.19, 0.31, 0.96)
    else
      backgroundTexture:SetColorTexture(0.09, 0.11, 0.16, 0.96)
    end
  end

  if checkTexture then
    setObjectShown(checkTexture, isChecked == true)
  end

  if inlineLabel and inlineLabel.SetTextColor then
    if isEnabled == false then
      inlineLabel:SetTextColor(0.5, 0.52, 0.58)
    else
      inlineLabel:SetTextColor(0.86, 0.88, 0.93)
    end
  end
end

local function CreateSettingsBox(parentFrame, startY, pageKey)
  local boxFrame = CreateFrame("Frame", nil, parentFrame) -- 统一设置构建容器
  boxFrame:SetSize(MODULE_BOX_WIDTH, SETTINGS_BOX_MIN_HEIGHT)
  boxFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, startY)
  boxFrame.realHeight = SETTINGS_BOX_MIN_HEIGHT
  boxFrame._toolboxCursorY = 0
  boxFrame._toolboxRefreshers = {}
  boxFrame._toolboxPageKey = pageKey

  function boxFrame:_UpdateRealHeight()
    self.realHeight = math.max(SETTINGS_BOX_MIN_HEIGHT, math.abs(self._toolboxCursorY) + SETTINGS_BOX_BOTTOM_PADDING)
    self:SetHeight(self.realHeight)
  end

  function boxFrame:_ConsumeHeight(heightValue, gapValue)
    local usedHeight = tonumber(heightValue) or 0 -- 当前占用高度
    local usedGap = tonumber(gapValue) or 0 -- 行尾间距
    self._toolboxCursorY = self._toolboxCursorY - usedHeight - usedGap
    self:_UpdateRealHeight()
  end

  function boxFrame:_RegisterRefresher(refreshFunc)
    if type(refreshFunc) == "function" then
      self._toolboxRefreshers[#self._toolboxRefreshers + 1] = refreshFunc
    end
  end

  function boxFrame:_IsRowEnabled(options)
    if type(options) ~= "table" then
      return true
    end
    if type(options.enabledWhen) == "function" then
      return options.enabledWhen() ~= false
    end
    if type(options.isEnabled) == "function" then
      return options.isEnabled() ~= false
    end
    return true
  end

  function boxFrame:RequestLocalRefresh()
    for _, refreshFunc in ipairs(self._toolboxRefreshers or {}) do
      refreshFunc()
    end
  end

  function boxFrame:RequestPageRebuild()
    Toolbox.SettingsHost:BuildPage(self._toolboxPageKey)
  end

  function boxFrame:AddSectionHeader(titleOrOptions, descriptionText)
    local options = type(titleOrOptions) == "table" and titleOrOptions or { title = titleOrOptions, description = descriptionText } -- 分节配置
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local usedHeight = 22 -- 当前分节高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 分节标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH + 180)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(options.title or "")

    if options.description and options.description ~= "" then
      local descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 分节说明
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 22)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH + 180)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(options.description)
      usedHeight = 22 + math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8))
    end

    self:_ConsumeHeight(usedHeight, 6)
  end

  function boxFrame:AddNoteRow(options)
    local rowOptions = type(options) == "table" and options or { text = tostring(options or "") } -- 说明配置
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local noteLabel = self:CreateFontString(nil, "OVERLAY", rowOptions.fontObject or "GameFontHighlightSmall") -- 说明文本
    noteLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    noteLabel:SetWidth(rowOptions.width or (SETTINGS_ROW_TEXT_WIDTH + 180))
    noteLabel:SetJustifyH("LEFT")
    noteLabel:SetText(rowOptions.text or "")
    self:_ConsumeHeight(math.max(18, math.ceil((noteLabel:GetStringHeight() or 0) + 8)), rowOptions.gap or 8)
    return noteLabel
  end

  function boxFrame:AddToggleRow(options)
    local rowOptions = options or {} -- 开关行配置
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local rowHeight = 24 -- 当前行高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 行标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_LABEL_WIDTH)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(rowOptions.label or "")

    local descriptionLabel = nil -- 说明文本
    if rowOptions.description and rowOptions.description ~= "" then
      descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 18)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(rowOptions.description)
      rowHeight = 18 + math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8))
    end

    local stateButton = createCheckboxControl(self) -- 开关勾选控件
    stateButton:SetSize(30, 29)
    stateButton:SetPoint("TOPLEFT", self, "TOPLEFT", SETTINGS_ROW_CONTROL_LEFT, rowTop - 5)

    local function getValue()
      if type(rowOptions.getValue) == "function" then
        return rowOptions.getValue()
      end
      return rowOptions.value
    end

    local function setValue(newValue)
      if type(rowOptions.setValue) == "function" then
        rowOptions.setValue(newValue == true)
      end
      if type(rowOptions.afterChange) == "function" then
        rowOptions.afterChange(newValue == true)
      end
    end

    local function refresh()
      local rawValue = getValue() -- 当前原始取值
      local isChecked, wasNormalized = normalizeToggleValue(rawValue, rowOptions.defaultValue) -- 当前开关值
      if wasNormalized and type(rowOptions.setValue) == "function" then
        rowOptions.setValue(isChecked == true)
      end
      local isEnabled = self:_IsRowEnabled(rowOptions) -- 当前行启用态
      stateButton:SetEnabled(isEnabled)
      stateButton:SetChecked(isChecked == true)
      applyCheckboxState(stateButton, isEnabled, isChecked == true)
      setFontStringTextColor(titleLabel, isEnabled)
      setFontStringTextColor(descriptionLabel, isEnabled)
    end

    stateButton:SetScript("OnClick", function()
      local currentValue = select(1, normalizeToggleValue(getValue(), rowOptions.defaultValue)) -- 当前归一后的布尔值
      setValue(not currentValue)
      triggerBoxRefresh(self, rowOptions)
    end)

    self:_RegisterRefresher(refresh)
    refresh()
    self:_ConsumeHeight(rowHeight, rowOptions.gap or 10)
    return stateButton
  end

  function boxFrame:AddChoiceRow(options)
    local rowOptions = options or {} -- 单值选择配置
    local choiceList = getChoiceOptions(rowOptions.options) -- 选项列表
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local rowHeight = 28 -- 当前行高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 行标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_LABEL_WIDTH)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(rowOptions.label or "")

    local descriptionLabel = nil -- 说明文本
    if rowOptions.description and rowOptions.description ~= "" then
      descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 18)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(rowOptions.description)
      rowHeight = math.max(28, 18 + math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8)))
    end

    local dropdownControl = ensureDropdownWithButtonsControl(self, rowOptions.buttonWidth or 160) -- 原生箭头+下拉控件
    dropdownControl:SetPoint("TOPLEFT", self, "TOPLEFT", SETTINGS_ROW_CONTROL_LEFT - 28, rowTop - 6)

    local function refresh()
      local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
      local currentOption, currentIndex = getChoiceOption(choiceList, currentValue) -- 当前选项与索引
      local isEnabled = self:_IsRowEnabled(rowOptions) -- 当前行启用态
      local currentLabel = currentOption and (currentOption.label or tostring(currentOption.value)) or "" -- 当前显示文本
      dropdownControl._toolboxCurrentLabel = currentLabel
      if dropdownControl.Dropdown and dropdownControl.Dropdown.SetEnabled then
        dropdownControl.Dropdown:SetEnabled(isEnabled)
      end
      setDropdownDisplayText(dropdownControl.Dropdown, currentLabel)

      local canDecrement = isEnabled and currentIndex and currentIndex > 1 or false -- 左箭头是否可用
      local canIncrement = isEnabled and currentIndex and currentIndex < #choiceList or false -- 右箭头是否可用
      dropdownControl:SetSteppersShown(#choiceList > 1)
      dropdownControl:SetSteppersEnabled(canDecrement == true, canIncrement == true)

      if dropdownControl.IncrementButton and dropdownControl.IncrementButton.SetEnabled then
        dropdownControl.IncrementButton:SetEnabled(canIncrement == true)
      end
      if dropdownControl.DecrementButton and dropdownControl.DecrementButton.SetEnabled then
        dropdownControl.DecrementButton:SetEnabled(canDecrement == true)
      end
      setFontStringTextColor(titleLabel, isEnabled)
      setFontStringTextColor(descriptionLabel, isEnabled)
    end

    local function commitValueByIndex(indexNumber)
      local optionObject = choiceList[indexNumber] -- 目标选项
      if not optionObject then
        return
      end
      if type(rowOptions.setValue) == "function" then
        rowOptions.setValue(optionObject.value)
      end
      if type(rowOptions.afterChange) == "function" then
        rowOptions.afterChange(optionObject.value)
      end
      triggerBoxRefresh(self, rowOptions)
    end

    if dropdownControl.IncrementButton then
      dropdownControl.IncrementButton:SetScript("OnClick", function()
        local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
        local currentIndex = findChoiceIndex(choiceList, currentValue) or 1 -- 当前索引
        if currentIndex < #choiceList then
          commitValueByIndex(currentIndex + 1)
        end
      end)
    end
    if dropdownControl.DecrementButton then
      dropdownControl.DecrementButton:SetScript("OnClick", function()
        local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
        local currentIndex = findChoiceIndex(choiceList, currentValue) or 1 -- 当前索引
        if currentIndex > 1 then
          commitValueByIndex(currentIndex - 1)
        end
      end)
    end

    if dropdownControl.Dropdown and type(dropdownControl.Dropdown.SetupMenu) == "function" then
      dropdownControl.Dropdown:SetupMenu(function(_, rootDescription)
        for _, optionObject in ipairs(choiceList) do
          local optionValue = optionObject.value -- 菜单项值
          local optionLabel = optionObject.label or tostring(optionValue) -- 菜单项文本
          rootDescription:CreateRadio(
            optionLabel,
            function()
              return getChoiceCurrentValue(rowOptions, choiceList) == optionValue
            end,
            function()
              if type(rowOptions.setValue) == "function" then
                rowOptions.setValue(optionValue)
              end
              if type(rowOptions.afterChange) == "function" then
                rowOptions.afterChange(optionValue)
              end
              triggerBoxRefresh(self, rowOptions)
            end,
            optionValue
          )
        end
      end)
    end

    self:_RegisterRefresher(refresh)
    refresh()
    self:_ConsumeHeight(rowHeight, rowOptions.gap or 10)
    return dropdownControl
  end

  function boxFrame:AddMenuRow(options)
    local rowOptions = options or {} -- 菜单行配置
    local choiceList = getChoiceOptions(rowOptions.options) -- 菜单选项
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local rowHeight = 28 -- 当前行高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 行标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_LABEL_WIDTH)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(rowOptions.label or "")

    local descriptionLabel = nil -- 说明文本
    if rowOptions.description and rowOptions.description ~= "" then
      descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 18)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(rowOptions.description)
      rowHeight = math.max(28, 18 + math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8)))
    end

    local menuButton = ensureDropdownWithButtonsControl(self, rowOptions.buttonWidth or 170) -- 原生箭头+下拉控件
    menuButton:SetPoint("TOPLEFT", self, "TOPLEFT", SETTINGS_ROW_CONTROL_LEFT - 28, rowTop - 6)

    local function refresh()
      local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
      local currentOption, currentIndex = getChoiceOption(choiceList, currentValue) -- 当前选项与索引
      local isEnabled = self:_IsRowEnabled(rowOptions) -- 当前行启用态
      local currentLabel = currentOption and (currentOption.label or tostring(currentOption.value)) or "" -- 当前按钮文案
      menuButton._toolboxCurrentLabel = currentLabel
      if menuButton.Dropdown and menuButton.Dropdown.SetEnabled then
        menuButton.Dropdown:SetEnabled(isEnabled)
      end
      setDropdownDisplayText(menuButton.Dropdown, currentLabel)

      local canDecrement = isEnabled and currentIndex and currentIndex > 1 or false -- 左箭头是否可用
      local canIncrement = isEnabled and currentIndex and currentIndex < #choiceList or false -- 右箭头是否可用
      menuButton:SetSteppersShown(#choiceList > 1)
      menuButton:SetSteppersEnabled(canDecrement == true, canIncrement == true)
      setFontStringTextColor(titleLabel, isEnabled)
      setFontStringTextColor(descriptionLabel, isEnabled)
    end

    local function commitValueByIndex(indexNumber)
      local optionObject = choiceList[indexNumber] -- 目标选项
      if not optionObject then
        return
      end
      if type(rowOptions.setValue) == "function" then
        rowOptions.setValue(optionObject.value)
      end
      if type(rowOptions.afterChange) == "function" then
        rowOptions.afterChange(optionObject.value)
      end
      triggerBoxRefresh(self, rowOptions)
    end

    if menuButton.IncrementButton then
      menuButton.IncrementButton:SetScript("OnClick", function()
        local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
        local currentIndex = findChoiceIndex(choiceList, currentValue) or 1 -- 当前索引
        if currentIndex < #choiceList then
          commitValueByIndex(currentIndex + 1)
        end
      end)
    end
    if menuButton.DecrementButton then
      menuButton.DecrementButton:SetScript("OnClick", function()
        local currentValue = getChoiceCurrentValue(rowOptions, choiceList) -- 当前归一后的取值
        local currentIndex = findChoiceIndex(choiceList, currentValue) or 1 -- 当前索引
        if currentIndex > 1 then
          commitValueByIndex(currentIndex - 1)
        end
      end)
    end

    if menuButton.Dropdown and type(menuButton.Dropdown.SetupMenu) == "function" then
      menuButton.Dropdown:SetupMenu(function(_, rootDescription)
        for _, optionObject in ipairs(choiceList) do
          local optionValue = optionObject.value -- 菜单项值
          local optionLabel = optionObject.label or tostring(optionValue) -- 菜单项文本
          rootDescription:CreateRadio(
            optionLabel,
            function()
              return getChoiceCurrentValue(rowOptions, choiceList) == optionValue
            end,
            function()
              if type(rowOptions.setValue) == "function" then
                rowOptions.setValue(optionValue)
              end
              if type(rowOptions.afterChange) == "function" then
                rowOptions.afterChange(optionValue)
              end
              triggerBoxRefresh(self, rowOptions)
            end,
            optionValue
          )
        end
      end)
    end

    self:_RegisterRefresher(refresh)
    refresh()
    self:_ConsumeHeight(rowHeight, rowOptions.gap or 10)
    return menuButton
  end

  function boxFrame:AddMultiSelectRow(options)
    local rowOptions = options or {} -- 多选列表配置
    local choiceList = getChoiceOptions(rowOptions.options) -- 多选项列表
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local rowHeight = 0 -- 当前累计高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 列表标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH + 180)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(rowOptions.label or "")
    rowHeight = rowHeight + 20

    local descriptionLabel = nil -- 说明文本
    if rowOptions.description and rowOptions.description ~= "" then
      descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 18)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH + 180)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(rowOptions.description)
      local descHeight = math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8))
      rowHeight = 18 + descHeight
    end

    local buttonList = {} -- 勾选按钮列表
    local optionTop = rowTop - rowHeight -- 第一项顶部
    for _, optionObject in ipairs(choiceList) do
      local checkButton = createCheckboxControl(self) -- 多选按钮
      checkButton:SetSize(30, 29)
      checkButton:SetPoint("TOPLEFT", self, "TOPLEFT", SETTINGS_ROW_CONTROL_LEFT, optionTop - 6)
      checkButton._toolboxValue = optionObject.value
      local optionLabel = checkButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 多选项文本
      optionLabel:SetPoint("LEFT", checkButton, "RIGHT", 8, 0)
      optionLabel:SetPoint("RIGHT", self, "RIGHT", -8, 0)
      optionLabel:SetJustifyH("LEFT")
      optionLabel:SetText(optionObject.label or tostring(optionObject.value))
      checkButton._toolboxInlineLabel = optionLabel
      checkButton:SetScript("OnClick", function()
        local currentlySelected = type(rowOptions.isSelected) == "function" and rowOptions.isSelected(optionObject.value) == true or false
        if type(rowOptions.setSelected) == "function" then
          rowOptions.setSelected(optionObject.value, currentlySelected ~= true)
        end
        if type(rowOptions.afterChange) == "function" then
          rowOptions.afterChange(optionObject.value, currentlySelected ~= true)
        end
        triggerBoxRefresh(self, rowOptions)
      end)
      buttonList[#buttonList + 1] = checkButton
      optionTop = optionTop - 28
      rowHeight = rowHeight + 28
    end

    local function refresh()
      local isEnabled = self:_IsRowEnabled(rowOptions) -- 当前行启用态
      for _, checkButton in ipairs(buttonList) do
        local isSelected = type(rowOptions.isSelected) == "function" and rowOptions.isSelected(checkButton._toolboxValue) == true or false
        checkButton:SetEnabled(isEnabled)
        checkButton:SetChecked(isSelected == true)
        applyCheckboxState(checkButton, isEnabled, isSelected == true)
      end
      setFontStringTextColor(titleLabel, isEnabled)
      setFontStringTextColor(descriptionLabel, isEnabled)
    end

    self:_RegisterRefresher(refresh)
    refresh()
    self:_ConsumeHeight(rowHeight, rowOptions.gap or 8)
    return buttonList
  end

  function boxFrame:AddActionRow(options)
    local rowOptions = options or {} -- 操作行配置
    local rowTop = self._toolboxCursorY -- 行顶部位置
    local rowHeight = 24 -- 当前行高度

    local titleLabel = self:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- 行标题
    titleLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    titleLabel:SetWidth(SETTINGS_ROW_LABEL_WIDTH)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(rowOptions.label or "")

    local descriptionLabel = nil -- 说明文本
    if rowOptions.description and rowOptions.description ~= "" then
      descriptionLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      descriptionLabel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop - 18)
      descriptionLabel:SetWidth(SETTINGS_ROW_TEXT_WIDTH)
      descriptionLabel:SetJustifyH("LEFT")
      descriptionLabel:SetText(rowOptions.description)
      rowHeight = 18 + math.max(18, math.ceil((descriptionLabel:GetStringHeight() or 0) + 8))
    end

    local actionButton = CreateFrame("Button", nil, self, "UIPanelButtonTemplate") -- 操作按钮
    actionButton:SetSize(rowOptions.buttonWidth or 170, 22)
    actionButton:SetPoint("TOPLEFT", self, "TOPLEFT", SETTINGS_ROW_CONTROL_LEFT, rowTop - 2)
    actionButton:SetText(rowOptions.buttonText or rowOptions.label or "")
    actionButton:SetScript("OnClick", function()
      if type(rowOptions.onClick) == "function" then
        rowOptions.onClick()
      end
      triggerBoxRefresh(self, rowOptions)
    end)

    local function refresh()
      local isEnabled = self:_IsRowEnabled(rowOptions) -- 当前行启用态
      actionButton:SetEnabled(isEnabled)
      setFontStringTextColor(titleLabel, isEnabled)
      setFontStringTextColor(descriptionLabel, isEnabled)
    end

    self:_RegisterRefresher(refresh)
    refresh()
    self:_ConsumeHeight(rowHeight, rowOptions.gap or 10)
    return actionButton
  end

  function boxFrame:AddCustomBlock(builderFunc)
    local rowTop = self._toolboxCursorY -- 当前块顶部
    local blockFrame = CreateFrame("Frame", nil, self) -- 自定义内容块
    blockFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, rowTop)
    blockFrame:SetSize(MODULE_BOX_WIDTH, 1)
    local reportedHeight = 0 -- 上报高度
    if type(builderFunc) == "function" then
      reportedHeight = tonumber(builderFunc(blockFrame, self)) or 0
    end
    if reportedHeight <= 0 then
      reportedHeight = tonumber(blockFrame.realHeight) or tonumber(blockFrame:GetHeight()) or 0
    end
    if reportedHeight <= 0 then
      reportedHeight = 1
    end
    blockFrame:SetHeight(reportedHeight)
    self:_ConsumeHeight(reportedHeight, 8)
    return blockFrame
  end

  boxFrame:_UpdateRealHeight()
  return boxFrame
end

local function buildHeader(childFrame, startY, titleText, introText)
  local yOffset = startY -- 当前纵向游标

  local titleLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 页面标题
  titleLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  titleLabel:SetText(titleText or "")
  yOffset = yOffset - 24

  if introText and introText ~= "" then
    local introLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 页面说明
    introLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
    introLabel:SetWidth(580)
    introLabel:SetJustifyH("LEFT")
    introLabel:SetText(introText)
    yOffset = yOffset - math.max(36, math.ceil((introLabel:GetStringHeight() or 0) + 12))
  end

  return yOffset
end

local function buildSectionHeader(childFrame, startY, titleText, introText)
  local yOffset = startY -- 当前纵向游标

  local titleLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 分节标题
  titleLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  titleLabel:SetText(titleText or "")
  yOffset = yOffset - 22

  if introText and introText ~= "" then
    local introLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 分节说明
    introLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
    introLabel:SetWidth(580)
    introLabel:SetJustifyH("LEFT")
    introLabel:SetText(introText)
    yOffset = yOffset - math.max(30, math.ceil((introLabel:GetStringHeight() or 0) + 10))
  end

  return yOffset
end

local function setChildHeight(childFrame, yOffset)
  childFrame:SetHeight(math.max(800, math.abs(yOffset) + 40))
end

function Toolbox.SettingsHost:GetPageByKey(pageKey)
  self.pagesByKey = self.pagesByKey or {}
  return self.pagesByKey[pageKey]
end

function Toolbox.SettingsHost:GetModulePageKey(moduleId)
  return MODULE_LEAF_KEY_MAP[tostring(moduleId or "")] or DEFAULT_LEAF_PAGE_KEY
end

--- 兼容旧调用面：额外子页已并回叶子页时，统一回到所属叶子页。
function Toolbox.SettingsHost:GetModuleSubPageKey(moduleId)
  return self:GetModulePageKey(moduleId)
end

--- 记录最近一次停留的叶子页，供 `/toolbox` 与各入口回到相同位置。
---@param pageKey string 叶子页键名
function Toolbox.SettingsHost:RememberLeafPageKey(pageKey)
  self:EnsureCreated()
  local pageObject = self:GetPageByKey(pageKey) -- 目标页面
  if not pageObject or pageObject.isLeaf ~= true then
    return
  end
  local globalDb = Toolbox.Config.GetGlobal() -- 全局存档
  globalDb.settingsLastLeafPage = pageKey
end

--- 返回默认应打开的叶子页：优先上次停留，否则回退到“通用”。
---@return string
function Toolbox.SettingsHost:GetPreferredLeafPageKey()
  self:EnsureCreated()
  local globalDb = Toolbox.Config.GetGlobal() -- 全局存档
  local savedPageKey = tostring(globalDb.settingsLastLeafPage or "") -- 记录中的叶子页键名
  local savedPage = self:GetPageByKey(savedPageKey) -- 记录中的页面
  if savedPage and savedPage.isLeaf == true then
    return savedPageKey
  end
  return DEFAULT_LEAF_PAGE_KEY
end

--- 重建单个设置页内容；用于语言切换、模块公共开关变化后刷新 UI。
---@param pageKey string 页面键
function Toolbox.SettingsHost:BuildPage(pageKey)
  self:EnsureCreated()
  local pageObject = self:GetPageByKey(pageKey) -- 目标页面
  if not pageObject or not pageObject.builder then
    return
  end
  pageObject.builder(pageObject)
end

--- 重建所有已注册的设置页内容。
function Toolbox.SettingsHost:RefreshAllPages()
  self:EnsureCreated()
  if self.category and self.category.SetName and Toolbox.L then
    self.category:SetName(Toolbox.L.SETTINGS_CATEGORY_TITLE or "Toolbox")
  end
  for _, pageObject in ipairs(self.pages or {}) do
    if pageObject.category and pageObject.category.SetName then
      pageObject.category:SetName(getPageTitle(pageObject))
    end
    if pageObject.builder then
      pageObject.builder(pageObject)
    end
  end
end

--- 兼容旧调用面：构建（现语义为重建）所有页面。
function Toolbox.SettingsHost:Build()
  self:RefreshAllPages()
end

--- 构建界面语言区。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@param pageKey string 当前叶子页键名
---@return number
function Toolbox.SettingsHost:BuildLanguageSection(childFrame, startY, pageKey)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local globalDb = Toolbox.Config.GetGlobal() -- 全局存档
  local settingsBox = CreateSettingsBox(childFrame, startY, pageKey) -- 语言设置容器
  settingsBox:AddMenuRow({
    label = localeTable.LOCALE_SECTION_TITLE,
    description = localeTable.LOCALE_HINT,
    defaultValue = "auto",
    refreshMode = "none",
    buttonWidth = 140,
    getValue = function()
      return globalDb.locale or "auto"
    end,
    setValue = function(localeKey)
      globalDb.locale = localeKey
    end,
    afterChange = function()
      Toolbox.Locale_Apply()
      Toolbox.SettingsHost:RefreshAllPages()
    end,
    options = {
      { value = "auto", label = localeTable.LOCALE_OPTION_AUTO or "Auto" },
      { value = "zhCN", label = localeTable.LOCALE_OPTION_ZHCN or "zhCN" },
      { value = "enUS", label = localeTable.LOCALE_OPTION_ENUS or "enUS" },
    },
  })
  return startY - settingsBox.realHeight - 10
end

--- 构建重载界面区。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@param pageKey string 当前叶子页键名
---@return number
function Toolbox.SettingsHost:BuildReloadSection(childFrame, startY, pageKey)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local settingsBox = CreateSettingsBox(childFrame, startY, pageKey) -- 重载设置容器
  settingsBox:AddActionRow({
    label = localeTable.SETTINGS_RELOAD_UI,
    description = localeTable.SETTINGS_RELOAD_HINT,
    buttonText = localeTable.SETTINGS_RELOAD_UI,
    refreshMode = "none",
    onClick = function()
      ReloadUI()
    end,
  })
  return startY - settingsBox.realHeight - 10
end

--- 构建模块页首的高频主开关。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@param moduleObject table 模块定义
---@param pageKey string 所属叶子页键名
---@return number
function Toolbox.SettingsHost:BuildModulePrimaryControls(childFrame, startY, moduleObject, pageKey)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local moduleDb = Toolbox.Config.GetModule(moduleObject.id) -- 模块存档
  local settingsBox = CreateSettingsBox(childFrame, startY, pageKey) -- 模块主控件容器
  settingsBox:AddToggleRow({
    label = localeTable.SETTINGS_MODULE_ENABLE or "",
    defaultValue = true,
    refreshMode = "page",
    getValue = function()
      return moduleDb.enabled ~= false
    end,
    setValue = function(value)
      moduleDb.enabled = value == true
    end,
    afterChange = function(enabled)
      if moduleObject.OnEnabledSettingChanged then
        moduleObject.OnEnabledSettingChanged(enabled == true)
      end
    end,
  })
  return startY - settingsBox.realHeight
end

--- 构建模块页尾的低频动作区（调试 / 重置并重建）。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@param moduleObject table 模块定义
---@param pageKey string 所属叶子页键名
---@return number
function Toolbox.SettingsHost:BuildModuleSecondaryControls(childFrame, startY, moduleObject, pageKey)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local moduleDb = Toolbox.Config.GetModule(moduleObject.id) -- 模块存档
  local settingsBox = CreateSettingsBox(childFrame, startY, pageKey) -- 模块次级控件容器
  settingsBox:AddToggleRow({
    label = localeTable.SETTINGS_MODULE_DEBUG or "",
    refreshMode = "page",
    getValue = function()
      return moduleDb.debug == true
    end,
    setValue = function(value)
      moduleDb.debug = value == true
    end,
    afterChange = function(enabled)
      if moduleObject.OnDebugSettingChanged then
        moduleObject.OnDebugSettingChanged(enabled == true)
      end
    end,
  })
  settingsBox:AddActionRow({
    label = localeTable.SETTINGS_MODULE_RESET_REBUILD or "",
    description = localeTable.SETTINGS_MODULE_RESET_HINT or "",
    buttonText = localeTable.SETTINGS_MODULE_RESET_REBUILD or "",
    refreshMode = "page",
    onClick = function()
      if moduleObject.ResetToDefaultsAndRebuild then
        moduleObject.ResetToDefaultsAndRebuild()
      else
        Toolbox.Config.ResetModule(moduleObject.id)
        applyModuleCallbacks(moduleObject)
      end
      if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage and localeTable.SETTINGS_MODULE_RESET_DONE_FMT then
        Toolbox.Chat.PrintAddonMessage(string.format(localeTable.SETTINGS_MODULE_RESET_DONE_FMT, getModuleTitle(moduleObject)))
      end
    end,
  })
  return startY - settingsBox.realHeight
end

--- 构建叶子页中的单个模块分节。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@param moduleObject table 模块定义
---@param pageKey string 所属叶子页键名
---@param showSectionHeader boolean 是否显示模块标题与简介
---@return number
function Toolbox.SettingsHost:BuildModuleSection(childFrame, startY, moduleObject, pageKey, showSectionHeader)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local yOffset = startY -- 当前纵向游标

  if showSectionHeader == true then
    yOffset = buildSectionHeader(childFrame, yOffset, getModuleTitle(moduleObject), getModuleIntro(moduleObject))
  end

  yOffset = self:BuildModulePrimaryControls(childFrame, yOffset, moduleObject, pageKey)

  local settingsTitle = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 模块设置标题
  settingsTitle:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  settingsTitle:SetText(localeTable.SETTINGS_MODULE_SECTION_TITLE or "")
  yOffset = yOffset - 24

  local boxFrame = CreateSettingsBox(childFrame, yOffset, pageKey) -- 模块专属设置容器
  moduleObject.RegisterSettings(boxFrame)
  boxFrame.realHeight = math.max(tonumber(boxFrame.realHeight) or 0, SETTINGS_BOX_MIN_HEIGHT)
  boxFrame:SetHeight(boxFrame.realHeight)
  yOffset = yOffset - boxFrame.realHeight - 16

  yOffset = self:BuildModuleSecondaryControls(childFrame, yOffset, moduleObject, pageKey)
  return yOffset - 12
end

--- 构建通用 / 界面 / 地图 / 任务 / 冒险手册叶子页。
---@param pageObject table 页面定义
function Toolbox.SettingsHost:BuildLeafPage(pageObject)
  local childFrame = resetCanvasPanel(pageObject.panel) -- 页面内容根节点
  local moduleIdList = pageObject.moduleIds or {} -- 叶子页包含的模块 id 列表
  local yOffset = -8 -- 当前纵向游标

  yOffset = buildHeader(childFrame, yOffset, getPageTitle(pageObject), getPageIntro(pageObject))

  if pageObject.includeLanguageSection == true then
    yOffset = self:BuildLanguageSection(childFrame, yOffset, pageObject.key)
  end
  if pageObject.includeReloadSection == true then
    yOffset = self:BuildReloadSection(childFrame, yOffset, pageObject.key)
  end

  for indexNumber, moduleId in ipairs(moduleIdList) do
    local moduleObject = self.modulesById and self.modulesById[moduleId] or nil -- 当前叶子页对应模块
    if moduleObject then
      local showSectionHeader = #moduleIdList > 1 -- 多模块页显示分节标题
      yOffset = self:BuildModuleSection(childFrame, yOffset, moduleObject, pageObject.key, showSectionHeader)
      if indexNumber < #moduleIdList then
        yOffset = yOffset - 8
      end
    end
  end

  setChildHeight(childFrame, yOffset)
end

--- 构建关于页。
---@param pageObject table 页面定义
function Toolbox.SettingsHost:BuildAboutPage(pageObject)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local childFrame = resetCanvasPanel(pageObject.panel) -- 页面内容根节点
  local yOffset = -8 -- 当前纵向游标

  yOffset = buildHeader(childFrame, yOffset, getPageTitle(pageObject), getPageIntro(pageObject))

  local versionLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- 版本文本
  versionLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  versionLabel:SetJustifyH("LEFT")
  versionLabel:SetText(string.format(
    localeTable.SETTINGS_ABOUT_VERSION_FMT or "%s",
    tostring(Toolbox.Chat.GetAddOnMetadata(Toolbox.ADDON_NAME, "Version") or "")
  ))
  yOffset = yOffset - 24

  local clientLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- 客户端文本
  clientLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  clientLabel:SetJustifyH("LEFT")
  clientLabel:SetText(localeTable.SETTINGS_ABOUT_CLIENT or "")
  yOffset = yOffset - 32

  local introText = localeTable.SETTINGS_ABOUT_INTRO or "" -- 对外插件说明
  if introText ~= "" then
    local introLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 插件说明文本
    introLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
    introLabel:SetWidth(560)
    introLabel:SetJustifyH("LEFT")
    introLabel:SetWordWrap(true)
    introLabel:SetText(introText)
    yOffset = yOffset - math.max(24, math.ceil((introLabel:GetStringHeight() or 0) + 10))
  end

  setChildHeight(childFrame, yOffset)
end

--- 确保 Settings 根类目与各叶子页已注册。
function Toolbox.SettingsHost:EnsureCreated()
  Toolbox_NamespaceEnsure()
  if self.category then
    return
  end

  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutSubcategory) then
    error("Toolbox: " .. (Toolbox.L and Toolbox.L.ERR_SETTINGS_API or "Retail Settings API required"))
  end

  self.pages = {}
  self.pagesByKey = {}
  self.modulesById = {}

  local moduleList = collectSettingsModules() -- 带设置页的模块列表
  for _, moduleObject in ipairs(moduleList) do
    self.modulesById[moduleObject.id] = moduleObject
  end

  local rootPanel = createCanvasPanel("ToolboxSettingsRootPanel") -- Toolbox 根类目占位面板
  local category = Settings.RegisterCanvasLayoutCategory(rootPanel, (Toolbox.L and Toolbox.L.SETTINGS_CATEGORY_TITLE) or "Toolbox")
  Settings.RegisterAddOnCategory(category)
  self.category = category

  local pageList = {
    {
      key = "general",
      panel = createCanvasPanel("ToolboxSettingsGeneralPanel"),
      titleKey = "SETTINGS_PAGE_GENERAL_TITLE",
      introKey = "SETTINGS_PAGE_GENERAL_INTRO",
      includeLanguageSection = true,
      includeReloadSection = true,
      moduleIds = { "minimap_button", "chat_notify" },
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildLeafPage(pageDef)
      end,
    },
    {
      key = "interface",
      panel = createCanvasPanel("ToolboxSettingsInterfacePanel"),
      titleKey = "SETTINGS_PAGE_INTERFACE_TITLE",
      introKey = "SETTINGS_PAGE_INTERFACE_INTRO",
      moduleIds = { "mover", "tooltip_anchor" },
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildLeafPage(pageDef)
      end,
    },
    {
      key = "map",
      panel = createCanvasPanel("ToolboxSettingsMapPanel"),
      titleKey = "SETTINGS_PAGE_MAP_TITLE",
      introKey = "SETTINGS_PAGE_MAP_INTRO",
      moduleIds = { "navigation" },
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildLeafPage(pageDef)
      end,
    },
    {
      key = "quest",
      panel = createCanvasPanel("ToolboxSettingsQuestPanel"),
      titleKey = "SETTINGS_PAGE_QUEST_TITLE",
      introKey = "SETTINGS_PAGE_QUEST_INTRO",
      moduleIds = { "quest" },
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildLeafPage(pageDef)
      end,
    },
    {
      key = "encounter_journal",
      panel = createCanvasPanel("ToolboxSettingsEncounterJournalPanel"),
      titleKey = "SETTINGS_PAGE_ENCOUNTER_JOURNAL_TITLE",
      introKey = "SETTINGS_PAGE_ENCOUNTER_JOURNAL_INTRO",
      moduleIds = { "encounter_journal" },
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildLeafPage(pageDef)
      end,
    },
    {
      key = "about",
      panel = createCanvasPanel("ToolboxSettingsAboutPanel"),
      titleKey = "SETTINGS_PAGE_ABOUT_TITLE",
      introKey = "SETTINGS_PAGE_ABOUT_INTRO",
      isLeaf = true,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildAboutPage(pageDef)
      end,
    },
  }

  for _, pageObject in ipairs(pageList) do
    self.pages[#self.pages + 1] = pageObject
    self.pagesByKey[pageObject.key] = pageObject

    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, pageObject.panel, getPageTitle(pageObject))
    Settings.RegisterAddOnCategory(subcategory)
    pageObject.category = subcategory
  end
end

--- 战斗内独立展示：全屏遮罩 + 底板（与 Canvas 分层，避免全透明与比例失调）。
local standalonePresentation

---@return table host, dimmer, box
local function ensureStandalonePresentationHost()
  if standalonePresentation then
    return standalonePresentation
  end
  local host = CreateFrame("Frame", "ToolboxSettingsStandaloneHost", UIParent) -- 独立展示宿主
  host:SetFrameStrata("DIALOG")
  host:SetFrameLevel(100)
  host:SetAllPoints(UIParent)
  host:Hide()

  local dimmer = CreateFrame("Button", nil, host) -- 全屏遮罩按钮
  dimmer:SetAllPoints(host)
  dimmer:SetFrameLevel(0)
  local dimTexture = dimmer:CreateTexture(nil, "BACKGROUND") -- 遮罩纹理
  dimTexture:SetAllPoints()
  dimTexture:SetColorTexture(0, 0, 0, 0.5)
  dimmer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  dimmer:SetScript("OnClick", function()
    Toolbox.SettingsHost:HideStandalonePresentation()
  end)

  local boxFrame -- 独立展示底板
  do
    local okFlag, backdropFrame = pcall(function()
      return CreateFrame("Frame", nil, host, "BackdropTemplate")
    end)
    boxFrame = (okFlag and backdropFrame) and backdropFrame or CreateFrame("Frame", nil, host)
  end
  boxFrame:SetFrameLevel(5)
  local padding = 40 -- 底板边距
  boxFrame:SetSize(PANEL_WIDTH + padding, PANEL_HEIGHT + padding)
  boxFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  local backdropOk = pcall(function()
    boxFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    boxFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    boxFrame:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  end)
  if not backdropOk then
    local fallbackTexture = boxFrame:CreateTexture(nil, "ARTWORK") -- 兜底底色
    fallbackTexture:SetAllPoints()
    fallbackTexture:SetColorTexture(0.09, 0.09, 0.11, 0.98)
  end

  standalonePresentation = { host = host, dimmer = dimmer, box = boxFrame }
  return standalonePresentation
end

--- 打开系统设置前收起 ESC 菜单，避免仅关闭设置后仍留在游戏菜单栈顶。
local function dismissGameMenuIfShown()
  local gameMenuFrame = _G.GameMenuFrame -- ESC 菜单框
  if gameMenuFrame and gameMenuFrame.IsShown and gameMenuFrame:IsShown() and HideUIPanel then
    pcall(HideUIPanel, gameMenuFrame)
  end
end

--- 关闭按钮模板：不同版本名称略有差异，依次尝试。
local STANDALONE_CLOSE_TEMPLATES = {
  "UIPanelCloseButtonDefaultTemplate",
  "UIPanelCloseButton",
}

---@param panel Frame
---@return Button
local function createStandaloneCloseButton(panel)
  for _, templateName in ipairs(STANDALONE_CLOSE_TEMPLATES) do
    local okFlag, closeButton = pcall(function()
      return CreateFrame("Button", nil, panel, templateName)
    end)
    if okFlag and closeButton then
      return closeButton
    end
  end
  local fallbackButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate") -- 兜底关闭按钮
  fallbackButton:SetSize(24, 22)
  fallbackButton:SetText("X")
  return fallbackButton
end

--- 隐藏所有已注册的 Canvas 面板与战斗内嵌独立展示用的关闭键（不卸载内容）。
function Toolbox.SettingsHost:HideStandalonePresentation()
  self:EnsureCreated()
  if standalonePresentation and standalonePresentation.host then
    standalonePresentation.host:Hide()
  end
  for _, pageObject in ipairs(self.pages or {}) do
    local panel = pageObject.panel -- 当前页面面板
    if panel then
      if panel._toolboxStandaloneScaleApplied then
        panel:SetScale(panel._toolboxStandaloneSavedScale or 1)
        panel._toolboxStandaloneScaleApplied = nil
        panel._toolboxStandaloneSavedScale = nil
      end
      panel:Hide()
      panel:SetScript("OnKeyDown", nil)
      panel:EnableKeyboard(false)
      if panel._toolboxStandaloneClose then
        panel._toolboxStandaloneClose:Hide()
      end
    end
  end
end

--- 战斗等场景：不经过 `Settings.OpenToCategory`，将指定叶子页 Canvas 置于遮罩+底板之上。
---@param pageKey string 叶子页键名
function Toolbox.SettingsHost:ShowStandalonePageByKey(pageKey)
  self:EnsureCreated()
  local pageObject = self:GetPageByKey(pageKey) -- 目标页面
  if not pageObject or not pageObject.panel then
    return
  end
  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  local presentation = ensureStandalonePresentationHost() -- 独立展示宿主
  local panel = pageObject.panel -- 页面面板
  local boxFrame = presentation.box -- 对话框底板
  panel:ClearAllPoints()
  panel:SetPoint("CENTER", boxFrame, "CENTER", 0, 0)
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(200)
  panel._toolboxStandaloneSavedScale = panel:GetScale() or 1
  panel._toolboxStandaloneScaleApplied = true
  panel:SetScale(panel._toolboxStandaloneSavedScale * STANDALONE_PANEL_SCALE)
  panel:EnableMouse(true)
  panel:EnableKeyboard(true)
  pcall(function()
    panel:SetPropagateKeyboardInput(false)
  end)
  panel:SetScript("OnKeyDown", function(_, keyName)
    if keyName == "ESCAPE" then
      Toolbox.SettingsHost:HideStandalonePresentation()
    end
  end)
  if not panel._toolboxStandaloneClose then
    local closeButton = createStandaloneCloseButton(panel) -- 独立展示关闭按钮
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
      Toolbox.SettingsHost:HideStandalonePresentation()
    end)
    panel._toolboxStandaloneClose = closeButton
  else
    panel._toolboxStandaloneClose:Show()
  end
  presentation.host:Show()
  panel:Show()
end

--- 打开设置并定位到指定叶子页。
---@param pageKey string 叶子页键名
function Toolbox.SettingsHost:OpenToPageKey(pageKey)
  self:EnsureCreated()
  local fallbackPage = self:GetPageByKey(DEFAULT_LEAF_PAGE_KEY) -- 默认页
  local pageObject = self:GetPageByKey(pageKey) or fallbackPage -- 目标页
  if not pageObject then
    return
  end

  self:RememberLeafPageKey(pageObject.key)
  if InCombatLockdown() then
    self:ShowStandalonePageByKey(pageObject.key)
    return
  end

  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  if Settings and Settings.OpenToCategory and pageObject.category then
    pcall(function()
      Settings.OpenToCategory(pageObject.category:GetID())
    end)
  end
end

--- 打开默认叶子页：优先上次停留，否则回退到“通用”。
function Toolbox.SettingsHost:Open()
  self:OpenToPageKey(self:GetPreferredLeafPageKey())
end

--- 打开设置并定位到指定功能模块所属叶子页。
---@param moduleId string modules.* 的模块 id
function Toolbox.SettingsHost:OpenToModulePage(moduleId)
  self:OpenToPageKey(self:GetModulePageKey(moduleId))
end

--- 打开设置并定位到关于页。
function Toolbox.SettingsHost:OpenToAbout()
  self:OpenToPageKey("about")
end

local function tryGameMenuAttach()
  if Toolbox._gameMenuBtn then
    return true
  end
  Toolbox_NamespaceEnsure()
  Toolbox.SettingsHost:EnsureCreated()
  local gameMenuFrame = _G.GameMenuFrame -- ESC 菜单框
  if not gameMenuFrame then
    return false
  end
  local anchorButton = _G.GameMenuButtonOptions or _G.GameMenuButtonSettings -- 设置按钮锚点
  if not anchorButton then
    return false
  end
  local toolboxButton = CreateFrame("Button", "GameMenuButtonToolbox", gameMenuFrame, "GameMenuButtonTemplate") -- ESC 菜单 Toolbox 按钮
  toolboxButton:SetText(Toolbox.L.GAMEMENU_TOOLBOX)
  toolboxButton:SetPoint("TOP", anchorButton, "BOTTOM", 0, -1)
  toolboxButton:SetScript("OnClick", function()
    HideUIPanel(_G.GameMenuFrame)
    Toolbox.SettingsHost:Open()
  end)
  Toolbox._gameMenuBtn = toolboxButton
  return true
end

--- 注册 ESC 菜单中的 Toolbox 入口；当锚点按钮延迟创建时通过 OnShow/事件重试。
function Toolbox.GameMenu_Init()
  if tryGameMenuAttach() then
    return
  end
  if Toolbox._gameMenuHooked then
    return
  end
  Toolbox._gameMenuHooked = true

  local function attemptAttach()
    local gameMenuFrame = _G.GameMenuFrame -- ESC 菜单框
    if gameMenuFrame and not Toolbox._gameMenuShowHooked then
      Toolbox._gameMenuShowHooked = true
      gameMenuFrame:HookScript("OnShow", tryGameMenuAttach)
    end
    tryGameMenuAttach()
  end

  local watcherFrame = CreateFrame("Frame") -- 延迟重试监听器
  watcherFrame:RegisterEvent("ADDON_LOADED")
  watcherFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcherFrame:SetScript("OnEvent", function()
    attemptAttach()
  end)
  attemptAttach()
end
