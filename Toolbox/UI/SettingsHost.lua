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
---@return number
function Toolbox.SettingsHost:BuildLanguageSection(childFrame, startY)
  local localeTable = Toolbox.L -- 本地化文案
  local globalDb = Toolbox.Config.GetGlobal() -- 全局存档
  local yOffset = startY -- 当前纵向游标

  local titleLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 分节标题
  titleLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  titleLabel:SetText(localeTable.LOCALE_SECTION_TITLE)
  yOffset = yOffset - 24

  local modeButtonList = {} -- 语言模式按钮列表
  local function setLocale(localeKey)
    globalDb.locale = localeKey
    for _, checkButton in ipairs(modeButtonList) do
      checkButton:SetChecked(checkButton.localePref == localeKey)
    end
    Toolbox.Locale_Apply()
    Toolbox.SettingsHost:RefreshAllPages()
  end

  local function makeOption(localeKey, labelText)
    local checkButton = CreateFrame("CheckButton", nil, childFrame, "InterfaceOptionsCheckButtonTemplate") -- 语言选项按钮
    checkButton:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 20, yOffset)
    checkButton.Text:SetText(labelText)
    checkButton.localePref = localeKey
    checkButton:SetChecked((globalDb.locale or "auto") == localeKey)
    checkButton:SetScript("OnClick", function(self)
      setLocale(self.localePref)
    end)
    modeButtonList[#modeButtonList + 1] = checkButton
    yOffset = yOffset - 28
  end

  makeOption("auto", localeTable.LOCALE_OPTION_AUTO)
  makeOption("zhCN", localeTable.LOCALE_OPTION_ZHCN)
  makeOption("enUS", localeTable.LOCALE_OPTION_ENUS)

  yOffset = yOffset - 8
  local hintLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 语言切换提示
  hintLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  hintLabel:SetWidth(580)
  hintLabel:SetJustifyH("LEFT")
  hintLabel:SetText(localeTable.LOCALE_HINT)
  yOffset = yOffset - 40

  return yOffset
end

--- 构建重载界面区。
---@param childFrame Frame 页面根 child
---@param startY number 当前纵向游标
---@return number
function Toolbox.SettingsHost:BuildReloadSection(childFrame, startY)
  local localeTable = Toolbox.L -- 本地化文案
  local yOffset = startY -- 当前纵向游标

  local reloadButton = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate") -- 重载按钮
  reloadButton:SetSize(180, 22)
  reloadButton:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  reloadButton:SetText(localeTable.SETTINGS_RELOAD_UI)
  reloadButton:SetScript("OnClick", function()
    ReloadUI()
  end)
  yOffset = yOffset - 32

  local hintLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 重载说明
  hintLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  hintLabel:SetWidth(580)
  hintLabel:SetJustifyH("LEFT")
  hintLabel:SetText(localeTable.SETTINGS_RELOAD_HINT)
  yOffset = yOffset - 44

  return yOffset
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
  local yOffset = startY -- 当前纵向游标

  local enableButton = CreateFrame("CheckButton", nil, childFrame, "InterfaceOptionsCheckButtonTemplate") -- 启用开关
  enableButton:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  enableButton.Text:SetText(localeTable.SETTINGS_MODULE_ENABLE or "")
  enableButton:SetChecked(moduleDb.enabled ~= false)
  enableButton:SetScript("OnClick", function(self)
    moduleDb.enabled = self:GetChecked() and true or false
    if moduleObject.OnEnabledSettingChanged then
      moduleObject.OnEnabledSettingChanged(moduleDb.enabled ~= false)
    end
    Toolbox.SettingsHost:BuildPage(pageKey)
  end)
  yOffset = yOffset - 34

  return yOffset
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
  local yOffset = startY -- 当前纵向游标

  local debugButton = CreateFrame("CheckButton", nil, childFrame, "InterfaceOptionsCheckButtonTemplate") -- 调试开关
  debugButton:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  debugButton.Text:SetText(localeTable.SETTINGS_MODULE_DEBUG or "")
  debugButton:SetChecked(moduleDb.debug == true)
  debugButton:SetScript("OnClick", function(self)
    moduleDb.debug = self:GetChecked() == true
    if moduleObject.OnDebugSettingChanged then
      moduleObject.OnDebugSettingChanged(moduleDb.debug == true)
    end
    Toolbox.SettingsHost:BuildPage(pageKey)
  end)
  yOffset = yOffset - 36

  local resetButton = CreateFrame("Button", nil, childFrame, "UIPanelButtonTemplate") -- 重置并重建按钮
  resetButton:SetSize(180, 24)
  resetButton:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  resetButton:SetText(localeTable.SETTINGS_MODULE_RESET_REBUILD or "")
  resetButton:SetScript("OnClick", function()
    if moduleObject.ResetToDefaultsAndRebuild then
      moduleObject.ResetToDefaultsAndRebuild()
    else
      Toolbox.Config.ResetModule(moduleObject.id)
      applyModuleCallbacks(moduleObject)
    end
    if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage and localeTable.SETTINGS_MODULE_RESET_DONE_FMT then
      Toolbox.Chat.PrintAddonMessage(string.format(localeTable.SETTINGS_MODULE_RESET_DONE_FMT, getModuleTitle(moduleObject)))
    end
    Toolbox.SettingsHost:BuildPage(pageKey)
  end)
  yOffset = yOffset - 32

  local hintLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 重置说明
  hintLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  hintLabel:SetWidth(580)
  hintLabel:SetJustifyH("LEFT")
  hintLabel:SetText(localeTable.SETTINGS_MODULE_RESET_HINT or "")
  yOffset = yOffset - 36

  return yOffset
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

  local boxFrame = CreateFrame("Frame", nil, childFrame) -- 模块专属设置容器
  boxFrame:SetSize(MODULE_BOX_WIDTH, 160)
  boxFrame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  moduleObject.RegisterSettings(boxFrame)
  yOffset = yOffset - (boxFrame.realHeight or 160) - 16

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
    yOffset = self:BuildLanguageSection(childFrame, yOffset)
  end
  if pageObject.includeReloadSection == true then
    yOffset = self:BuildReloadSection(childFrame, yOffset)
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

  local commandsTitle = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 常用命令标题
  commandsTitle:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  commandsTitle:SetText(localeTable.SETTINGS_ABOUT_COMMANDS_TITLE or "")
  yOffset = yOffset - 24

  for _, localeKey in ipairs({
    "SETTINGS_ABOUT_COMMAND_1",
    "SETTINGS_ABOUT_COMMAND_2",
    "SETTINGS_ABOUT_COMMAND_3",
    "SETTINGS_ABOUT_COMMAND_4",
  }) do
    local lineLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 命令文本
    lineLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 16, yOffset)
    lineLabel:SetWidth(560)
    lineLabel:SetJustifyH("LEFT")
    lineLabel:SetText("• " .. tostring(Toolbox.L[localeKey] or ""))
    yOffset = yOffset - 20
  end

  yOffset = yOffset - 8
  local docsTitle = childFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 文档标题
  docsTitle:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, yOffset)
  docsTitle:SetText(localeTable.SETTINGS_ABOUT_DOCS_TITLE or "")
  yOffset = yOffset - 24

  for _, localeKey in ipairs({
    "SETTINGS_ABOUT_DOC_1",
    "SETTINGS_ABOUT_DOC_2",
    "SETTINGS_ABOUT_DOC_3",
  }) do
    local lineLabel = childFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 文档文本
    lineLabel:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 16, yOffset)
    lineLabel:SetWidth(560)
    lineLabel:SetJustifyH("LEFT")
    lineLabel:SetText("• " .. tostring(Toolbox.L[localeKey] or ""))
    yOffset = yOffset - 20
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
