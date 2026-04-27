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
---@param difficultyID number|nil 指定难度 ID；为空时走非难度特定兜底判定
---@return table[] bosses 首领列表
--- 返回格式：[{ name = string, encounterID = number }]
local function isEncounterKilledForDifficulty(encounterID, difficultyID)
  if type(encounterID) ~= "number" then
    return false
  end

  -- 优先走难度敏感判定：C_RaidLocks.IsEncounterComplete(mapID, dungeonEncounterID, difficultyID)
  -- mapID / dungeonEncounterID 由 EJ_GetEncounterInfo 返回（参照 Blizzard_EncounterJournal.lua）。
  if type(difficultyID) == "number"
      and C_RaidLocks and type(C_RaidLocks.IsEncounterComplete) == "function"
      and type(EJ_GetEncounterInfo) == "function" then
    local infoSuccess, _, _, _, _, _, _, dungeonEncounterID, mapID = pcall(EJ_GetEncounterInfo, encounterID)
    if infoSuccess
        and type(mapID) == "number" and mapID > 0
        and type(dungeonEncounterID) == "number" and dungeonEncounterID > 0 then
      local lockoutSuccess, isComplete = pcall(C_RaidLocks.IsEncounterComplete, mapID, dungeonEncounterID, difficultyID)
      if lockoutSuccess then
        return isComplete == true
      end
    end
  end

  -- 兜底：当难度敏感路径不可用时，退回 EncounterJournal 维度的完成判定。
  if C_EncounterJournal and type(C_EncounterJournal.IsEncounterComplete) == "function" then
    local completeSuccess, isComplete = pcall(C_EncounterJournal.IsEncounterComplete, encounterID)
    if completeSuccess then
      return isComplete == true
    end
  end

  return false
end

function Toolbox.EJ.GetKilledBosses(journalInstanceID, difficultyID)
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
      if isEncounterKilledForDifficulty(encounterID, difficultyID) then
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
-- 副本入口导航 API
-- ============================================================================

local dungeonEntranceCandidateCache = nil -- 可扫描入口地图候选缓存

