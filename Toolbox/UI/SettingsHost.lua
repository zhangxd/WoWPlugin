--[[
  正式服 Settings 宿主：注册 Toolbox 主类目总览页、各功能真实子页面与关于页。
  宿主负责统一绘制模块页公共区（简介、启用、调试、清理并重建），模块只渲染专属设置区。
  `/toolbox` 与 ESC 菜单按钮默认打开主类目总览页。
  战斗中暴雪 `Settings.OpenToCategory` 不可靠：用独立宿主（全屏半透明遮罩 + Dialog 风格底板）托起 Canvas，缩放接近系统设置内嵌时的观感；脱战后仍走系统设置。
  非战斗打开设置前会 `HideUIPanel(GameMenuFrame)`，避免关闭设置后仍显示 ESC 菜单。
  勿缓存 Toolbox.L；语言切换后会重建所有页面内容。
]]

Toolbox.SettingsHost = Toolbox.SettingsHost or {}

local PANEL_WIDTH = 700
local PANEL_HEIGHT = 920
local SCROLL_CHILD_WIDTH = 640
local MODULE_BOX_WIDTH = 604
--- 战斗内独立展示时相对裸 `UIParent` 居中略缩小，贴近系统设置窗口内嵌 Canvas 的观感（可按实机再调）。
local STANDALONE_PANEL_SCALE = 0.82

local function sanitizePageName(value)
  return tostring(value or "Page"):gsub("[^%w_]", "_")
end

local function createCanvasPanel(frameName)
  local panel = CreateFrame("Frame", frameName, UIParent)
  panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
  panel:Hide()

  local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(SCROLL_CHILD_WIDTH, 800)
  scroll:SetScrollChild(child)

  panel._toolboxScroll = scroll
  panel._toolboxChild = child
  return panel
end

local function resetCanvasPanel(panel)
  local scroll = panel._toolboxScroll
  local old = panel._toolboxChild
  if old then
    old:SetParent(nil)
    old:Hide()
  end

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(SCROLL_CHILD_WIDTH, 800)
  scroll:SetScrollChild(child)
  panel._toolboxChild = child
  if scroll.SetVerticalScroll then
    scroll:SetVerticalScroll(0)
  end
  return child
end

