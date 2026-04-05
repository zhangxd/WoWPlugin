--[[
  模块 tooltip_anchor：提示框锚点与跟随的配置与设置 UI。
  实现见 Core/Tooltip.lua（Toolbox.Tooltip）；本文件不直接 hook GameTooltip。
]]

Toolbox.RegisterModule({
  id = "tooltip_anchor",
  nameKey = "MODULE_TOOLTIP",
  settingsIntroKey = "MODULE_TOOLTIP_INTRO",
  settingsOrder = 40,
  OnModuleLoad = function()
    Toolbox.Tooltip.InstallDefaultAnchorHook()
  end,
  OnModuleEnable = function()
    Toolbox.Tooltip.RefreshDriver()
  end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_TOOLTIP or "tooltip_anchor"))
    Toolbox.Tooltip.RefreshDriver()
  end,
  OnDebugSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_TOOLTIP or "tooltip_anchor"))
    Toolbox.Tooltip.RefreshDriver()
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.DB.ResetModule("tooltip_anchor")
    Toolbox.Tooltip.RefreshDriver()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = Toolbox.DB.GetModule("tooltip_anchor")
    local y = 0

    local modeButtons = {}
    local function setMode(mode)
      db.mode = mode
      for _, cb in ipairs(modeButtons) do
        cb:SetChecked(cb.modeValue == mode)
      end
      Toolbox.Tooltip.RefreshDriver()
    end

    local function makeMode(mode, label)
      local cb = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
      cb:SetPoint("TOPLEFT", 20, y)
      cb.Text:SetText(label)
      cb.modeValue = mode
      cb:SetChecked(db.mode == mode)
      cb:SetScript("OnClick", function(self)
        setMode(self.modeValue)
      end)
      modeButtons[#modeButtons + 1] = cb
      y = y - 28
    end

    makeMode("default", L.TOOLTIP_MODE_DEFAULT)
    makeMode("cursor", L.TOOLTIP_MODE_CURSOR)

    setMode(db.mode or "default")

    y = y - 8
    local oxL = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    oxL:SetPoint("TOPLEFT", 0, y)
    oxL:SetText(L.TOOLTIP_OFFSET_X)
    local ox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    ox:SetSize(80, 22)
    ox:SetPoint("LEFT", oxL, "RIGHT", 8, 0)
    ox:SetAutoFocus(false)
    ox:SetText(tostring(db.offsetX or 0))
    ox:SetScript("OnEnterPressed", function(self)
      db.offsetX = tonumber(self:GetText()) or 0
      self:ClearFocus()
      Toolbox.Tooltip.RefreshDriver()
    end)
    y = y - 32

    local oyL = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    oyL:SetPoint("TOPLEFT", 0, y)
    oyL:SetText(L.TOOLTIP_OFFSET_Y)
    local oy = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    oy:SetSize(80, 22)
    oy:SetPoint("LEFT", oyL, "RIGHT", 8, 0)
    oy:SetAutoFocus(false)
    oy:SetText(tostring(db.offsetY or 0))
    oy:SetScript("OnEnterPressed", function(self)
      db.offsetY = tonumber(self:GetText()) or 0
      self:ClearFocus()
      Toolbox.Tooltip.RefreshDriver()
    end)
    y = y - 40

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.TOOLTIP_HINT)
    y = y - 36

    box.realHeight = math.abs(y) + 8
  end,
})