--- 向列表追加不重复的地图 ID。
---@param mapIDList table 地图 ID 列表
---@param seenMapID table 已加入集合
---@param uiMapID number|nil 地图 ID
local function appendUniqueMapID(mapIDList, seenMapID, uiMapID)
  if type(uiMapID) ~= "number" or uiMapID <= 0 or seenMapID[uiMapID] then
    return
  end
  seenMapID[uiMapID] = true
  mapIDList[#mapIDList + 1] = uiMapID
end

--- 沿 C_Map.GetMapInfo 的 parentMapID 收集地图父链。
---@param mapIDList table 地图 ID 列表
---@param seenMapID table 已加入集合
---@param startMapID number|nil 起始地图 ID
local function appendMapParentChain(mapIDList, seenMapID, startMapID)
  if not C_Map or type(C_Map.GetMapInfo) ~= "function" then
    return
  end

  local currentMapID = startMapID -- 当前向上追溯的地图 ID
  local guardCount = 0 -- 防止异常父链死循环
  while type(currentMapID) == "number" and currentMapID > 0 and guardCount < 16 do
    guardCount = guardCount + 1
    appendUniqueMapID(mapIDList, seenMapID, currentMapID)

    local infoSuccess, mapInfo = pcall(C_Map.GetMapInfo, currentMapID)
    if not infoSuccess or type(mapInfo) ~= "table" or type(mapInfo.parentMapID) ~= "number" then
      return
    end
    if mapInfo.parentMapID == currentMapID or mapInfo.parentMapID <= 0 then
      return
    end
    currentMapID = mapInfo.parentMapID
  end
end

--- 递归收集某个地图树下的子地图。用于无法从副本 mapID 父链直接命中入口时的兜底扫描。
---@param mapIDList table 地图 ID 列表
---@param seenMapID table 已加入集合
---@param rootMapID number 根地图 ID
local function appendMapDescendants(mapIDList, seenMapID, rootMapID)
  if not C_Map or type(C_Map.GetMapChildrenInfo) ~= "function" then
    return
  end

  local childrenSuccess, childMapList = pcall(C_Map.GetMapChildrenInfo, rootMapID, nil, true)
  if not childrenSuccess or type(childMapList) ~= "table" then
    return
  end
  for _, childMapInfo in ipairs(childMapList) do
    local childMapID = type(childMapInfo) == "table" and childMapInfo.mapID or nil -- 子地图 ID
    appendUniqueMapID(mapIDList, seenMapID, childMapID)
  end
end

--- 构建副本入口扫描候选地图。
---@param journalInstanceID number 冒险指南副本 ID
---@param options table|nil 可选：candidateMapIDs 直接指定候选地图
---@return table mapIDList 地图 ID 列表
local function buildDungeonEntranceCandidateMapIDs(journalInstanceID, options)
  local mapIDList = {} -- 候选地图 ID 列表
  local seenMapID = {} -- 去重集合

  if type(options) == "table" and type(options.candidateMapIDs) == "table" then
    for _, uiMapID in ipairs(options.candidateMapIDs) do
      appendUniqueMapID(mapIDList, seenMapID, uiMapID)
    end
    return mapIDList
  end

  local journalMapID = getJournalMapID(journalInstanceID) -- 副本自身地图 ID
  appendMapParentChain(mapIDList, seenMapID, journalMapID)

  local worldMapFrame = _G.WorldMapFrame -- 世界地图框体
  if worldMapFrame and type(worldMapFrame.GetMapID) == "function" then
    local mapSuccess, currentMapID = pcall(worldMapFrame.GetMapID, worldMapFrame)
    if mapSuccess then
      appendMapParentChain(mapIDList, seenMapID, currentMapID)
    end
  end

  if C_Map and type(C_Map.GetFallbackWorldMapID) == "function" then
    local fallbackSuccess, fallbackMapID = pcall(C_Map.GetFallbackWorldMapID)
    if fallbackSuccess then
      appendUniqueMapID(mapIDList, seenMapID, fallbackMapID)
    end
  end

  if dungeonEntranceCandidateCache == nil then
    dungeonEntranceCandidateCache = {} -- 全局入口扫描候选缓存
    local cacheSeenMapID = {} -- 缓存去重集合
    local rootMapIDs = { 946, 947 } -- Cosmic / Azeroth 常见根地图；失败时静默跳过
    for _, rootMapID in ipairs(rootMapIDs) do
      appendUniqueMapID(dungeonEntranceCandidateCache, cacheSeenMapID, rootMapID)
      appendMapDescendants(dungeonEntranceCandidateCache, cacheSeenMapID, rootMapID)
    end
  end
  for _, cachedMapID in ipairs(dungeonEntranceCandidateCache) do
    appendUniqueMapID(mapIDList, seenMapID, cachedMapID)
  end

  return mapIDList
end

--- 构建可传给 UiMapPoint 的归一化坐标对象。
---@param x number 归一化 X 坐标
---@param y number 归一化 Y 坐标
---@return table position 坐标对象
local function createEntrancePosition(x, y)
  if type(CreateVector2D) == "function" then
    local vectorSuccess, vectorValue = pcall(CreateVector2D, x, y) -- 暴雪 Vector2D 构造结果
    if vectorSuccess and type(vectorValue) == "table" then
      return vectorValue
    end
  end

  return {
    x = x,
    y = y,
    GetXY = function(self)
      return self.x, self.y
    end,
  }
end

--- 从运行时冒险指南 API 精确查找副本入口；只接受 journalInstanceID 完全相同的记录。
---@param journalInstanceID number 冒险指南副本 ID
---@param options table|nil 可选：candidateMapIDs 直接指定候选地图
---@return table|nil entrance 入口信息
local function findRuntimeDungeonEntranceForJournalInstance(journalInstanceID, options)
  if not C_EncounterJournal or type(C_EncounterJournal.GetDungeonEntrancesForMap) ~= "function" then
    return nil
  end

  local mapIDList = buildDungeonEntranceCandidateMapIDs(journalInstanceID, options) -- 候选地图 ID 列表
  for _, uiMapID in ipairs(mapIDList) do
    local entranceSuccess, entranceList = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, uiMapID) -- 运行时入口列表
    if entranceSuccess and type(entranceList) == "table" then
      for _, runtimeEntrance in ipairs(entranceList) do
        local runtimeJournalInstanceID = type(runtimeEntrance) == "table" and tonumber(runtimeEntrance.journalInstanceID) or nil -- 入口所属副本 ID
        if runtimeJournalInstanceID == journalInstanceID and runtimeEntrance.position then
          runtimeEntrance.uiMapID = uiMapID
          runtimeEntrance.source = "runtime"
          return runtimeEntrance
        end
      end
    end
  end

  return nil
end