local function collectSettingsModules()
  local out = {}
  for _, module in ipairs(Toolbox.ModuleRegistry:GetSorted()) do
    if module.RegisterSettings then
      out[#out + 1] = module
    end
  end

  table.sort(out, function(a, b)
    local orderA = tonumber(a.settingsOrder) or 9999
    local orderB = tonumber(b.settingsOrder) or 9999
    if orderA ~= orderB then
      return orderA < orderB
    end
    return tostring(a.id) < tostring(b.id)
  end)

  return out
end

local function getModuleTitle(module)
  local L = Toolbox.L or {}
  if module.nameKey and L[module.nameKey] then
    return L[module.nameKey]
  end
  if module.name then
    return module.name
  end
  return module.id
end

local function getModuleIntro(module)
  local L = Toolbox.L or {}
  if module.settingsIntroKey and L[module.settingsIntroKey] then
    return L[module.settingsIntroKey]
  end
  return ""
end

local function applyModuleCallbacks(module)
  local db = Toolbox.Config.GetModule(module.id)
  if module.OnEnabledSettingChanged then
    module.OnEnabledSettingChanged(db.enabled ~= false)
  end
  if module.OnDebugSettingChanged then
    module.OnDebugSettingChanged(db.debug == true)
  end
end

local function buildHeader(child, startY, titleText, introText)
  local y = startY

  local title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  title:SetText(titleText or "")
  y = y - 24

  if introText and introText ~= "" then
    local intro = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    intro:SetWidth(580)
    intro:SetJustifyH("LEFT")
    intro:SetText(introText)
    y = y - math.max(36, math.ceil((intro:GetStringHeight() or 0) + 12))
  end

  return y
end

local function setChildHeight(child, y)
  child:SetHeight(math.max(800, math.abs(y) + 40))
end

function Toolbox.SettingsHost:GetPageByKey(pageKey)
  self.pagesByKey = self.pagesByKey or {}
  return self.pagesByKey[pageKey]
end

function Toolbox.SettingsHost:GetModulePageKey(moduleId)
  return "module:" .. tostring(moduleId)
end

--- 重建单个设置页内容；用于语言切换、模块公共开关变化后刷新 UI。
---@param pageKey string 页面键
function Toolbox.SettingsHost:BuildPage(pageKey)
  self:EnsureCreated()
  local page = self:GetPageByKey(pageKey)
  if not page or not page.builder then
    return
  end
  page.builder(page)
end

--- 重建所有已注册的设置页内容。
function Toolbox.SettingsHost:RefreshAllPages()
  self:EnsureCreated()
  if self.category and self.category.SetName and Toolbox.L then
    self.category:SetName(Toolbox.L.SETTINGS_CATEGORY_TITLE or "Toolbox")
  end
  for _, page in ipairs(self.pages or {}) do
    if page.category and page.category.SetName then
      if page.module then
        page.category:SetName(getModuleTitle(page.module))
      elseif page.key == "about" and Toolbox.L then
        page.category:SetName(Toolbox.L.SETTINGS_ABOUT_TITLE or "About")
      end
    end
    if page.builder then
      page.builder(page)
    end
  end
end

--- 兼容旧调用面：构建（现语义为重建）所有页面。
function Toolbox.SettingsHost:Build()
  self:RefreshAllPages()
end

--- 构建总览页里的界面语言区。
---@param child Frame 页面根 child
---@param startY number 当前纵向游标
---@return number
function Toolbox.SettingsHost:BuildLanguageSection(child, startY)
  local L = Toolbox.L
  local g = Toolbox.Config.GetGlobal()
  local y = startY

  local title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  title:SetText(L.LOCALE_SECTION_TITLE)
  y = y - 24

  local modeButtons = {}
  local function setLocale(pref)
    g.locale = pref
    for _, cb in ipairs(modeButtons) do
      cb:SetChecked(cb.localePref == pref)
    end
    Toolbox.Locale_Apply()
    Toolbox.SettingsHost:RefreshAllPages()
  end

  local function makeOption(pref, label)
    local cb = CreateFrame("CheckButton", nil, child, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", child, "TOPLEFT", 20, y)
    cb.Text:SetText(label)
    cb.localePref = pref
    cb:SetChecked((g.locale or "auto") == pref)
    cb:SetScript("OnClick", function(self)
      setLocale(self.localePref)
    end)
    modeButtons[#modeButtons + 1] = cb
    y = y - 28
  end

  makeOption("auto", L.LOCALE_OPTION_AUTO)
  makeOption("zhCN", L.LOCALE_OPTION_ZHCN)
  makeOption("enUS", L.LOCALE_OPTION_ENUS)

  y = y - 8
  local hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  hint:SetWidth(580)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.LOCALE_HINT)
  y = y - 40

  return y
end

--- 构建总览页里的重载界面区。
---@param child Frame 页面根 child
---@param startY number 当前纵向游标
---@return number
function Toolbox.SettingsHost:BuildReloadSection(child, startY)
  local L = Toolbox.L
  local y = startY

  local btn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
  btn:SetSize(180, 22)
  btn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  btn:SetText(L.SETTINGS_RELOAD_UI)
  btn:SetScript("OnClick", function()
    ReloadUI()
  end)
  y = y - 32

  local hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  hint:SetWidth(580)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.SETTINGS_RELOAD_HINT)
  y = y - 44

  return y
end

--- 构建总览页里的功能导航说明。
---@param child Frame 页面根 child
---@param startY number 当前纵向游标
---@return number
function Toolbox.SettingsHost:BuildOverviewModuleList(child, startY)
  local L = Toolbox.L or {}
  local y = startY

  local title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  title:SetText(L.SETTINGS_OVERVIEW_MODULES_TITLE or "")
  y = y - 22

  local hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  hint:SetWidth(580)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.SETTINGS_OVERVIEW_MODULES_HINT or "")
  y = y - 32

  for _, module in ipairs(collectSettingsModules()) do
    local line = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
    line:SetWidth(564)
    line:SetJustifyH("LEFT")
    line:SetText(string.format("• %s", getModuleTitle(module)))
    y = y - 20

    local intro = getModuleIntro(module)
    if intro ~= "" then
      local desc = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      desc:SetPoint("TOPLEFT", child, "TOPLEFT", 32, y)
      desc:SetWidth(548)
      desc:SetJustifyH("LEFT")
      desc:SetText(intro)
      y = y - math.max(24, math.ceil((desc:GetStringHeight() or 0) + 8))
    end
  end

  y = y - 8
  return y
