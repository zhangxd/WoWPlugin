--[[
  navigation 模块共享命名空间。
  子文件通过 Toolbox.NavigationModule 访问模块 DB、启用状态与内部组件。
]]

Toolbox.NavigationModule = Toolbox.NavigationModule or {}

local MODULE_ID = "navigation"

--- 获取 navigation 模块存档。
---@return table
function Toolbox.NavigationModule.GetModuleDb()
  return Toolbox.Config.GetModule(MODULE_ID)
end

--- 判断 navigation 模块当前是否启用。
---@return boolean
function Toolbox.NavigationModule.IsEnabled()
  local moduleDb = Toolbox.NavigationModule.GetModuleDb() -- navigation 模块存档
  return moduleDb.enabled ~= false
end
