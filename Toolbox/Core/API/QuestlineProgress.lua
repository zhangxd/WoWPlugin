--[[
  任务线进度领域 API（Toolbox.Questlines）。
  设计目标：
    1. 兼容 schema v3/v4 的任务线静态数据结构。
    2. 提供 strict 校验、任务页签查询模型与任务详情查询接口。
    3. 字段名与 wow.db 对齐：ID/UiMapID；任务线名称由运行时 API 或注释回溯兜底。
]]

Toolbox.Questlines = Toolbox.Questlines or {}

local staticModelCache = { -- 静态结构模型缓存
  dataRef = nil,
  generatedAt = nil,
  model = nil,
  errorObject = nil,
}
local runtimeStateCache = { -- 任务运行时字段缓存
  runtimeKey = nil,
  byQuestID = {},
}
local typeIndexCache = { -- 类型索引缓存
  dataRef = nil,
  generatedAt = nil,
  runtimeKey = nil,
  model = nil,
  errorObject = nil,
}
local navigationModelCache = { -- 资料片导航模型缓存
  dataRef = nil,
  generatedAt = nil,
  runtimeKey = nil,
  model = nil,
  errorObject = nil,
}
local progressCache = { -- 地图/任务线进度缓存
  dataRef = nil,
  generatedAt = nil,
  runtimeKey = nil,
  mapByID = {},
  questLineByID = {},
}
local questLineNameCache = { -- 任务线显示名缓存
  runtimeKey = nil,
  byQuestLineID = {},
}
local dataOverrideTable = nil -- 测试框架注入的数据源（nil 表示使用 live 数据）

local getLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID -- 任务日志索引查询函数
local isQuestCompletedFn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted -- 任务完成状态函数
local isQuestReadyForTurnInFn = C_QuestLog and C_QuestLog.ReadyForTurnIn or nil -- 任务可交付状态函数
local getQuestTypeFn = C_QuestLog and C_QuestLog.GetQuestType or nil -- 任务类型函数
local getQuestTagInfoFn = C_QuestLog and C_QuestLog.GetQuestTagInfo or nil -- 任务类型标签函数
local getQuestObjectivesFn = C_QuestLog and C_QuestLog.GetQuestObjectives or nil -- 任务目标查询函数
local requestLoadQuestByIDFn = C_QuestLog and C_QuestLog.RequestLoadQuestByID or nil -- 任务缓存请求函数
local getNumQuestLogEntriesFn = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or nil -- Quest Log 条目总数函数
local getQuestLogInfoFn = C_QuestLog and C_QuestLog.GetInfo or nil -- Quest Log 条目详情函数
local getQuestLogQuestTextFn = GetQuestLogQuestText -- Quest Log 描述文本函数
local asyncQuestDumpState = { -- 任务详情异步输出状态
  eventFrame = nil,
  callbackListByQuestID = {},
  pendingRequestByQuestID = {},
  lastDumpAtByQuestID = {},
}
local getQuestZoneIDFn = C_TaskQuest and C_TaskQuest.GetQuestZoneID or nil -- 任务地图查询函数
local playableRaceBitByRaceID = { -- raceID -> PlayableRaceBit 映射（Retail）
  [1] = 0,
  [2] = 1,
  [3] = 2,
  [4] = 3,
  [5] = 4,
  [6] = 5,
  [7] = 6,
  [8] = 7,
  [9] = 8,
  [10] = 9,
  [11] = 10,
  [22] = 21,
  [24] = 23,
  [25] = 24,
  [26] = 25,
  [27] = 26,
  [28] = 27,
  [29] = 28,
  [30] = 29,
  [31] = 30,
  [32] = 31,
  [34] = 11,
  [35] = 12,
  [36] = 13,
  [37] = 14,
  [52] = 16,
  [70] = 15,
  [84] = 17,
  [85] = 18,
  [86] = 20,
  [91] = 19,
}

--- 兼容运行时的按位与操作。
---@param leftValue number
---@param rightValue number
---@return number
local function bitAnd(leftValue, rightValue)
  if type(bit) == "table" and type(bit.band) == "function" then
    return bit.band(leftValue, rightValue)
  end
  if type(bit32) == "table" and type(bit32.band) == "function" then
    return bit32.band(leftValue, rightValue)
  end
  return 0
end

--- 清空任务线运行时缓存，确保后续按当前数据源重新构建模型。
local function resetRuntimeCache()
  staticModelCache = {
    dataRef = nil,
    generatedAt = nil,
    model = nil,
    errorObject = nil,
  }
  runtimeStateCache = {
    runtimeKey = nil,
    byQuestID = {},
  }
  typeIndexCache = {
    dataRef = nil,
    generatedAt = nil,
    runtimeKey = nil,
    model = nil,
    errorObject = nil,
  }
  navigationModelCache = {
    dataRef = nil,
    generatedAt = nil,
    runtimeKey = nil,
    model = nil,
    errorObject = nil,
  }
  progressCache = {
    dataRef = nil,
    generatedAt = nil,
    runtimeKey = nil,
    mapByID = {},
    questLineByID = {},
  }
  questLineNameCache = {
    runtimeKey = nil,
    byQuestLineID = {},
  }
end

--- 构建校验错误对象。
---@param errorCode string 错误码
---@param errorPath string 字段路径
---@param messageText string 错误描述
---@return table
local function buildValidationError(errorCode, errorPath, messageText)
  return {
    code = errorCode,
    path = errorPath,
    message = messageText,
  }
end

--- 查询任务名（按任务 ID）。
---@param questID number
---@return string|nil
local function getQuestNameByID(questID)
  if type(questID) ~= "number" then
    return nil
  end

  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local questName = C_QuestLog.GetTitleForQuestID(questID) -- C_QuestLog 任务名
    if type(questName) == "string" and questName ~= "" then
      return questName
    end
  end

  if type(QuestUtils_GetQuestName) == "function" then
    local questName = QuestUtils_GetQuestName(questID) -- 旧接口任务名
    if type(questName) == "string" and questName ~= "" then
      return questName
    end
  end

  return nil
end

--- 获取当前运行时的任务日志索引查询函数。
---@return function|nil
local function getLiveQuestLogIndexForQuestID()
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
    return C_QuestLog.GetLogIndexForQuestID
  end
  if type(getLogIndexForQuestID) == "function" then
    return getLogIndexForQuestID
  end
  if type(GetQuestLogIndexByID) == "function" then
    return GetQuestLogIndexByID
  end
  return nil
end

--- 获取当前运行时的任务完成状态查询函数。
---@return function|nil
local function getLiveQuestCompletedFunction()
  if type(C_QuestLog) == "table" and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
    return C_QuestLog.IsQuestFlaggedCompleted
  end
  if type(isQuestCompletedFn) == "function" then
    return isQuestCompletedFn
  end
  if type(IsQuestFlaggedCompleted) == "function" then
    return IsQuestFlaggedCompleted
  end
  return nil
end

--- 获取当前运行时的任务可交付状态函数。
---@return function|nil
local function getLiveQuestReadyForTurnInFunction()
  if type(C_QuestLog) == "table" and type(C_QuestLog.ReadyForTurnIn) == "function" then
    return C_QuestLog.ReadyForTurnIn
  end
  if type(isQuestReadyForTurnInFn) == "function" then
    return isQuestReadyForTurnInFn
  end
  return nil
end

--- 获取当前运行时的任务类型函数。
---@return function|nil
local function getLiveQuestTypeFunction()
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestType) == "function" then
    return C_QuestLog.GetQuestType
  end
  if type(getQuestTypeFn) == "function" then
    return getQuestTypeFn
  end
  return nil
end

--- 查询地图名（按 UiMapID）。
---@param uiMapID number
---@return string
local function getMapNameByID(uiMapID)
  if type(uiMapID) == "number" and C_Map and C_Map.GetMapInfo then
    local success, mapInfo = pcall(C_Map.GetMapInfo, uiMapID) -- 地图信息查询
    if success and type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
      return mapInfo.name
    end
  end
  return "Map #" .. tostring(uiMapID or "?")
end

--- 获取任务状态（completed | active | pending）。
---@param questID number
---@return string
local function getQuestStatus(questID)
  if type(questID) ~= "number" then
    return "pending"
  end

  local liveIsQuestCompletedFn = getLiveQuestCompletedFunction() -- 当前任务完成状态函数
  if type(liveIsQuestCompletedFn) == "function" and liveIsQuestCompletedFn(questID) then
    return "completed"
  end

  local liveGetLogIndexForQuestID = getLiveQuestLogIndexForQuestID() -- 当前任务日志索引函数
  if type(liveGetLogIndexForQuestID) == "function" then
    local logIndex = liveGetLogIndexForQuestID(questID) -- 当前任务日志索引
    if type(logIndex) == "number" and logIndex > 0 then
      return "active"
    end
  end

  return "pending"
end

--- 对外暴露任务状态查询。
---@param questID number
---@return string
function Toolbox.Questlines.GetQuestStatus(questID)
  return getQuestStatus(questID)
end

--- 获取任务类型映射表。
---@return table|nil
local function getQuestTypeNameTable()
  return Toolbox.Data and Toolbox.Data.QuestTypeNames or nil
end

--- 查询任务类型展示名。
---@param typeID number|nil
---@return string
local function getQuestTypeLabel(typeID)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local mappingTable = getQuestTypeNameTable() -- 类型映射表
  local localeKey = type(mappingTable) == "table" and mappingTable[typeID] or nil -- 本地化键名
  if type(localeKey) == "string" then
    local localizedText = localeTable[localeKey] -- 本地化文案
    if type(localizedText) == "string" and localizedText ~= "" then
      return localizedText
    end
  end

  local fallbackFormat = localeTable.EJ_QUEST_TYPE_UNKNOWN_FMT or "Unknown Type (%s)" -- 未知类型兜底格式
  return string.format(fallbackFormat, tostring(typeID or "?"))
end

--- 获取当前角色阵营标记。
---@return string
local function getCurrentPlayerFactionTag()
  if type(UnitFactionGroup) ~= "function" then
    return ""
  end
  local factionName = UnitFactionGroup("player") -- 当前角色阵营名
  if factionName == "Alliance" then
    return "alliance"
  end
  if factionName == "Horde" then
    return "horde"
  end
  if factionName == "Neutral" then
    return "neutral"
  end
  return ""
end

--- 获取当前角色种族位索引。
---@return number|nil
local function getCurrentPlayerRaceBit()
  if type(UnitRace) ~= "function" then
    return nil
  end
  local _, _, raceID = UnitRace("player") -- 当前角色 raceID
  if type(raceID) ~= "number" then
    return nil
  end
  return playableRaceBitByRaceID[raceID]
end

--- 获取当前角色职业位掩码。
---@return number|nil
local function getCurrentPlayerClassMask()
  if type(UnitClass) ~= "function" then
    return nil
  end
  local _, _, classID = UnitClass("player") -- 当前角色 classID
  if type(classID) ~= "number" or classID <= 0 then
    return nil
  end
  return 2 ^ (classID - 1)
end

--- 判断当前角色是否命中任一阵营标记。
---@param factionTagList table|nil
---@return boolean
local function matchesFactionTags(factionTagList)
  if type(factionTagList) ~= "table" or #factionTagList == 0 then
    return true
  end
  local currentFactionTag = getCurrentPlayerFactionTag() -- 当前角色阵营标记
  for _, factionTag in ipairs(factionTagList) do
    if factionTag == "shared" then
      return true
    end
    if type(factionTag) == "string" and factionTag ~= "" and factionTag == currentFactionTag then
      return true
    end
  end
  return false
end

--- 判断当前角色是否命中任一种族限制。
---@param raceMaskValueList table|nil
---@return boolean
local function matchesRaceMasks(raceMaskValueList)
  if type(raceMaskValueList) ~= "table" or #raceMaskValueList == 0 then
    return true
  end
  local currentRaceBit = getCurrentPlayerRaceBit() -- 当前角色种族位索引
  if type(currentRaceBit) ~= "number" then
    return true
  end
  local currentRaceMask = 2 ^ currentRaceBit -- 当前角色种族位掩码
  for _, raceMaskValue in ipairs(raceMaskValueList) do
    if type(raceMaskValue) == "number" and raceMaskValue > 0 and bitAnd(raceMaskValue, currentRaceMask) ~= 0 then
      return true
    end
  end
  return false
end