end

--- 构建总览页里的效果预览区。
---@param child Frame 页面根 child
---@param startY number 当前纵向游标
---@return number
function Toolbox.SettingsHost:BuildPreviewSection(child, startY)
  local L = Toolbox.L
  local y = startY

  local title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  title:SetText(L.SETTINGS_PREVIEW_TITLE)
  y = y - 22

  local intro = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  intro:SetWidth(580)
  intro:SetJustifyH("LEFT")
  intro:SetText(L.SETTINGS_PREVIEW_INTRO)
  y = y - 36

  local box = CreateFrame("Frame", "ToolboxSettingsPreviewBox", child, "BackdropTemplate")
  box:SetSize(620, 200)
  box:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  box:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  box:SetBackdropColor(0, 0, 0, 0.35)

  local subTT = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  subTT:SetPoint("TOPLEFT", 12, -12)
  subTT:SetText(L.SETTINGS_PREVIEW_TOOLTIP_SUB)

  local ttBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  ttBtn:SetSize(280, 26)
  ttBtn:SetPoint("TOPLEFT", subTT, "BOTTOMLEFT", 0, -8)
  ttBtn:SetText(L.SETTINGS_PREVIEW_TOOLTIP_BTN)
  ttBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    if GameTooltip_SetDefaultAnchor then
      GameTooltip_SetDefaultAnchor(GameTooltip, self)
    end
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L.SETTINGS_PREVIEW_TOOLTIP_LINE1, 1, 1, 1)
    GameTooltip:AddLine(L.SETTINGS_PREVIEW_TOOLTIP_LINE2, 0.75, 0.85, 1)
    GameTooltip:Show()
  end)
  ttBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local moverHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  moverHint:SetPoint("TOPLEFT", ttBtn, "BOTTOMLEFT", 0, -14)
  moverHint:SetWidth(560)
  moverHint:SetJustifyH("LEFT")
  moverHint:SetText(L.SETTINGS_PREVIEW_MOVER)

  y = y - 200 - 16
  return y
end

--- 构建模块页公共区（启用、调试、清理并重建）。
---@param child Frame 页面根 child
---@param startY number 当前纵向游标
---@param module table 模块定义
---@return number
function Toolbox.SettingsHost:BuildSharedModuleControls(child, startY, module)
  local L = Toolbox.L or {}
  local db = Toolbox.Config.GetModule(module.id)
  local y = startY

  local enable = CreateFrame("CheckButton", nil, child, "InterfaceOptionsCheckButtonTemplate")
  enable:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  enable.Text:SetText(L.SETTINGS_MODULE_ENABLE or "")
  enable:SetChecked(db.enabled ~= false)
  enable:SetScript("OnClick", function(self)
    db.enabled = self:GetChecked() and true or false
    if module.OnEnabledSettingChanged then
      module.OnEnabledSettingChanged(db.enabled ~= false)
    end
    Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(module.id))
  end)
  y = y - 32

  local debug = CreateFrame("CheckButton", nil, child, "InterfaceOptionsCheckButtonTemplate")
  debug:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  debug.Text:SetText(L.SETTINGS_MODULE_DEBUG or "")
  debug:SetChecked(db.debug == true)
  debug:SetScript("OnClick", function(self)
    db.debug = self:GetChecked() == true
    if module.OnDebugSettingChanged then
      module.OnDebugSettingChanged(db.debug == true)
    end
    Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(module.id))
  end)
  y = y - 36

  local reset = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
  reset:SetSize(180, 24)
  reset:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  reset:SetText(L.SETTINGS_MODULE_RESET_REBUILD or "")
  reset:SetScript("OnClick", function()
    if module.ResetToDefaultsAndRebuild then
      module.ResetToDefaultsAndRebuild()
    else
      Toolbox.Config.ResetModule(module.id)
      applyModuleCallbacks(module)
    end
    if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage and L.SETTINGS_MODULE_RESET_DONE_FMT then
      Toolbox.Chat.PrintAddonMessage(string.format(L.SETTINGS_MODULE_RESET_DONE_FMT, getModuleTitle(module)))
    end
    Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(module.id))
  end)
  y = y - 32

  local hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  hint:SetWidth(580)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.SETTINGS_MODULE_RESET_HINT or "")
  y = y - 36

  return y
