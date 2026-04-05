--[[
  兼容层：旧版「微型菜单面板」模块已并入 modules.mover。
  斜杠仍保留部分子命令名，委托或提示；`Toolbox.MicroMenuPanels.RefreshHooks` 委托 Mover 刷新挂钩。
]]

Toolbox.MicroMenuPanels = Toolbox.MicroMenuPanels or {}

--- 与旧版一致：重新尝试懒加载 Hook 与当前可见面板。
function Toolbox.MicroMenuPanels.RefreshHooks()
  if Toolbox.Mover and Toolbox.Mover.BlizzardPanelsRefresh then
    Toolbox.Mover.BlizzardPanelsRefresh()
  end
end

--- 旧 API：曾用于追加额外顶层 Frame；已移除，始终失败。
---@return boolean, string|nil
function Toolbox.MicroMenuPanels.AddExtraFrame(_name)
  return false, "removed"
end

--- 旧 API：曾用于覆盖额外 Frame 名单；已无效果。
function Toolbox.MicroMenuPanels.SetExtraFrameNamesFromText(_text)
end
