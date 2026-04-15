--[[
  quest 模块内部共享状态。
  仅供 Modules/Quest/*.lua 私有实现文件复用，不作为对外 API。
]]

Toolbox.QuestInternal = Toolbox.QuestInternal or {}

local Internal = Toolbox.QuestInternal -- quest 模块内部命名空间
local MODULE_ID = "quest" -- 模块 ID

Internal.MODULE_ID = MODULE_ID
Internal.Runtime = Toolbox.Runtime
Internal.CreateFrame = Internal.Runtime.CreateFrame

--- 读取模块存档。
---@return table
function Internal.GetModuleDb()
  Toolbox.Config.Init()
  return Toolbox.Config.GetModule(MODULE_ID)
end

--- 检查模块是否启用。
---@return boolean
function Internal.IsModuleEnabled()
  return Internal.GetModuleDb().enabled ~= false
end

--- 检查任务视图是否启用。
---@return boolean
function Internal.IsQuestlineTreeEnabled()
  local moduleDb = Internal.GetModuleDb() -- 模块存档
  return Internal.IsModuleEnabled() and moduleDb.questlineTreeEnabled ~= false
end
