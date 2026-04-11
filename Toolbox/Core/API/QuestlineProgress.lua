--[[
  任务线进度领域 API（Toolbox.Questlines）。
  设计目标：
    1. 以 schema v3（quests/questLines/questLineQuestIDs）作为唯一数据源。
    2. 提供 strict 校验、任务页签查询模型与任务详情查询接口。
    3. 字段名与 wow.db 对齐：ID/Name_lang/UiMapID。
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
local progressCache = { -- 地图/任务线进度缓存
  dataRef = nil,
  generatedAt = nil,
  runtimeKey = nil,
  mapByID = {},
  questLineByID = {},
}
local dataOverrideTable = nil -- 测试框架注入的数据源（nil 表示使用 live 数据）

local getLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID -- 任务日志索引查询函数
local isQuestCompletedFn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted -- 任务完成状态函数
local isQuestReadyForTurnInFn = C_QuestLog and C_QuestLog.ReadyForTurnIn or nil -- 任务可交付状态函数
local getQuestTypeFn = C_QuestLog and C_QuestLog.GetQuestType or nil -- 任务类型函数
local getNumQuestLogEntriesFn = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or nil -- Quest Log 条目总数函数
local getQuestLogInfoFn = C_QuestLog and C_QuestLog.GetInfo or nil -- Quest Log 条目详情函数

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
  progressCache = {
    dataRef = nil,
    generatedAt = nil,
    runtimeKey = nil,
    mapByID = {},
    questLineByID = {},
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

  if isQuestCompletedFn and isQuestCompletedFn(questID) then
    return "completed"
  end

  if getLogIndexForQuestID then
    local logIndex = getLogIndexForQuestID(questID) -- 当前任务日志索引
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

  if isQuestReadyForTurnInFn then
    local success, readyValue = pcall(isQuestReadyForTurnInFn, questID) -- 任务可交付状态
    if success then
      runtimeState.readyForTurnIn = readyValue == true
    end
  end

  if getQuestTypeFn then
    local success, typeValue = pcall(getQuestTypeFn, questID) -- 任务类型
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
  if type(questID) ~= "number" or type(getLogIndexForQuestID) ~= "function" then
    return false
  end

  local success, logIndex = pcall(getLogIndexForQuestID, questID) -- Quest Log 索引
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

--- strict 校验 schema v3 数据。
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
  if dataTable.schemaVersion == 4 then
    requiredRootFields[#requiredRootFields + 1] = "questLineXQuest"
  else
    requiredRootFields[#requiredRootFields + 1] = "questLineQuestIDs"
  end
  for _, fieldName in ipairs(requiredRootFields) do
    if dataTable[fieldName] == nil then
      return false, buildValidationError("E_MISSING_FIELD", fieldName, "required root field missing")
    end
  end

  if strictEnabled and dataTable.schemaVersion ~= 3 and dataTable.schemaVersion ~= 4 then
    return false, buildValidationError("E_INVALID_SCHEMA", "schemaVersion", "schemaVersion must be 3 or 4")
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
  if dataTable.schemaVersion == 4 and type(dataTable.questLineXQuest) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "questLineXQuest", "table expected")
  end
  if dataTable.schemaVersion ~= 4 and type(dataTable.questLineQuestIDs) ~= "table" then
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
    if type(questEntry.UiMapID) ~= "number" or questEntry.UiMapID <= 0 then
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
    if type(questLineEntry.Name_lang) ~= "string" or questLineEntry.Name_lang == "" then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].Name_lang", "non-empty string expected")
    end
    if type(questLineEntry.UiMapID) ~= "number" or questLineEntry.UiMapID <= 0 then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].UiMapID", "positive number expected")
    end
    questLineExistsByID[questLineID] = true
  end

  local questOwnerByID = {} -- questID -> questLineID
  local questLinkRoot = dataTable.schemaVersion == 4 and dataTable.questLineXQuest or dataTable.questLineQuestIDs -- 任务线链接根表
  local questLinkPath = dataTable.schemaVersion == 4 and "questLineXQuest" or "questLineQuestIDs" -- 任务线链接字段路径
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
    if dataTable.schemaVersion == 4 then
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
        local questID = dataTable.schemaVersion == 4 and questLinkObject.QuestID or questLinkObject -- 当前任务 ID
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
    if type(questID) == "number" and type(questRecord) == "table" then
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
  if type(questRecord) ~= "table" then
    return nil
  end

  local runtimeState = getCachedQuestRuntimeState(questID) -- 任务运行时字段
  return {
    id = questID,
    name = runtimeState.name,
    status = runtimeState.status,
    readyForTurnIn = runtimeState.readyForTurnIn,
    UiMapID = questRecord.UiMapID,
    typeID = runtimeState.typeID,
    mapPos = resolveQuestMapPos(dataTable, questID, questRecord),
    npcIDs = runtimeState.npcIDs,
    npcPos = runtimeState.npcPos,
    quest = questRecord,
    runtime = runtimeState,
  }
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
        name = questLineRecord.Name_lang,
        UiMapID = uiMapID,
        questIDs = questIDList,
        questCount = #questIDList,
      }

      mapEntry.questLines[#mapEntry.questLines + 1] = questLineModel
      mapEntry.questCount = (mapEntry.questCount or 0) + questLineModel.questCount
      model.questLineByID[questLineID] = questLineModel

      for _, questID in ipairs(questIDList) do
        model.questToQuestLineID[questID] = questLineID
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
            typeIndexModel.typeList[#typeIndexModel.typeList + 1] = typeID
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

  table.sort(typeIndexModel.typeList)
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
---@return table|nil detailObject
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestDetailByID(questID)
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
  if type(questRecord) ~= "table" then
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
        runtime = runtimeState,
      }, nil
    end
    return nil, nil
  end

  local questLineID = model.questToQuestLineID[questID] -- 任务所属任务线 ID
  local questLineEntry = type(questLineID) == "number" and model.questLineByID[questLineID] or nil -- 任务线对象

  return {
    questID = questID,
    name = runtimeState.name,
    status = runtimeState.status,
    readyForTurnIn = runtimeState.readyForTurnIn,
    UiMapID = questRecord.UiMapID,
    typeID = runtimeState.typeID,
    mapPos = resolveQuestMapPos(dataTable, questID, questRecord),
    npcIDs = runtimeState.npcIDs,
    npcPos = runtimeState.npcPos,
    questLineID = questLineID,
    questLineName = questLineEntry and questLineEntry.name or nil,
    runtime = runtimeState,
  }, nil
end
