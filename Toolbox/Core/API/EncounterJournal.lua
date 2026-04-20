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

--- 读取 journalInstanceID 对应的地图 ID（优先运行时 API，静态表兜底）。
---@param journalInstanceID number 冒险手册副本 ID
---@return number|nil mapID
local function getJournalMapID(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return nil
  end

  -- Blizzard AdventureGuideUtil 使用 select(10, EJ_GetInstanceInfo(journalInstanceID)) 读取 mapID。
  if type(EJ_GetInstanceInfo) == "function" then
    local infoSuccess, _, _, _, _, _, _, _, _, _, mapID = pcall(EJ_GetInstanceInfo, journalInstanceID)
    if infoSuccess and type(mapID) == "number" and mapID > 0 then
      return mapID
    end
  end

  local mapData = Toolbox.Data and Toolbox.Data.InstanceMapIDs
  local staticMapID = type(mapData) == "table" and mapData[journalInstanceID] or nil
  if type(staticMapID) == "number" and staticMapID > 0 then
    return staticMapID
  end

  return nil
end

--- 读取 journalInstanceID 对应的副本名称（用于 mapID 不可用时兜底）。
---@param journalInstanceID number 冒险手册副本 ID
---@return string|nil instanceName
local function getJournalInstanceName(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return nil
  end

  if type(EJ_GetInstanceInfo) ~= "function" then
    return nil
  end

  local infoSuccess, instanceName = pcall(EJ_GetInstanceInfo, journalInstanceID)
  if infoSuccess and type(instanceName) == "string" and instanceName ~= "" then
    return instanceName
  end

  return nil
end

--- 将地图 ID 映射到 journalInstanceID（运行时权威路径）。
---@param mapID number 地图 ID（GetSavedInstanceInfo 第14个返回值）
---@return number|nil journalInstanceID
local function mapGameMapIDToJournalID(mapID)
  if type(mapID) ~= "number" then
    return nil
  end

  if C_EncounterJournal and type(C_EncounterJournal.GetInstanceForGameMap) == "function" then
    local mapSuccess, journalInstanceID = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
    if mapSuccess and type(journalInstanceID) == "number" and journalInstanceID > 0 then
      return journalInstanceID
    end
  end

  return nil
end

local function doesSavedInstanceNameMatch(savedInstanceName, targetInstanceName)
  if type(savedInstanceName) ~= "string" or savedInstanceName == "" then
    return false
  end
  if type(targetInstanceName) ~= "string" or targetInstanceName == "" then
    return false
  end
  return savedInstanceName == targetInstanceName
end

--- 判断 SavedInstances 条目是否属于目标 journalInstanceID。
---@param savedMapID number SavedInstances 的 instanceId（mapID）
---@param savedInstanceName string|nil SavedInstances 副本名
---@param journalInstanceID number 目标冒险手册副本 ID
---@param targetMapID number|nil 目标副本 mapID（可选）
---@param targetInstanceName string|nil 目标副本名（可选）
---@return boolean
local function isSavedInstanceForJournal(savedMapID, savedInstanceName, journalInstanceID, targetMapID, targetInstanceName)
  if type(journalInstanceID) ~= "number" then
    return false
  end

  if type(savedMapID) == "number" and savedMapID > 0 then
    local runtimeJournalID = mapGameMapIDToJournalID(savedMapID)
    if type(runtimeJournalID) == "number" then
      return runtimeJournalID == journalInstanceID
    end

    if type(targetMapID) == "number" and targetMapID > 0 then
      return savedMapID == targetMapID
    end

    -- 运行时 API 不可用时，保留静态表同键对齐兜底（禁止 mapID 反向遍历，避免歧义）。
    local mapData = Toolbox.Data and Toolbox.Data.InstanceMapIDs
    if type(mapData) == "table" and mapData[journalInstanceID] == savedMapID then
      return true
    end
  end

  -- mapID 缺失或不可判定时，按副本名称兜底匹配。
  return doesSavedInstanceNameMatch(savedInstanceName, targetInstanceName)
end

--- 格式化重置剩余时间（用于 tooltip 文本）。
---@param seconds number
---@return string
local function formatResetDuration(seconds)
  local loc = Toolbox.L or {}
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if days > 0 then
    return string.format(loc.EJ_LOCKOUT_TIME_DAY_HOUR_FMT or "%dd %dh", days, hours)
  end
  if hours > 0 then
    return string.format(loc.EJ_LOCKOUT_TIME_HOUR_MIN_FMT or "%dh %dm", hours, mins)
  end
  return string.format(loc.EJ_LOCKOUT_TIME_MIN_FMT or "%dm", mins)
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
  local targetMapID = getJournalMapID(journalInstanceID)
  local targetInstanceName = getJournalInstanceName(journalInstanceID)

  for i = 1, numSaved do
    -- 安全调用（防止 API 变更）
    -- 返回值：name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig,
    --         isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
    local success, name, lockoutId, reset, difficulty, locked, extended,
          instanceIDMostSig, isRaid, maxPlayers, difficultyName,
          numEncounters, encounterProgress, extendDisabled, instanceId = pcall(GetSavedInstanceInfo, i)

    local mappedSuccess = isSavedInstanceForJournal(instanceId, name, journalInstanceID, targetMapID, targetInstanceName)
    -- 只添加未过期的锁定（reset > 0 表示还有剩余时间）
    if mappedSuccess and reset and reset > 0 then
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

  return lockouts
end

--- 获取冒险手册当前选中的难度 ID（来自右侧难度下拉）。
---@return number|nil difficultyID
function Toolbox.EJ.GetSelectedDifficultyID()
  if type(EJ_GetDifficulty) ~= "function" then
    return nil
  end
  local ok, difficultyID = pcall(EJ_GetDifficulty)
  if ok and type(difficultyID) == "number" then
    return difficultyID
  end
  return nil
end

--- 获取指定副本在指定难度下的锁定信息（精确匹配难度 ID）。
---@param journalInstanceID number
---@param difficultyID number|nil
---@return table|nil lockout
function Toolbox.EJ.GetLockoutForInstanceAndDifficulty(journalInstanceID, difficultyID)
  if type(journalInstanceID) ~= "number" then
    return nil
  end
  local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(journalInstanceID)
  if #lockouts == 0 then
    return nil
  end
  if type(difficultyID) == "number" then
    for _, lockout in ipairs(lockouts) do
      if lockout and lockout.difficultyID == difficultyID then
        return lockout
      end
    end
    return nil
  end
  if #lockouts == 1 then
    return lockouts[1]
  end
  return nil
end

--- 汇总当前角色所有已锁定副本（按剩余时间升序）。
---@return table[] lockouts
--- 返回格式：[{ instanceName=string, difficultyName=string, resetTime=number, isRaid=boolean, encounterProgress=number, numEncounters=number, isExtended=boolean }]
function Toolbox.EJ.GetSavedInstanceLockoutSummary()
  if not GetNumSavedInstances or not GetSavedInstanceInfo then
    return {}
  end

  local lockouts = {}
  local savedCount = GetNumSavedInstances()
  for idx = 1, savedCount do
    local ok, instanceName, lockoutId, resetTime, difficultyId, isLocked, isExtended,
      instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters,
      encounterProgress = pcall(GetSavedInstanceInfo, idx)
    -- Retail 下部分有效 CD 记录会出现 isLocked=false（尤其是非实例 ID 绑定场景），
    -- 这里以 resetTime>0 作为“仍有锁定信息”的主判据，避免摘要漏报。
    if ok and resetTime and resetTime > 0 then
      lockouts[#lockouts + 1] = {
        instanceName = instanceName or "",
        difficultyName = difficultyName or "",
        resetTime = resetTime or 0,
        isRaid = isRaid == true,
        encounterProgress = encounterProgress or 0,
        numEncounters = numEncounters or 0,
        isExtended = isExtended == true,
      }
    end
  end

  table.sort(lockouts, function(left, right)
    local leftReset = left.resetTime or 0
    local rightReset = right.resetTime or 0
    if leftReset ~= rightReset then
      return leftReset < rightReset
    end
    local leftName = left.instanceName or ""
    local rightName = right.instanceName or ""
    if leftName ~= rightName then
      return leftName < rightName
    end
    local leftDifficulty = left.difficultyName or ""
    local rightDifficulty = right.difficultyName or ""
    return leftDifficulty < rightDifficulty
  end)

  return lockouts
end

--- 构建“当前副本锁定”tooltip 行文本。
---@param maxLines number|nil 最多行数，默认 8，上限 30
---@return string[] lines
---@return number overflow 未显示的其余条数
function Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(maxLines)
  local lineLimit = tonumber(maxLines) or 8
  if lineLimit < 1 then
    lineLimit = 1
  end
  if lineLimit > 30 then
    lineLimit = 30
  end

  local loc = Toolbox.L or {}
  local allLockouts = Toolbox.EJ.GetSavedInstanceLockoutSummary()
  local lineCount = math.min(#allLockouts, lineLimit)
  local lines = {}

  for idx = 1, lineCount do
    local lockout = allLockouts[idx]
    local instanceName = lockout.instanceName or ""
    local difficultyName = lockout.difficultyName or ""
    local resetText = formatResetDuration(lockout.resetTime or 0)
    local lineText
    if lockout.isRaid and (lockout.numEncounters or 0) > 0 then
      lineText = string.format(
        "%s · %s %d/%d · %s",
        instanceName,
        difficultyName,
        lockout.encounterProgress or 0,
        lockout.numEncounters or 0,
        resetText
      )
    else
      lineText = string.format("%s · %s · %s", instanceName, difficultyName, resetText)
    end
    if lockout.isExtended then
      lineText = lineText .. " " .. (loc.EJ_LOCKOUT_EXTENDED or "(Extended)")
    end
    lines[#lines + 1] = lineText
  end

  return lines, math.max(0, #allLockouts - lineCount)
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
  local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
  if not encounterJournalFrame then
    return false
  end

  local journalIsOpen = true -- 冒险手册是否打开
  if encounterJournalFrame.IsShown then
    local shownSuccess, shownValue = pcall(function() return encounterJournalFrame:IsShown() end)
    if shownSuccess then
      journalIsOpen = shownValue == true
    end
  end
  if not journalIsOpen then
    return false
  end

  local dungeonTabButton = encounterJournalFrame.dungeonsTab -- 地下城页签按钮
  local raidTabButton = encounterJournalFrame.raidsTab -- 团队副本页签按钮

  local dungeonTabID = dungeonTabButton and dungeonTabButton.GetID and dungeonTabButton:GetID() or nil -- 地下城页签 ID
  local raidTabID = raidTabButton and raidTabButton.GetID and raidTabButton:GetID() or nil -- 团队副本页签 ID
  if type(dungeonTabID) ~= "number" and type(raidTabID) ~= "number" then
    return false
  end

  local selectedRootTabID = encounterJournalFrame.selectedTab -- 当前选中的根页签 ID
  if type(selectedRootTabID) ~= "number" then
    return false
  end

  return selectedRootTabID == dungeonTabID or selectedRootTabID == raidTabID
end

-- ============================================================================
-- 坐骑查询 API
-- ============================================================================

local mountItemSetCache = {}

--- 获取副本坐骑掉落 itemID 集合（集合键为 itemID，值为 true）。
---@param journalInstanceID number
---@return table|nil itemSet
function Toolbox.EJ.GetMountItemSetForInstance(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return nil
  end
  if mountItemSetCache[journalInstanceID] then
    return mountItemSetCache[journalInstanceID]
  end
  local drops = Toolbox.Data and Toolbox.Data.MountDrops
  local itemList = drops and drops[journalInstanceID]
  if type(itemList) ~= "table" then
    return nil
  end
  local itemSet = {}
  for _, itemID in ipairs(itemList) do
    if type(itemID) == "number" then
      itemSet[itemID] = true
    end
  end
  mountItemSetCache[journalInstanceID] = itemSet
  return itemSet
end

--- 检查副本是否掉落坐骑
---@param journalInstanceID number
---@return boolean
function Toolbox.EJ.HasMountDrops(journalInstanceID)
  return Toolbox.EJ.GetMountItemSetForInstance(journalInstanceID) ~= nil
end
