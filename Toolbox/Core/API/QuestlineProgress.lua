--[[
  任务线进度领域 API（Toolbox.Questlines）。
  设计目标：
    1. 数据结构与冒险手册副本 ID 解耦，只按离线静态表展示任务线。
    2. 提供统一任务状态、任务线进度与树形查询接口。
    3. 兼容旧入口 GetInstanceTree（保留函数名，内部转到扩展包树）。
]]

Toolbox.Questlines = Toolbox.Questlines or {}

local typeRegistry = {}

local getLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID -- 任务日志索引查询函数
local isQuestCompletedFn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted -- 任务完成状态函数

--- 查询任务名（按任务 ID）。
---@param questID number
---@return string|nil
local function getQuestNameByID(questID)
  if type(questID) ~= "number" then
    return nil
  end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local questName = C_QuestLog.GetTitleForQuestID(questID) -- 任务标题
    if type(questName) == "string" and questName ~= "" then
      return questName
    end
  end
  if type(QuestUtils_GetQuestName) == "function" then
    local questName = QuestUtils_GetQuestName(questID) -- 旧接口任务标题
    if type(questName) == "string" and questName ~= "" then
      return questName
    end
  end
  return nil
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
    local logIndex = getLogIndexForQuestID(questID) -- 当前任务日志中的索引
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

--- 将任意任务数据标准化为统一结构。
---@param rawQuest number|table
---@return table|nil
local function normalizeQuest(rawQuest)
  if type(rawQuest) == "number" then
    local questID = rawQuest -- 任务 ID
    return {
      id = questID,
      name = getQuestNameByID(questID) or ("Quest #" .. tostring(questID)),
      status = getQuestStatus(questID),
    }
  end
  if type(rawQuest) ~= "table" then
    return nil
  end

  local questID = tonumber(rawQuest.id) -- 任务 ID
  local questName = rawQuest.name -- 任务名
  if type(questName) ~= "string" or questName == "" then
    if type(questID) == "number" then
      questName = getQuestNameByID(questID) or ("Quest #" .. tostring(questID))
    else
      questName = "Unknown Quest"
    end
  end

  return {
    id = questID,
    name = questName,
    status = type(questID) == "number" and getQuestStatus(questID) or "pending",
  }
end

