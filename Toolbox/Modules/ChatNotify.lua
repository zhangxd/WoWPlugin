--[[
  模块 chat_notify：加载完成聊天提示、输出颜色与「复制默认聊天框最近内容」等聊天相关设置。
  输出与复制经 Core/Chat.lua（Toolbox.Chat）；设置页公共区负责启用/调试/重置。
]]

Toolbox.ChatNotify = Toolbox.ChatNotify or {}

local MODULE_ID = "chat_notify"

local function getModuleDb()
  return Toolbox.Config.GetModule(MODULE_ID)
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
  local g = Toolbox.Config.GetGlobal()
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
    Toolbox.Config.ResetModule(MODULE_ID)
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {} -- 本地化文案
    local db = getModuleDb() -- 模块存档

    -- 与 Core/Chat.PrintAddonMessage、存档 prefixColor / contentColor 一致
    local colors = {
      { nameKey = "CHAT_NOTIFY_COLOR_GREEN", color = "00ff00" },
      { nameKey = "CHAT_NOTIFY_COLOR_GOLD", color = "ffd700" },
      { nameKey = "CHAT_NOTIFY_COLOR_ORANGE", color = "ffaa00" },
      { nameKey = "CHAT_NOTIFY_COLOR_BLUE", color = "00aaff" },
      { nameKey = "CHAT_NOTIFY_COLOR_PURPLE", color = "cc88ff" },
      { nameKey = "CHAT_NOTIFY_COLOR_WHITE", color = "ffffff" },
    } -- 可选颜色列表

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

    local function buildColorOptions()
      local optionList = {} -- box helper 菜单项
      for _, colorInfo in ipairs(colors) do
        optionList[#optionList + 1] = {
          value = colorInfo.color,
          label = menuTextForHex(colorInfo.color),
        }
      end
      return optionList
    end

    ---@param dbField string 模块表键名，如 "prefixColor" / "contentColor"
    ---@param defaultHex string 缺省或非法存档时的十六进制色（无 |cff）
    ---@param labelKey string 本地化标签键
    local function addColorMenuRow(dbField, defaultHex, labelKey)
      box:AddMenuRow({
        label = L[labelKey] or labelKey,
        options = buildColorOptions(),
        defaultValue = defaultHex,
        buttonWidth = 240,
        getValue = function()
          local storedHex = db[dbField] -- 当前存档色值
          if type(storedHex) ~= "string" or storedHex == "" then
            return defaultHex
          end
          return storedHex
        end,
        setValue = function(value)
          db[dbField] = value
        end,
      })
    end

    box:AddNoteRow({
      text = L.CHAT_NOTIFY_HINT or "",
      gap = 12,
    })
    box:AddActionRow({
      label = L.CHAT_NOTIFY_COPY_SECTION or "",
      description = L.CHAT_NOTIFY_COPY_HINT or "",
      buttonText = L.CHAT_NOTIFY_COPY_BUTTON or "",
      buttonWidth = 200,
      onClick = function()
        local success, resultKey = Toolbox.Chat.CopyDefaultChatToClipboard(30) -- 复制最近聊天结果
        local latestLocaleTable = Toolbox.L or {} -- 点击时最新本地化文案
        if success then
          if resultKey == "CHAT_COPY_SUCCESS" then
            Toolbox.Chat.PrintAddonMessage(latestLocaleTable.CHAT_NOTIFY_COPY_DONE or "")
          elseif resultKey == "CHAT_COPY_FALLBACK" then
            Toolbox.Chat.PrintAddonMessage(latestLocaleTable.CHAT_NOTIFY_COPY_FALLBACK or "")
          end
          return
        end
        Toolbox.Chat.PrintAddonMessage(latestLocaleTable[resultKey or "CHAT_COPY_ERR_FAILED"] or "")
      end,
    })
    box:AddNoteRow({
      text = L.CHAT_NOTIFY_COLORS_SECTION or "",
      fontObject = "GameFontNormal",
      gap = 8,
    })
    addColorMenuRow("prefixColor", "ffd700", "CHAT_NOTIFY_PREFIX_COLOR_LABEL")
    addColorMenuRow("contentColor", "ffffff", "CHAT_NOTIFY_CONTENT_COLOR_LABEL")
  end,
})