--- 判断当前角色是否命中任一职业限制。
---@param classMaskValueList table|nil
---@return boolean
local function matchesClassMasks(classMaskValueList)
  if type(classMaskValueList) ~= "table" or #classMaskValueList == 0 then
    return true
  end
  local currentClassMask = getCurrentPlayerClassMask() -- 当前角色职业位掩码
  if type(currentClassMask) ~= "number" then
    return true
  end
  for _, classMaskValue in ipairs(classMaskValueList) do
    if type(classMaskValue) == "number" and classMaskValue > 0 and bitAnd(classMaskValue, currentClassMask) ~= 0 then
      return true
    end
  end
  return false
end

--- 判断任务是否允许当前角色查看。
---@param questRecord table|nil
---@return boolean
local function isQuestAllowedForPlayer(questRecord)
  if type(questRecord) ~= "table" then
    return false
  end
  if not matchesFactionTags(questRecord.FactionTags) then
    return false
  end
  if not matchesRaceMasks(questRecord.RaceMaskValues) then
    return false
  end
  if not matchesClassMasks(questRecord.ClassMaskValues) then
    return false
  end
  return true
end

--- 判断任务线是否允许当前角色查看。
---@param questLineRecord table|nil
---@return boolean
local function isQuestLineAllowedForPlayer(questLineRecord)
  if type(questLineRecord) ~= "table" then
    return false
  end
  if not matchesFactionTags(questLineRecord.FactionTags) then
    return false
  end
  if not matchesRaceMasks(questLineRecord.RaceMaskValues) then
    return false
  end
  if not matchesClassMasks(questLineRecord.ClassMaskValues) then
    return false
  end
  return true
end

--- 构建未知任务类型兜底名称。
---@param typeID number|nil
---@return string
local function formatUnknownQuestTypeLabel(typeID)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local fallbackFormat = localeTable.EJ_QUEST_TYPE_UNKNOWN_FMT or "Unknown Type (%s)" -- 未知类型兜底格式
  return string.format(fallbackFormat, tostring(typeID or "?"))
end

--- 按任务 ID 查询运行时任务类型名称。
---@param questID number
---@param typeID number|nil
---@return string
local function getRuntimeQuestTypeName(questID, typeID)
  if type(questID) == "number" and type(getQuestTagInfoFn) == "function" then
    local success, tagInfo = pcall(getQuestTagInfoFn, questID) -- 任务类型标签
    if success and type(tagInfo) == "table" then
      local tagName = tagInfo.tagName -- 运行时类型名称
      if type(tagName) == "string" and tagName ~= "" then
        return tagName
      end
    end
  end
  return formatUnknownQuestTypeLabel(typeID)
end

--- 按任务读取类型分组键与显示名。
---@param questID number
---@param typeID number|nil
---@return string groupKey
---@return string groupName
local function getQuestTypeGroupInfo(questID, typeID)
  if type(questID) == "number" and type(getQuestTagInfoFn) == "function" then
    local success, tagInfo = pcall(getQuestTagInfoFn, questID) -- 任务标签信息
    if success and type(tagInfo) == "table" then
      local tagID = tagInfo.tagID -- 任务标签 ID
      local tagName = tagInfo.tagName -- 任务标签名称
      if type(tagID) == "number" then
        local groupName = type(tagName) == "string" and tagName ~= "" and tagName or formatUnknownQuestTypeLabel(tagID)
        return "tag:" .. tostring(tagID), groupName
      end
    end
  end

  if type(typeID) == "number" then
    return "type:" .. tostring(typeID), getQuestTypeLabel(typeID)
  end
  return "other", (Toolbox.L and Toolbox.L.EJ_QUEST_TYPE_UNKNOWN_FMT and string.format(Toolbox.L.EJ_QUEST_TYPE_UNKNOWN_FMT, "?")) or "Unknown Type (?)"
end

--- 查询资料片展示名。
---@param expansionID number|nil
---@return string
local function getExpansionLabel(expansionID)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local localeKey = type(expansionID) == "number" and ("EJ_QUEST_EXPANSION_" .. tostring(expansionID)) or nil -- 资料片本地化键
  if type(localeKey) == "string" then
    local localizedText = localeTable[localeKey] -- 资料片本地化文案
    if type(localizedText) == "string" and localizedText ~= "" then
      return localizedText
    end
  end

  local fallbackFormat = localeTable.EJ_QUEST_EXPANSION_UNKNOWN_FMT or "Expansion #%s" -- 资料片兜底格式
  return string.format(fallbackFormat, tostring(expansionID or "?"))
end

--- 获取当前时间（秒），供节流和异步请求去重使用。
---@return number
local function getCurrentTimeSeconds()
  if type(GetTime) == "function" then
    local success, currentTime = pcall(GetTime) -- 当前运行时秒数
    if success and type(currentTime) == "number" then
      return currentTime
    end
  end
  return 0
end

--- 安全读取任务日志索引。
---@param questID number
---@return number|nil
local function getSafeQuestLogIndex(questID)
  local liveGetLogIndexForQuestID = getLiveQuestLogIndexForQuestID() -- 当前任务日志索引函数
  if type(questID) ~= "number" or type(liveGetLogIndexForQuestID) ~= "function" then
    return nil
  end

  local success, logIndex = pcall(liveGetLogIndexForQuestID, questID) -- 当前任务日志索引
  if success and type(logIndex) == "number" and logIndex > 0 then
    return logIndex
  end
  return nil
end

--- 安全读取任务描述与目标文本。
---@param questLogIndex number|nil
---@return string|nil
---@return string|nil
local function getQuestTextByLogIndex(questLogIndex)
  local liveGetQuestLogQuestTextFn = type(GetQuestLogQuestText) == "function" and GetQuestLogQuestText or getQuestLogQuestTextFn -- 当前任务文本函数
  if type(questLogIndex) ~= "number" or type(liveGetQuestLogQuestTextFn) ~= "function" then
    return nil, nil
  end

  local success, descriptionText, objectiveText = pcall(liveGetQuestLogQuestTextFn, questLogIndex) -- 任务描述与目标文本
  if not success then
    return nil, nil
  end
  return descriptionText, objectiveText
end

--- 安全读取任务目标列表。
---@param questID number
---@return table[]
local function getQuestObjectivesByID(questID)
  local liveGetQuestObjectivesFn = type(C_QuestLog) == "table" and C_QuestLog.GetQuestObjectives or getQuestObjectivesFn -- 当前任务目标查询函数
  if type(questID) ~= "number" or type(liveGetQuestObjectivesFn) ~= "function" then
    return {}
  end

  local success, objectiveList = pcall(liveGetQuestObjectivesFn, questID) -- 任务目标列表
  if success and type(objectiveList) == "table" then
    return objectiveList
  end
  return {}
end

--- 安全读取任务标签信息。
---@param questID number
---@return table|nil
local function getQuestTagInfoByID(questID)
  local liveGetQuestTagInfoFn = type(C_QuestLog) == "table" and C_QuestLog.GetQuestTagInfo or getQuestTagInfoFn -- 当前任务标签函数
  if type(questID) ~= "number" or type(liveGetQuestTagInfoFn) ~= "function" then
    return nil
  end

  local success, tagInfo = pcall(liveGetQuestTagInfoFn, questID) -- 任务标签信息
  if success and type(tagInfo) == "table" then
    return tagInfo
  end
  return nil
end

--- 安全读取任务所在地图 ID。
---@param questID number
---@return number|nil
local function getQuestZoneMapID(questID)
  local liveGetQuestZoneIDFn = type(C_TaskQuest) == "table" and C_TaskQuest.GetQuestZoneID or getQuestZoneIDFn -- 当前任务地图查询函数
  if type(questID) ~= "number" or type(liveGetQuestZoneIDFn) ~= "function" then
    return nil
  end

  local success, uiMapID = pcall(liveGetQuestZoneIDFn, questID) -- 任务所在地图 ID
  if success and type(uiMapID) == "number" and uiMapID > 0 then
    return uiMapID
  end
  return nil
end

--- 安全读取地图原始信息。
---@param uiMapID number|nil
---@return table|nil
local function getRawMapInfoByID(uiMapID)
  if type(uiMapID) ~= "number" or uiMapID <= 0 or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then
    return nil
  end

  local success, mapInfo = pcall(C_Map.GetMapInfo, uiMapID) -- 地图原始信息
  if success and type(mapInfo) == "table" then
    return mapInfo
  end
  return nil
end

--- 读取地图父链与大陆层级信息。
---@param uiMapID number|nil
---@return table
local function buildMapChainSnapshot(uiMapID)
  local resultObject = {
    zoneMapID = uiMapID,
    zoneMapName = nil,
    parentMapList = {},
    continentMapID = nil,
    continentMapName = nil,
  }
  if type(uiMapID) ~= "number" or uiMapID <= 0 then
    return resultObject
  end

  local currentMapID = uiMapID -- 当前遍历地图 ID
  local guardCount = 0 -- 父链保护计数
  while type(currentMapID) == "number" and currentMapID > 0 and guardCount < 20 do
    guardCount = guardCount + 1
    local mapInfo = getRawMapInfoByID(currentMapID) -- 当前地图原始信息
    if type(mapInfo) ~= "table" then
      break
    end

    if currentMapID == uiMapID then
      resultObject.zoneMapName = type(mapInfo.name) == "string" and mapInfo.name or nil
    else
      resultObject.parentMapList[#resultObject.parentMapList + 1] = {
        mapID = currentMapID,
        name = type(mapInfo.name) == "string" and mapInfo.name or nil,
        mapType = mapInfo.mapType,
      }
    end

    if mapInfo.mapType == Enum.UIMapType.Continent then
      resultObject.continentMapID = currentMapID
      resultObject.continentMapName = type(mapInfo.name) == "string" and mapInfo.name or nil
      break
    end

    if type(mapInfo.parentMapID) ~= "number" or mapInfo.parentMapID <= 0 then
      break
    end
    currentMapID = mapInfo.parentMapID
  end

  return resultObject
end

--- 安全读取任务线原始 API 信息。
---@param questID number
---@param uiMapID number|nil
---@return table|nil
local function getQuestLineApiInfo(questID, uiMapID)
  if type(questID) ~= "number" or type(C_QuestLine) ~= "table" or type(C_QuestLine.GetQuestLineInfo) ~= "function" then
    return nil
  end

  local success, questLineInfo = pcall(C_QuestLine.GetQuestLineInfo, questID, uiMapID, false) -- 任务线原始 API 信息
  if success and type(questLineInfo) == "table" then
    return questLineInfo
  end
  return nil
end

--- 统一输出聊天调试文本。
---@param messageText string|nil
local function printQuestDumpLine(messageText)
  if type(messageText) ~= "string" or messageText == "" then
    return
  end
  if Toolbox.Chat and type(Toolbox.Chat.PrintAddonMessage) == "function" then
    Toolbox.Chat.PrintAddonMessage(messageText)
  end
end

--- 读取任务详情输出的本地化文案。
---@param keyName string
---@param fallbackText string
---@return string
local function getQuestDumpLocaleText(keyName, fallbackText)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local localizedText = localeTable[keyName] -- 当前键的文案
  if type(localizedText) == "string" and localizedText ~= "" then
    return localizedText
  end
  return fallbackText
end

--- 对外暴露任务类型展示名查询。
---@param typeID number|nil
---@return string
function Toolbox.Questlines.GetQuestTypeLabel(typeID)
  return getQuestTypeLabel(typeID)
end

--- 获取任务运行时字段。
---@param questID number
---@return table
local function getQuestRuntimeState(questID)
  local runtimeState = {
    name = getQuestNameByID(questID) or ("Quest #" .. tostring(questID or "?")),
    status = getQuestStatus(questID),
    readyForTurnIn = false,
    typeID = nil,
    npcIDs = nil,
    npcPos = nil,
  }

  if type(questID) ~= "number" then
    return runtimeState
  end

  local liveIsQuestReadyForTurnInFn = getLiveQuestReadyForTurnInFunction() -- 当前任务可交付状态函数
  if type(liveIsQuestReadyForTurnInFn) == "function" then
    local success, readyValue = pcall(liveIsQuestReadyForTurnInFn, questID) -- 任务可交付状态
    if success then
      runtimeState.readyForTurnIn = readyValue == true
    end
  end

  local liveGetQuestTypeFn = getLiveQuestTypeFunction() -- 当前任务类型函数
  if type(liveGetQuestTypeFn) == "function" then
    local success, typeValue = pcall(liveGetQuestTypeFn, questID) -- 任务类型
    if success and type(typeValue) == "number" then
      runtimeState.typeID = typeValue
    end
  end

  return runtimeState
end

--- 对外暴露任务运行时字段查询。
---@param questID number
---@return table
function Toolbox.Questlines.GetQuestRuntimeState(questID)
  return getQuestRuntimeState(questID)
end

