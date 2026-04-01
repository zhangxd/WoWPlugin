--[[
  正式服 Settings：RegisterCanvasLayoutCategory 注册整页设置（标题见 Locales）。
  Build() 先渲染「界面语言」与「重载界面」按钮，再按模块顺序堆叠 RegisterSettings，
  末尾「效果预览」区：提示框悬停示例、窗口拖动说明。
  勿缓存 Toolbox.L 引用，语言切换后会替换整张表。
  GameMenu_Init：ESC 菜单增加按钮，与 选项→插件 打开同一 category。
]]

Toolbox.SettingsHost = Toolbox.SettingsHost or {}

-- panel 作为 Canvas 根；子 ScrollFrame 的 child 高度在 Build 末尾按内容撑开
local function createPanel()
  local panel = CreateFrame("Frame", "ToolboxSettingsPanel", UIParent)
  panel:SetSize(700, 920)
  panel:Hide()

  local scroll = CreateFrame("ScrollFrame", "ToolboxSettingsScroll", panel, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(640, 800)
  scroll:SetScrollChild(child)

  return panel, scroll, child
end

function Toolbox.SettingsHost:EnsureCreated()
  Toolbox_NamespaceEnsure()
  if self.category then
    return
  end
  local panel, scroll, child = createPanel()
  self.panel = panel
  self.scrollFrame = scroll
  self.scrollChild = child

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, Toolbox.L.SETTINGS_CATEGORY_TITLE)
    Settings.RegisterAddOnCategory(category)
    self.category = category
  else
    error("Toolbox: " .. Toolbox.L.ERR_SETTINGS_API)
  end
end

-- 顶部「界面语言」区 + 各模块设置；切换语言后整页重建
function Toolbox.SettingsHost:BuildLanguageSection(child, startY)
  local L = Toolbox.L
  local g = Toolbox.DB.GetGlobal()
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
    Toolbox.SettingsHost:Build()
  end

  local function makeOpt(pref, label)
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

  makeOpt("auto", L.LOCALE_OPTION_AUTO)
  makeOpt("zhCN", L.LOCALE_OPTION_ZHCN)
  makeOpt("enUS", L.LOCALE_OPTION_ENUS)

  y = y - 8
  local hint = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
  hint:SetWidth(580)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.LOCALE_HINT)
  y = y - 40

  return y
end

-- 重载界面按钮：调用暴雪 ReloadUI()，便于改完插件或部分选项后立即生效
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

-- 自上而下累加 y（负方向）；box.realHeight 由各模块 RegisterSettings 末尾设置
function Toolbox.SettingsHost:Build()
  self:EnsureCreated()
  local scroll = self.scrollFrame
  -- 每次整页重建时换新的内容根 Frame，避免仅 GetChildren/GetRegions 卸不干净导致切换语言后叠字
  local old = self.scrollChild
  if old then
    old:SetParent(nil)
    old:Hide()
  end
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(640, 800)
  scroll:SetScrollChild(child)
  self.scrollChild = child
  if scroll.SetVerticalScroll then
    scroll:SetVerticalScroll(0)
  end

  local L = Toolbox.L
  local y = -8
  y = self:BuildLanguageSection(child, y)
  y = self:BuildReloadSection(child, y)

  local sorted = Toolbox.ModuleRegistry:GetSorted()
  for _, mod in ipairs(sorted) do
    if mod.RegisterSettings then
      local title = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
      title:SetText(mod.nameKey and L[mod.nameKey] or mod.name or mod.id)
      y = y - 24

      local box = CreateFrame("Frame", nil, child)
      box:SetSize(620, 160)
      box:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
      mod.RegisterSettings(box)
      local h = box.realHeight or 160
      y = y - h - 16
    end
  end
  y = self:BuildPreviewSection(child, y)
  child:SetHeight(math.max(800, math.abs(y) + 40))
end

function Toolbox.SettingsHost:Open()
  self:EnsureCreated()
  if self.category then
    Settings.OpenToCategory(self.category:GetID())
  end
end

-- ESC 菜单往往在首次打开时才完整创建；ADDON_LOADED 时 GameMenuFrame/锚点按钮可能尚不存在，需延迟重试
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

function Toolbox.GameMenu_Init()
  if tryGameMenuAttach() then
    return
  end
  if not Toolbox._gameMenuHooked then
    Toolbox._gameMenuHooked = true
    local function ensureShowHook()
      if Toolbox._gameMenuShowHooked then
        return
      end
      local gm = _G.GameMenuFrame
      if not gm then
        return
      end
      Toolbox._gameMenuShowHooked = true
      gm:HookScript("OnShow", tryGameMenuAttach)
    end
    local function tick()
      ensureShowHook()
      tryGameMenuAttach()
    end
    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_ENTERING_WORLD")
    w:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      for i = 0, 12 do
        C_Timer.After(i * 0.5, tick)
      end
    end)
    tick()
  end
end
