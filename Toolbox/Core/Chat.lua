--[[
  聊天领域门面（Toolbox.Chat）：默认聊天框输出、插件 TOC 元数据读取。
  凡面向玩家的聊天框展示须经本文件 API；业务逻辑放在各模块，勿在此处堆存档分支。
]]

Toolbox.Chat = Toolbox.Chat or {}

-- 正式服已移除全局 GetAddOnMetadata，优先使用 C_AddOns（10.1+）
function Toolbox.Chat.GetAddOnMetadata(name, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, field)
    if ok then
      return v
    end
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(name, field)
  end
  return nil
end

-- 在默认聊天框输出一行；正文 body 可含颜色码；前缀为绿色 [插件名]（Toolbox.ADDON_NAME）
function Toolbox.Chat.PrintAddonMessage(body)
  if not body or body == "" then
    return
  end
  Toolbox_NamespaceEnsure()
  local addon = Toolbox.ADDON_NAME or "Toolbox"
  local prefix = string.format("|cff00ff00[%s]|r ", addon)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then
    f:AddMessage(prefix .. body)
  end
end
