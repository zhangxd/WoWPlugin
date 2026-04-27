--[[
  冒险指南内部共享状态（encounter_journal）。
  仅供 Modules/EncounterJournal/*.lua 私有实现文件复用，不作为对外 API。
]]

Toolbox.EncounterJournalInternal = Toolbox.EncounterJournalInternal or {}

local Internal = Toolbox.EncounterJournalInternal -- 冒险指南内部命名空间
local MODULE_ID = "encounter_journal" -- 模块 ID

Internal.MODULE_ID = MODULE_ID
Internal.Runtime = Toolbox.Runtime
Internal.CreateFrame = Internal.Runtime.CreateFrame
Internal.microTooltipAppendState = Internal.microTooltipAppendState or setmetatable({}, { __mode = "k" })
Internal.scrollBoxCache = Internal.scrollBoxCache or {
  ref = nil,
  lastUpdate = 0,
  ttl = 5,
}
Internal.listNavigationState = Internal.listNavigationState or {
  focusedJournalInstanceID = nil,
  hoveredJournalInstanceID = nil,
}

--- 读取模块存档。
---@return table
function Internal.GetModuleDb()
  Toolbox.Config.Init()
  return Toolbox.Config.GetModule(MODULE_ID)
end

--- 检查模块是否启用。
---@return boolean
function Internal.IsModuleEnabled()
  return Toolbox.Config.GetModule(MODULE_ID).enabled ~= false
end

--- 检查列表“仅坐骑”筛选是否启用。
---@return boolean
function Internal.IsMountFilterChecked()
  return Internal.GetModuleDb().mountFilterEnabled == true
end

--- 检查列表锁定叠加是否启用。
---@return boolean
function Internal.IsOverlayEnabled()
  return Internal.IsModuleEnabled() and Internal.GetModuleDb().lockoutOverlayEnabled ~= false
end

--- 检查副本列表图钉是否常驻显示。
---@return boolean
function Internal.IsListPinAlwaysVisible()
  return Internal.IsModuleEnabled() and Internal.GetModuleDb().listPinAlwaysVisible == true
end

--- 检查任务页签是否启用。
---@return boolean
function Internal.IsQuestlineTreeEnabled()
  local moduleDb = Internal.GetModuleDb() -- 模块存档
  return Internal.IsModuleEnabled() and moduleDb.questlineTreeEnabled ~= false
end

--- 格式化重置时间。
---@param seconds number
---@return string
function Internal.FormatResetTime(seconds)
  local localeTable = Toolbox.L or {} -- 本地化文案
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if days > 0 then
    return string.format(localeTable.EJ_LOCKOUT_TIME_DAY_HOUR_FMT or "%dd %dh", days, hours)
  elseif hours > 0 then
    return string.format(localeTable.EJ_LOCKOUT_TIME_HOUR_MIN_FMT or "%dh %dm", hours, mins)
  end
  return string.format(localeTable.EJ_LOCKOUT_TIME_MIN_FMT or "%dm", mins)
end

--- 从 elementData 提取 journalInstanceID。
---@param elementData table|nil
---@return number|nil
function Internal.GetJournalInstanceID(elementData)
  if type(elementData) ~= "table" then
    return nil
  end
  local instId = elementData.instanceID or elementData.journalInstanceID -- 当前实例 ID
  if type(instId) == "number" then
    return instId
  end
  local nested = elementData.data or elementData.elementData or elementData.node -- 嵌套节点数据
  if type(nested) == "table" and nested ~= elementData then
    local nestedId = nested.instanceID or nested.journalInstanceID -- 嵌套实例 ID
    if type(nestedId) == "number" then
      return nestedId
    end
  end
  return nil
end

--- 读取当前 ScrollBox。
---@return table|nil
function Internal.GetCurrentScrollBox()
  local cache = Internal.scrollBoxCache -- ScrollBox 缓存
  local currentTime = GetTime()
  if cache.ref and (currentTime - cache.lastUpdate) < cache.ttl then
    return cache.ref
  end
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  if journalFrame and journalFrame.instanceSelect then
    cache.ref = journalFrame.instanceSelect.ScrollBox or journalFrame.instanceSelect.scrollBox
    cache.lastUpdate = currentTime
  end
  return cache.ref
end

--- 清空 ScrollBox 缓存。
function Internal.ResetScrollBoxCache()
  Internal.scrollBoxCache.ref = nil
  Internal.scrollBoxCache.lastUpdate = 0
end

--- 读取当前列表交互状态。
---@return table
function Internal.GetListNavigationState()
  return Internal.listNavigationState
end

--- 清空当前列表交互状态。
function Internal.ResetListNavigationState()
  Internal.listNavigationState.focusedJournalInstanceID = nil
  Internal.listNavigationState.hoveredJournalInstanceID = nil
end

--- 获取详情信息面板。
---@return table|nil
function Internal.GetEncounterInfoFrame()
  local journalFrame = _G.EncounterJournal -- 冒险手册根面板
  local encounterFrame = journalFrame and journalFrame.encounter -- 首领详情面板
  return encounterFrame and encounterFrame.info or nil
end
