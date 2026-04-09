--[[
  任务线进度领域 API（Toolbox.Questlines）。
  设计目标：
    1. 以 schema v2（quests/questLines/questLineQuestIDs/expansionQuestLineIDs）作为唯一数据源。
    2. 提供 strict 校验、任务页签查询模型与任务详情查询接口。
    3. 保留旧入口 GetExpansionTree/GetInstanceTree，供旧 UI 过渡期兼容。
]]

Toolbox.Questlines = Toolbox.Questlines or {}

local typeRegistry = {} -- 类型注册表（兼容旧树输出）
local runtimeCache = { -- 运行时模型缓存
  dataRef = nil,
  generatedAt = nil,
  model = nil,
  errorObject = nil,
}

local getLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID -- 任务日志索引查询函数
local isQuestCompletedFn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted -- 任务完成状态函数

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

--- 查询地图名（按 mapID）。
---@param mapID number
---@return string
local function getMapNameByID(mapID)
  if type(mapID) == "number" and C_Map and C_Map.GetMapInfo then
    local success, mapInfo = pcall(C_Map.GetMapInfo, mapID) -- 地图信息查询
    if success and type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
      return mapInfo.name
    end
  end
  return "Map #" .. tostring(mapID or "?")
end

--- 查询资料片名（按 expansionID）。
---@param expansionID number
---@return string
local function getExpansionNameByID(expansionID)
  return "Expansion #" .. tostring(expansionID or "?")
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

--- 获取任务页签静态数据根对象。
---@return table|nil
local function getQuestlineDataTable()
  return Toolbox.Data and Toolbox.Data.InstanceQuestlines
end

