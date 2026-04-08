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
    Toolbox.Config.ResetModule("tooltip_anchor")
    Toolbox.Tooltip.RefreshDriver()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = Toolbox.Config.GetModule("tooltip_anchor")
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
    makeMode("follow", L.TOOLTIP_MODE_FOLLOW)

    setMode(db.mode or "default")

    y = y - 8
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.TOOLTIP_HINT)
    y = y - 36

    box.realHeight = math.abs(y) + 8
  end,
})