--- 获取运行时缓存键，避免动态字段永久缓存。
---@return number
local function getRuntimeCacheKey()
  if type(GetTime) == "function" then
    local success, currentTime = pcall(GetTime) -- 当前运行时秒数
    if success and type(currentTime) == "number" then
      return math.floor(currentTime)
    end
  end
  return 0
end

--- 按当前运行时窗口读取任务运行时字段缓存。
---@param questID number
---@return table
local function getCachedQuestRuntimeState(questID)
  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if runtimeStateCache.runtimeKey ~= runtimeKey then
    runtimeStateCache.runtimeKey = runtimeKey
    runtimeStateCache.byQuestID = {}
  end

  local cachedState = runtimeStateCache.byQuestID[questID] -- 已缓存运行时字段
  if type(cachedState) == "table" then
    return cachedState
  end

  local runtimeState = getQuestRuntimeState(questID) -- 最新运行时字段
  runtimeStateCache.byQuestID[questID] = runtimeState
  return runtimeState
end

--- 判断任务是否仍在当前任务日志中。
---@param questID number
---@return boolean
local function isQuestCurrentlyInLog(questID)
  local liveGetLogIndexForQuestID = getLiveQuestLogIndexForQuestID() -- 当前任务日志索引函数
  if type(questID) ~= "number" or type(liveGetLogIndexForQuestID) ~= "function" then
    return false
  end

  local success, logIndex = pcall(liveGetLogIndexForQuestID, questID) -- Quest Log 索引
  return success and type(logIndex) == "number" and logIndex > 0
end

--- 检查 number 数组类型，并可选检查是否非空。
---@param value any 待校验值
---@param requiredNonEmpty boolean 是否要求非空
---@param pathText string 字段路径
---@return boolean ok
---@return table|nil errorObject
local function validateNumberArray(value, requiredNonEmpty, pathText)
  if value == nil then
    if requiredNonEmpty then
      return false, buildValidationError("E_MISSING_FIELD", pathText, "missing number array")
    end
    return true, nil
  end

  if type(value) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", pathText, "number array expected")
  end

  if requiredNonEmpty and #value == 0 then
    return false, buildValidationError("E_EMPTY_ARRAY", pathText, "array cannot be empty")
  end

  local seenNumberSet = {} -- 数组去重集合
  for arrayIndex, numberValue in ipairs(value) do
    if type(numberValue) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", pathText .. "[" .. tostring(arrayIndex) .. "]", "number expected")
    end
    if seenNumberSet[numberValue] == true then
      return false, buildValidationError("E_DUPLICATE_VALUE", pathText, "duplicate number value")
    end
    seenNumberSet[numberValue] = true
  end

  return true, nil
end

--- 检查任务线链接对象数组。
---@param value any 待校验值
---@param requiredNonEmpty boolean 是否要求非空
---@param pathText string 字段路径
---@return boolean ok
---@return table|nil errorObject
local function validateQuestLinkArray(value, requiredNonEmpty, pathText)
  if value == nil then
    if requiredNonEmpty then
      return false, buildValidationError("E_MISSING_FIELD", pathText, "missing quest link array")
    end
    return true, nil
  end

  if type(value) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", pathText, "quest link array expected")
  end

  if requiredNonEmpty and #value == 0 then
    return false, buildValidationError("E_EMPTY_ARRAY", pathText, "array cannot be empty")
  end

  local seenQuestSet = {} -- 已出现任务集合
  for arrayIndex, linkObject in ipairs(value) do
    if type(linkObject) ~= "table" then
      return false, buildValidationError("E_TYPE_MISMATCH", pathText .. "[" .. tostring(arrayIndex) .. "]", "table expected")
    end
    if type(linkObject.QuestID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", pathText .. "[" .. tostring(arrayIndex) .. "].QuestID", "number expected")
    end
    if type(linkObject.OrderIndex) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", pathText .. "[" .. tostring(arrayIndex) .. "].OrderIndex", "number expected")
    end
    if seenQuestSet[linkObject.QuestID] == true then
      return false, buildValidationError("E_DUPLICATE_VALUE", pathText, "duplicate QuestID in link array")
    end
    seenQuestSet[linkObject.QuestID] = true
  end

  return true, nil
end

--- 获取任务页签静态数据根对象。
---@return table|nil
local function getQuestlineDataTable()
  if dataOverrideTable ~= nil then
    return dataOverrideTable
  end
  return Toolbox.Data and Toolbox.Data.InstanceQuestlines
end

--- 覆盖任务线数据源（仅供测试框架调用）。传 nil 恢复 live 数据源。
---@param dataTable table|nil 覆盖数据表
function Toolbox.Questlines.SetDataOverride(dataTable)
  dataOverrideTable = dataTable
  resetRuntimeCache()
end

--- strict 校验任务线静态数据。
---@param dataTable table|nil 数据根对象
---@param strictMode boolean|nil strict 开关
---@return boolean ok
---@return table|nil errorObject
function Toolbox.Questlines.ValidateInstanceQuestlinesData(dataTable, strictMode)
  local strictEnabled = strictMode ~= false -- strict 是否开启

  if type(dataTable) ~= "table" then
    return false, buildValidationError("E_MISSING_FIELD", "root", "InstanceQuestlines table missing")
  end

  local requiredRootFields = { -- 根字段定义
    "schemaVersion",
    "sourceMode",
    "generatedAt",
    "quests",
    "questLines",
  }
  if dataTable.schemaVersion >= 6 then
    requiredRootFields[#requiredRootFields + 1] = "expansions"
  elseif dataTable.schemaVersion >= 4 then
    requiredRootFields[#requiredRootFields + 1] = "questLineXQuest"
  else
    requiredRootFields[#requiredRootFields + 1] = "questLineQuestIDs"
  end
  for _, fieldName in ipairs(requiredRootFields) do
    if dataTable[fieldName] == nil then
      return false, buildValidationError("E_MISSING_FIELD", fieldName, "required root field missing")
    end
  end

  if strictEnabled and dataTable.schemaVersion ~= 3 and dataTable.schemaVersion ~= 4 and dataTable.schemaVersion ~= 5 and dataTable.schemaVersion ~= 6 then
    return false, buildValidationError("E_INVALID_SCHEMA", "schemaVersion", "schemaVersion must be 3, 4, 5 or 6")
  end

  if type(dataTable.sourceMode) ~= "string" then
    return false, buildValidationError("E_TYPE_MISMATCH", "sourceMode", "string expected")
  end
  if dataTable.sourceMode ~= "mock" and dataTable.sourceMode ~= "live" then
    return false, buildValidationError("E_INVALID_ENUM", "sourceMode", "sourceMode must be mock/live")
  end

  if type(dataTable.generatedAt) ~= "string" or not string.find(dataTable.generatedAt, "Z$") then
    return false, buildValidationError("E_INVALID_TIMESTAMP", "generatedAt", "UTC ISO8601 string expected")
  end

  if type(dataTable.quests) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "quests", "table expected")
  end
  if type(dataTable.questLines) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "questLines", "table expected")
  end
  if dataTable.schemaVersion >= 6 and type(dataTable.expansions) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "expansions", "table expected")
  end
  if dataTable.schemaVersion >= 4 and dataTable.schemaVersion < 6 and type(dataTable.questLineXQuest) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "questLineXQuest", "table expected")
  end
  if dataTable.schemaVersion < 4 and type(dataTable.questLineQuestIDs) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "questLineQuestIDs", "table expected")
  end

  local questExistsByID = {} -- 任务存在集合
  for questKey, questEntry in pairs(dataTable.quests) do
    local questID = tonumber(questKey) -- 规范化 questID
    if type(questID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questKey) .. "]", "numeric key required")
    end
    if type(questEntry) ~= "table" then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "]", "table expected")
    end
    if type(questEntry.ID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", "quests[" .. tostring(questID) .. "].ID", "ID missing")
    end
    if questEntry.ID ~= questID then
      return false, buildValidationError("E_KEY_VALUE_MISMATCH", "quests[" .. tostring(questID) .. "].ID", "ID must match key")
    end
    if dataTable.schemaVersion < 6 and (type(questEntry.UiMapID) ~= "number" or questEntry.UiMapID <= 0) then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].UiMapID", "positive number expected")
    end
    questExistsByID[questID] = true
  end

  local questLineExistsByID = {} -- 任务线存在集合
  for questLineKey, questLineEntry in pairs(dataTable.questLines) do
    local questLineID = tonumber(questLineKey) -- 规范化 questLineID
    if type(questLineID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "questLines[" .. tostring(questLineKey) .. "]", "numeric key required")
    end
    if type(questLineEntry) ~= "table" then
      return false, buildValidationError("E_TYPE_MISMATCH", "questLines[" .. tostring(questLineID) .. "]", "table expected")
    end
    if type(questLineEntry.ID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].ID", "number expected")
    end
    if questLineEntry.ID ~= questLineID then
      return false, buildValidationError("E_KEY_VALUE_MISMATCH", "questLines[" .. tostring(questLineID) .. "].ID", "ID must match key")
    end
    if questLineEntry.Name_lang ~= nil and (type(questLineEntry.Name_lang) ~= "string" or questLineEntry.Name_lang == "") then
      return false, buildValidationError("E_TYPE_MISMATCH", "questLines[" .. tostring(questLineID) .. "].Name_lang", "non-empty string expected when provided")
    end
    if type(questLineEntry.UiMapID) ~= "number" or questLineEntry.UiMapID <= 0 then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].UiMapID", "positive number expected")
    end
    if dataTable.schemaVersion >= 5 and dataTable.schemaVersion < 6 and (type(questLineEntry.ExpansionID) ~= "number" or questLineEntry.ExpansionID < 0) then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].ExpansionID", "non-negative number expected")
    end
    if dataTable.schemaVersion >= 6 then
      local questListOk, questListError = validateNumberArray(
        questLineEntry.QuestIDs,
        strictEnabled,
        "questLines[" .. tostring(questLineID) .. "].QuestIDs"
      )
      if not questListOk then
        return false, questListError
      end
    end
    questLineExistsByID[questLineID] = true
  end

  local questOwnerByID = {} -- questID -> questLineID
  if dataTable.schemaVersion >= 6 then
    for questLineKey, questLineEntry in pairs(dataTable.questLines) do
      local questLineID = tonumber(questLineKey) -- 规范化 questLineID
      local questIDList = type(questLineEntry) == "table" and questLineEntry.QuestIDs or nil -- 当前任务线任务列表
      for questIndex, questID in ipairs(questIDList or {}) do
        if questExistsByID[questID] ~= true then
          return false, buildValidationError("E_BAD_REF", "questLines[" .. tostring(questLineID) .. "].QuestIDs[" .. tostring(questIndex) .. "]", "questID not found in quests")
        end
        if questOwnerByID[questID] == nil then
          questOwnerByID[questID] = questLineID
        end
      end
    end

    for expansionKey, questLineIDList in pairs(dataTable.expansions) do
      local expansionID = tonumber(expansionKey) -- 规范化资料片 ID
      if type(expansionID) ~= "number" or expansionID < 0 then
        return false, buildValidationError("E_TYPE_MISMATCH", "expansions[" .. tostring(expansionKey) .. "]", "non-negative numeric key required")
      end
      local validList, listError = validateNumberArray(
        questLineIDList,
        strictEnabled,
        "expansions[" .. tostring(expansionID) .. "]"
      )
      if not validList then
        return false, listError
      end
      for listIndex, questLineID in ipairs(questLineIDList or {}) do
        if questLineExistsByID[questLineID] ~= true then
          return false, buildValidationError("E_BAD_REF", "expansions[" .. tostring(expansionID) .. "][" .. tostring(listIndex) .. "]", "questLineID not found in questLines")
        end
      end
    end
  else
    local questLinkRoot = dataTable.schemaVersion >= 4 and dataTable.questLineXQuest or dataTable.questLineQuestIDs -- 任务线链接根表
    local questLinkPath = dataTable.schemaVersion >= 4 and "questLineXQuest" or "questLineQuestIDs" -- 任务线链接字段路径
    for questLineKey, questLinkList in pairs(questLinkRoot) do
      local questLineID = tonumber(questLineKey) -- 规范化 questLineID
      if type(questLineID) ~= "number" then
        return false, buildValidationError("E_TYPE_MISMATCH", questLinkPath .. "[" .. tostring(questLineKey) .. "]", "numeric key required")
      end
      if questLineExistsByID[questLineID] ~= true then
        return false, buildValidationError("E_BAD_REF", questLinkPath .. "[" .. tostring(questLineID) .. "]", "questLineID not found in questLines")
      end

      local questListOk = nil -- 任务链接数组校验结果
      local questListError = nil -- 任务链接数组校验错误
      if dataTable.schemaVersion >= 4 then
        questListOk, questListError = validateQuestLinkArray(
          questLinkList,
          strictEnabled,
          questLinkPath .. "[" .. tostring(questLineID) .. "]"
        )
      else
        questListOk, questListError = validateNumberArray(
          questLinkList,
          strictEnabled,
          questLinkPath .. "[" .. tostring(questLineID) .. "]"
        )
      end
      if not questListOk then
        return false, questListError
      end

      if type(questLinkList) == "table" then
        for questIndex, questLinkObject in ipairs(questLinkList) do
          local questID = dataTable.schemaVersion >= 4 and questLinkObject.QuestID or questLinkObject -- 当前任务 ID
          if questExistsByID[questID] ~= true then
            return false, buildValidationError("E_BAD_REF", questLinkPath .. "[" .. tostring(questLineID) .. "][" .. tostring(questIndex) .. "]", "questID not found in quests")
          end
          if questOwnerByID[questID] ~= nil and questOwnerByID[questID] ~= questLineID then
            return false, buildValidationError("E_DUPLICATE_REF", questLinkPath .. "[" .. tostring(questLineID) .. "][" .. tostring(questIndex) .. "]", "questID bound to multiple questLines")
          end
          questOwnerByID[questID] = questLineID
        end
      end
    end
  end

  return true, nil