--- strict 校验 schema v2 数据。
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
    "questLineQuestIDs",
    "expansionQuestLineIDs",
  }
  for _, fieldName in ipairs(requiredRootFields) do
    if dataTable[fieldName] == nil then
      return false, buildValidationError("E_MISSING_FIELD", fieldName, "required root field missing")
    end
  end

  if strictEnabled and dataTable.schemaVersion ~= 2 then
    return false, buildValidationError("E_INVALID_SCHEMA", "schemaVersion", "schemaVersion must be 2")
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
  if type(dataTable.questLineQuestIDs) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "questLineQuestIDs", "table expected")
  end
  if type(dataTable.expansionQuestLineIDs) ~= "table" then
    return false, buildValidationError("E_TYPE_MISMATCH", "expansionQuestLineIDs", "table expected")
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
    if type(questEntry.questID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", "quests[" .. tostring(questID) .. "].questID", "questID missing")
    end
    if questEntry.questID ~= questID then
      return false, buildValidationError("E_KEY_VALUE_MISMATCH", "quests[" .. tostring(questID) .. "].questID", "questID must match key")
    end
    if type(questEntry.mapID) ~= "number" or questEntry.mapID <= 0 then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].mapID", "positive number expected")
    end
    if questEntry.startNpcID ~= nil and type(questEntry.startNpcID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].startNpcID", "number expected")
    end
    if questEntry.turnInNpcID ~= nil and type(questEntry.turnInNpcID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].turnInNpcID", "number expected")
    end

    local prerequisiteOk, prerequisiteError = validateNumberArray(
      questEntry.prerequisiteQuestIDs,
      false,
      "quests[" .. tostring(questID) .. "].prerequisiteQuestIDs"
    )
    if not prerequisiteOk then
      return false, prerequisiteError
    end

    local nextQuestOk, nextQuestError = validateNumberArray(
      questEntry.nextQuestIDs,
      false,
      "quests[" .. tostring(questID) .. "].nextQuestIDs"
    )
    if not nextQuestOk then
      return false, nextQuestError
    end

    if questEntry.unlockConditions ~= nil then
      if type(questEntry.unlockConditions) ~= "table" then
        return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].unlockConditions", "table expected")
      end
      local unlockConditions = questEntry.unlockConditions -- 解锁条件对象
      if unlockConditions.minLevel ~= nil and type(unlockConditions.minLevel) ~= "number" then
        return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].unlockConditions.minLevel", "number expected")
      end

      local classOk, classError = validateNumberArray(
        unlockConditions.classIDs,
        false,
        "quests[" .. tostring(questID) .. "].unlockConditions.classIDs"
      )
      if not classOk then
        return false, classError
      end

      local stateFlagOk, stateFlagError = validateNumberArray(
        unlockConditions.worldStateFlags,
        false,
        "quests[" .. tostring(questID) .. "].unlockConditions.worldStateFlags"
      )
      if not stateFlagOk then
        return false, stateFlagError
      end

      if unlockConditions.renown ~= nil then
        if type(unlockConditions.renown) ~= "table" then
          return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].unlockConditions.renown", "table expected")
        end
        for renownIndex, renownEntry in ipairs(unlockConditions.renown) do
          if type(renownEntry) ~= "table" then
            return false, buildValidationError("E_TYPE_MISMATCH", "quests[" .. tostring(questID) .. "].unlockConditions.renown[" .. tostring(renownIndex) .. "]", "table expected")
          end
          if type(renownEntry.factionID) ~= "number" then
            return false, buildValidationError("E_MISSING_FIELD", "quests[" .. tostring(questID) .. "].unlockConditions.renown[" .. tostring(renownIndex) .. "].factionID", "number expected")
          end
          if type(renownEntry.minLevel) ~= "number" then
            return false, buildValidationError("E_MISSING_FIELD", "quests[" .. tostring(questID) .. "].unlockConditions.renown[" .. tostring(renownIndex) .. "].minLevel", "number expected")
          end
        end
      end
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
    if type(questLineEntry.questLineID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].questLineID", "number expected")
    end
    if questLineEntry.questLineID ~= questLineID then
      return false, buildValidationError("E_KEY_VALUE_MISMATCH", "questLines[" .. tostring(questLineID) .. "].questLineID", "questLineID must match key")
    end
    if type(questLineEntry.name) ~= "string" or questLineEntry.name == "" then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].name", "non-empty string expected")
    end
    if type(questLineEntry.expansionID) ~= "number" then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].expansionID", "number expected")
    end
    if type(questLineEntry.primaryMapID) ~= "number" or questLineEntry.primaryMapID <= 0 then
      return false, buildValidationError("E_MISSING_FIELD", "questLines[" .. tostring(questLineID) .. "].primaryMapID", "positive number expected")
    end
    questLineExistsByID[questLineID] = true
  end

  local questOwnerByID = {} -- questID -> questLineID
  for questLineKey, questIDList in pairs(dataTable.questLineQuestIDs) do
    local questLineID = tonumber(questLineKey) -- 规范化 questLineID
    if type(questLineID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "questLineQuestIDs[" .. tostring(questLineKey) .. "]", "numeric key required")
    end
    if questLineExistsByID[questLineID] ~= true then
      return false, buildValidationError("E_BAD_REF", "questLineQuestIDs[" .. tostring(questLineID) .. "]", "questLineID not found in questLines")
    end

    local questListOk, questListError = validateNumberArray(
      questIDList,
      strictEnabled,
      "questLineQuestIDs[" .. tostring(questLineID) .. "]"
    )
    if not questListOk then
      return false, questListError
    end

    if type(questIDList) == "table" then
      for questIndex, questID in ipairs(questIDList) do
        if questExistsByID[questID] ~= true then
          return false, buildValidationError("E_BAD_REF", "questLineQuestIDs[" .. tostring(questLineID) .. "][" .. tostring(questIndex) .. "]", "questID not found in quests")
        end
        if questOwnerByID[questID] ~= nil and questOwnerByID[questID] ~= questLineID then
          return false, buildValidationError("E_DUPLICATE_REF", "questLineQuestIDs[" .. tostring(questLineID) .. "][" .. tostring(questIndex) .. "]", "questID bound to multiple questLines")
        end
        questOwnerByID[questID] = questLineID
      end
    end
  end

  for expansionKey, questLineIDList in pairs(dataTable.expansionQuestLineIDs) do
    local expansionID = tonumber(expansionKey) -- 规范化 expansionID
    if type(expansionID) ~= "number" then
      return false, buildValidationError("E_TYPE_MISMATCH", "expansionQuestLineIDs[" .. tostring(expansionKey) .. "]", "numeric key required")
    end

    local expansionListOk, expansionListError = validateNumberArray(
      questLineIDList,
      strictEnabled,
      "expansionQuestLineIDs[" .. tostring(expansionID) .. "]"
    )
    if not expansionListOk then
      return false, expansionListError
    end

    if type(questLineIDList) == "table" then
      for questLineIndex, questLineID in ipairs(questLineIDList) do
        local questLineEntry = dataTable.questLines[questLineID] -- 任务线对象
        if type(questLineEntry) ~= "table" then
          return false, buildValidationError("E_BAD_REF", "expansionQuestLineIDs[" .. tostring(expansionID) .. "][" .. tostring(questLineIndex) .. "]", "questLineID not found")
        end
        if questLineEntry.expansionID ~= expansionID then
          return false, buildValidationError("E_BAD_REF", "questLines[" .. tostring(questLineID) .. "].expansionID", "questLine expansionID mismatch")
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
      questID = tonumber(questEntry.id or questEntry.questID)
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