end

--- 构建主类目总览页。
---@param page table 页面定义
function Toolbox.SettingsHost:BuildOverviewPage(page)
  local L = Toolbox.L or {}
  local child = resetCanvasPanel(page.panel)
  local y = -8

  y = buildHeader(child, y, L.SETTINGS_OVERVIEW_TITLE or "", L.SETTINGS_OVERVIEW_INTRO or "")
  y = self:BuildLanguageSection(child, y)
  y = self:BuildReloadSection(child, y)
  y = self:BuildOverviewModuleList(child, y)
  y = self:BuildPreviewSection(child, y)
  setChildHeight(child, y)
end

--- 构建单个功能模块页。
---@param page table 页面定义
function Toolbox.SettingsHost:BuildModulePage(page)
  local module = page.module
  local child = resetCanvasPanel(page.panel)
  local y = -8

  y = buildHeader(child, y, getModuleTitle(module), getModuleIntro(module))
  y = self:BuildSharedModuleControls(child, y, module)

  local customTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  customTitle:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  customTitle:SetText((Toolbox.L and Toolbox.L.SETTINGS_MODULE_SECTION_TITLE) or "")
  y = y - 24

  local box = CreateFrame("Frame", nil, child)
  box:SetSize(MODULE_BOX_WIDTH, 160)
  box:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  module.RegisterSettings(box)
  y = y - (box.realHeight or 160) - 16

  setChildHeight(child, y)
end

--- 构建关于页。
---@param page table 页面定义
function Toolbox.SettingsHost:BuildAboutPage(page)
  local L = Toolbox.L or {}
  local child = resetCanvasPanel(page.panel)
  local y = -8

  y = buildHeader(child, y, L.SETTINGS_ABOUT_TITLE or "", L.SETTINGS_ABOUT_INTRO or "")

  local versionLabel = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  versionLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  versionLabel:SetJustifyH("LEFT")
  versionLabel:SetText(string.format(
    L.SETTINGS_ABOUT_VERSION_FMT or "%s",
    tostring(Toolbox.Chat.GetAddOnMetadata(Toolbox.ADDON_NAME, "Version") or "")
  ))
  y = y - 24

  local clientLabel = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  clientLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  clientLabel:SetJustifyH("LEFT")
  clientLabel:SetText(L.SETTINGS_ABOUT_CLIENT or "")
  y = y - 32

  local commandsTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  commandsTitle:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  commandsTitle:SetText(L.SETTINGS_ABOUT_COMMANDS_TITLE or "")
  y = y - 24

  for _, key in ipairs({
    "SETTINGS_ABOUT_COMMAND_1",
    "SETTINGS_ABOUT_COMMAND_2",
    "SETTINGS_ABOUT_COMMAND_3",
    "SETTINGS_ABOUT_COMMAND_4",
  }) do
    local line = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
    line:SetWidth(560)
    line:SetJustifyH("LEFT")
    line:SetText("• " .. tostring(L[key] or ""))
    y = y - 20
  end

  y = y - 8
  local docsTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  docsTitle:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  docsTitle:SetText(L.SETTINGS_ABOUT_DOCS_TITLE or "")
  y = y - 24

  for _, key in ipairs({
    "SETTINGS_ABOUT_DOC_1",
    "SETTINGS_ABOUT_DOC_2",
    "SETTINGS_ABOUT_DOC_3",
  }) do
    local line = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
    line:SetWidth(560)
    line:SetJustifyH("LEFT")
    line:SetText("• " .. tostring(L[key] or ""))
    y = y - 20
  end

  setChildHeight(child, y)
end