end

--- 计算任务链进度。
---@param chain table
---@return table
function Toolbox.Questlines.GetChainProgress(chain)
  local questList = chain and chain.quests -- 任务列表
  if type(questList) ~= "table" or #questList == 0 then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }
  end

  local completedCount = 0 -- 完成任务数量
  local hasActiveQuest = false -- 是否存在进行中任务
  local nextQuestID = nil -- 下一任务 ID
  local nextQuestName = nil -- 下一任务名称

  for _, questEntry in ipairs(questList) do
    local questID = nil -- 当前任务 ID
    local questStatus = nil -- 当前任务状态
    local questName = nil -- 当前任务名称

    if type(questEntry) == "number" then
      questID = questEntry
      questStatus = getQuestStatus(questID)
      questName = getQuestNameByID(questID) or ("Quest #" .. tostring(questID))
    elseif type(questEntry) == "table" then
      questID = tonumber(questEntry.id or questEntry.ID)
      questStatus = questEntry.status or getQuestStatus(questID)
      questName = questEntry.name or (type(questID) == "number" and (getQuestNameByID(questID) or ("Quest #" .. tostring(questID))) or "Unknown Quest")
    end

    if questStatus == "completed" then
      completedCount = completedCount + 1
    elseif questStatus == "active" then
      hasActiveQuest = true
      if nextQuestID == nil then
        nextQuestID = questID
        nextQuestName = questName
      end
    elseif nextQuestID == nil then
      nextQuestID = questID
      nextQuestName = questName
    end
  end

  local totalCount = #questList -- 总任务数
  return {
    completed = completedCount,
    total = totalCount,
    hasActive = hasActiveQuest,
    nextQuestID = nextQuestID,
    nextQuestName = nextQuestName,
    isCompleted = completedCount == totalCount and totalCount > 0,
  }
end

--- 解析任务主点位。
---@param dataTable table 根数据
---@param questID number 任务 ID
---@param questRecord table 任务静态记录
---@return table|nil
local function resolveQuestMapPos(dataTable, questID, questRecord)
  if type(dataTable) == "table" and type(dataTable.schemaVersion) == "number" and dataTable.schemaVersion >= 6 then
    return nil
  end
  local mapPos = type(questRecord) == "table" and questRecord.MapPos or nil -- 任务主点位
  if type(mapPos) ~= "table" and type(dataTable.questPOIBlobs) == "table" and type(dataTable.questPOIPoints) == "table" then
    local blobList = dataTable.questPOIBlobs[questID] -- 当前任务 blob 列表
    if type(blobList) == "table" and type(blobList[1]) == "table" and type(blobList[1].BlobID) == "number" then
      local pointList = dataTable.questPOIPoints[blobList[1].BlobID] -- 当前 blob 点位列表
      if type(pointList) == "table" and type(pointList[1]) == "table" then
        mapPos = pointList[1]
      end
    end
  end
  return mapPos
end

--- 读取任务线关联链接列表。
---@param dataTable table 根数据
---@param questLineID number 任务线 ID
---@return table|nil
local function getQuestLinkList(dataTable, questLineID)
  if type(dataTable) == "table" and type(dataTable.schemaVersion) == "number" and dataTable.schemaVersion >= 6 then
    local questLineEntry = dataTable.questLines and dataTable.questLines[questLineID] or nil -- 当前任务线对象
    return type(questLineEntry) == "table" and questLineEntry.QuestIDs or nil
  end
  return dataTable.questLineXQuest and dataTable.questLineXQuest[questLineID]
    or dataTable.questLineQuestIDs and dataTable.questLineQuestIDs[questLineID]
    or nil
end

