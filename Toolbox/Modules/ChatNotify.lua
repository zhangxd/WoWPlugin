--[[
  模块 chat_notify：加载完成聊天提示、输出颜色与「复制默认聊天框最近内容」等聊天相关设置。
  输出与复制经 Core/Chat.lua（Toolbox.Chat）；设置页公共区负责启用/调试/重置。
]]

Toolbox.ChatNotify = Toolbox.ChatNotify or {}

local MODULE_ID = "chat_notify"

local function getModuleDb()
  return Toolbox.DB.GetModule(MODULE_ID)
end

local function isDebugEnabled()
  return getModuleDb().debug == true
end

local function debugPrint(message)
  if not isDebugEnabled() or not message or message == "" then
    return
  end
  Toolbox.Chat.PrintAddonMessage(message)
end

-- 兼容旧存档 global.notifyLoadComplete；新逻辑只看 modules.chat_notify.enabled
local function shouldPrint()
  local g = Toolbox.DB.GetGlobal()
  if g.notifyLoadComplete == false then
    return false
  end
  local m = getModuleDb()
  return m.enabled ~= false
end

--- 根据当前模块开关输出加载完成提示。
function Toolbox.ChatNotify.PrintLoadComplete()
  Toolbox_NamespaceEnsure()
  local L = Toolbox.L or {}
  if not shouldPrint() then
    debugPrint(L.CHAT_NOTIFY_DEBUG_SKIP or "")
    return
  end
  local body = L.LOAD_COMPLETE_MSG or "Toolbox"
  local ver = Toolbox.Chat.GetAddOnMetadata(Toolbox.ADDON_NAME, "Version")
  if ver and ver ~= "" then
    local cc = getModuleDb().contentColor or "ffffff"
    body = body .. string.format("  |cff%sv%s|r", cc, ver)
  end
  Toolbox.Chat.PrintAddonMessage(body)
  debugPrint(string.format(L.CHAT_NOTIFY_DEBUG_PRINT_FMT or "%s", tostring(ver or "")))
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_CHAT_NOTIFY",
  settingsIntroKey = "MODULE_CHAT_NOTIFY_INTRO",
  settingsOrder = 10,
  OnModuleLoad = function() end,
  OnModuleEnable = function() end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local title = L.MODULE_CHAT_NOTIFY or MODULE_ID
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", title))
  end,
  OnDebugSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local title = L.MODULE_CHAT_NOTIFY or MODULE_ID
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", title))
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.DB.ResetModule(MODULE_ID)
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {}
    local db = getModuleDb()
    local y = 0

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CHAT_NOTIFY_HINT)
    y = y - 36

    local copySec = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copySec:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    copySec:SetWidth(580)
    copySec:SetJustifyH("LEFT")
    copySec:SetText(L.CHAT_NOTIFY_COPY_SECTION or "")
    y = y - 20

    local copyHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyHint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    copyHint:SetWidth(560)
    copyHint:SetJustifyH("LEFT")
    copyHint:SetText(L.CHAT_NOTIFY_COPY_HINT or "")
    y = y - math.max(28, math.ceil((copyHint:GetStringHeight() or 0) + 8))

    local copyBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    copyBtn:SetSize(200, 26)
    copyBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    copyBtn:SetText(L.CHAT_NOTIFY_COPY_BUTTON or "")
    copyBtn:SetScript("OnClick", function()
      local ok, key = Toolbox.Chat.CopyDefaultChatToClipboard(30)
      local L2 = Toolbox.L or {}
      if ok then
        local msgKey = key or "CHAT_NOTIFY_COPY_DONE"
        Toolbox.Chat.PrintAddonMessage(L2[msgKey] or "")
      else
        Toolbox.Chat.PrintAddonMessage(L2[key or "CHAT_COPY_ERR_FAILED"] or "")
      end
    end)
    y = y - 36

    -- 与 Core/Chat.PrintAddonMessage、存档 prefixColor / contentColor 一致
    local colors = {
      { nameKey = "CHAT_NOTIFY_COLOR_GREEN", color = "00ff00" },
      { nameKey = "CHAT_NOTIFY_COLOR_GOLD", color = "ffd700" },
      { nameKey = "CHAT_NOTIFY_COLOR_ORANGE", color = "ffaa00" },
      { nameKey = "CHAT_NOTIFY_COLOR_BLUE", color = "00aaff" },
      { nameKey = "CHAT_NOTIFY_COLOR_PURPLE", color = "cc88ff" },
      { nameKey = "CHAT_NOTIFY_COLOR_WHITE", color = "ffffff" },
    }

    local function labelForHex(hex)
      for _, c in ipairs(colors) do
        if c.color == hex then
          return L[c.nameKey] or c.nameKey
        end
      end
      return hex
    end

    local function menuTextForHex(hex)
      return string.format("|cff%s%s|r", hex, labelForHex(hex))
    end

    ---@param dbField string 模块表键名，如 "prefixColor" / "contentColor"
    ---@param defaultHex string 缺省或非法存档时的十六进制色（无 |cff）
    local function addColorDropdownRow(dbField, defaultHex, labelKey)
      local rowLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      rowLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
      rowLabel:SetWidth(168)
      rowLabel:SetJustifyH("LEFT")
      rowLabel:SetText(L[labelKey] or labelKey)

      local dd = CreateFrame("Frame", nil, box, "UIDropDownMenuTemplate")
      dd:SetPoint("TOPLEFT", box, "TOPLEFT", 170, y - 2)

      local function currentHex()
        local v = db[dbField]
        if type(v) ~= "string" or v == "" then
          return defaultHex
        end
        return v
      end

      local function refreshButtonText()
        UIDropDownMenu_SetText(dd, menuTextForHex(currentHex()))
      end

      UIDropDownMenu_SetWidth(dd, 240)
      UIDropDownMenu_JustifyText(dd, "LEFT")
      UIDropDownMenu_Initialize(dd, function(_, level)
        if level and level > 1 then
          return
        end
        for _, c in ipairs(colors) do
          local info = UIDropDownMenu_CreateInfo()
          info.text = menuTextForHex(c.color)
          info.func = function()
            db[dbField] = c.color
            refreshButtonText()
            CloseDropDownMenus()
          end
          UIDropDownMenu_AddButton(info)
        end
      end)
      refreshButtonText()
      y = y - 38
    end

    local section = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    section:SetWidth(580)
    section:SetJustifyH("LEFT")
    section:SetText(L.CHAT_NOTIFY_COLORS_SECTION or "")
    y = y - 22

    addColorDropdownRow("prefixColor", "ffd700", "CHAT_NOTIFY_PREFIX_COLOR_LABEL")
    addColorDropdownRow("contentColor", "ffffff", "CHAT_NOTIFY_CONTENT_COLOR_LABEL")

    y = y - 8
    box.realHeight = math.abs(y) + 8
  end,
})