--- 从链对象中读取原始链列表，兼容数组/字典两种形状。
---@param rawNode table
---@return table[]
local function collectRawChains(rawNode)
  local chainList = {} -- 归一化链列表
  local rawChains = rawNode and rawNode.chains -- 原始链数据
  if type(rawChains) ~= "table" then
    return chainList
  end

  if type(rawNode.chainOrder) == "table" then
    for _, chainID in ipairs(rawNode.chainOrder) do
      local chainEntry = rawChains[chainID] -- 指定顺序下的链对象
      if type(chainEntry) == "table" then
        local chainObject = {
          id = chainEntry.id or chainID,
          name = chainEntry.name,
          quests = chainEntry.quests,
        }
        chainList[#chainList + 1] = chainObject
      end
    end
    return chainList
  end

  if #rawChains > 0 then
    for _, chainEntry in ipairs(rawChains) do
      if type(chainEntry) == "table" then
        chainList[#chainList + 1] = chainEntry
      end
    end
    return chainList
  end

  local chainIDs = {} -- 字典链 ID 列表
  for chainID in pairs(rawChains) do
    chainIDs[#chainIDs + 1] = tostring(chainID)
  end
  table.sort(chainIDs)
  for _, chainID in ipairs(chainIDs) do
    local chainEntry = rawChains[chainID] -- 字典链对象
    if type(chainEntry) == "table" then
      local chainObject = {
        id = chainEntry.id or chainID,
        name = chainEntry.name,
        quests = chainEntry.quests,
      }
      chainList[#chainList + 1] = chainObject
    end
  end

  return chainList
end

--- 标准化任务链。
---@param rawChain table
---@return table|nil
local function normalizeChain(rawChain)
  if type(rawChain) ~= "table" then
    return nil
  end

  local chainEntry = {
    id = rawChain.id or rawChain.name or "chain",
    name = rawChain.name or "Chain",
    quests = {},
  }

  local sourceQuests = rawChain.quests -- 原始任务数组
  if type(sourceQuests) == "table" then
    for _, rawQuest in ipairs(sourceQuests) do
      local questEntry = normalizeQuest(rawQuest) -- 标准化任务对象
      if questEntry then
        chainEntry.quests[#chainEntry.quests + 1] = questEntry
      end
    end
  end

  return chainEntry
end

--- 标准化节点对象。
---@param rawNode table
---@return table|nil
local function normalizeNode(rawNode)
  if type(rawNode) ~= "table" then
    return nil
  end

  local nodeEntry = {
    id = rawNode.id or rawNode.name or "node",
    name = rawNode.name or "Node",
    chains = {},
  }

  local sourceChains = collectRawChains(rawNode) -- 归一化链来源
  for _, rawChain in ipairs(sourceChains) do
    local chainEntry = normalizeChain(rawChain) -- 标准化链对象
    if chainEntry then
      chainEntry.progress = Toolbox.Questlines.GetChainProgress(chainEntry)
      nodeEntry.chains[#nodeEntry.chains + 1] = chainEntry
    end
  end

  return nodeEntry
end

--- 获取类型定义（含默认策略）。
---@param typeID string
---@return table
local function getTypeDefinition(typeID)
  return typeRegistry[typeID] or {
    id = typeID,
    order = 1000,
    localeKey = nil,
    normalizeNodes = function(rawNodes)
      return rawNodes
    end,
  }
end

--- 从类型原始节点中拉平成数组，兼容 nodeOrder + nodes 结构。
---@param rawNodes table
---@return table[]
local function collectNodeList(rawNodes)
  local nodeList = {} -- 归一化节点列表
  if type(rawNodes) ~= "table" then
    return nodeList
  end

  if type(rawNodes.nodeOrder) == "table" and type(rawNodes.nodes) == "table" then
    for _, nodeID in ipairs(rawNodes.nodeOrder) do
      local nodeEntry = rawNodes.nodes[nodeID] -- 指定顺序节点
      if type(nodeEntry) == "table" then
        local nodeObject = {
          id = nodeEntry.id or nodeID,
          name = nodeEntry.name,
          chains = nodeEntry.chains,
          chainOrder = nodeEntry.chainOrder,
        }
        nodeList[#nodeList + 1] = nodeObject
      end
    end
    return nodeList
  end

  if #rawNodes > 0 then
    for _, nodeEntry in ipairs(rawNodes) do
      if type(nodeEntry) == "table" then
        nodeList[#nodeList + 1] = nodeEntry
      end
    end
    return nodeList
  end

  local nodeIDs = {} -- 字典节点 ID
  for nodeID in pairs(rawNodes) do
    nodeIDs[#nodeIDs + 1] = tostring(nodeID)
  end
  table.sort(nodeIDs)
  for _, nodeID in ipairs(nodeIDs) do
    local nodeEntry = rawNodes[nodeID] -- 字典节点对象
    if type(nodeEntry) == "table" then
      local nodeObject = {
        id = nodeEntry.id or nodeID,
        name = nodeEntry.name,
        chains = nodeEntry.chains,
        chainOrder = nodeEntry.chainOrder,
      }
      nodeList[#nodeList + 1] = nodeObject
    end
  end

  return nodeList
end

--- 注册任务线类型解析器。
---@param typeID string
---@param definition table|nil
function Toolbox.Questlines.RegisterType(typeID, definition)
  if type(typeID) ~= "string" or typeID == "" then
    return
  end
  if type(definition) ~= "table" then
    definition = {}
  end

  local typeDefinition = {
    id = typeID,
    order = tonumber(definition.order) or 1000,
    localeKey = definition.localeKey,
    normalizeNodes = definition.normalizeNodes,
  }
  if type(typeDefinition.normalizeNodes) ~= "function" then
    typeDefinition.normalizeNodes = function(rawNodes)
      return rawNodes
    end
  end

  typeRegistry[typeID] = typeDefinition
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

  local completedCount = 0 -- 完成数量
  local hasActiveQuest = false -- 是否有进行中任务
  local nextQuestID = nil -- 下一步任务 ID
  local nextQuestName = nil -- 下一步任务名

  for _, questEntry in ipairs(questList) do
    if questEntry.status == "completed" then
      completedCount = completedCount + 1
    elseif questEntry.status == "active" then
      hasActiveQuest = true
      if not nextQuestID then
        nextQuestID = questEntry.id
        nextQuestName = questEntry.name
      end
    elseif not nextQuestID then
      nextQuestID = questEntry.id
      nextQuestName = questEntry.name
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

--- 返回任务线扩展包树（与冒险手册副本 ID 解耦）。
---@param expansionID number|nil 可选，指定资料片 ID
---@return table
function Toolbox.Questlines.GetExpansionTree(expansionID)
  local allData = Toolbox.Data and Toolbox.Data.InstanceQuestlines -- 任务线根数据
  local expansionBuckets = allData and allData.expansions -- 资料片分桶
  local result = {expansions = {}}
  if type(expansionBuckets) ~= "table" then
    return result
  end

  local expansionIDs = {} -- 要输出的资料片 ID 列表
  if type(expansionID) == "number" then
    if type(expansionBuckets[expansionID]) == "table" then
      expansionIDs[1] = expansionID
    else
      return result
    end
  else
    for keyID in pairs(expansionBuckets) do
      if type(keyID) == "number" then
        expansionIDs[#expansionIDs + 1] = keyID
      end
    end
    table.sort(expansionIDs, function(leftID, rightID)
      local leftExp = expansionBuckets[leftID] or {} -- 左侧资料片定义
      local rightExp = expansionBuckets[rightID] or {} -- 右侧资料片定义
      local leftOrder = tonumber(leftExp.order) or leftID
      local rightOrder = tonumber(rightExp.order) or rightID
      if leftOrder ~= rightOrder then
        return leftOrder < rightOrder
      end
      return leftID < rightID
    end)
  end

  local localeTable = Toolbox.L or {} -- 本地化文案表
  for _, expID in ipairs(expansionIDs) do
    local rawExpansion = expansionBuckets[expID] -- 原始资料片对象
    local expansionEntry = {
      id = expID,
      name = rawExpansion.name or ("Expansion " .. tostring(expID)),
      types = {},
    }

    local rawTypes = rawExpansion.types -- 类型分桶
    if type(rawTypes) == "table" then
      local typeIDs = {}
      for typeID in pairs(rawTypes) do
        typeIDs[#typeIDs + 1] = tostring(typeID)
      end
      table.sort(typeIDs, function(leftID, rightID)
        local leftDef = getTypeDefinition(leftID)
        local rightDef = getTypeDefinition(rightID)
        if leftDef.order ~= rightDef.order then
          return leftDef.order < rightDef.order
        end
        return leftID < rightID
      end)

      for _, typeID in ipairs(typeIDs) do
        local typeDefinition = getTypeDefinition(typeID) -- 类型定义
        local typeSource = rawTypes[typeID] -- 原始类型数据
        local normalizedInput = typeDefinition.normalizeNodes(typeSource, rawExpansion, expID) -- 类型归一化前置
        local nodeSourceList = collectNodeList(normalizedInput) -- 拉平后的节点数组
        local typeEntry = {
          id = typeID,
          label = (typeDefinition.localeKey and localeTable[typeDefinition.localeKey]) or tostring(typeID),
          nodes = {},
        }

        for _, rawNode in ipairs(nodeSourceList) do
          local nodeEntry = normalizeNode(rawNode) -- 标准化节点
          if nodeEntry then
            typeEntry.nodes[#typeEntry.nodes + 1] = nodeEntry
          end
        end

        expansionEntry.types[#expansionEntry.types + 1] = typeEntry
      end
    end

    result.expansions[#result.expansions + 1] = expansionEntry
  end

  return result
end

--- 兼容旧接口：保持函数名，返回当前全部扩展包树。
---@param journalInstanceID number|nil
---@return table
function Toolbox.Questlines.GetInstanceTree(journalInstanceID)
  local expansionTree = Toolbox.Questlines.GetExpansionTree() -- 与 EJ ID 解耦后的统一树
  expansionTree.journalInstanceID = type(journalInstanceID) == "number" and journalInstanceID or nil
  return expansionTree
end

-- 默认类型：map（地图分组）
Toolbox.Questlines.RegisterType("map", {
  order = 10,
  localeKey = "EJ_QUESTLINE_TREE_TYPE_MAP",
  normalizeNodes = function(rawNodes)
    return collectNodeList(rawNodes)
  end,
})