--- 基于数据表构建任务 ID 列表。
---@param dataTable table 根数据
---@param questLineID number 任务线 ID
---@return number[]
local function buildQuestIDListByQuestLineID(dataTable, questLineID)
  local questIDList = {} -- 任务 ID 列表
  local questLinkList = getQuestLinkList(dataTable, questLineID) -- 任务线关联任务链接列表
  if type(questLinkList) ~= "table" then
    return questIDList
  end

  for _, questLinkObject in ipairs(questLinkList) do
    local questID = type(questLinkObject) == "table" and questLinkObject.QuestID or questLinkObject -- 当前任务 ID
    local questRecord = dataTable.quests and dataTable.quests[questID] or nil -- 任务静态记录
    if type(questID) == "number" and type(questRecord) == "table" and isQuestAllowedForPlayer(questRecord) then
      questIDList[#questIDList + 1] = questID
    end
  end

  return questIDList
end

--- 构建单个任务展示对象。
---@param dataTable table 根数据
---@param questID number 任务 ID
---@return table|nil
local function buildQuestEntryByID(dataTable, questID)
  local questRecord = dataTable.quests and dataTable.quests[questID] or nil -- 任务静态记录
  if type(questRecord) ~= "table" or not isQuestAllowedForPlayer(questRecord) then
    return nil
  end

  local runtimeState = getCachedQuestRuntimeState(questID) -- 任务运行时字段
  return {
    id = questID,
    name = runtimeState.name,
    status = runtimeState.status,
    readyForTurnIn = runtimeState.readyForTurnIn,
    UiMapID = type(questRecord.UiMapID) == "number" and questRecord.UiMapID or nil,
    typeID = runtimeState.typeID,
    mapPos = resolveQuestMapPos(dataTable, questID, questRecord),
    npcIDs = runtimeState.npcIDs,
    npcPos = runtimeState.npcPos,
    quest = questRecord,
    runtime = runtimeState,
  }
end

--- 解析共享任务在当前上下文下应归属的任务线。
---@param model table 任务页签模型
---@param questRecord table 任务静态记录
---@param questID number 任务 ID
---@param contextOptions table|nil 上下文选项
---@return number|nil
---@return table|nil
local function resolveQuestLineContext(model, questRecord, questID, contextOptions)
  local candidateQuestLineIDs = {} -- 候选任务线 ID 列表
  if type(questRecord) == "table" and type(questRecord.QuestLineIDs) == "table" then
    for _, questLineID in ipairs(questRecord.QuestLineIDs) do
      if type(questLineID) == "number" and type(model.questLineByID[questLineID]) == "table" then
        candidateQuestLineIDs[#candidateQuestLineIDs + 1] = questLineID
      end
    end
  end
  if #candidateQuestLineIDs == 0 and type(model.questToQuestLineID[questID]) == "number" then
    candidateQuestLineIDs[1] = model.questToQuestLineID[questID]
  end
  if #candidateQuestLineIDs == 0 then
    return nil, nil
  end

  local requestedQuestLineID = type(contextOptions) == "table" and contextOptions.questLineID or nil -- 指定任务线 ID
  if type(requestedQuestLineID) == "number" then
    for _, questLineID in ipairs(candidateQuestLineIDs) do
      if questLineID == requestedQuestLineID then
        return questLineID, model.questLineByID[questLineID]
      end
    end
  end

  local requestedExpansionID = type(contextOptions) == "table" and contextOptions.expansionID or nil -- 指定资料片 ID
  local requestedMapID = type(contextOptions) == "table" and contextOptions.mapID or nil -- 指定地图 ID
  local fallbackQuestLineID = candidateQuestLineIDs[1] -- 兜底任务线 ID
  local fallbackQuestLineEntry = model.questLineByID[fallbackQuestLineID] -- 兜底任务线对象

  if type(requestedExpansionID) == "number" or type(requestedMapID) == "number" then
    for _, questLineID in ipairs(candidateQuestLineIDs) do
      local questLineEntry = model.questLineByID[questLineID] -- 当前候选任务线对象
      if type(questLineEntry) == "table" then
        local expansionMatched = type(requestedExpansionID) ~= "number" or questLineEntry.ExpansionID == requestedExpansionID
        local mapMatched = type(requestedMapID) ~= "number" or questLineEntry.UiMapID == requestedMapID
        if expansionMatched and mapMatched then
          return questLineID, questLineEntry
        end
      end
    end
    for _, questLineID in ipairs(candidateQuestLineIDs) do
      local questLineEntry = model.questLineByID[questLineID] -- 当前候选任务线对象
      if type(questLineEntry) == "table" and type(requestedExpansionID) == "number" and questLineEntry.ExpansionID == requestedExpansionID then
        return questLineID, questLineEntry
      end
    end
    for _, questLineID in ipairs(candidateQuestLineIDs) do
      local questLineEntry = model.questLineByID[questLineID] -- 当前候选任务线对象
      if type(questLineEntry) == "table" and type(requestedMapID) == "number" and questLineEntry.UiMapID == requestedMapID then
        return questLineID, questLineEntry
      end
    end
  end

  return fallbackQuestLineID, fallbackQuestLineEntry
end

--- 基于任务 ID 列表构建任务展示列表。
---@param dataTable table 根数据
---@param questIDList number[] 任务 ID 列表
---@return table[]
local function buildQuestListByQuestIDs(dataTable, questIDList)
  local questList = {} -- 任务展示列表
  for _, questID in ipairs(questIDList or {}) do
    local questEntry = buildQuestEntryByID(dataTable, questID) -- 任务展示对象
    if type(questEntry) == "table" then
      questList[#questList + 1] = questEntry
    end
  end
  return questList
end

--- 基于任务 ID 列表计算进度。
---@param questIDList number[] 任务 ID 列表
---@return table
local function buildProgressFromQuestIDs(questIDList)
  if type(questIDList) ~= "table" or #questIDList == 0 then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }
  end

  local seenQuestSet = {} -- 已统计任务集合
  local completedCount = 0 -- 已完成任务数量
  local totalCount = 0 -- 总任务数量
  local hasActiveQuest = false -- 是否存在进行中任务
  local nextQuestID = nil -- 下一任务 ID
  local nextQuestName = nil -- 下一任务名称

  for _, questID in ipairs(questIDList) do
    if type(questID) == "number" and seenQuestSet[questID] ~= true then
      seenQuestSet[questID] = true
      totalCount = totalCount + 1

      local runtimeState = getCachedQuestRuntimeState(questID) -- 当前任务运行时字段
      local questStatus = runtimeState.status -- 当前任务状态
      local questName = runtimeState.name -- 当前任务名称

      if questStatus == "completed" then
        completedCount = completedCount + 1
      elseif questStatus == "active" then
        hasActiveQuest = true
        if nextQuestID == nil then
          nextQuestID = questID
          nextQuestName = questName
        end
      elseif nextQuestID == nil then
        nextQuestID = questID
        nextQuestName = questName
      end
    end
  end

  return {
    completed = completedCount,
    total = totalCount,
    hasActive = hasActiveQuest,
    nextQuestID = nextQuestID,
    nextQuestName = nextQuestName,
    isCompleted = completedCount == totalCount and totalCount > 0,
  }
end

--- 判断 strict 校验失败是否可按“降级模式”继续构建模型。
---@param errorObject table|nil
---@return boolean
local function isRecoverableValidationError(errorObject)
  if type(errorObject) ~= "table" then
    return false
  end
  local errorCode = errorObject.code -- 错误码
  return errorCode == "E_BAD_REF" or errorCode == "E_DUPLICATE_REF"
end

--- 构建任务页签静态结构模型。
---@param dataTable table 根数据
---@return table|nil model
---@return table|nil errorObject
local function buildQuestTabModel(dataTable)
  local valid, validationError = Toolbox.Questlines.ValidateInstanceQuestlinesData(dataTable, true) -- strict 校验结果
  if not valid and not isRecoverableValidationError(validationError) then
    return nil, validationError
  end

  local model = {
    maps = {},
    mapByID = {},
    questLineByID = {},
    questToQuestLineID = {},
    typeList = {},
    typeToQuestIDs = {},
    typeToQuestLineIDs = {},
    typeToMapIDs = {},
  }
  -- 按 UiMapID 分组任务线，保持 questLines 定义顺序
  local orderedQuestLineIDList = {} -- 有序任务线 ID 列表
  for questLineID in pairs(dataTable.questLines) do
    orderedQuestLineIDList[#orderedQuestLineIDList + 1] = questLineID
  end
  table.sort(orderedQuestLineIDList)

  for _, questLineID in ipairs(orderedQuestLineIDList) do
    local questLineRecord = dataTable.questLines[questLineID] -- 任务线元数据
    if type(questLineRecord) == "table" then
      if isQuestLineAllowedForPlayer(questLineRecord) then
        local uiMapID = questLineRecord.UiMapID -- 归属地图 ID
        local mapEntry = model.mapByID[uiMapID] -- 地图模型
        if type(mapEntry) ~= "table" then
          mapEntry = {
            id = uiMapID,
            name = getMapNameByID(uiMapID),
            questLines = {},
            questCount = 0,
          }
          model.mapByID[uiMapID] = mapEntry
          model.maps[#model.maps + 1] = mapEntry
        end

        local questIDList = buildQuestIDListByQuestLineID(dataTable, questLineID) -- 任务 ID 列表
        local questLineModel = {
          id = questLineID,
          name = type(questLineRecord.Name_lang) == "string" and questLineRecord.Name_lang or nil,
          UiMapID = uiMapID,
          ExpansionID = type(questLineRecord.ContentExpansionID) == "number" and questLineRecord.ContentExpansionID
            or type(questLineRecord.ExpansionID) == "number" and questLineRecord.ExpansionID
            or nil,
          ContentExpansionID = type(questLineRecord.ContentExpansionID) == "number" and questLineRecord.ContentExpansionID or nil,
          UiMapIDs = type(questLineRecord.UiMapIDs) == "table" and questLineRecord.UiMapIDs or nil,
          PrimaryUiMapID = type(questLineRecord.PrimaryUiMapID) == "number" and questLineRecord.PrimaryUiMapID or uiMapID,
          PrimaryMapShare = type(questLineRecord.PrimaryMapShare) == "number" and questLineRecord.PrimaryMapShare or nil,
          FactionTags = type(questLineRecord.FactionTags) == "table" and questLineRecord.FactionTags or nil,
          questIDs = questIDList,
          questCount = #questIDList,
        }

        if questLineModel.questCount > 0 then
          mapEntry.questLines[#mapEntry.questLines + 1] = questLineModel
          mapEntry.questCount = (mapEntry.questCount or 0) + questLineModel.questCount
          model.questLineByID[questLineID] = questLineModel

          for _, questID in ipairs(questIDList) do
            if model.questToQuestLineID[questID] == nil then
              model.questToQuestLineID[questID] = questLineID
            end
          end
        end
      end
    end
  end

  return model, nil
end

--- 获取缓存后的任务页签静态结构模型。
---@return table|nil model
---@return table|nil errorObject
local function getCachedQuestTabModel()
  local dataTable = getQuestlineDataTable() -- 根数据表
  if type(dataTable) ~= "table" then
    return nil, buildValidationError("E_MISSING_FIELD", "root", "InstanceQuestlines table missing")
  end

  if staticModelCache.dataRef == dataTable
    and staticModelCache.generatedAt == dataTable.generatedAt
    and (staticModelCache.model ~= nil or staticModelCache.errorObject ~= nil)
  then
    return staticModelCache.model, staticModelCache.errorObject
  end

  local model, errorObject = buildQuestTabModel(dataTable) -- 构建模型
  staticModelCache.dataRef = dataTable
  staticModelCache.generatedAt = dataTable.generatedAt
  staticModelCache.model = model
  staticModelCache.errorObject = errorObject
  return model, errorObject
end

--- 获取任务页签完整查询模型。
---@return table model
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestTabModel()
  local model, errorObject = getCachedQuestTabModel() -- 缓存模型读取
  if type(model) == "table" then
    return model, nil
  end
  return {
    maps = {},
    mapByID = {},
    questLineByID = {},
    questToQuestLineID = {},
    typeList = {},
    typeToQuestIDs = {},
    typeToQuestLineIDs = {},
    typeToMapIDs = {},
  }, errorObject
end

--- 确保分类分组对象存在。
---@param groupList table[] 分组列表
---@param groupByID table<number, table> 分组索引
---@param groupID number 分组 ID
---@param groupName string 分组名称
---@return table
local function ensureCategoryGroup(groupList, groupByID, groupID, groupName)
  local existingGroup = groupByID[groupID] -- 已存在分组
  if type(existingGroup) == "table" then
    return existingGroup
  end

  local groupEntry = {
    kind = "map",
    id = groupID,
    name = groupName,
    questLines = {},
    _questLineSeen = {},
  }
  groupByID[groupID] = groupEntry
  groupList[#groupList + 1] = groupEntry
  return groupEntry
end

--- 向分类分组追加任务线，避免重复追加。
---@param groupEntry table 分组对象
---@param questLineEntry table 任务线对象
local function appendQuestLineToGroup(groupEntry, questLineEntry)
  if type(groupEntry) ~= "table" or type(questLineEntry) ~= "table" then
    return
  end

  local questLineID = questLineEntry.id -- 当前任务线 ID
  if type(questLineID) ~= "number" then
    return
  end
  if groupEntry._questLineSeen[questLineID] == true then
    return
  end

  groupEntry._questLineSeen[questLineID] = true
  groupEntry.questLines[#groupEntry.questLines + 1] = questLineEntry
end

--- 判断任务线是否适合按地图稳定归类。
---@param questLineEntry table|nil
---@return boolean
local function isQuestLineMapStable(questLineEntry)
  if type(questLineEntry) ~= "table" then
    return false
  end
  if type(questLineEntry.PrimaryUiMapID) ~= "number" or questLineEntry.PrimaryUiMapID <= 0 then
    return false
  end
  local primaryMapShare = questLineEntry.PrimaryMapShare -- 主地图占比
  if type(primaryMapShare) ~= "number" then
    return false
  end
  return primaryMapShare >= 0.60
end

--- 向混合导航列表追加直接任务线项。
---@param expansionEntry table 资料片分组对象
---@param questLineEntry table 任务线对象
local function appendDirectQuestLineToExpansion(expansionEntry, questLineEntry)
  if type(expansionEntry) ~= "table" or type(questLineEntry) ~= "table" then
    return
  end
  expansionEntry._directQuestLineByID = expansionEntry._directQuestLineByID or {} -- 直接任务线索引
  local questLineID = questLineEntry.id -- 当前任务线 ID
  if type(questLineID) ~= "number" or expansionEntry._directQuestLineByID[questLineID] == true then
    return
  end
  expansionEntry._directQuestLineByID[questLineID] = true
  expansionEntry.modeByKey.map_questline.entries[#expansionEntry.modeByKey.map_questline.entries + 1] = {
    kind = "questline",
    id = questLineID,
    name = questLineEntry.name or ("QuestLine #" .. tostring(questLineID)),
    questLine = questLineEntry,
  }
end

--- 排序混合导航列表：地图先、任务线后，各自按名称。
---@param entryList table[]
local function sortMixedNavigationEntries(entryList)
  table.sort(entryList, function(leftEntry, rightEntry)
    local leftKind = type(leftEntry) == "table" and leftEntry.kind or nil -- 左侧条目类型
    local rightKind = type(rightEntry) == "table" and rightEntry.kind or nil -- 右侧条目类型
    if leftKind ~= rightKind then
      if leftKind == "map" then
        return true
      end
      if rightKind == "map" then
        return false
      end
    end
    return tostring(leftEntry and leftEntry.name or "") < tostring(rightEntry and rightEntry.name or "")
  end)
end

--- 构建资料片导航模型。
---@return table model
---@return table|nil errorObject
local function buildQuestNavigationModel()
  local questTabModel, questTabError = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if questTabError then
    return {
      expansionList = {},
      expansionByID = {},
    }, questTabError
  end

  local navigationModel = {
    expansionList = {},
    expansionByID = {},
  }
  local dataTable = getQuestlineDataTable() -- 根数据表

  local function ensureExpansionEntry(expansionID)
    local expansionEntry = navigationModel.expansionByID[expansionID] -- 已存在资料片分组
    if type(expansionEntry) == "table" then
      return expansionEntry
    end

    expansionEntry = {
      id = expansionID,
      name = getExpansionLabel(expansionID),
      modes = {
        {
          key = "map_questline",
          name = (Toolbox.L and Toolbox.L.EJ_QUEST_NAV_MODE_MAP_QUESTLINE) or "地图任务线",
          entries = {},
        },
      },
      modeByKey = {},
      _mapEntryByID = {},
    }
    for _, modeEntry in ipairs(expansionEntry.modes) do
      expansionEntry.modeByKey[modeEntry.key] = modeEntry
    end
    navigationModel.expansionByID[expansionID] = expansionEntry
    navigationModel.expansionList[#navigationModel.expansionList + 1] = {
      id = expansionID,
      name = expansionEntry.name,
    }
    return expansionEntry
  end

  if type(dataTable) == "table" and type(dataTable.schemaVersion) == "number" and dataTable.schemaVersion >= 6 then
    for expansionID, questLineIDList in pairs(dataTable.expansions or {}) do
      if type(expansionID) == "number" and expansionID >= 0 then
        local expansionEntry = ensureExpansionEntry(expansionID) -- 资料片分组
        for _, questLineID in ipairs(questLineIDList or {}) do
          local questLineEntry = questTabModel.questLineByID and questTabModel.questLineByID[questLineID] or nil -- 当前任务线
          local mapEntry = type(questLineEntry) == "table" and questTabModel.mapByID and questTabModel.mapByID[questLineEntry.UiMapID] or nil -- 当前地图
          if type(questLineEntry) == "table" then
            if isQuestLineMapStable(questLineEntry) and type(mapEntry) == "table" then
              local mapGroup = ensureCategoryGroup(
                expansionEntry.modeByKey.map_questline.entries,
                expansionEntry._mapEntryByID,
                mapEntry.id,
                mapEntry.name or getMapNameByID(mapEntry.id)
              )
              appendQuestLineToGroup(mapGroup, questLineEntry)
            else
              appendDirectQuestLineToExpansion(expansionEntry, questLineEntry)
            end
          end
        end
      end
    end
  else
    for _, mapEntry in ipairs(questTabModel.maps or {}) do
      for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
        local expansionID = questLineEntry.ExpansionID -- 当前任务线资料片 ID
        if type(expansionID) == "number" and expansionID >= 0 then
          local expansionEntry = ensureExpansionEntry(expansionID) -- 资料片分组
          local mapGroup = ensureCategoryGroup(
            expansionEntry.modeByKey.map_questline.entries,
            expansionEntry._mapEntryByID,
            mapEntry.id,
            mapEntry.name or getMapNameByID(mapEntry.id)
          )
          appendQuestLineToGroup(mapGroup, questLineEntry)
        end
      end
    end

  end

  table.sort(navigationModel.expansionList, function(leftEntry, rightEntry)
    return (leftEntry.id or 0) < (rightEntry.id or 0)
  end)

  for _, expansionEntry in pairs(navigationModel.expansionByID) do
    sortMixedNavigationEntries(expansionEntry.modeByKey.map_questline.entries or {})
    expansionEntry._mapEntryByID = nil
    expansionEntry._directQuestLineByID = nil
    for _, groupEntry in ipairs(expansionEntry.modeByKey.map_questline.entries or {}) do
      groupEntry._questLineSeen = nil
    end
  end

  return navigationModel, nil
end

--- 获取资料片导航模型。
---@return table model
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestNavigationModel()
  local dataTable = getQuestlineDataTable() -- 根数据表
  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if type(dataTable) ~= "table" then
    return {
      expansionList = {},
      expansionByID = {},
    }, buildValidationError("E_MISSING_FIELD", "root", "InstanceQuestlines table missing")
  end

  if navigationModelCache.dataRef == dataTable
    and navigationModelCache.generatedAt == dataTable.generatedAt
    and navigationModelCache.runtimeKey == runtimeKey
    and (navigationModelCache.model ~= nil or navigationModelCache.errorObject ~= nil)
  then
    return navigationModelCache.model, navigationModelCache.errorObject
  end

  local navigationModel, errorObject = buildQuestNavigationModel() -- 最新导航模型
  navigationModelCache.dataRef = dataTable
  navigationModelCache.generatedAt = dataTable.generatedAt
  navigationModelCache.runtimeKey = runtimeKey
  navigationModelCache.model = navigationModel
  navigationModelCache.errorObject = errorObject
  return navigationModel, errorObject
end

--- 按地图 ID 获取任务线列表。
---@param mapID number|nil
---@param expansionID number|nil 可选资料片 ID；传入后仅返回该资料片下的任务线
---@return table[] questLineList
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestLinesForMap(mapID, expansionID)
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return {}, errorObject
  end
  local mapEntry = type(mapID) == "number" and model.mapByID and model.mapByID[mapID] or nil -- 当前地图对象
  if type(mapEntry) ~= "table" then
    return {}, nil
  end
  if type(expansionID) ~= "number" then
    return mapEntry.questLines or {}, nil
  end

  local filteredQuestLineList = {} -- 指定资料片下的任务线列表
  for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
    if type(questLineEntry) == "table" and questLineEntry.ExpansionID == expansionID then
      filteredQuestLineList[#filteredQuestLineList + 1] = questLineEntry
    end
  end
  return filteredQuestLineList, nil
end

--- 获取任务线显示名缓存表。
---@return table
local function getQuestLineNameCacheBucket()
  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if questLineNameCache.runtimeKey ~= runtimeKey then
    questLineNameCache.runtimeKey = runtimeKey
    questLineNameCache.byQuestLineID = {}
  end
  return questLineNameCache.byQuestLineID
end

--- 选择用于查询任务线名称的代表任务 ID。
---@param questLineEntry table 任务线对象
---@return number|nil
local function selectRepresentativeQuestID(questLineEntry)
  local fallbackQuestID = nil -- 当前任务线回退任务 ID
  for _, questID in ipairs(questLineEntry and questLineEntry.questIDs or {}) do
    if type(questID) == "number" then
      if fallbackQuestID == nil then
        fallbackQuestID = questID
      end
      if isQuestCurrentlyInLog(questID) then
        return questID
      end
    end
  end
  return fallbackQuestID
end

--- 按代表任务查询运行时任务线名称。
---@param questLineID number 任务线 ID
---@param questLineEntry table 任务线对象
---@return string|nil
local function queryRuntimeQuestLineName(questLineID, questLineEntry)
  if type(C_QuestLine) ~= "table" or type(C_QuestLine.GetQuestLineInfo) ~= "function" then
    return nil
  end

  local representativeQuestID = selectRepresentativeQuestID(questLineEntry) -- 代表任务 ID
  if type(representativeQuestID) ~= "number" then
    return nil
  end

  local success, questLineInfo = pcall(C_QuestLine.GetQuestLineInfo, representativeQuestID, questLineEntry.UiMapID, false) -- 运行时任务线信息
  if not success or type(questLineInfo) ~= "table" then
    return nil
  end

  local runtimeQuestLineID = questLineInfo.questLineID -- 运行时任务线 ID
  local runtimeQuestLineName = questLineInfo.questLineName -- 运行时任务线名称
  if type(runtimeQuestLineID) == "number" and runtimeQuestLineID ~= questLineID then
    return nil
  end
  if type(runtimeQuestLineName) ~= "string" or runtimeQuestLineName == "" then
    return nil
  end
  return runtimeQuestLineName
end

--- 获取任务线显示名。优先使用运行时 API，失败时回退到静态名称。
---@param questLineID number 任务线 ID
---@return string|nil displayName
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestLineDisplayName(questLineID)
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return nil, errorObject
  end
  if type(questLineID) ~= "number" then
    return nil, nil
  end

  local questLineEntry = model.questLineByID and model.questLineByID[questLineID] or nil -- 当前任务线对象
  if type(questLineEntry) ~= "table" then
    return nil, nil
  end

  local staticName = type(questLineEntry.name) == "string" and questLineEntry.name or ("QuestLine #" .. tostring(questLineID or "?")) -- 静态任务线名称
  local cacheBucket = getQuestLineNameCacheBucket() -- 任务线显示名缓存表
  local cachedName = cacheBucket[questLineID] -- 已缓存显示名
  if type(cachedName) == "string" and cachedName ~= "" then
    return cachedName, nil
  end

  local runtimeName = queryRuntimeQuestLineName(questLineID, questLineEntry) -- 运行时任务线名称
  local displayName = type(runtimeName) == "string" and runtimeName ~= "" and runtimeName or staticName -- 最终显示名称
  cacheBucket[questLineID] = displayName
  return displayName, nil
end

--- 按当前选中节点查询任务线列表。
---@param selectedKind string 选中类型（map|questline|quest）
---@param mapID number|nil 地图 ID
---@return table[] questLineList
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestLinesForSelection(selectedKind, mapID)
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return {}, errorObject
  end

  if selectedKind == "questline" or selectedKind == "quest" then
    return {}, nil
  end

  if selectedKind == "map" and type(mapID) == "number" then
    local mapEntry = model.mapByID[mapID] -- 地图模型
    if type(mapEntry) == "table" then
      return mapEntry.questLines or {}, nil
    end
    return {}, nil
  end

  -- 默认返回全部任务线（平铺）
  local resultList = {} -- 全部任务线列表
  for _, mapEntry in ipairs(model.maps or {}) do
    for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
      resultList[#resultList + 1] = questLineEntry
    end
  end
  return resultList, nil
end

--- 按任务线 ID 获取任务列表。
---@param questLineID number
---@return table[] questList
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestListByQuestLineID(questLineID)
  local dataTable = getQuestlineDataTable() -- 根数据表
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject or type(dataTable) ~= "table" then
    return {}, errorObject
  end
  local questLineEntry = type(questLineID) == "number" and model.questLineByID[questLineID] or nil -- 任务线对象
  if type(questLineEntry) ~= "table" then
    return {}, nil
  end
  return buildQuestListByQuestIDs(dataTable, questLineEntry.questIDs or {}), nil
end

--- 枚举当前 Quest Log 中的任务条目。
---@return table[] questEntryList
---@return table|nil errorObject
function Toolbox.Questlines.GetCurrentQuestLogEntries()
  if type(getNumQuestLogEntriesFn) ~= "function" or type(getQuestLogInfoFn) ~= "function" then
    return {}, nil
  end

  local countSuccess, numShownEntries = pcall(getNumQuestLogEntriesFn) -- Quest Log 可枚举条目数
  if not countSuccess or type(numShownEntries) ~= "number" or numShownEntries <= 0 then
    return {}, nil
  end

  local questEntryList = {} -- 当前 Quest Log 任务列表
  local seenQuestSet = {} -- 已收集任务集合
  for questLogIndex = 1, numShownEntries do
    local infoSuccess, questInfo = pcall(getQuestLogInfoFn, questLogIndex) -- 当前 Quest Log 条目
    local questID = infoSuccess and type(questInfo) == "table" and questInfo.questID or nil -- 当前任务 ID
    if type(questID) == "number" and questID > 0 and seenQuestSet[questID] ~= true and questInfo.isHeader ~= true then
      seenQuestSet[questID] = true

      local runtimeState = getCachedQuestRuntimeState(questID) -- 当前任务运行时字段
      local detailObject = nil -- 当前任务详情对象
      local detailError = nil -- 当前任务详情错误
      detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(questID)
      if detailError then
        detailObject = nil
      end

      questEntryList[#questEntryList + 1] = {
        questID = questID,
        name = type(questInfo.title) == "string" and questInfo.title or runtimeState.name,
        status = runtimeState.status,
        readyForTurnIn = runtimeState.readyForTurnIn,
        typeID = runtimeState.typeID,
        questLineID = type(detailObject) == "table" and detailObject.questLineID or nil,
        questLineName = type(detailObject) == "table" and detailObject.questLineName or nil,
        UiMapID = type(detailObject) == "table" and detailObject.UiMapID or nil,
      }
    end
  end

  return questEntryList, nil
end

--- 按任务线 ID 获取进度摘要。
---@param questLineID number
---@return table progressObject
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestLineProgress(questLineID)
  local dataTable = getQuestlineDataTable() -- 根数据表
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject or type(dataTable) ~= "table" then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }, errorObject
  end

  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if progressCache.dataRef ~= dataTable
    or progressCache.generatedAt ~= dataTable.generatedAt
    or progressCache.runtimeKey ~= runtimeKey
  then
    progressCache.dataRef = dataTable
    progressCache.generatedAt = dataTable.generatedAt
    progressCache.runtimeKey = runtimeKey
    progressCache.mapByID = {}
    progressCache.questLineByID = {}
  end

  if type(progressCache.questLineByID[questLineID]) == "table" then
    return progressCache.questLineByID[questLineID], nil
  end

  local questLineEntry = type(questLineID) == "number" and model.questLineByID[questLineID] or nil -- 任务线对象
  if type(questLineEntry) ~= "table" then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }, nil
  end

  local progressObject = buildProgressFromQuestIDs(questLineEntry.questIDs or {}) -- 任务线进度
  progressCache.questLineByID[questLineID] = progressObject
  return progressObject, nil
end

--- 按地图 ID 获取聚合进度。
---@param mapID number
---@return table progressObject
---@return table|nil errorObject
function Toolbox.Questlines.GetMapProgress(mapID)
  local dataTable = getQuestlineDataTable() -- 根数据表
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject or type(dataTable) ~= "table" then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }, errorObject
  end

  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if progressCache.dataRef ~= dataTable
    or progressCache.generatedAt ~= dataTable.generatedAt
    or progressCache.runtimeKey ~= runtimeKey
  then
    progressCache.dataRef = dataTable
    progressCache.generatedAt = dataTable.generatedAt
    progressCache.runtimeKey = runtimeKey
    progressCache.mapByID = {}
    progressCache.questLineByID = {}
  end

  if type(progressCache.mapByID[mapID]) == "table" then
    return progressCache.mapByID[mapID], nil
  end

  local mapEntry = type(mapID) == "number" and model.mapByID[mapID] or nil -- 地图对象
  if type(mapEntry) ~= "table" then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }, nil
  end

  local questIDList = {} -- 地图内任务 ID 列表
  for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
    for _, questID in ipairs(questLineEntry.questIDs or {}) do
      questIDList[#questIDList + 1] = questID
    end
  end

  local progressObject = buildProgressFromQuestIDs(questIDList) -- 地图聚合进度
  progressCache.mapByID[mapID] = progressObject
  return progressObject, nil
end

--- 构建按任务类型聚合的运行时索引。
---@param questTabModel table 任务页签静态模型
---@return table typeIndexModel
local function buildQuestTypeIndexModel(questTabModel)
  local typeIndexModel = {
    typeList = {},
    typeToQuestIDs = {},
    typeToQuestLineIDs = {},
    typeToMapIDs = {},
  }
  local typeSeenSet = {} -- 已收录类型集合
  local typeQuestSeenSet = {} -- typeID -> questID 集合
  local typeQuestLineSeenSet = {} -- typeID -> questLineID 集合
  local typeMapSeenSet = {} -- typeID -> mapID 集合

  for _, mapEntry in ipairs(questTabModel.maps or {}) do
    for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
      local questLineTypeIDSet = {} -- 当前任务线出现的类型集合
      for _, questID in ipairs(questLineEntry.questIDs or {}) do
        local runtimeState = getCachedQuestRuntimeState(questID) -- 任务运行时字段
        local typeID = runtimeState.typeID -- 当前任务类型 ID
        if type(typeID) == "number" then
          if typeSeenSet[typeID] ~= true then
            typeSeenSet[typeID] = true
            typeIndexModel.typeList[#typeIndexModel.typeList + 1] = {
              id = typeID,
              name = getRuntimeQuestTypeName(questID, typeID),
            }
          end

          if type(typeQuestSeenSet[typeID]) ~= "table" then
            typeQuestSeenSet[typeID] = {}
            typeIndexModel.typeToQuestIDs[typeID] = {}
          end
          if typeQuestSeenSet[typeID][questID] ~= true then
            typeQuestSeenSet[typeID][questID] = true
            typeIndexModel.typeToQuestIDs[typeID][#typeIndexModel.typeToQuestIDs[typeID] + 1] = questID
          end

          questLineTypeIDSet[typeID] = true

          if type(typeMapSeenSet[typeID]) ~= "table" then
            typeMapSeenSet[typeID] = {}
            typeIndexModel.typeToMapIDs[typeID] = {}
          end
          if typeMapSeenSet[typeID][mapEntry.id] ~= true then
            typeMapSeenSet[typeID][mapEntry.id] = true
            typeIndexModel.typeToMapIDs[typeID][#typeIndexModel.typeToMapIDs[typeID] + 1] = mapEntry.id
          end
        end
      end

      for typeID in pairs(questLineTypeIDSet) do
        if type(typeQuestLineSeenSet[typeID]) ~= "table" then
          typeQuestLineSeenSet[typeID] = {}
          typeIndexModel.typeToQuestLineIDs[typeID] = {}
        end
        if typeQuestLineSeenSet[typeID][questLineEntry.id] ~= true then
          typeQuestLineSeenSet[typeID][questLineEntry.id] = true
          typeIndexModel.typeToQuestLineIDs[typeID][#typeIndexModel.typeToQuestLineIDs[typeID] + 1] = questLineEntry.id
        end
      end
    end
  end

  table.sort(typeIndexModel.typeList, function(leftEntry, rightEntry)
    local leftID = type(leftEntry) == "table" and leftEntry.id or nil -- 左侧类型 ID
    local rightID = type(rightEntry) == "table" and rightEntry.id or nil -- 右侧类型 ID
    if type(leftID) ~= "number" then
      return false
    end
    if type(rightID) ~= "number" then
      return true
    end
    return leftID < rightID
  end)
  return typeIndexModel
end

--- 获取按任务类型聚合的运行时索引。
---@return table typeIndexModel
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestTypeIndex()
  local dataTable = getQuestlineDataTable() -- 根数据表
  local questTabModel, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 静态结构模型
  if errorObject or type(dataTable) ~= "table" then
    return {
      typeList = {},
      typeToQuestIDs = {},
      typeToQuestLineIDs = {},
      typeToMapIDs = {},
    }, errorObject
  end

  local runtimeKey = getRuntimeCacheKey() -- 当前运行时缓存键
  if typeIndexCache.dataRef == dataTable
    and typeIndexCache.generatedAt == dataTable.generatedAt
    and typeIndexCache.runtimeKey == runtimeKey
    and (typeIndexCache.model ~= nil or typeIndexCache.errorObject ~= nil)
  then
    return typeIndexCache.model, typeIndexCache.errorObject
  end

  local typeIndexModel = buildQuestTypeIndexModel(questTabModel) -- 类型运行时索引
  typeIndexCache.dataRef = dataTable
  typeIndexCache.generatedAt = dataTable.generatedAt
  typeIndexCache.runtimeKey = runtimeKey
  typeIndexCache.model = typeIndexModel
  typeIndexCache.errorObject = nil
  return typeIndexModel, nil
end

--- 按任务 ID 获取任务详情。
---@param questID number
---@param contextOptions table|nil 任务线上下文（可选）
---@return table|nil detailObject
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestDetailByID(questID, contextOptions)
  local dataTable = getQuestlineDataTable() -- 根数据表
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return nil, errorObject
  end

  if type(questID) ~= "number" then
    return nil, nil
  end

  local questRecord = dataTable.quests and dataTable.quests[questID] or nil -- 任务静态记录
  local runtimeState = getCachedQuestRuntimeState(questID) -- 任务运行时字段
  if type(questRecord) ~= "table" or not isQuestAllowedForPlayer(questRecord) then
    if isQuestCurrentlyInLog(questID) then
      return {
        questID = questID,
        name = runtimeState.name,
        status = runtimeState.status,
        readyForTurnIn = runtimeState.readyForTurnIn,
        UiMapID = nil,
        typeID = runtimeState.typeID,
        mapPos = nil,
        npcIDs = runtimeState.npcIDs,
        npcPos = runtimeState.npcPos,
        questLineID = nil,
        questLineName = nil,
        questLineExpansionID = nil,
        runtime = runtimeState,
      }, nil
    end
    return nil, nil
  end

  local questLineID, questLineEntry = resolveQuestLineContext(model, questRecord, questID, contextOptions) -- 当前上下文任务线
  local resolvedUiMapID = type(questRecord.UiMapID) == "number" and questRecord.UiMapID
    or type(questLineEntry) == "table" and questLineEntry.UiMapID
    or nil -- 详情页使用的地图 ID

  return {
    questID = questID,
    name = runtimeState.name,
    status = runtimeState.status,
    readyForTurnIn = runtimeState.readyForTurnIn,
    UiMapID = resolvedUiMapID,
    typeID = runtimeState.typeID,
    mapPos = resolveQuestMapPos(dataTable, questID, questRecord),
    npcIDs = runtimeState.npcIDs,
    npcPos = runtimeState.npcPos,
    questLineID = questLineID,
    questLineName = questLineEntry and questLineEntry.name or nil,
    questLineExpansionID = type(questLineEntry) == "table" and questLineEntry.ExpansionID or nil,
    runtime = runtimeState,
  }, nil
end

--- 构建任务详情调试快照，供异步输出使用。
---@param questID number
---@return table|nil snapshotObject
---@return table|nil errorObject
local function buildQuestDebugSnapshot(questID)
  if type(questID) ~= "number" then
    return nil, nil
  end

  local questLogIndex = getSafeQuestLogIndex(questID) -- 当前任务日志索引
  local descriptionText, objectiveText = getQuestTextByLogIndex(questLogIndex) -- 任务描述与目标摘要
  local objectiveList = getQuestObjectivesByID(questID) -- 任务目标列表
  local tagInfo = getQuestTagInfoByID(questID) -- 任务标签信息
  local uiMapID = getQuestZoneMapID(questID) -- API 返回的任务地图 ID
  local mapChainObject = buildMapChainSnapshot(uiMapID) -- 地图父链快照
  local questLineInfo = getQuestLineApiInfo(questID, uiMapID) -- 任务线原始 API 信息
  local runtimeState = getCachedQuestRuntimeState(questID) -- 任务运行时状态
  local titleText = getQuestNameByID(questID) or runtimeState.name -- 任务标题
  if type(titleText) ~= "string" or titleText == "" then
    titleText = "Quest #" .. tostring(questID)
  end

  return {
    questID = questID,
    title = titleText,
    logIndex = questLogIndex,
    inQuestLog = type(questLogIndex) == "number",
    status = runtimeState.status,
    readyForTurnIn = runtimeState.readyForTurnIn == true,
    mapID = uiMapID,
    mapName = mapChainObject.zoneMapName or getMapNameByID(uiMapID),
    parentMapList = mapChainObject.parentMapList,
    continentMapID = mapChainObject.continentMapID,
    continentMapName = mapChainObject.continentMapName,
    questLineInfo = questLineInfo,
    questLine = type(questLineInfo) == "table" and {
      questLineID = questLineInfo.questLineID,
      questLineName = questLineInfo.questLineName,
      questLineQuestID = questLineInfo.questLineQuestID,
      campaignID = questLineInfo.campaignID,
      x = questLineInfo.x,
      y = questLineInfo.y,
    } or nil,
    questLineID = type(questLineInfo) == "table" and questLineInfo.questLineID or nil,
    questLineName = type(questLineInfo) == "table" and questLineInfo.questLineName or nil,
    questLineQuestID = type(questLineInfo) == "table" and questLineInfo.questLineQuestID or nil,
    campaignID = type(questLineInfo) == "table" and questLineInfo.campaignID or nil,
    typeID = runtimeState.typeID,
    typeLabel = getQuestTypeLabel(runtimeState.typeID),
    tagID = type(tagInfo) == "table" and tagInfo.tagID or nil,
    tagName = type(tagInfo) == "table" and tagInfo.tagName or nil,
    worldQuestType = type(tagInfo) == "table" and tagInfo.worldQuestType or nil,
    description = descriptionText,
    objectiveText = objectiveText,
    objectiveList = objectiveList,
    objectives = objectiveList,
  }, nil
end

--- 将标量值格式化为任务详情查询页使用的文本。
---@param valueObject any
---@return string
local function formatQuestInspectorScalar(valueObject)
  local unavailableText = getQuestDumpLocaleText("EJ_QUEST_DEBUG_UNAVAILABLE", "unavailable") -- 缺失值占位文本
  if valueObject == nil then
    return unavailableText
  end
  if type(valueObject) == "boolean" then
    return tostring(valueObject == true)
  end
  return tostring(valueObject)
end

--- 递归拍平任务详情快照为“字段名: 字段值”文本行。
---@param lineList string[]
---@param pathText string
---@param valueObject any
local function appendQuestInspectorLines(lineList, pathText, valueObject)
  if type(valueObject) ~= "table" then
    lineList[#lineList + 1] = string.format("%s: %s", pathText, formatQuestInspectorScalar(valueObject))
    return
  end

  local hasValue = false -- 当前表是否包含可遍历字段
  if #valueObject > 0 then
    hasValue = true
    for index, nestedValue in ipairs(valueObject) do
      appendQuestInspectorLines(lineList, string.format("%s[%d]", pathText, index), nestedValue)
    end
  end

  local keyList = {} -- 非数组键列表
  for keyName in pairs(valueObject) do
    if not (type(keyName) == "number" and keyName >= 1 and keyName <= #valueObject and math.floor(keyName) == keyName) then
      keyList[#keyList + 1] = keyName
    end
  end
  table.sort(keyList, function(leftKey, rightKey)
    return tostring(leftKey) < tostring(rightKey)
  end)

  if #keyList > 0 then
    hasValue = true
    for _, keyName in ipairs(keyList) do
      appendQuestInspectorLines(lineList, string.format("%s.%s", pathText, tostring(keyName)), valueObject[keyName])
    end
  end

  if not hasValue then
    lineList[#lineList + 1] = string.format("%s: {}", pathText)
  end
end

--- 构建任务详情查询页的扁平化文本行。
---@param snapshotObject table
---@return string[]
local function buildQuestInspectorFlatLines(snapshotObject)
  local lineList = {} -- 扁平化结果行
  local orderedKeyList = {
    "questID",
    "title",
    "status",
    "readyForTurnIn",
    "logIndex",
    "inQuestLog",
    "typeID",
    "typeLabel",
    "tagID",
    "tagName",
    "worldQuestType",
    "mapID",
    "mapName",
    "continentMapID",
    "continentMapName",
    "questLineID",
    "questLineName",
    "questLineQuestID",
    "campaignID",
    "questLine",
    "description",
    "objectiveText",
    "parentMapList",
    "objectives",
    "questLineInfo",
  }
  local appendedKeySet = {} -- 已输出字段集合

  for _, keyName in ipairs(orderedKeyList) do
    appendedKeySet[keyName] = true
    appendQuestInspectorLines(lineList, keyName, snapshotObject[keyName])
  end

  local remainingKeyList = {} -- 其余字段
  for keyName in pairs(snapshotObject) do
    if keyName ~= "flatLines" and not appendedKeySet[keyName] then
      remainingKeyList[#remainingKeyList + 1] = keyName
    end
  end
  table.sort(remainingKeyList, function(leftKey, rightKey)
    return tostring(leftKey) < tostring(rightKey)
  end)
  for _, keyName in ipairs(remainingKeyList) do
    appendQuestInspectorLines(lineList, tostring(keyName), snapshotObject[keyName])
  end

  return lineList
end

--- 构建供设置页展示的结构化任务详情快照。
---@param questID number 任务 ID
---@return table|nil snapshotObject
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestInspectorSnapshot(questID)
  local snapshotObject, errorObject = buildQuestDebugSnapshot(questID) -- 任务详情快照
  if errorObject or type(snapshotObject) ~= "table" then
    return snapshotObject, errorObject
  end
  snapshotObject.flatLines = buildQuestInspectorFlatLines(snapshotObject)
  return snapshotObject, nil
end

--- 将任务调试快照转成聊天输出文本。
---@param snapshotObject table
---@param loadStateText string
---@return string[]
local function buildQuestDumpLines(snapshotObject, loadStateText)
  local lineList = {} -- 聊天输出文本列表
  local objectiveList = type(snapshotObject.objectiveList) == "table" and snapshotObject.objectiveList or {} -- 任务目标列表
  local titleFormat = getQuestDumpLocaleText("EJ_QUEST_DEBUG_HEADER_FMT", "Quest Debug | id=%s | %s") -- 标题格式
  local loadLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_LOAD_STATE", "Load") -- 加载状态标签
  local questLogLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_IN_LOG", "In Log") -- 任务日志标签
  local mapLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_MAP", "Map") -- 地图标签
  local parentMapLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_PARENT_MAPS", "Parent Maps") -- 父地图标签
  local continentMapLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_CONTINENT_MAP", "Continent Map") -- 大陆地图标签
  local questLineLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_QUESTLINE_API", "QuestLine API") -- 任务线 API 标签
  local typeLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_TYPE", "Type") -- 类型标签
  local tagLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_TAG", "Tag") -- 标签标签
  local descriptionLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_DESCRIPTION", "Description") -- 描述标签
  local objectiveTextLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_OBJECTIVE_TEXT", "Objective Text") -- 目标摘要标签
  local objectiveHeaderLabel = getQuestDumpLocaleText("EJ_QUEST_DEBUG_OBJECTIVES", "Objectives") -- 目标列表标签
  local unavailableText = getQuestDumpLocaleText("EJ_QUEST_DEBUG_UNAVAILABLE", "unavailable") -- 缺失字段文本

  lineList[#lineList + 1] = string.format(titleFormat, tostring(snapshotObject.questID), tostring(snapshotObject.title))
  lineList[#lineList + 1] = string.format(
    "status=%s | ready=%s | logIndex=%s | %s=%s | %s=%s",
    tostring(snapshotObject.status or unavailableText),
    tostring(snapshotObject.readyForTurnIn == true),
    tostring(snapshotObject.logIndex or unavailableText),
    loadLabel,
    tostring(loadStateText or unavailableText),
    questLogLabel,
    tostring(snapshotObject.inQuestLog == true)
  )
  lineList[#lineList + 1] = string.format(
    "%s=%s(%s) | %s=%s(%s) | %s=%s(%s)",
    mapLabel,
    tostring(snapshotObject.mapName or unavailableText),
    tostring(snapshotObject.mapID or unavailableText),
    continentMapLabel,
    tostring(snapshotObject.continentMapName or unavailableText),
    tostring(snapshotObject.continentMapID or unavailableText),
    typeLabel,
    tostring(snapshotObject.typeLabel or unavailableText),
    tostring(snapshotObject.typeID or unavailableText)
  )
  lineList[#lineList + 1] = string.format(
    "%s=%s(%s) | worldQuestType=%s",
    tagLabel,
    tostring(snapshotObject.tagName or unavailableText),
    tostring(snapshotObject.tagID or unavailableText),
    tostring(snapshotObject.worldQuestType or unavailableText)
  )
  if type(snapshotObject.parentMapList) == "table" and #snapshotObject.parentMapList > 0 then
    local parentTextList = {} -- 父地图文本列表
    for _, parentEntry in ipairs(snapshotObject.parentMapList) do
      parentTextList[#parentTextList + 1] = string.format(
        "%s(%s)",
        tostring(parentEntry.name or unavailableText),
        tostring(parentEntry.mapID or unavailableText)
      )
    end
    lineList[#lineList + 1] = string.format("%s: %s", parentMapLabel, table.concat(parentTextList, " -> "))
  end
  if type(snapshotObject.questLineInfo) == "table" then
    lineList[#lineList + 1] = string.format(
      "%s: questLineID=%s | questLineName=%s | campaignID=%s",
      questLineLabel,
      tostring(snapshotObject.questLineInfo.questLineID or unavailableText),
      tostring(snapshotObject.questLineInfo.questLineName or unavailableText),
      tostring(snapshotObject.questLineInfo.campaignID or unavailableText)
    )
  end

  if type(snapshotObject.description) == "string" and snapshotObject.description ~= "" then
    lineList[#lineList + 1] = string.format("%s: %s", descriptionLabel, snapshotObject.description)
  end
  if type(snapshotObject.objectiveText) == "string" and snapshotObject.objectiveText ~= "" then
    lineList[#lineList + 1] = string.format("%s: %s", objectiveTextLabel, snapshotObject.objectiveText)
  end

  if #objectiveList > 0 then
    lineList[#lineList + 1] = objectiveHeaderLabel .. ":"
    for objectiveIndex, objectiveObject in ipairs(objectiveList) do
      local progressText = string.format(
        "%s/%s",
        tostring(objectiveObject.numFulfilled or 0),
        tostring(objectiveObject.numRequired or 0)
      )
      lineList[#lineList + 1] = string.format(
        "  %d. %s | type=%s | finished=%s | progress=%s",
        objectiveIndex,
        tostring(objectiveObject.text or unavailableText),
        tostring(objectiveObject.type or unavailableText),
        tostring(objectiveObject.finished == true),
        progressText
      )
    end
  end

  return lineList
end

--- 记录本次任务详情输出时间，供后续同任务节流。
---@param questID number
local function markQuestDumpPrinted(questID)
  if type(questID) ~= "number" then
    return
  end
  asyncQuestDumpState.lastDumpAtByQuestID[questID] = getCurrentTimeSeconds()
end

--- 判断是否应跳过过于频繁的同任务输出。
---@param questID number
---@param forcePrint boolean|nil
---@return boolean
local function shouldThrottleQuestDump(questID, forcePrint)
  if forcePrint == true or type(questID) ~= "number" then
    return false
  end

  local lastDumpAt = asyncQuestDumpState.lastDumpAtByQuestID[questID] -- 上次输出时间
  if type(lastDumpAt) ~= "number" then
    return false
  end
  return (getCurrentTimeSeconds() - lastDumpAt) < 1.5
end

--- 执行任务详情聊天输出。
---@param questID number
---@param loadStateText string
---@param forcePrint boolean|nil
local function dumpQuestDetailsToChat(questID, loadStateText, forcePrint)
  if shouldThrottleQuestDump(questID, forcePrint) then
    return
  end

  local snapshotObject, errorObject = buildQuestDebugSnapshot(questID) -- 任务调试快照
  if errorObject or type(snapshotObject) ~= "table" then
    local failureFormat = getQuestDumpLocaleText("EJ_QUEST_DEBUG_FAILED_FMT", "Quest Debug failed for %s") -- 失败提示格式
    printQuestDumpLine(string.format(failureFormat, tostring(questID)))
    markQuestDumpPrinted(questID)
    return
  end

  local lineList = buildQuestDumpLines(snapshotObject, loadStateText) -- 聊天输出文本列表
  for _, messageText in ipairs(lineList) do
    printQuestDumpLine(messageText)
  end
  markQuestDumpPrinted(questID)
end

--- 分发任务缓存加载回调。
---@param questID number
---@param success boolean
local function dispatchQuestLoadCallbacks(questID, success)
  local callbackList = asyncQuestDumpState.callbackListByQuestID[questID] -- 当前任务挂起回调列表
  asyncQuestDumpState.callbackListByQuestID[questID] = nil
  asyncQuestDumpState.pendingRequestByQuestID[questID] = nil
  if type(callbackList) ~= "table" then
    return
  end

  for _, callbackFunction in ipairs(callbackList) do
    if type(callbackFunction) == "function" then
      pcall(callbackFunction, questID, success == true)
    end
  end
end

--- 确保任务缓存加载事件框体已创建。
---@return table|nil
local function ensureQuestDumpEventFrame()
  if asyncQuestDumpState.eventFrame then
    return asyncQuestDumpState.eventFrame
  end

  local runtimeTable = Toolbox and Toolbox.Runtime or nil -- 运行时适配表
  local createFrameFn = runtimeTable and runtimeTable.CreateFrame or CreateFrame -- Frame 创建函数
  if type(createFrameFn) ~= "function" then
    return nil
  end

  local eventFrame = createFrameFn("Frame", "ToolboxQuestDetailLoaderFrame", UIParent) -- 任务加载事件框体
  if not eventFrame then
    return nil
  end
  eventFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
  eventFrame:SetScript("OnEvent", function(_, eventName, loadedQuestID, success)
    if eventName == "QUEST_DATA_LOAD_RESULT" and type(loadedQuestID) == "number" then
      dispatchQuestLoadCallbacks(loadedQuestID, success == true)
    end
  end)
  asyncQuestDumpState.eventFrame = eventFrame
  return eventFrame
end

--- 请求任务缓存并在加载结果返回后执行回调。
---@param questID number
---@param callbackFunction function
---@return boolean accepted
---@return string stateText
local function requestQuestDataAsync(questID, callbackFunction)
  local liveRequestLoadQuestByIDFn = type(C_QuestLog) == "table" and C_QuestLog.RequestLoadQuestByID or requestLoadQuestByIDFn -- 当前任务缓存请求函数
  if type(questID) ~= "number" or type(callbackFunction) ~= "function" then
    return false, "invalid"
  end

  if type(liveRequestLoadQuestByIDFn) ~= "function" then
    callbackFunction(questID, false)
    return false, "unsupported"
  end

  if not ensureQuestDumpEventFrame() then
    callbackFunction(questID, false)
    return false, "no_frame"
  end

  local callbackList = asyncQuestDumpState.callbackListByQuestID[questID] -- 当前任务挂起回调列表
  if type(callbackList) ~= "table" then
    callbackList = {}
    asyncQuestDumpState.callbackListByQuestID[questID] = callbackList
  end
  callbackList[#callbackList + 1] = callbackFunction

  if asyncQuestDumpState.pendingRequestByQuestID[questID] == true then
    return true, "pending"
  end

  asyncQuestDumpState.pendingRequestByQuestID[questID] = true
  local requestSuccess = pcall(liveRequestLoadQuestByIDFn, questID) -- 请求任务缓存
  if not requestSuccess then
    dispatchQuestLoadCallbacks(questID, false)
    return false, "request_failed"
  end
  return true, "pending"
end

--- 异步请求任务缓存，并将当前可解析到的任务详情输出到聊天框。
---@param questID number 任务 ID
---@param options table|nil 可选项：`force` 为 true 时跳过短时间节流
---@return boolean accepted 是否已接受本次请求
---@return string stateText `ready`|`pending`|`throttled` 等状态
function Toolbox.Questlines.RequestAndDumpQuestDetailsToChat(questID, options)
  local requestOptions = type(options) == "table" and options or {} -- 调用选项
  if type(questID) ~= "number" or questID <= 0 then
    return false, "invalid_quest_id"
  end
  if shouldThrottleQuestDump(questID, requestOptions.force) then
    return true, "throttled"
  end

  if getSafeQuestLogIndex(questID) ~= nil then
    dumpQuestDetailsToChat(questID, "ready", requestOptions.force)
    return true, "ready"
  end

  local questTitle = getQuestNameByID(questID) -- 当前已缓存的任务标题
  local liveRequestLoadQuestByIDFn = type(C_QuestLog) == "table" and C_QuestLog.RequestLoadQuestByID or requestLoadQuestByIDFn -- 当前任务缓存请求函数
  if type(questTitle) == "string" and questTitle ~= "" and type(liveRequestLoadQuestByIDFn) ~= "function" then
    dumpQuestDetailsToChat(questID, "ready", requestOptions.force)
    return true, "ready"
  end

  return requestQuestDataAsync(questID, function(loadedQuestID, success)
    local loadStateText = success == true and "loaded" or "failed" -- 加载结果文本
    dumpQuestDetailsToChat(loadedQuestID, loadStateText, true)
  end)
end

--- 异步请求任务详情快照；若当前已可读取，则直接返回结果。
---@param questID number 任务 ID
---@param callbackFunction function|nil 回调：`function(questID, stateText, snapshotObject, errorObject)`。
---@return boolean accepted
---@return string stateText
---@return table|nil snapshotObject
---@return table|nil errorObject
function Toolbox.Questlines.RequestQuestInspectorSnapshot(questID, callbackFunction)
  if type(questID) ~= "number" or questID <= 0 then
    return false, "invalid_quest_id", nil, nil
  end

  local snapshotObject, errorObject = Toolbox.Questlines.GetQuestInspectorSnapshot(questID) -- 当前可读快照
  if getSafeQuestLogIndex(questID) ~= nil then
    if type(callbackFunction) == "function" then
      pcall(callbackFunction, questID, "ready", snapshotObject, errorObject)
    end
    return true, "ready", snapshotObject, errorObject
  end

  local questTitle = getQuestNameByID(questID) -- 当前已缓存的任务标题
  local liveRequestLoadQuestByIDFn = type(C_QuestLog) == "table" and C_QuestLog.RequestLoadQuestByID or requestLoadQuestByIDFn -- 当前任务缓存请求函数
  if type(questTitle) == "string" and questTitle ~= "" and type(liveRequestLoadQuestByIDFn) ~= "function" then
    if type(callbackFunction) == "function" then
      pcall(callbackFunction, questID, "ready", snapshotObject, errorObject)
    end
    return true, "ready", snapshotObject, errorObject
  end

  local accepted, stateText = requestQuestDataAsync(questID, function(loadedQuestID, success)
    local loadedStateText = success == true and "loaded" or "failed" -- 异步加载状态
    local loadedSnapshotObject, loadedErrorObject = Toolbox.Questlines.GetQuestInspectorSnapshot(loadedQuestID) -- 加载完成后的快照
    if type(callbackFunction) == "function" then
      pcall(callbackFunction, loadedQuestID, loadedStateText, loadedSnapshotObject, loadedErrorObject)
    end
  end)
  return accepted, stateText, snapshotObject, errorObject
end