--- 基于数据表构建任务列表。
---@param dataTable table 根数据
---@param questLineID number 任务线 ID
---@return table[]
local function buildQuestListByQuestLineID(dataTable, questLineID)
  local questList = {} -- 任务展示列表
  local questIDList = dataTable.questLineQuestIDs and dataTable.questLineQuestIDs[questLineID] or nil -- 任务线关联任务 ID 列表
  if type(questIDList) ~= "table" then
    return questList
  end

  for _, questID in ipairs(questIDList) do
    local questRecord = dataTable.quests and dataTable.quests[questID] or nil -- 任务静态记录
    if type(questRecord) == "table" then
      local questName = getQuestNameByID(questID) or ("Quest #" .. tostring(questID)) -- 任务名称
      questList[#questList + 1] = {
        id = questID,
        name = questName,
        status = getQuestStatus(questID),
        mapID = questRecord.mapID,
        quest = questRecord,
      }
    end
  end

  return questList
end

--- 计算地图聚合进度（去重）。
---@param questLineList table[] 任务线列表
---@return table
local function buildMapProgress(questLineList)
  local seenQuestSet = {} -- 地图内任务去重集合
  local completedCount = 0 -- 地图已完成数量
  local totalCount = 0 -- 地图总任务数量

  for _, questLineEntry in ipairs(questLineList) do
    local questList = questLineEntry.quests or {} -- 任务线任务列表
    for _, questEntry in ipairs(questList) do
      local questID = questEntry.id -- 当前任务 ID
      if type(questID) == "number" and seenQuestSet[questID] ~= true then
        seenQuestSet[questID] = true
        totalCount = totalCount + 1
        if questEntry.status == "completed" then
          completedCount = completedCount + 1
        end
      end
    end
  end

  return {
    completed = completedCount,
    total = totalCount,
  }
end

