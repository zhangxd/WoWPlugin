--[[
  Toolbox — 根命名空间（须最先加载）。
  使用独立全局 ToolboxAddon 存根；若其它脚本覆盖 _G.Toolbox，仍可通过 ToolboxAddon 与 Toolbox_NamespaceEnsure 恢复。
]]

ToolboxAddon = ToolboxAddon or {}
Toolbox = ToolboxAddon
Toolbox.ADDON_NAME = "Toolbox"
Toolbox.DB = Toolbox.DB or {}
_G.ToolboxAddon = ToolboxAddon
_G.Toolbox = ToolboxAddon

-- 在事件/回调入口调用，将 _G.Toolbox 指回本插件
function Toolbox_NamespaceEnsure()
  local T = _G.ToolboxAddon
  if T then
    _G.Toolbox = T
  end
end
