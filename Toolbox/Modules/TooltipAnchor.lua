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
    local L = Toolbox.L or {} -- 本地化文案
    local db = Toolbox.Config.GetModule("tooltip_anchor") -- 模块存档

    box:AddMenuRow({
      label = L.MODULE_TOOLTIP or "tooltip_anchor",
      description = L.TOOLTIP_HINT or "",
      buttonWidth = 160,
      options = {
        { value = "default", label = L.TOOLTIP_MODE_DEFAULT or "default" },
        { value = "cursor", label = L.TOOLTIP_MODE_CURSOR or "cursor" },
        { value = "follow", label = L.TOOLTIP_MODE_FOLLOW or "follow" },
      },
      defaultValue = "default",
      getValue = function()
        return db.mode
      end,
      setValue = function(value)
        db.mode = value
      end,
      afterChange = function()
        Toolbox.Tooltip.RefreshDriver()
      end,
    })
  end,
})