--- 获取 DB 契约导出的静态副本入口列表。
---@param journalInstanceID number 冒险指南副本 ID
---@return table|nil entranceList 静态入口列表
local function getStaticEntranceList(journalInstanceID)
  local staticData = Toolbox.Data and Toolbox.Data.InstanceEntrances -- DB 导出的静态入口数据
  local entrancesByJournalInstanceID = type(staticData) == "table" and staticData.entrances or nil -- 按副本 ID 索引的入口表
  local entranceList = type(entrancesByJournalInstanceID) == "table" and entrancesByJournalInstanceID[journalInstanceID] or nil -- 命中的入口列表
  if type(entranceList) ~= "table" then
    return nil
  end

  return entranceList
end

--- 将 DB 世界坐标入口转换为可设置 waypoint 的地图坐标入口。
---@param entranceRecord table DB 导出的入口记录
---@return table|nil entrance 入口信息
local function buildStaticDungeonEntrance(entranceRecord)
  if type(entranceRecord) ~= "table" then
    return nil
  end
  if not C_Map or type(C_Map.GetMapPosFromWorldPos) ~= "function" or type(CreateVector2D) ~= "function" then
    return nil
  end

  local worldMapID = tonumber(entranceRecord.WorldMapID) -- 世界坐标所属 WorldMapArea ID
  local worldX = tonumber(entranceRecord.WorldX) -- 世界坐标 X
  local worldY = tonumber(entranceRecord.WorldY) -- 世界坐标 Y
  local hintUiMapID = tonumber(entranceRecord.HintUiMapID) -- 坐标转换时使用的目标地图提示
  if not worldMapID or worldMapID <= 0 or not worldX or not worldY then
    return nil
  end

  local vectorSuccess, worldPosition = pcall(CreateVector2D, worldX, worldY) -- 暴雪世界坐标向量
  if not vectorSuccess or not worldPosition then
    return nil
  end

  local convertSuccess = false -- 坐标转换是否成功
  local targetUiMapID = nil -- 转换后的地图 ID
  local targetPosition = nil -- 转换后的归一化地图坐标
  if hintUiMapID and hintUiMapID > 0 then
    convertSuccess, targetUiMapID, targetPosition = pcall(C_Map.GetMapPosFromWorldPos, worldMapID, worldPosition, hintUiMapID)
  else
    convertSuccess, targetUiMapID, targetPosition = pcall(C_Map.GetMapPosFromWorldPos, worldMapID, worldPosition)
  end
  if not convertSuccess or type(targetUiMapID) ~= "number" or targetUiMapID <= 0 or not targetPosition then
    return nil
  end

  return {
    uiMapID = targetUiMapID,
    position = targetPosition,
    areaPoiID = tonumber(entranceRecord.AreaPoiID),
    name = entranceRecord.InstanceName,
    description = entranceRecord.AreaName,
    atlasName = nil,
    journalInstanceID = tonumber(entranceRecord.JournalInstanceID),
    source = "static",
    entranceID = tonumber(entranceRecord.EntranceID),
  }
end

--- 从 DB 契约导出的静态入口表精确查找副本入口。
---@param journalInstanceID number 冒险指南副本 ID
---@return table|nil entrance 入口信息
local function findStaticDungeonEntranceForJournalInstance(journalInstanceID)
  local entranceList = getStaticEntranceList(journalInstanceID) -- 静态入口候选列表
  if not entranceList then
    return nil
  end

  for _, entranceRecord in ipairs(entranceList) do
    local entranceInfo = buildStaticDungeonEntrance(entranceRecord) -- 转换后的入口信息
    if entranceInfo then
      return entranceInfo
    end
  end

  return nil
end

