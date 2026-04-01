--[[
  模块 chat_notify：加载完成那一行聊天提示的策略与设置（是否输出、文案键、旧档迁移）。
  实际输出经 Core/Chat.lua（Toolbox.Chat）；调用时机由 Core/Bootstrap.lua 在 ADDON_LOADED 主流程末尾触发。
]]

Toolbox.ChatNotify = Toolbox.ChatNotify or {}

-- 兼容旧存档 global.notifyLoadComplete；新逻辑只看 modules.chat_notify.enabled
local function shouldPrint()
  local g = Toolbox.DB.GetGlobal()
  if g.notifyLoadComplete == false then
    return false
  end
  local m = Toolbox.DB.GetModule("chat_notify")
  return m.enabled ~= false
end

function Toolbox.ChatNotify.PrintLoadComplete()
  Toolbox_NamespaceEnsure()
  if not shouldPrint() then
    return
  end
  local L = Toolbox.L
  local body = L.LOAD_COMPLETE_MSG or "Toolbox"
  local ver = Toolbox.Chat.GetAddOnMetadata(Toolbox.ADDON_NAME, "Version")
  if ver and ver ~= "" then
    body = body .. "  |cffffd100v" .. ver .. "|r"
  end
  Toolbox.Chat.PrintAddonMessage(body)
end

Toolbox.RegisterModule({
  id = "chat_notify",
  nameKey = "MODULE_CHAT_NOTIFY",
  OnModuleLoad = function() end,
  OnModuleEnable = function() end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = Toolbox.DB.GetModule("chat_notify")
    local y = 0

    local en = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    en:SetPoint("TOPLEFT", 0, y)
    en.Text:SetText(L.CHAT_NOTIFY_ENABLE)
    en:SetChecked(db.enabled ~= false)
    en:SetScript("OnClick", function(self)
      db.enabled = self:GetChecked()
    end)
    y = y - 36

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.CHAT_NOTIFY_HINT)
    y = y - 40

    box.realHeight = math.abs(y) + 8
  end,
})
