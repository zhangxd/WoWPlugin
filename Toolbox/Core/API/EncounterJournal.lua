--[[
  冒险指南（领域对外 API）：封装 WoW 原生 API，提供高层查询接口。
  职责：
    1. 锁定查询：GetAllLockoutsForInstance - 查询副本所有难度的锁定信息
    2. 首领查询：GetKilledBosses - 查询副本已击杀的首领列表
    3. UI 状态查询：IsRaidOrDungeonInstanceListTab - 检查当前是否在副本列表标签页
    4. 坐骑查询：HasMountDrops - 检查副本是否掉落坐骑
]]

Toolbox.EJ = Toolbox.EJ or {}

-- ============================================================================
-- 内部辅助函数
-- ============================================================================

--- 将 instanceID + difficultyID 映射到 journalInstanceID
---@param instanceID number 副本 ID（来自 GetSavedInstanceInfo 第14个返回值）
---@param difficultyID number 难度 ID
---@return number|nil journalInstanceID
local function mapInstanceIDToJournalID(instanceID, difficultyID)
  local mapData = Toolbox.Data and Toolbox.Data.InstanceMapIDs
  if not mapData then return nil end

  -- InstanceMapIDs 的结构是 [journalInstanceID] = mapID
  -- 我们需要反向查找：给定 instanceID (mapID)，找到对应的 journalInstanceID
  for journalID, mapID in pairs(mapData) do
    if mapID == instanceID then
      return journalID
    end
  end

  return nil
end

-- ============================================================================
-- 锁定查询 API
-- ============================================================================

--- 获取副本的所有难度锁定信息
---@param journalInstanceID number 冒险指南副本 ID
---@return table[] lockouts 锁定列表
--- 返回格式：[{
---   difficultyID = number,
---   difficultyName = string,
---   resetTime = number,        -- 剩余秒数
---   encounterProgress = number, -- 已击杀数
---   numEncounters = number,     -- 总首领数
---   isRaid = boolean,
---   isExtended = boolean
--- }]
function Toolbox.EJ.GetAllLockoutsForInstance(journalInstanceID)
  -- 参数校验
  if type(journalInstanceID) ~= "number" then
    return {}
  end

  -- API 可用性检查
  if not GetNumSavedInstances or not GetSavedInstanceInfo then
    return {}
  end

  local lockouts = {}
  local numSaved = GetNumSavedInstances()

  for i = 1, numSaved do
    -- 安全调用（防止 API 变更）
    -- 返回值：name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig,
    --         isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
    local success, name, lockoutId, reset, difficulty, locked, extended,
          instanceIDMostSig, isRaid, maxPlayers, difficultyName,
          numEncounters, encounterProgress, extendDisabled, instanceId = pcall(GetSavedInstanceInfo, i)

    if success and instanceId then
      local mappedJID = mapInstanceIDToJournalID(instanceId, difficulty)
      -- 只添加未过期的锁定（reset > 0 表示还有剩余时间）
      if mappedJID == journalInstanceID and reset and reset > 0 then
        table.insert(lockouts, {
          difficultyID = difficulty,
          difficultyName = difficultyName or "Unknown",
          resetTime = reset or 0,
          encounterProgress = encounterProgress or 0,
          numEncounters = numEncounters or 0,
          isRaid = isRaid == true,
          isExtended = extended == true
        })
      end
    end
  end

  return lockouts
end

-- ============================================================================
-- 首领查询 API
-- ============================================================================

--- 获取副本已击杀的首领列表
---@param journalInstanceID number
---@return table[] bosses 首领列表
--- 返回格式：[{ name = string, encounterID = number }]
function Toolbox.EJ.GetKilledBosses(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return {}
  end

  if not EJ_SelectInstance or not EJ_GetNumEncounters or not EJ_GetEncounterInfoByIndex then
    return {}
  end

  local killed = {}

  -- 保存当前选中的 EJ 副本，避免本查询影响 UI 上下文
  local previousInstanceID = nil
  if type(EJ_GetCurrentInstance) == "function" then
    local currentSuccess, currentID = pcall(EJ_GetCurrentInstance)
    if currentSuccess and type(currentID) == "number" then
      previousInstanceID = currentID
    end
  end

  -- 选择副本
  local success = pcall(EJ_SelectInstance, journalInstanceID)
  if not success then
    return {}
  end

  -- 遍历首领
  local numEncounters = EJ_GetNumEncounters()
  for i = 1, numEncounters do
    local name, _, encounterID = EJ_GetEncounterInfoByIndex(i)
    if name and encounterID then
      -- 检查是否已击杀
      local isKilled = false
      if C_EncounterJournal and C_EncounterJournal.GetEncounterProgress then
        local progressSuccess, progress = pcall(C_EncounterJournal.GetEncounterProgress, encounterID)
        if progressSuccess and progress then
          isKilled = true
        end
      end

      if isKilled then
        table.insert(killed, {
          name = name,
          encounterID = encounterID
        })
      end
    end
  end

  -- 恢复调用前的选中上下文，避免对用户当前 EJ 页面造成副作用
  if previousInstanceID and previousInstanceID ~= journalInstanceID then
    pcall(EJ_SelectInstance, previousInstanceID)
  end

  return killed
end

-- ============================================================================
-- UI 状态查询 API
-- ============================================================================

--- 检查当前是否在副本列表标签页
---@return boolean
function Toolbox.EJ.IsRaidOrDungeonInstanceListTab()
  local ej = _G.EncounterJournal
  if not ej or not ej.instanceSelect then
    return false
  end

  -- 检查 instanceSelect 是否可见
  if not ej.instanceSelect:IsVisible() then
    return false
  end

  -- 检查 ScrollBox 是否显示
  local scrollBox = ej.instanceSelect.ScrollBox or ej.instanceSelect.scrollBox
  if scrollBox and scrollBox.IsShown then
    local success, shown = pcall(function() return scrollBox:IsShown() end)
    if success and not shown then
      return false
    end
  end

  return true
end

-- ============================================================================
-- 坐骑查询 API
-- ============================================================================

--- 检查副本是否掉落坐骑
---@param journalInstanceID number
---@return boolean
function Toolbox.EJ.HasMountDrops(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return false
  end

  local drops = Toolbox.Data and Toolbox.Data.MountDrops
  return drops ~= nil and drops[journalInstanceID] ~= nil
end