--- 确保 Settings 主类目与各子页面已注册。
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

  local overviewPanel = createCanvasPanel("ToolboxSettingsOverviewPanel")
  local overviewPage = {
    key = "overview",
    panel = overviewPanel,
    builder = function(page)
      Toolbox.SettingsHost:BuildOverviewPage(page)
    end,
  }
  self.pages[#self.pages + 1] = overviewPage
  self.pagesByKey[overviewPage.key] = overviewPage

  local category = Settings.RegisterCanvasLayoutCategory(overviewPanel, (Toolbox.L and Toolbox.L.SETTINGS_CATEGORY_TITLE) or "Toolbox")
  Settings.RegisterAddOnCategory(category)
  self.category = category

  for _, module in ipairs(collectSettingsModules()) do
    local panelName = "ToolboxSettingsModule" .. sanitizePageName(module.id) .. "Panel"
    local panel = createCanvasPanel(panelName)
    local pageKey = self:GetModulePageKey(module.id)
    local page = {
      key = pageKey,
      panel = panel,
      module = module,
      builder = function(pageDef)
        Toolbox.SettingsHost:BuildModulePage(pageDef)
      end,
    }
    self.pages[#self.pages + 1] = page
    self.pagesByKey[page.key] = page

    local subcategory = Settings.RegisterCanvasLayoutSubcategory(category, panel, getModuleTitle(module))
    Settings.RegisterAddOnCategory(subcategory)
    page.category = subcategory
  end

  local aboutPanel = createCanvasPanel("ToolboxSettingsAboutPanel")
  local aboutPage = {
    key = "about",
    panel = aboutPanel,
    builder = function(page)
      Toolbox.SettingsHost:BuildAboutPage(page)
    end,
  }
  self.pages[#self.pages + 1] = aboutPage
  self.pagesByKey[aboutPage.key] = aboutPage

  local aboutCategory = Settings.RegisterCanvasLayoutSubcategory(category, aboutPanel, (Toolbox.L and Toolbox.L.SETTINGS_ABOUT_TITLE) or "About")
  Settings.RegisterAddOnCategory(aboutCategory)
  aboutPage.category = aboutCategory
end

--- 战斗内独立展示：全屏遮罩 + 底板（与 Canvas 分层，避免全透明与比例失调）。
local standalonePresentation

---@return table host, dimmer, box
local function ensureStandalonePresentationHost()
  if standalonePresentation then
    return standalonePresentation
  end
  local host = CreateFrame("Frame", "ToolboxSettingsStandaloneHost", UIParent)
  host:SetFrameStrata("DIALOG")
  host:SetFrameLevel(100)
  host:SetAllPoints(UIParent)
  host:Hide()

  local dimmer = CreateFrame("Button", nil, host)
  dimmer:SetAllPoints(host)
  dimmer:SetFrameLevel(0)
  local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
  dimTex:SetAllPoints()
  dimTex:SetColorTexture(0, 0, 0, 0.5)
  dimmer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  dimmer:SetScript("OnClick", function()
    Toolbox.SettingsHost:HideStandalonePresentation()
  end)

  local box
  do
    local ok, f = pcall(function()
      return CreateFrame("Frame", nil, host, "BackdropTemplate")
    end)
    box = (ok and f) and f or CreateFrame("Frame", nil, host)
  end
  box:SetFrameLevel(5)
  local pad = 40
  box:SetSize(PANEL_WIDTH + pad, PANEL_HEIGHT + pad)
  box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  local backdropOk = pcall(function()
    box:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    box:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    box:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  end)
  if not backdropOk then
    local bt = box:CreateTexture(nil, "ARTWORK")
    bt:SetAllPoints()
    bt:SetColorTexture(0.09, 0.09, 0.11, 0.98)
  end

  standalonePresentation = { host = host, dimmer = dimmer, box = box }
  return standalonePresentation
end

--- 打开系统设置前收起 ESC 菜单，避免仅关闭设置后仍留在游戏菜单栈顶。
local function dismissGameMenuIfShown()
  local gm = _G.GameMenuFrame
  if gm and gm.IsShown and gm:IsShown() and HideUIPanel then
    pcall(HideUIPanel, gm)
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
  for _, tmpl in ipairs(STANDALONE_CLOSE_TEMPLATES) do
    local ok, btn = pcall(function()
      return CreateFrame("Button", nil, panel, tmpl)
    end)
    if ok and btn then
      return btn
    end
  end
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(24, 22)
  b:SetText("X")
  return b
end

--- 隐藏所有已注册的 Canvas 面板与战斗内嵌独立展示用的关闭键（不卸载内容）。
function Toolbox.SettingsHost:HideStandalonePresentation()
  self:EnsureCreated()
  if standalonePresentation and standalonePresentation.host then
    standalonePresentation.host:Hide()
  end
  for _, page in ipairs(self.pages or {}) do
    local p = page.panel
    if p then
      if p._toolboxStandaloneScaleApplied then
        p:SetScale(p._toolboxStandaloneSavedScale or 1)
        p._toolboxStandaloneScaleApplied = nil
        p._toolboxStandaloneSavedScale = nil
      end
      p:Hide()
      p:SetScript("OnKeyDown", nil)
      p:EnableKeyboard(false)
      if p._toolboxStandaloneClose then
        p._toolboxStandaloneClose:Hide()
      end
    end
  end
end

--- 战斗等场景：不经过 `Settings.OpenToCategory`，将指定页 Canvas 置于遮罩+底板之上（观感接近系统设置内嵌）。
---@param pageKey string overview / module:… / about
function Toolbox.SettingsHost:ShowStandalonePageByKey(pageKey)
  self:EnsureCreated()
  local page = self:GetPageByKey(pageKey)
  if not page or not page.panel then
    return
  end
  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  local sp = ensureStandalonePresentationHost()
  local panel = page.panel
  local box = sp.box
  panel:ClearAllPoints()
  panel:SetPoint("CENTER", box, "CENTER", 0, 0)
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
  panel:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then
      Toolbox.SettingsHost:HideStandalonePresentation()
    end
  end)
  if not panel._toolboxStandaloneClose then
    local close = createStandaloneCloseButton(panel)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
      Toolbox.SettingsHost:HideStandalonePresentation()
    end)
    panel._toolboxStandaloneClose = close
  else
    panel._toolboxStandaloneClose:Show()
  end
  sp.host:Show()
  panel:Show()
end

--- 打开主类目总览页。
function Toolbox.SettingsHost:Open()
  self:EnsureCreated()
  if not self.category then
    return
  end
  if InCombatLockdown() then
    self:ShowStandalonePageByKey("overview")
    return
  end
  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  if Settings and Settings.OpenToCategory then
    pcall(function()
      Settings.OpenToCategory(self.category:GetID())
    end)
  end
end

--- 打开设置并定位到指定功能模块子页（与总览 / 关于同级）。
---@param moduleId string modules.* 的模块 id
function Toolbox.SettingsHost:OpenToModulePage(moduleId)
  self:EnsureCreated()
  if not moduleId or not Settings or not Settings.OpenToCategory then
    self:Open()
    return
  end
  local key = self:GetModulePageKey(moduleId)
  local page = self:GetPageByKey(key)
  if not page or not page.category then
    self:Open()
    return
  end
  if InCombatLockdown() then
    self:ShowStandalonePageByKey(key)
    return
  end
  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  local subCat = page.category
  pcall(function()
    Settings.OpenToCategory(subCat:GetID())
  end)
end

--- 打开设置并定位到关于页。
function Toolbox.SettingsHost:OpenToAbout()
  self:EnsureCreated()
  if not Settings or not Settings.OpenToCategory then
    self:Open()
    return
  end
  local page = self:GetPageByKey("about")
  if not page or not page.category then
    self:Open()
    return
  end
  if InCombatLockdown() then
    self:ShowStandalonePageByKey("about")
    return
  end
  self:HideStandalonePresentation()
  dismissGameMenuIfShown()
  pcall(function()
    Settings.OpenToCategory(page.category:GetID())
  end)
end

local function tryGameMenuAttach()
  if Toolbox._gameMenuBtn then
    return true
  end
  Toolbox_NamespaceEnsure()
  Toolbox.SettingsHost:EnsureCreated()
  local gm = _G.GameMenuFrame
  if not gm then
    return false
  end
  local anchor = _G.GameMenuButtonOptions or _G.GameMenuButtonSettings
  if not anchor then
    return false
  end
  local b = CreateFrame("Button", "GameMenuButtonToolbox", gm, "GameMenuButtonTemplate")
  b:SetText(Toolbox.L.GAMEMENU_TOOLBOX)
  b:SetPoint("TOP", anchor, "BOTTOM", 0, -1)
  b:SetScript("OnClick", function()
    HideUIPanel(_G.GameMenuFrame)
    Toolbox.SettingsHost:Open()
  end)
  Toolbox._gameMenuBtn = b
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

  local function attempt()
    local gm = _G.GameMenuFrame
    if gm and not Toolbox._gameMenuShowHooked then
      Toolbox._gameMenuShowHooked = true
      gm:HookScript("OnShow", tryGameMenuAttach)
    end
    tryGameMenuAttach()
  end

  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("ADDON_LOADED")
  watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcher:SetScript("OnEvent", function()
    attempt()
  end)
  attempt()
end