--- 构建任务页签运行时模型。
---@param dataTable table 根数据
---@return table|nil model
---@return table|nil errorObject
local function buildQuestTabModel(dataTable)
  local valid, validationError = Toolbox.Questlines.ValidateInstanceQuestlinesData(dataTable, true) -- strict 校验结果
  if not valid then
    return nil, validationError
  end

  local model = {
    expansions = {},
    expansionByID = {},
    questLineByID = {},
    questToQuestLineID = {},
  }

  local expansionIDList = {} -- 资料片 ID 列表
  for expansionID in pairs(dataTable.expansionQuestLineIDs) do
    if type(expansionID) == "number" then
      expansionIDList[#expansionIDList + 1] = expansionID
    end
  end
  table.sort(expansionIDList)

  for _, expansionID in ipairs(expansionIDList) do
    local expansionEntry = { -- 资料片模型
      id = expansionID,
      name = getExpansionNameByID(expansionID),
      maps = {},
      mapByID = {},
      questLineIDs = {},
    }

    local orderedQuestLineIDList = dataTable.expansionQuestLineIDs[expansionID] or {} -- 资料片下任务线顺序
    for _, questLineID in ipairs(orderedQuestLineIDList) do
      local questLineRecord = dataTable.questLines[questLineID] -- 任务线元数据
      if type(questLineRecord) == "table" then
        local primaryMapID = questLineRecord.primaryMapID -- 主归属地图 ID
        local mapEntry = expansionEntry.mapByID[primaryMapID] -- 地图模型
        if type(mapEntry) ~= "table" then
          mapEntry = {
            id = primaryMapID,
            name = getMapNameByID(primaryMapID),
            questLines = {},
            progress = { completed = 0, total = 0 },
          }
          expansionEntry.mapByID[primaryMapID] = mapEntry
          expansionEntry.maps[#expansionEntry.maps + 1] = mapEntry
        end

        local questList = buildQuestListByQuestLineID(dataTable, questLineID) -- 任务线任务列表
        local questLineModel = {
          id = questLineID,
          name = questLineRecord.name,
          expansionID = expansionID,
          mapID = primaryMapID,
          quests = questList,
        }
        questLineModel.progress = Toolbox.Questlines.GetChainProgress(questLineModel)

        mapEntry.questLines[#mapEntry.questLines + 1] = questLineModel
        expansionEntry.questLineIDs[#expansionEntry.questLineIDs + 1] = questLineID
        model.questLineByID[questLineID] = questLineModel

        for _, questEntry in ipairs(questList) do
          model.questToQuestLineID[questEntry.id] = questLineID
        end
      end
    end

    for _, mapEntry in ipairs(expansionEntry.maps) do
      mapEntry.progress = buildMapProgress(mapEntry.questLines)
    end

    model.expansions[#model.expansions + 1] = expansionEntry
    model.expansionByID[expansionID] = expansionEntry
  end

  return model, nil
end

--- 获取缓存后的任务页签模型。
---@return table|nil model
---@return table|nil errorObject
local function getCachedQuestTabModel()
  local dataTable = getQuestlineDataTable() -- 根数据表
  if type(dataTable) ~= "table" then
    return nil, buildValidationError("E_MISSING_FIELD", "root", "InstanceQuestlines table missing")
  end

  if runtimeCache.dataRef == dataTable
    and runtimeCache.generatedAt == dataTable.generatedAt
    and (runtimeCache.model ~= nil or runtimeCache.errorObject ~= nil)
  then
    return runtimeCache.model, runtimeCache.errorObject
  end

  local model, errorObject = buildQuestTabModel(dataTable) -- 构建模型
  runtimeCache.dataRef = dataTable
  runtimeCache.generatedAt = dataTable.generatedAt
  runtimeCache.model = model
  runtimeCache.errorObject = errorObject
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
    expansions = {},
    expansionByID = {},
    questLineByID = {},
    questToQuestLineID = {},
  }, errorObject
end

--- 按当前选中节点查询任务线列表。
---@param selectedKind string 选中类型（expansion|map|questline|quest）
---@param expansionID number|nil 资料片 ID
---@param mapID number|nil 地图 ID
---@return table[] questLineList
---@return table|nil errorObject
function Toolbox.Questlines.GetQuestLinesForSelection(selectedKind, expansionID, mapID)
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return {}, errorObject
  end

  if selectedKind == "questline" then
    return {}, nil
  end
  if selectedKind == "quest" then
    return {}, nil
  end

  local expansionEntry = type(expansionID) == "number" and model.expansionByID[expansionID] or nil -- 资料片模型
  if type(expansionEntry) ~= "table" then
    return {}, nil
  end

  if selectedKind == "map" and type(mapID) == "number" then
    local mapEntry = expansionEntry.mapByID[mapID] -- 地图模型
    if type(mapEntry) == "table" then
      return mapEntry.questLines or {}, nil
    end
    return {}, nil
  end

  local resultList = {} -- 资料片层任务线聚合列表
  for _, questLineID in ipairs(expansionEntry.questLineIDs or {}) do
    local questLineEntry = model.questLineByID[questLineID] -- 任务线对象
    if type(questLineEntry) == "table" then
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
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
  if errorObject then
    return {}, errorObject
  end
  local questLineEntry = type(questLineID) == "number" and model.questLineByID[questLineID] or nil -- 任务线对象
  if type(questLineEntry) ~= "table" then
    return {}, nil
  end
  return questLineEntry.quests or {}, nil
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

  if type(questID) ~= "number" or type(dataTable) ~= "table" then
    return nil, nil
  end

  local questRecord = dataTable.quests and dataTable.quests[questID] or nil -- 任务静态记录
  if type(questRecord) ~= "table" then
    return nil, nil
  end

  local questLineID = model.questToQuestLineID[questID] -- 任务所属任务线 ID
  local questLineEntry = type(questLineID) == "number" and model.questLineByID[questLineID] or nil -- 任务线对象

  return {
    questID = questID,
    name = getQuestNameByID(questID) or ("Quest #" .. tostring(questID)),
    status = getQuestStatus(questID),
    mapID = questRecord.mapID,
    questLineID = questLineID,
    questLineName = questLineEntry and questLineEntry.name or nil,
    expansionID = questLineEntry and questLineEntry.expansionID or nil,
    startNpcID = questRecord.startNpcID,
    turnInNpcID = questRecord.turnInNpcID,
    prerequisiteQuestIDs = questRecord.prerequisiteQuestIDs,
    nextQuestIDs = questRecord.nextQuestIDs,
    unlockConditions = questRecord.unlockConditions,
  }, nil
end

--- 获取类型定义（含默认策略）。
---@param typeID string
---@return table
local function getTypeDefinition(typeID)
  return typeRegistry[typeID] or {
    id = typeID,
    order = 1000,
    localeKey = nil,
  }
end

--- 注册任务线类型解析器（兼容旧接口签名）。
---@param typeID string
---@param definition table|nil
function Toolbox.Questlines.RegisterType(typeID, definition)
  if type(typeID) ~= "string" or typeID == "" then
    return
  end
  if type(definition) ~= "table" then
    definition = {}
  end

  typeRegistry[typeID] = {
    id = typeID,
    order = tonumber(definition.order) or 1000,
    localeKey = definition.localeKey,
  }
end

--- 将 v2 任务页签模型转换为旧树形结构（兼容旧 UI）。
---@param model table 任务页签模型
---@param targetExpansionID number|nil 指定资料片过滤
---@return table
local function buildLegacyTreeFromModel(model, targetExpansionID)
  local localeTable = Toolbox.L or {} -- 本地化文案表
  local mapTypeDef = getTypeDefinition("map") -- map 类型定义
  local mapTypeLabel = (mapTypeDef.localeKey and localeTable[mapTypeDef.localeKey]) or "map" -- map 类型标签
  local resultTree = { expansions = {} } -- 兼容树返回值

  for _, expansionEntry in ipairs(model.expansions or {}) do
    if type(targetExpansionID) ~= "number" or expansionEntry.id == targetExpansionID then
      local legacyExpansion = {
        id = expansionEntry.id,
        name = expansionEntry.name,
        types = {
          {
            id = "map",
            label = mapTypeLabel,
            nodes = {},
          },
        },
      }

      local mapTypeEntry = legacyExpansion.types[1] -- map 类型节点
      for _, mapEntry in ipairs(expansionEntry.maps or {}) do
        local legacyNode = {
          id = mapEntry.id,
          name = mapEntry.name,
          chains = {},
          progress = mapEntry.progress,
        }
        for _, questLineEntry in ipairs(mapEntry.questLines or {}) do
          legacyNode.chains[#legacyNode.chains + 1] = {
            id = questLineEntry.id,
            name = questLineEntry.name,
            quests = questLineEntry.quests,
            progress = questLineEntry.progress,
          }
        end
        mapTypeEntry.nodes[#mapTypeEntry.nodes + 1] = legacyNode
      end

      resultTree.expansions[#resultTree.expansions + 1] = legacyExpansion
    end
  end

  return resultTree
end

--- 返回任务线扩展包树（旧兼容接口）。
---@param expansionID number|nil 可选资料片 ID
---@return table
function Toolbox.Questlines.GetExpansionTree(expansionID)
  local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- v2 模型
  if errorObject then
    return { expansions = {}, error = errorObject }
  end
  return buildLegacyTreeFromModel(model, expansionID)
end

--- 兼容旧接口：保持函数名，返回当前全部扩展包树。
---@param journalInstanceID number|nil
---@return table
function Toolbox.Questlines.GetInstanceTree(journalInstanceID)
  local expansionTree = Toolbox.Questlines.GetExpansionTree() -- 兼容扩展包树
  expansionTree.journalInstanceID = type(journalInstanceID) == "number" and journalInstanceID or nil
  return expansionTree
end

-- 默认类型：map（地图分组）
Toolbox.Questlines.RegisterType("map", {
  order = 10,
  localeKey = "EJ_QUESTLINE_TREE_TYPE_MAP",
})