--- 从契约导出的副本入口表读取入口位置。
---@param journalInstanceID number 冒险指南副本 ID
---@param options table|nil 可选：candidateMapIDs 用于运行时入口扫描
---@return table|nil entrance 入口信息，含 uiMapID / position / areaPoiID / name / journalInstanceID
function Toolbox.EJ.FindDungeonEntranceForJournalInstance(journalInstanceID, options)
  if type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
    return nil
  end

  local staticEntrance = findStaticDungeonEntranceForJournalInstance(journalInstanceID) -- DB 静态精确入口
  if staticEntrance then
    return staticEntrance
  end

  local entranceData = Toolbox.Data and Toolbox.Data.NavigationInstanceEntrances -- 导出的副本入口数据
  local entrancesByJournalInstanceID = type(entranceData) == "table" and entranceData.entrancesByJournalInstanceID or nil -- 按副本 ID 索引
  local exportedEntrance = type(entrancesByJournalInstanceID) == "table" and entrancesByJournalInstanceID[journalInstanceID] or nil -- 命中的入口记录
  if type(exportedEntrance) == "table" then
    local targetUiMapID = tonumber(exportedEntrance.TargetUiMapID) -- 外部目标地图
    local targetX = tonumber(exportedEntrance.TargetX) -- 外部目标 X
    local targetY = tonumber(exportedEntrance.TargetY) -- 外部目标 Y
    if targetUiMapID and targetUiMapID > 0 and targetX and targetY and targetX >= 0 and targetX <= 1 and targetY >= 0 and targetY <= 1 then
      return {
        source = "exported",
        uiMapID = targetUiMapID,
        position = createEntrancePosition(targetX, targetY),
        entranceID = exportedEntrance.EntranceID,
        areaPoiID = exportedEntrance.AreaPoiID,
        name = exportedEntrance.Name_lang or exportedEntrance.AreaPoiName_lang,
        journalInstanceID = exportedEntrance.JournalInstanceID or journalInstanceID,
        instanceMapID = exportedEntrance.InstanceMapID,
        worldMapID = exportedEntrance.WorldMapID,
        worldX = exportedEntrance.WorldX,
        worldY = exportedEntrance.WorldY,
        worldZ = exportedEntrance.WorldZ,
      }
    end
  end

  return findRuntimeDungeonEntranceForJournalInstance(journalInstanceID, options)
end

--- 打开世界地图到指定地图 ID。优先使用 OpenWorldMap，回退到 ToggleWorldMap + WorldMapFrame:SetMapID。
---@param uiMapID number 地图 ID
local function openWorldMapToMap(uiMapID)
  if type(uiMapID) ~= "number" or uiMapID <= 0 then
    return
  end

  if type(OpenWorldMap) == "function" then
    local openSuccess = pcall(OpenWorldMap, uiMapID)
    if openSuccess then
      local worldMapFrame = _G.WorldMapFrame -- 世界地图框体
      if worldMapFrame and type(worldMapFrame.SetMapID) == "function" then
        pcall(worldMapFrame.SetMapID, worldMapFrame, uiMapID)
      end
      return
    end
  end

  if type(ToggleWorldMap) == "function" then
    pcall(ToggleWorldMap)
  end

  local worldMapFrame = _G.WorldMapFrame -- 世界地图框体
  if worldMapFrame and type(worldMapFrame.SetMapID) == "function" then
    pcall(worldMapFrame.SetMapID, worldMapFrame, uiMapID)
  end
end

--- 导航到指定副本入口：打开地图、设置用户 waypoint，并启用系统追踪。
---@param journalInstanceID number 冒险指南副本 ID
---@param options table|nil 可选：candidateMapIDs 用于测试或调用方传入更小地图范围
---@return boolean success 是否成功
---@return table|string result 成功时为入口信息；失败时为原因：not_found / waypoint_api_missing / waypoint_forbidden / point_api_missing / set_failed
function Toolbox.EJ.NavigateToDungeonEntrance(journalInstanceID, options)
  local entranceInfo = Toolbox.EJ.FindDungeonEntranceForJournalInstance(journalInstanceID, options) -- 命中的入口信息
  if not entranceInfo then
    return false, "not_found"
  end

  if not C_Map or type(C_Map.CanSetUserWaypointOnMap) ~= "function" or type(C_Map.SetUserWaypoint) ~= "function" then
    return false, "waypoint_api_missing"
  end

  local canSetSuccess, canSetWaypoint = pcall(C_Map.CanSetUserWaypointOnMap, entranceInfo.uiMapID)
  if not canSetSuccess or canSetWaypoint ~= true then
    return false, "waypoint_forbidden"
  end

  if not UiMapPoint or type(UiMapPoint.CreateFromVector2D) ~= "function" then
    return false, "point_api_missing"
  end

  local pointSuccess, mapPoint = pcall(UiMapPoint.CreateFromVector2D, entranceInfo.uiMapID, entranceInfo.position)
  if not pointSuccess or not mapPoint then
    return false, "point_api_missing"
  end

  openWorldMapToMap(entranceInfo.uiMapID)

  local setSuccess = pcall(C_Map.SetUserWaypoint, mapPoint)
  if not setSuccess then
    return false, "set_failed"
  end

  if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end

  return true, entranceInfo
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
