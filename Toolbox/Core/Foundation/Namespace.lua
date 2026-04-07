--[[
  Toolbox — 根命名空间（须最先加载）。
  使用独立全局 ToolboxAddon 存根；若其它脚本覆盖 _G.Toolbox，仍可通过 ToolboxAddon 与 Toolbox_NamespaceEnsure 恢复。
]]

-- 使用更安全的初始化方式：检查现有全局变量是否为本插件所有
local _addonStub = _G.ToolboxAddon
if not _addonStub or type(_addonStub) ~= "table" or _addonStub.ADDON_NAME ~= "Toolbox" then
  _addonStub = { ADDON_NAME = "Toolbox" }
  _G.ToolboxAddon = _addonStub
end

Toolbox = _addonStub
Toolbox.Config = Toolbox.Config or {}
_G.Toolbox = Toolbox

-- 在事件/回调入口调用，将 _G.Toolbox 指回本插件
function Toolbox_NamespaceEnsure()
  local T = _G.ToolboxAddon
  if T and type(T) == "table" and T.ADDON_NAME == "Toolbox" then
    _G.Toolbox = T
  end
end
