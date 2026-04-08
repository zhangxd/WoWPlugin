--[[
  Questline progress API for Encounter Journal.
  Provides:
  - extensible type registry (default: "map")
  - instance tree resolution by journalInstanceID
  - quest status and chain progress calculation
]]

Toolbox.Questlines = Toolbox.Questlines or {}

local typeRegistry = {}

local getLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID
local isQuestCompletedFn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted

local function getQuestNameByID(questID)
  if type(questID) ~= "number" then
    return nil
  end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local name = C_QuestLog.GetTitleForQuestID(questID)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  if type(QuestUtils_GetQuestName) == "function" then
    local name = QuestUtils_GetQuestName(questID)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  return nil
end

local function getQuestStatus(questID)
  if type(questID) ~= "number" then
    return "pending"
  end

  if isQuestCompletedFn and isQuestCompletedFn(questID) then
    return "completed"
  end

  if getLogIndexForQuestID then
    local index = getLogIndexForQuestID(questID)
    if type(index) == "number" and index > 0 then
      return "active"
    end
  end

  return "pending"
end

local function normalizeQuest(rawQuest)
  if type(rawQuest) == "number" then
    local questID = rawQuest
    return {
      id = questID,
      name = getQuestNameByID(questID) or ("Quest #" .. tostring(questID)),
      status = getQuestStatus(questID),
    }
  end
  if type(rawQuest) ~= "table" then
    return nil
  end

  local questID = tonumber(rawQuest.id)
  local questName = rawQuest.name
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

local function normalizeChain(rawChain)
  if type(rawChain) ~= "table" then
    return nil
  end

  local chain = {
    id = rawChain.id or rawChain.name or "chain",
    name = rawChain.name or "Chain",
    quests = {},
  }

  local sourceQuests = rawChain.quests
  if type(sourceQuests) == "table" then
    for _, rawQuest in ipairs(sourceQuests) do
      local quest = normalizeQuest(rawQuest)
      if quest then
        chain.quests[#chain.quests + 1] = quest
      end
    end
  end

  return chain
end

local function normalizeNode(rawNode)
  if type(rawNode) ~= "table" then
    return nil
  end

  local node = {
    id = rawNode.id or rawNode.name or "node",
    name = rawNode.name or "Node",
    chains = {},
  }

  local sourceChains = rawNode.chains
  if type(sourceChains) == "table" then
    for _, rawChain in ipairs(sourceChains) do
      local chain = normalizeChain(rawChain)
      if chain then
        chain.progress = Toolbox.Questlines.GetChainProgress(chain)
        node.chains[#node.chains + 1] = chain
      end
    end
  end

  return node
end

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

function Toolbox.Questlines.RegisterType(typeID, definition)
  if type(typeID) ~= "string" or typeID == "" then
    return
  end
  if type(definition) ~= "table" then
    definition = {}
  end

  local def = {
    id = typeID,
    order = tonumber(definition.order) or 1000,
    localeKey = definition.localeKey,
    normalizeNodes = definition.normalizeNodes,
  }
  if type(def.normalizeNodes) ~= "function" then
    def.normalizeNodes = function(rawNodes)
      return rawNodes
    end
  end

  typeRegistry[typeID] = def
end

function Toolbox.Questlines.GetChainProgress(chain)
  local quests = chain and chain.quests
  if type(quests) ~= "table" or #quests == 0 then
    return {
      completed = 0,
      total = 0,
      hasActive = false,
      nextQuestID = nil,
      nextQuestName = nil,
      isCompleted = false,
    }
  end

  local completedCount = 0
  local hasActive = false
  local nextQuestID = nil
  local nextQuestName = nil

  for _, quest in ipairs(quests) do
    if quest.status == "completed" then
      completedCount = completedCount + 1
    elseif quest.status == "active" then
      hasActive = true
      if not nextQuestID then
        nextQuestID = quest.id
        nextQuestName = quest.name
      end
    elseif not nextQuestID then
      nextQuestID = quest.id
      nextQuestName = quest.name
    end
  end

  local total = #quests
  return {
    completed = completedCount,
    total = total,
    hasActive = hasActive,
    nextQuestID = nextQuestID,
    nextQuestName = nextQuestName,
    isCompleted = completedCount == total and total > 0,
  }
end

function Toolbox.Questlines.GetInstanceTree(journalInstanceID)
  if type(journalInstanceID) ~= "number" then
    return nil
  end

  local allData = Toolbox.Data and Toolbox.Data.InstanceQuestlines
  local raw = allData and allData[journalInstanceID]
  if type(raw) ~= "table" then
    return nil
  end

  local result = {
    journalInstanceID = journalInstanceID,
    expansion = raw.expansion or {},
    types = {},
  }

  local rawTypes = raw.types
  if type(rawTypes) ~= "table" then
    return result
  end

  local typeIDs = {}
  for typeID in pairs(rawTypes) do
    typeIDs[#typeIDs + 1] = typeID
  end

  table.sort(typeIDs, function(leftID, rightID)
    local leftDef = getTypeDefinition(leftID)
    local rightDef = getTypeDefinition(rightID)
    if leftDef.order ~= rightDef.order then
      return leftDef.order < rightDef.order
    end
    return tostring(leftID) < tostring(rightID)
  end)

  local loc = Toolbox.L or {}
  for _, typeID in ipairs(typeIDs) do
    local def = getTypeDefinition(typeID)
    local rawNodes = rawTypes[typeID]
    local normalizedNodes = def.normalizeNodes(rawNodes, raw)
    local typeEntry = {
      id = typeID,
      label = (def.localeKey and loc[def.localeKey]) or tostring(typeID),
      nodes = {},
    }

    if type(normalizedNodes) == "table" then
      for _, rawNode in ipairs(normalizedNodes) do
        local node = normalizeNode(rawNode)
        if node then
          typeEntry.nodes[#typeEntry.nodes + 1] = node
        end
      end
    end

    result.types[#result.types + 1] = typeEntry
  end

  return result
end

-- Default type: map
Toolbox.Questlines.RegisterType("map", {
  order = 10,
  localeKey = "EJ_QUESTLINE_TREE_TYPE_MAP",
  normalizeNodes = function(rawNodes)
    if type(rawNodes) ~= "table" then
      return {}
    end
    return rawNodes
  end,
})
