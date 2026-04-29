--[[
  地图导航（领域对外 API）（Toolbox.Navigation）：路径图、可用性过滤与最短路径求解。
  业务模块只负责入口与 UI，本文件不直接操作世界地图 Frame。
]]

Toolbox.Navigation = Toolbox.Navigation or {}

local WALK_LOCAL_MODE = "walk_local" -- 本地步行模式

--- 按 from 节点为边建立索引，便于路径查询相邻边。
---@param edgeList table|nil 路径边列表
---@return table edgeListByFrom 按起点分组的边表
local function buildEdgeListByFrom(edgeList)
  local edgeListByFrom = {} -- 起点到边列表的索引
  for _, edge in ipairs(edgeList or {}) do
    local fromNodeId = edge and (edge.from or edge.FromNodeID or edge.From) -- 边起点
    local toNodeId = edge and (edge.to or edge.ToNodeID or edge.To) -- 边终点
    if fromNodeId and toNodeId then
      edgeListByFrom[fromNodeId] = edgeListByFrom[fromNodeId] or {}
      edgeListByFrom[fromNodeId][#edgeListByFrom[fromNodeId] + 1] = edge
    end
  end
  return edgeListByFrom
end

--- 复制一个 Lua 数组。
---@param rawList table|nil 原始数组
---@return table
local function copyArray(rawList)
  local copiedList = {} -- 复制后的数组
  for _, value in ipairs(type(rawList) == "table" and rawList or {}) do
    copiedList[#copiedList + 1] = value
  end
  return copiedList
end

--- 归一化导航名称，便于静态名字匹配。
---@param rawValue any
---@return string
local function normalizeNavigationName(rawValue)
  local normalizedValue = string.lower(tostring(rawValue or "")) -- 小写化名称
  normalizedValue = string.gsub(normalizedValue, "%s+", "")
  return normalizedValue
end

--- 将来源数组里的值追加到目标数组，保持去重。
---@param targetList table 目标数组
---@param sourceList table|nil 来源数组
local function appendUniqueArray(targetList, sourceList)
  local seenValue = {} -- 已写入值集合
  for _, value in ipairs(targetList or {}) do
    seenValue[tostring(value)] = true
  end
  for _, value in ipairs(type(sourceList) == "table" and sourceList or {}) do
    local marker = tostring(value) -- 去重标记
    if not seenValue[marker] then
      seenValue[marker] = true
      targetList[#targetList + 1] = value
    end
  end
end

--- 读取路线边模式。
---@param edge table|nil 路线边
---@return string
local function readEdgeMode(edge)
  return tostring((type(edge) == "table" and (edge.mode or edge.Mode)) or "unknown")
end

--- 读取路线边显示标签。
---@param edge table|nil 路线边
---@return string
local function readEdgeLabel(edge)
  return tostring((type(edge) == "table" and (edge.label or edge.Label or edge.name or edge.Name_lang)) or "")
end

--- 为路线边生成稳定排序标记。
---@param edge table|nil 路线边
---@return string
local function buildEdgeStableMarker(edge)
  local edgeValue = type(edge) == "table" and edge or {} -- 路线边定义
  local edgeID = edgeValue.id or edgeValue.ID or edgeValue.SourceRowID or readEdgeLabel(edgeValue) -- 稳定边 ID
  local fromNodeId = edgeValue.from or edgeValue.FromNodeID or edgeValue.From or "" -- 边起点
  local toNodeId = edgeValue.to or edgeValue.ToNodeID or edgeValue.To or "" -- 边终点
  return table.concat({
    tostring(readEdgeMode(edgeValue)),
    tostring(edgeID),
    tostring(fromNodeId),
    tostring(toNodeId),
  }, "::")
end

--- 比较两个路径分数；返回 -1 表示左侧更优，1 表示右侧更优，0 表示相同。
---@param leftScore table 左侧分数
---@param rightScore table 右侧分数
---@return integer
local function compareRouteScore(leftScore, rightScore)
  local leftSteps = tonumber(leftScore and leftScore.steps) or math.huge -- 左侧总步数
  local rightSteps = tonumber(rightScore and rightScore.steps) or math.huge -- 右侧总步数
  if leftSteps ~= rightSteps then
    return leftSteps < rightSteps and -1 or 1
  end

  local leftWalkSegments = tonumber(leftScore and leftScore.walkSegments) or math.huge -- 左侧步行段数
  local rightWalkSegments = tonumber(rightScore and rightScore.walkSegments) or math.huge -- 右侧步行段数
  if leftWalkSegments ~= rightWalkSegments then
    return leftWalkSegments < rightWalkSegments and -1 or 1
  end

  local leftWalkDistance = tonumber(leftScore and leftScore.walkDistance) or math.huge -- 左侧步行距离
  local rightWalkDistance = tonumber(rightScore and rightScore.walkDistance) or math.huge -- 右侧步行距离
  if leftWalkDistance ~= rightWalkDistance then
    return leftWalkDistance < rightWalkDistance and -1 or 1
  end

  local leftDisplayChanges = tonumber(leftScore and leftScore.displayChanges) or math.huge -- 左侧步骤切换数
  local rightDisplayChanges = tonumber(rightScore and rightScore.displayChanges) or math.huge -- 右侧步骤切换数
  if leftDisplayChanges ~= rightDisplayChanges then
    return leftDisplayChanges < rightDisplayChanges and -1 or 1
  end

  local leftStableKey = tostring(leftScore and leftScore.stableKey or "") -- 左侧稳定键
  local rightStableKey = tostring(rightScore and rightScore.stableKey or "") -- 右侧稳定键
  if leftStableKey ~= rightStableKey then
    return leftStableKey < rightStableKey and -1 or 1
  end
  return 0
end

--- 计算进入一条路线边后新增的路线步数。
---@param edge table 路线边
---@param lastMode string|nil 上一条边模式
---@return number
local function buildEdgeStepIncrement(edge, lastMode)
  local edgeMode = readEdgeMode(edge) -- 当前边模式
  if edgeMode == WALK_LOCAL_MODE and lastMode == WALK_LOCAL_MODE then
    return 0
  end
  local stepCost = tonumber(edge and (edge.stepCost or edge.StepCost)) -- 边步数成本
  return (stepCost and stepCost > 0) and stepCost or 1
end

--- 计算进入一条路线边后新增的步行段数。
---@param edge table 路线边
---@param lastMode string|nil 上一条边模式
---@return number
local function buildWalkSegmentIncrement(edge, lastMode)
  local edgeMode = readEdgeMode(edge) -- 当前边模式
  if edgeMode == WALK_LOCAL_MODE and lastMode ~= WALK_LOCAL_MODE then
    return 1
  end
  return 0
end

--- 计算进入一条路线边后新增的本地步行距离。
---@param edge table 路线边
---@return number
local function buildWalkDistanceIncrement(edge)
  if readEdgeMode(edge) ~= WALK_LOCAL_MODE then
    return 0
  end
  return tonumber(edge and (edge.walkDistance or edge.WalkDistance or edge.cost or edge.Cost)) or 0
end

--- 生成状态键，允许同一节点按“上一动作模式”分离状态。
---@param nodeId any 节点 ID
---@param lastMode string|nil 上一动作模式
---@return string
local function buildRouteStateKey(nodeId, lastMode)
  return tostring(nodeId) .. "::" .. tostring(lastMode or "")
end

--- 从开放列表中取出当前最优状态。
---@param openStateList table 开放状态列表
---@param bestStateByKey table 当前最佳状态表
---@return table|nil
local function popBestOpenState(openStateList, bestStateByKey)
  while #openStateList > 0 do
    local bestIndex = 1 -- 最优状态索引
    local bestState = openStateList[1] -- 当前最优状态
    for stateIndex = 2, #openStateList do
      local candidateState = openStateList[stateIndex] -- 候选状态
      if compareRouteScore(candidateState.score, bestState.score) < 0 then
        bestIndex = stateIndex
        bestState = candidateState
      end
    end
    table.remove(openStateList, bestIndex)
    if bestStateByKey[bestState.stateKey] == bestState then
      return bestState
    end
  end
  return nil
end

--- 将路径边数组压缩为最终展示段。
---@param routeGraph table 路径图
---@param edgePath table 原始边路径
---@return table segments 展示段
---@return table stepLabels 兼容步骤文案
local function buildRouteSegments(routeGraph, edgePath)
  local segments = {} -- 展示段列表
  for _, edge in ipairs(edgePath or {}) do
    local edgeMode = readEdgeMode(edge) -- 当前边模式
    local fromNodeId = edge.from or edge.FromNodeID or edge.From -- 边起点
    local toNodeId = edge.to or edge.ToNodeID or edge.To -- 边终点
    local fromNode = routeGraph.nodes[fromNodeId] or {} -- 起点节点
    local toNode = routeGraph.nodes[toNodeId] or {} -- 终点节点
    local edgeLabel = readEdgeLabel(edge) -- 当前边显示标签

    if edgeMode == WALK_LOCAL_MODE and #segments > 0 and segments[#segments].mode == WALK_LOCAL_MODE then
      local lastSegment = segments[#segments] -- 最近一个步行段
      lastSegment.to = toNodeId
      lastSegment.toName = tostring(toNode.name or toNodeId)
      lastSegment.walkDistance = tonumber(lastSegment.walkDistance or 0) + buildWalkDistanceIncrement(edge)
      lastSegment.label = edgeLabel
      appendUniqueArray(lastSegment.traversedUiMapIDs, edge.traversedUiMapIDs or edge.TraversedUiMapIDs)
      appendUniqueArray(lastSegment.traversedUiMapNames, edge.traversedUiMapNames or edge.TraversedUiMapNames)
    else
      segments[#segments + 1] = {
        mode = edgeMode,
        from = fromNodeId,
        to = toNodeId,
        fromName = tostring(fromNode.name or fromNodeId),
        toName = tostring(toNode.name or toNodeId),
        label = edgeLabel,
        traversedUiMapIDs = copyArray(edge.traversedUiMapIDs or edge.TraversedUiMapIDs),
        traversedUiMapNames = copyArray(edge.traversedUiMapNames or edge.TraversedUiMapNames),
        walkDistance = buildWalkDistanceIncrement(edge),
      }
    end
  end

  local stepLabels = {} -- 兼容旧界面的步骤文案
  for _, segment in ipairs(segments) do
    local segmentLabel = segment.label -- 当前段显示标签
    if segmentLabel == nil or segmentLabel == "" then
      segmentLabel = string.format("%s: %s -> %s", tostring(segment.mode), tostring(segment.fromName), tostring(segment.toName))
    end
    stepLabels[#stepLabels + 1] = segmentLabel
  end
  return segments, stepLabels
end

--- 回溯路径状态，生成路线结果。
---@param routeGraph table 路径图
---@param finalState table 最终状态
---@return table
local function buildRouteResult(routeGraph, finalState)
  local reversedNodePath = {} -- 反向节点路径
  local reversedEdgePath = {} -- 反向边路径
  local currentState = finalState -- 当前回溯状态

  while currentState do
    reversedNodePath[#reversedNodePath + 1] = currentState.nodeId
    if currentState.previousEdge then
      reversedEdgePath[#reversedEdgePath + 1] = currentState.previousEdge
    end
    currentState = currentState.previousState
  end

  local rawNodePath = {} -- 正向节点路径
  for pathIndex = #reversedNodePath, 1, -1 do
    rawNodePath[#rawNodePath + 1] = reversedNodePath[pathIndex]
  end

  local rawEdgePath = {} -- 正向边路径
  for pathIndex = #reversedEdgePath, 1, -1 do
    rawEdgePath[#rawEdgePath + 1] = reversedEdgePath[pathIndex]
  end

  local segments, stepLabels = buildRouteSegments(routeGraph, rawEdgePath) -- 展示段与兼容文案
  return {
    totalSteps = tonumber(finalState and finalState.score and finalState.score.steps) or #segments,
    segments = segments,
    rawNodePath = rawNodePath,
    rawEdgePath = rawEdgePath,
    totalCost = tonumber(finalState and finalState.score and finalState.score.steps) or #segments,
    nodePath = rawNodePath,
    stepLabels = stepLabels,
  }
end

--- 判断单条边是否满足当前角色可用性要求。
---@param edge table 路径边
---@param availabilityContext table|nil 当前角色可用性快照
---@return boolean
local function isEdgeAvailable(edge, availabilityContext)
  local requirements = edge and edge.requirements or nil -- 边可用性要求
  local context = availabilityContext or {} -- 当前角色上下文
  if type(requirements) ~= "table" then
    requirements = nil
  else
    if requirements.classFile and requirements.classFile ~= context.classFile then
      return false
    end
    if requirements.faction and requirements.faction ~= context.faction then
      return false
    end
    if requirements.spellID then
      local knownSpellByID = context.knownSpellByID -- 已确认技能集合
      if type(knownSpellByID) ~= "table" or knownSpellByID[requirements.spellID] ~= true then
        return false
      end
    end
  end

  local edgeMode = readEdgeMode(edge)
  if edgeMode == "taxi" or edgeMode == "transport" then
    local knownTaxiNodeByID = context.knownTaxiNodeByID -- 已开航点集合
    local fromTaxiNodeID = tonumber(edge and (edge.fromTaxiNodeID or edge.FromTaxiNodeID)) -- 起点飞行点 ID
    local toTaxiNodeID = tonumber(edge and (edge.toTaxiNodeID or edge.ToTaxiNodeID)) -- 终点飞行点 ID
    if type(knownTaxiNodeByID) ~= "table" or not fromTaxiNodeID or not toTaxiNodeID then
      return false
    end
    if knownTaxiNodeByID[fromTaxiNodeID] ~= true or knownTaxiNodeByID[toTaxiNodeID] ~= true then
      return false
    end
  end

  if edgeMode == "public_portal" then
    local factionRequirement = edge and edge.FactionRequirement or nil -- 阵营限制
    if factionRequirement and factionRequirement ~= context.faction then
      return false
    end
  end

  return true
end

--- 过滤路径图中当前角色不可用或未知可用性的边。
---@param routeGraph table 路径图，包含 `nodes` 与 `edges`
---@param availabilityContext table|nil 当前角色可用性快照
---@return table filteredGraph 过滤后的路径图
function Toolbox.Navigation.FilterRouteGraph(routeGraph, availabilityContext)
  local filteredGraph = {
    nodes = type(routeGraph) == "table" and routeGraph.nodes or {},
    edges = {},
  } -- 过滤后的路径图

  if type(routeGraph) ~= "table" then
    return filteredGraph
  end

  for _, edge in ipairs(routeGraph.edges or {}) do
    if isEdgeAvailable(edge, availabilityContext) then
      filteredGraph.edges[#filteredGraph.edges + 1] = edge
    end
  end

  return filteredGraph
end

--- 在路径图中查找起点到终点的最少步数路线。
---@param routeGraph table 路径图，包含 `nodes` 与 `edges`
---@param startNodeId any 起点节点 ID
---@param targetNodeId any 终点节点 ID
---@return table|nil routeResult 成功时包含 `totalSteps`、`segments`、`rawNodePath`、`rawEdgePath`
---@return table|nil errorObject 失败时包含 `code`
function Toolbox.Navigation.FindShortestPath(routeGraph, startNodeId, targetNodeId)
  if type(routeGraph) ~= "table" or type(routeGraph.nodes) ~= "table" then
    return nil, { code = "NAVIGATION_ERR_BAD_GRAPH" }
  end
  if routeGraph.nodes[startNodeId] == nil or routeGraph.nodes[targetNodeId] == nil then
    return nil, { code = "NAVIGATION_ERR_UNKNOWN_NODE" }
  end

  local edgeListByFrom = buildEdgeListByFrom(routeGraph.edges) -- 起点到边列表索引
  local bestStateByKey = {} -- 每个状态键的当前最优状态
  local openStateList = {} -- 待展开状态列表

  local startState = {
    nodeId = startNodeId,
    lastMode = nil,
    previousState = nil,
    previousEdge = nil,
    score = {
      steps = 0,
      walkSegments = 0,
      walkDistance = 0,
      displayChanges = 0,
      stableKey = "",
    },
  } -- 起点状态
  startState.stateKey = buildRouteStateKey(startNodeId, nil)
  bestStateByKey[startState.stateKey] = startState
  openStateList[#openStateList + 1] = startState

  while true do
    local currentState = popBestOpenState(openStateList, bestStateByKey) -- 当前最优状态
    if currentState == nil then
      break
    end
    if currentState.nodeId == targetNodeId then
      return buildRouteResult(routeGraph, currentState), nil
    end

    for _, edge in ipairs(edgeListByFrom[currentState.nodeId] or {}) do
      local toNodeId = edge.to or edge.ToNodeID or edge.To -- 边终点
      local edgeMode = readEdgeMode(edge) -- 当前边模式
      if toNodeId ~= nil and routeGraph.nodes[toNodeId] ~= nil then
        local candidateState = {
          nodeId = toNodeId,
          lastMode = edgeMode,
          previousState = currentState,
          previousEdge = edge,
          score = {
            steps = tonumber(currentState.score.steps) + buildEdgeStepIncrement(edge, currentState.lastMode),
            walkSegments = tonumber(currentState.score.walkSegments) + buildWalkSegmentIncrement(edge, currentState.lastMode),
            walkDistance = tonumber(currentState.score.walkDistance) + buildWalkDistanceIncrement(edge),
            displayChanges = tonumber(currentState.score.displayChanges) + ((currentState.lastMode and currentState.lastMode ~= edgeMode) and 1 or 0),
            stableKey = tostring(currentState.score.stableKey or "") .. "|" .. buildEdgeStableMarker(edge),
          },
        } -- 候选状态
        candidateState.stateKey = buildRouteStateKey(candidateState.nodeId, candidateState.lastMode)

        local bestState = bestStateByKey[candidateState.stateKey] -- 该状态键的已知最优状态
        if bestState == nil or compareRouteScore(candidateState.score, bestState.score) < 0 then
          bestStateByKey[candidateState.stateKey] = candidateState
          openStateList[#openStateList + 1] = candidateState
        end
      end
    end
  end

  return nil, { code = "NAVIGATION_ERR_NO_ROUTE" }
end

--- 按当前角色可用性过滤路径图后规划最少步数路线。
---@param routeGraph table 路径图，包含 `nodes` 与 `edges`
---@param startNodeId any 起点节点 ID
---@param targetNodeId any 终点节点 ID
---@param availabilityContext table|nil 当前角色可用性快照
---@return table|nil routeResult 成功时包含 `totalSteps`、`segments`、`rawNodePath`、`rawEdgePath`
---@return table|nil errorObject 失败时包含 `code`
function Toolbox.Navigation.PlanRoute(routeGraph, startNodeId, targetNodeId, availabilityContext)
  local filteredGraph = Toolbox.Navigation.FilterRouteGraph(routeGraph, availabilityContext) -- 可用边过滤后的路径图
  return Toolbox.Navigation.FindShortestPath(filteredGraph, startNodeId, targetNodeId)
end

--- 从路径数据中收集所有需要检查的 spellID，供运行时构建当前角色可用性快照。
---@param routeData table|nil 路径数据；导航运行时只允许传入契约导出的数据表
---@return table spellIDList 去重后的技能 ID 序列
function Toolbox.Navigation.GetRequiredSpellIDList(routeData)
  local exportedData = routeData or {} -- 契约导出的路径数据
  local seenSpellID = {} -- 已收集技能 ID 集合
  local spellIDList = {} -- 技能 ID 序列

  for _, edge in ipairs(type(exportedData.edges) == "table" and exportedData.edges or {}) do
    local requirements = type(edge) == "table" and edge.requirements or nil -- 边可用性要求
    local spellID = type(requirements) == "table" and tonumber(requirements.spellID) or nil -- 技能 ID
    if spellID and not seenSpellID[spellID] then
      seenSpellID[spellID] = true
      spellIDList[#spellIDList + 1] = spellID
    end
  end

  local abilityTemplateData = Toolbox.Data and Toolbox.Data.NavigationAbilityTemplates or {} -- 契约导出的能力模板
  local templateTable = type(abilityTemplateData.templates) == "table" and abilityTemplateData.templates or {} -- 模板表
  local templateIDList = {} -- 稳定模板键列表
  for templateID in pairs(templateTable) do
    templateIDList[#templateIDList + 1] = tostring(templateID)
  end
  table.sort(templateIDList)
  for _, templateID in ipairs(templateIDList) do
    local templateDef = templateTable[templateID] -- 模板定义
    local spellID = type(templateDef) == "table" and tonumber(templateDef.SpellID or templateDef.spellID) or nil -- 模板技能 ID
    if spellID and not seenSpellID[spellID] then
      seenSpellID[spellID] = true
      spellIDList[#spellIDList + 1] = spellID
    end
  end

  return spellIDList
end

--- 从 Vector2DMixin 或普通表读取归一化坐标。
---@param vectorValue table|nil 坐标对象
---@return number|nil, number|nil
local function readVectorXY(vectorValue)
  if type(vectorValue) ~= "table" then
    return nil, nil
  end
  if type(vectorValue.GetXY) == "function" then
    local success, x, y = pcall(vectorValue.GetXY, vectorValue) -- GetXY 返回值
    if success and type(x) == "number" and type(y) == "number" then
      return x, y
    end
  end
  local x = vectorValue.x -- 坐标 X
  local y = vectorValue.y -- 坐标 Y
  if type(x) ~= "number" or type(y) ~= "number" then
    return nil, nil
  end
  return x, y
end
Toolbox.Navigation.ReadVectorXY = readVectorXY

--- 判断归一化坐标是否合法。
---@param x number|nil 坐标 X
---@param y number|nil 坐标 Y
---@return boolean
local function isNormalizedPosition(x, y)
  return type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

--- 解析绑定地点名称对应的导航节点 ID。
---@param bindLocationName string|nil 绑定地点名称
---@return string|nil
local function resolveHearthBindNodeID(bindLocationName)
  local normalizedTargetName = normalizeNavigationName(bindLocationName) -- 归一化绑定地点名
  if normalizedTargetName == "" then
    return nil
  end

  local routeNodeTable = Toolbox.Data and Toolbox.Data.NavigationRouteEdges and Toolbox.Data.NavigationRouteEdges.nodes or {} -- 导出的导航节点表
  local bestNodeId = nil -- 当前最佳节点 ID
  local bestRank = nil -- 当前最佳节点排序
  for nodeId, nodeDef in pairs(type(routeNodeTable) == "table" and routeNodeTable or {}) do
    local nodeName = type(nodeDef) == "table" and (nodeDef.Name_lang or nodeDef.name or nodeId) or nodeId -- 节点显示名
    if normalizeNavigationName(nodeName) == normalizedTargetName then
      local nodeKind = tostring(type(nodeDef) == "table" and (nodeDef.Kind or nodeDef.kind) or "") -- 节点类型
      local uiMapID = tonumber(type(nodeDef) == "table" and (nodeDef.UiMapID or nodeDef.uiMapID) or 0) or 0 -- 节点地图 ID
      local taxiNodeID = tonumber(type(nodeDef) == "table" and (nodeDef.TaxiNodeID or nodeDef.taxiNodeID) or 0) or 0 -- 节点飞行点 ID
      local kindRank = (nodeKind == "map_anchor" or nodeKind == "uimap") and 0 or 1 -- 优先选地图锚点
      local candidateRank = kindRank * 1000000000 + uiMapID * 1000 + taxiNodeID -- 稳定候选排序
      if bestRank == nil or candidateRank < bestRank or (candidateRank == bestRank and tostring(nodeId) < tostring(bestNodeId or "")) then
        bestRank = candidateRank
        bestNodeId = nodeId
      end
    end
  end
  return bestNodeId
end

--- 从导出的导航节点表中收集当前角色已开航点集合。
---@return table
local function buildKnownTaxiNodeByID()
  local knownTaxiNodeByID = {} -- 已开航点集合
  local taxiMapApi = type(C_TaxiMap) == "table" and C_TaxiMap or nil -- 飞行点 API 表
  local getTaxiNodesForMap = taxiMapApi and taxiMapApi.GetTaxiNodesForMap or nil -- 指定地图飞行点查询
  if type(getTaxiNodesForMap) ~= "function" then
    return knownTaxiNodeByID
  end

  local routeNodeTable = Toolbox.Data and Toolbox.Data.NavigationRouteEdges and Toolbox.Data.NavigationRouteEdges.nodes or {} -- 导出的导航节点表
  local checkedUiMapID = {} -- 已查询过的飞行点地图 ID
  for _, nodeDef in pairs(type(routeNodeTable) == "table" and routeNodeTable or {}) do
    local nodeKind = tostring(type(nodeDef) == "table" and (nodeDef.Kind or nodeDef.kind) or "") -- 节点类型
    local nodeUiMapID = tonumber(type(nodeDef) == "table" and (nodeDef.UiMapID or nodeDef.uiMapID) or 0) -- 节点地图 ID
    if nodeKind == "taxi" and nodeUiMapID and nodeUiMapID > 0 and not checkedUiMapID[nodeUiMapID] then
      checkedUiMapID[nodeUiMapID] = true
      local success, taxiNodeList = pcall(getTaxiNodesForMap, nodeUiMapID) -- 当前地图飞行点列表
      if success and type(taxiNodeList) == "table" then
        for _, taxiNodeInfo in ipairs(taxiNodeList) do
          local taxiNodeID = tonumber(type(taxiNodeInfo) == "table" and taxiNodeInfo.nodeID) -- 飞行点 ID
          local isUndiscovered = type(taxiNodeInfo) == "table" and taxiNodeInfo.isUndiscovered == true -- 是否未开启
          if taxiNodeID and taxiNodeID > 0 and not isUndiscovered then
            knownTaxiNodeByID[taxiNodeID] = true
          end
        end
      end
    end
  end

  return knownTaxiNodeByID
end

--- 估算同一地图内两点之间的移动成本。
---@param uiMapID number|nil 地图 ID
---@param fromX number|nil 起点 X
---@param fromY number|nil 起点 Y
---@param toX number|nil 终点 X
---@param toY number|nil 终点 Y
---@return number|nil
local function estimateInMapTravelCost(uiMapID, fromX, fromY, toX, toY)
  if not tonumber(uiMapID) or not isNormalizedPosition(fromX, fromY) or not isNormalizedPosition(toX, toY) then
    return nil
  end
  local deltaX = toX - fromX -- X 轴归一化偏移
  local deltaY = toY - fromY -- Y 轴归一化偏移
  local distance = math.sqrt((deltaX * deltaX) + (deltaY * deltaY)) -- 归一化平面距离
  return math.floor((distance * 120) + 0.5)
end

--- 从当前角色运行时状态构建路径边可用性快照。
--- `C_SpellBook.IsSpellInSpellBook` 是当前 Retail 推荐的 spellbook 查询入口；
--- 旧客户端或测试环境缺失时回退到 `C_SpellBook.IsSpellKnown`，调用失败按未知处理。
---@param spellIDList table|nil 需要确认的技能 ID 列表
---@return table availabilityContext 当前角色可用性快照
function Toolbox.Navigation.BuildCurrentCharacterAvailability(spellIDList)
  local availabilityContext = {
    classFile = nil,
    faction = nil,
    currentUiMapID = nil,
    currentX = nil,
    currentY = nil,
    knownSpellByID = {},
    knownTaxiNodeByID = {},
    hearthBindNodeID = nil,
  } -- 当前角色可用性快照

  if type(UnitClass) == "function" then
    local success, localizedClassName, classFile = pcall(UnitClass, "player") -- 职业查询结果
    if success then
      availabilityContext.classFile = classFile
    end
  end

  if type(UnitFactionGroup) == "function" then
    local success, factionName = pcall(UnitFactionGroup, "player") -- 阵营查询结果
    if success then
      availabilityContext.faction = factionName
    end
  end

  local mapApi = type(C_Map) == "table" and C_Map or nil -- 地图 API 表
  local getBestMapForUnit = mapApi and mapApi.GetBestMapForUnit or nil -- 当前单位所在 UiMap 查询
  if type(getBestMapForUnit) == "function" then
    local success, currentMapID = pcall(getBestMapForUnit, "player") -- 当前角色所在地图查询结果
    if success and type(currentMapID) == "number" and currentMapID > 0 then
      availabilityContext.currentUiMapID = currentMapID
    end
  end
  local getPlayerMapPosition = mapApi and mapApi.GetPlayerMapPosition or nil -- 当前单位坐标查询
  if availabilityContext.currentUiMapID and type(getPlayerMapPosition) == "function" then
    local success, positionValue = pcall(getPlayerMapPosition, availabilityContext.currentUiMapID, "player") -- 当前角色坐标查询结果
    if success then
      local currentX, currentY = readVectorXY(positionValue) -- 当前角色归一化坐标
      if isNormalizedPosition(currentX, currentY) then
        availabilityContext.currentX = currentX
        availabilityContext.currentY = currentY
      end
    end
  end

  availabilityContext.knownTaxiNodeByID = buildKnownTaxiNodeByID()
  if type(GetBindLocation) == "function" then
    local success, bindLocationName = pcall(GetBindLocation) -- 炉石绑定地点名称
    if success then
      availabilityContext.hearthBindNodeID = resolveHearthBindNodeID(bindLocationName)
    end
  end

  local spellBookApi = type(C_SpellBook) == "table" and C_SpellBook or nil -- spellbook API 表
  local spellCheckFn = spellBookApi and (spellBookApi.IsSpellInSpellBook or spellBookApi.IsSpellKnown) or nil -- 技能已学判定
  if type(spellCheckFn) == "function" then
    for _, spellID in ipairs(spellIDList or {}) do
      local numericSpellID = tonumber(spellID) -- 技能 ID
      if numericSpellID then
        local success, isKnown = pcall(spellCheckFn, numericSpellID) -- 技能已学查询结果
        if success and isKnown == true then
          availabilityContext.knownSpellByID[numericSpellID] = true
        end
      end
    end
  end

  -- 炉石（SpellID 8690）由物品触发，不依赖于法术书；检查玩家背包中是否有炉石物品（ItemID 6948）
  if not availabilityContext.knownSpellByID[8690] then
    local itemApi = type(C_Item) == "table" and C_Item or nil
    local getItemCountFn = (itemApi and itemApi.GetItemCount) or GetItemCount
    if type(getItemCountFn) == "function" then
      local itemSuccess, itemCount = pcall(getItemCountFn, 6948)
      if itemSuccess and tonumber(itemCount) and tonumber(itemCount) > 0 then
        availabilityContext.knownSpellByID[8690] = true
      end
    end
  end

  return availabilityContext
end

--- 生成最终目标坐标点的步骤文案。
---@param target table 地图目标
---@param targetName string 目标显示名
---@return string
local function buildTargetPointLabel(target, targetName)
  local targetX = tonumber(target and target.x) -- 目标 X
  local targetY = tonumber(target and target.y) -- 目标 Y
  if isNormalizedPosition(targetX, targetY) then
    return string.format("目标位置：%s %.1f, %.1f", tostring(targetName), targetX * 100, targetY * 100)
  end
  return "目标位置：" .. tostring(targetName)
end

--- 为指定地图 ID 建立一组可回退的候选地图 ID。
---@param mapID number|nil 原始地图 ID
---@param mapNodes table 地图节点表
---@return table
local function buildRouteMapCandidateSet(mapID, mapNodes)
  local candidateSet = {} -- 可回退地图 ID 集合
  local currentMapID = tonumber(mapID) -- 当前候选地图 ID
  local guardCount = 0 -- 父链保护计数

  while currentMapID and currentMapID > 0 and guardCount < 16 do
    if candidateSet[currentMapID] then
      break
    end
    candidateSet[currentMapID] = true
    local nodeDef = type(mapNodes) == "table" and mapNodes[currentMapID] or nil -- 当前地图定义
    currentMapID = tonumber(nodeDef and nodeDef.ParentUiMapID) -- 父地图 ID
    guardCount = guardCount + 1
  end
  -- guardCount >= 16: 父链异常过长，静默截断以避免死循环

  return candidateSet
end

--- 统计每个 UiMap 节点参与的路线边数量。
---@param edgeList table|nil 路线边列表
---@return table
local function buildEdgeDegreeByUiMapID(edgeList)
  local degreeByUiMapID = {} -- 地图节点关联边数量
  for _, edge in ipairs(type(edgeList) == "table" and edgeList or {}) do
    local fromUiMapID = tonumber(edge and edge.fromUiMapID) -- 边起点地图 ID
    local toUiMapID = tonumber(edge and edge.toUiMapID) -- 边终点地图 ID
    if fromUiMapID and fromUiMapID > 0 then
      degreeByUiMapID[fromUiMapID] = (degreeByUiMapID[fromUiMapID] or 0) + 1
    end
    if toUiMapID and toUiMapID > 0 then
      degreeByUiMapID[toUiMapID] = (degreeByUiMapID[toUiMapID] or 0) + 1
    end
  end
  return degreeByUiMapID
end

--- 将地图 ID 解析为更适合参与导航的路线节点地图 ID。
---@param rawMapID number|nil 原始地图 ID
---@param resolvedAtPositionMapID number|nil 指定点位解析出的地图 ID
---@param mapNodes table 地图节点表
---@param edgeDegreeByUiMapID table 地图边数量表
---@return number|nil
local function resolveRouteMapID(rawMapID, resolvedAtPositionMapID, mapNodes, edgeDegreeByUiMapID)
  local searchMapIDList = {} -- 需要展开候选的地图 ID 列表
  local searchSet = {} -- 已加入的地图 ID 集合
  local function appendSearchMapID(mapID)
    local numericMapID = tonumber(mapID) -- 目标地图 ID
    if numericMapID and numericMapID > 0 and not searchSet[numericMapID] then
      searchSet[numericMapID] = true
      searchMapIDList[#searchMapIDList + 1] = numericMapID
    end
  end

  appendSearchMapID(rawMapID)
  appendSearchMapID(resolvedAtPositionMapID)

  local rankedCandidateList = {} -- 排序后的候选地图列表
  local rankedSet = {} -- 已加入候选的地图 ID 集合
  local function pushRankedCandidate(mapID)
    local numericMapID = tonumber(mapID) -- 候选地图 ID
    if numericMapID and numericMapID > 0 and not rankedSet[numericMapID] then
      rankedSet[numericMapID] = true
      rankedCandidateList[#rankedCandidateList + 1] = numericMapID
    end
  end

  for _, searchMapID in ipairs(searchMapIDList) do
    local parentCandidateSet = buildRouteMapCandidateSet(searchMapID, mapNodes) -- 原始地图与父链候选
    pushRankedCandidate(searchMapID)
    for candidateMapID in pairs(parentCandidateSet) do
      if candidateMapID ~= searchMapID then
        pushRankedCandidate(candidateMapID)
      end
    end

    local searchNode = type(mapNodes) == "table" and mapNodes[searchMapID] or nil -- 搜索地图定义
    local searchName = tostring(searchNode and searchNode.Name_lang or "") -- 搜索地图名称
    if searchName ~= "" then
      for candidateMapID, nodeDef in pairs(type(mapNodes) == "table" and mapNodes or {}) do
        if tostring(nodeDef and nodeDef.Name_lang or "") == searchName then
          pushRankedCandidate(candidateMapID)
        end
      end
    end
  end

  local bestMapID = nil -- 最优候选地图 ID
  local bestScore = nil -- 最优候选评分
  for _, candidateMapID in ipairs(rankedCandidateList) do
    local nodeDef = type(mapNodes) == "table" and mapNodes[candidateMapID] or nil -- 候选地图定义
    local mapType = tonumber(nodeDef and nodeDef.MapType) or 99 -- 候选地图类型
    local degree = tonumber(edgeDegreeByUiMapID and edgeDegreeByUiMapID[candidateMapID]) or 0 -- 候选地图关联边数量
    local mapTypeRank = 4 -- 地图类型优先级
    if mapType == 3 then
      mapTypeRank = 0
    elseif mapType == 6 then
      mapTypeRank = 1
    elseif mapType == 4 or mapType == 5 then
      mapTypeRank = 2
    elseif mapType < 3 then
      mapTypeRank = 3
    end
    local score = mapTypeRank * 10000000 + (degree > 0 and 0 or 100000) + candidateMapID -- 候选排序分数
    if bestScore == nil or score < bestScore then
      bestScore = score
      bestMapID = candidateMapID
    end
  end

  return bestMapID or tonumber(rawMapID)
end

--- 若目标点位于更具体的子图，优先把目标解析为该子图。
---@param target table 地图目标
---@return table
local function resolveConcreteTarget(target)
  if type(target) ~= "table" then
    return target
  end
  local targetMapID = tonumber(target.uiMapID) -- 原始目标地图 ID
  local targetX = tonumber(target.x) -- 原始目标 X
  local targetY = tonumber(target.y) -- 原始目标 Y
  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local routeEdgeData = Toolbox.Data and Toolbox.Data.NavigationRouteEdges or {} -- 契约导出的统一路线边数据
  local edgeDegreeByUiMapID = buildEdgeDegreeByUiMapID(routeEdgeData.edges) -- 地图边数量
  if not targetMapID then
    return target
  end

  local mapApi = type(C_Map) == "table" and C_Map or nil -- 地图 API 表
  local getMapInfoAtPosition = mapApi and mapApi.GetMapInfoAtPosition or nil -- 指定点位命中的更具体地图
  local resolvedAtPositionMapID = nil -- 指定点位解析出的更具体地图 ID
  local resolvedName = nil -- 指定点位解析出的地图名
  if isNormalizedPosition(targetX, targetY) and type(getMapInfoAtPosition) == "function" then
    local success, mapInfo = pcall(getMapInfoAtPosition, targetMapID, targetX, targetY) -- 命中的地图信息
    resolvedAtPositionMapID = success and type(mapInfo) == "table" and tonumber(mapInfo.mapID) or nil
    resolvedName = success and type(mapInfo) == "table" and mapInfo.name or nil
  end

  local resolvedMapID = resolveRouteMapID(targetMapID, resolvedAtPositionMapID, mapNodes, edgeDegreeByUiMapID) -- 参与导航的目标地图 ID
  if not resolvedMapID or resolvedMapID <= 0 or resolvedMapID == targetMapID then
    return target
  end

  local resolvedTarget = {} -- 解析后的目标
  for key, value in pairs(target) do
    resolvedTarget[key] = value
  end
  resolvedTarget.uiMapID = resolvedMapID
  if type(resolvedName) == "string" and resolvedName ~= "" then
    resolvedTarget.name = resolvedName
  elseif type(mapNodes[resolvedMapID]) == "table" and type(mapNodes[resolvedMapID].Name_lang) == "string" then
    resolvedTarget.name = mapNodes[resolvedMapID].Name_lang
  end
  return resolvedTarget
end

--- 读取路线边文案。
---@param edge table|nil 路线边
---@return string|nil
local function buildRouteEdgeLabel(edge)
  return type(edge) == "table" and edge.label or nil
end

--- 向路径图写入一组节点定义。
---@param routeGraph table 正在构建的路径图
---@param nodeTable table|nil 节点定义表
local function addRouteGraphNodes(routeGraph, nodeTable)
  for nodeId, nodeDef in pairs(type(nodeTable) == "table" and nodeTable or {}) do
    if type(nodeDef) == "table" then
      routeGraph.nodes[nodeId] = {
        id = nodeId,
        name = nodeDef.Name_lang or tostring(nodeId),
        uiMapID = tonumber(nodeDef.UiMapID),
        source = nodeDef.Source,
        kind = nodeDef.Kind,
        walkClusterKey = tostring(nodeDef.WalkClusterKey or nodeDef.walkClusterKey or nodeId),
        taxiNodeID = tonumber(nodeDef.TaxiNodeID or nodeDef.taxiNodeID),
      }
    end
  end
end

--- 向路径图追加一组边定义。
---@param routeGraph table 正在构建的路径图
---@param edgeList table|nil 边定义列表
local function addRouteGraphEdges(routeGraph, edgeList)
  for _, edge in ipairs(type(edgeList) == "table" and edgeList or {}) do
    local edgeCopy = {} -- 运行时路线边副本
    for key, value in pairs(type(edge) == "table" and edge or {}) do
      edgeCopy[key] = value
    end
    edgeCopy.label = buildRouteEdgeLabel(edgeCopy) or edgeCopy.label
    edgeCopy.stepCost = tonumber(edgeCopy.stepCost or edgeCopy.StepCost) or 1
    edgeCopy.mode = edgeCopy.mode or edgeCopy.Mode or "unknown"
    edgeCopy.traversedUiMapIDs = copyArray(edgeCopy.traversedUiMapIDs or edgeCopy.TraversedUiMapIDs)
    edgeCopy.traversedUiMapNames = copyArray(edgeCopy.traversedUiMapNames or edgeCopy.TraversedUiMapNames)
    routeGraph.edges[#routeGraph.edges + 1] = edgeCopy
  end
end

--- 若当前角色已在某个路径节点对应地图，添加零成本起点边。
---@param routeGraph table 正在构建的路径图
---@param nodeTable table|nil 节点定义表
---@param availabilityContext table|nil 当前角色可用性快照
local function addCurrentLocationEdges(routeGraph, nodeTable, availabilityContext)
  local currentMapID = tonumber(availabilityContext and availabilityContext.currentUiMapID) -- 当前角色所在地图
  if not currentMapID then
    return
  end

  local currentX = tonumber(availabilityContext and availabilityContext.currentX) -- 当前角色 X
  local currentY = tonumber(availabilityContext and availabilityContext.currentY) -- 当前角色 Y
  local resolvedAtPositionMapID = nil -- 当前点位命中的更具体地图 ID
  local mapApi = type(C_Map) == "table" and C_Map or nil -- 地图 API 表
  local getMapInfoAtPosition = mapApi and mapApi.GetMapInfoAtPosition or nil -- 指定点位命中的更具体地图
  if isNormalizedPosition(currentX, currentY) and type(getMapInfoAtPosition) == "function" then
    local success, mapInfo = pcall(getMapInfoAtPosition, currentMapID, currentX, currentY) -- 当前点位命中的地图信息
    resolvedAtPositionMapID = success and type(mapInfo) == "table" and tonumber(mapInfo.mapID) or nil
  end

  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local routeEdgeData = Toolbox.Data and Toolbox.Data.NavigationRouteEdges or {} -- 契约导出的统一路线边数据
  local edgeDegreeByUiMapID = buildEdgeDegreeByUiMapID(routeEdgeData.edges) -- 地图边数量
  local resolvedCurrentMapID = resolveRouteMapID(currentMapID, resolvedAtPositionMapID, mapNodes, edgeDegreeByUiMapID) -- 可参与导航的当前地图 ID

  for nodeId, nodeDef in pairs(type(nodeTable) == "table" and nodeTable or {}) do
    local nodeSource = nodeDef and nodeDef.Source -- 导出节点来源
    local nodeMapID = tonumber(nodeDef and nodeDef.UiMapID) -- 导出节点对应地图
    if nodeSource == "uimap" and nodeMapID == resolvedCurrentMapID then
      routeGraph.edges[#routeGraph.edges + 1] = {
        from = "current",
        to = nodeId,
        cost = 0,
        stepCost = 1,
        label = "当前位置：" .. tostring(nodeDef.Name_lang or nodeId),
        mode = WALK_LOCAL_MODE,
        traversedUiMapIDs = { resolvedCurrentMapID },
        traversedUiMapNames = { tostring(nodeDef.Name_lang or nodeId) },
      }
    end
  end
end

--- 向路径图追加一条本地步行边。
---@param routeGraph table 正在构建的路径图
---@param fromNodeId any 起点节点 ID
---@param toNodeId any 终点节点 ID
---@param traversedUiMapIDs table|nil 经过地图 ID 列表
---@param traversedUiMapNames table|nil 经过地图名称列表
local function addWalkLocalEdge(routeGraph, fromNodeId, toNodeId, traversedUiMapIDs, traversedUiMapNames)
  if fromNodeId == nil or toNodeId == nil or fromNodeId == toNodeId then
    return
  end
  if routeGraph.nodes[fromNodeId] == nil or routeGraph.nodes[toNodeId] == nil then
    return
  end
  local fromNode = routeGraph.nodes[fromNodeId] or {} -- 起点节点
  local toNode = routeGraph.nodes[toNodeId] or {} -- 终点节点
  routeGraph.edges[#routeGraph.edges + 1] = {
    from = fromNodeId,
    to = toNodeId,
    cost = 0,
    stepCost = 1,
    label = string.format("步行：%s -> %s", tostring(fromNode.name or fromNodeId), tostring(toNode.name or toNodeId)),
    mode = WALK_LOCAL_MODE,
    walkDistance = 0,
    traversedUiMapIDs = copyArray(traversedUiMapIDs),
    traversedUiMapNames = copyArray(traversedUiMapNames),
  }
end

--- 基于 WalkClusterKey 为本地可步行节点补动态接线。
---@param routeGraph table 正在构建的路径图
local function addDynamicWalkLocalEdges(routeGraph)
  for nodeId, nodeDef in pairs(routeGraph.nodes or {}) do
    local walkClusterKey = tostring(nodeDef and nodeDef.walkClusterKey or "") -- 节点所属本地步行连通域
    local clusterNode = routeGraph.nodes[walkClusterKey] -- 连通域锚点节点
    if walkClusterKey ~= "" and clusterNode ~= nil and walkClusterKey ~= nodeId then
      local traversedUiMapIDs = {} -- 本地步行段经过地图 ID
      local traversedUiMapNames = {} -- 本地步行段经过地图名
      appendUniqueArray(traversedUiMapIDs, { tonumber(nodeDef.uiMapID) })
      appendUniqueArray(traversedUiMapIDs, { tonumber(clusterNode.uiMapID) })
      appendUniqueArray(traversedUiMapNames, { tostring(nodeDef.name or nodeId) })
      appendUniqueArray(traversedUiMapNames, { tostring(clusterNode.name or walkClusterKey) })
      addWalkLocalEdge(routeGraph, nodeId, walkClusterKey, traversedUiMapIDs, traversedUiMapNames)
      addWalkLocalEdge(routeGraph, walkClusterKey, nodeId, traversedUiMapIDs, traversedUiMapNames)
    end
  end
end

--- 判断能力模板是否满足当前角色可用性。
---@param templateDef table|nil 能力模板
---@param availabilityContext table|nil 当前角色可用性快照
---@return boolean
local function isAbilityTemplateAvailable(templateDef, availabilityContext)
  if type(templateDef) ~= "table" then
    return false
  end
  local context = availabilityContext or {} -- 当前角色上下文
  local classFile = templateDef.ClassFile or templateDef.classFile -- 模板职业限制
  local factionGroup = templateDef.FactionGroup or templateDef.factionGroup -- 模板阵营限制
  local spellID = tonumber(templateDef.SpellID or templateDef.spellID) -- 模板技能 ID
  if classFile and classFile ~= context.classFile then
    return false
  end
  if factionGroup and factionGroup ~= context.faction then
    return false
  end
  if spellID then
    local knownSpellByID = context.knownSpellByID -- 已确认技能集合
    if type(knownSpellByID) ~= "table" or knownSpellByID[spellID] ~= true then
      return false
    end
  end
  return true
end

--- 解析能力模板本次查询的目标节点。
---@param templateDef table|nil 能力模板
---@param availabilityContext table|nil 当前角色可用性快照
---@return string|nil
local function resolveAbilityTemplateTargetNodeID(templateDef, availabilityContext)
  local targetRuleKind = tostring(type(templateDef) == "table" and (templateDef.TargetRuleKind or templateDef.targetRuleKind) or "") -- 目标规则
  if targetRuleKind == "fixed_node" then
    return type(templateDef) == "table" and (templateDef.ToNodeID or templateDef.toNodeID) or nil
  end
  if targetRuleKind == "hearth_bind" then
    return availabilityContext and availabilityContext.hearthBindNodeID or nil
  end
  return nil
end

--- 按当前角色配置从能力模板展开边。
---@param routeGraph table 正在构建的路径图
---@param availabilityContext table|nil 当前角色可用性快照
local function addAbilityTemplateEdges(routeGraph, availabilityContext)
  local abilityTemplateData = Toolbox.Data and Toolbox.Data.NavigationAbilityTemplates or {} -- 契约导出的能力模板
  local templateTable = type(abilityTemplateData.templates) == "table" and abilityTemplateData.templates or {} -- 模板表
  local templateIDList = {} -- 稳定模板键列表
  for templateID in pairs(templateTable) do
    templateIDList[#templateIDList + 1] = tostring(templateID)
  end
  table.sort(templateIDList)

  for _, templateID in ipairs(templateIDList) do
    local templateDef = templateTable[templateID] -- 模板定义
    if isAbilityTemplateAvailable(templateDef, availabilityContext) then
      local toNodeId = resolveAbilityTemplateTargetNodeID(templateDef, availabilityContext) -- 模板展开后的目标节点
      local targetNode = toNodeId and routeGraph.nodes[toNodeId] or nil -- 目标节点定义
      if toNodeId and targetNode then
        routeGraph.edges[#routeGraph.edges + 1] = {
          from = "current",
          to = toNodeId,
          cost = 0,
          stepCost = 1,
          label = tostring(templateDef.Label or templateDef.label or templateID),
          mode = tostring(templateDef.Mode or templateDef.mode or "unknown"),
          traversedUiMapIDs = targetNode.uiMapID and { targetNode.uiMapID } or {},
          traversedUiMapNames = { tostring(targetNode.name or toNodeId) },
        }
      end
    end
  end
end

--- 计算当前位置直接前往目标点的成本。
---@param target table 地图目标
---@param availabilityContext table|nil 当前角色可用性快照
---@return number
local function buildDirectTargetCost(target, availabilityContext)
  local targetMapID = tonumber(target and target.uiMapID) -- 目标地图 ID
  local currentMapID = tonumber(availabilityContext and availabilityContext.currentUiMapID) -- 当前地图 ID
  local currentX = tonumber(availabilityContext and availabilityContext.currentX) -- 当前 X
  local currentY = tonumber(availabilityContext and availabilityContext.currentY) -- 当前 Y
  local targetX = tonumber(target and target.x) -- 目标 X
  local targetY = tonumber(target and target.y) -- 目标 Y
  if targetMapID and currentMapID and targetMapID == currentMapID then
    local travelCost = estimateInMapTravelCost(targetMapID, currentX, currentY, targetX, targetY) -- 同图直接移动成本
    if tonumber(travelCost) then
      return travelCost
    end
  end
  return 180
end

--- 构建第一版地图目标路径图。
---@param target table 目标，包含 `uiMapID` 与可选 `x` / `y`
---@param availabilityContext table|nil 当前角色可用性快照
---@return table routeGraph 路径图
local function buildMapTargetRouteGraph(target, availabilityContext)
  local targetMapID = tonumber(target and target.uiMapID) or 0 -- 目标地图 ID
  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local routeEdgeData = Toolbox.Data and Toolbox.Data.NavigationRouteEdges or {} -- 契约导出的统一路线边数据
  local targetNodeId = "target" -- 目标节点 ID
  local targetMapNodeId = "uimap_" .. tostring(targetMapID) -- 目标 UiMap 节点 ID
  local targetNode = mapNodes[targetMapID] -- 目标地图节点
  local targetName = tostring((target and target.name) or (targetNode and targetNode.Name_lang) or ("Map #" .. tostring(targetMapID))) -- 目标显示名
  local targetPointLabel = buildTargetPointLabel(target, targetName) -- 目标坐标点步骤文案
  local mergedNodes = {} -- 契约导出节点的合并视图
  local routeGraph = {
    nodes = {
      current = { id = "current", name = "当前位置" },
      target = { id = targetNodeId, name = targetName },
    },
    edges = {},
  } -- 目标路径图；所有跨地图路线边由契约导出，运行时只补当前位置与目标坐标点

  for nodeId, nodeDef in pairs(type(routeEdgeData.nodes) == "table" and routeEdgeData.nodes or {}) do
    if mergedNodes[nodeId] == nil then
      mergedNodes[nodeId] = nodeDef
    end
  end

  addRouteGraphNodes(routeGraph, mergedNodes)
  addRouteGraphEdges(routeGraph, routeEdgeData.edges)
  addDynamicWalkLocalEdges(routeGraph)
  addCurrentLocationEdges(routeGraph, mergedNodes, availabilityContext)
  addAbilityTemplateEdges(routeGraph, availabilityContext)

  if routeGraph.nodes[targetMapNodeId] ~= nil then
    routeGraph.edges[#routeGraph.edges + 1] = {
      from = targetMapNodeId,
      to = targetNodeId,
      cost = buildDirectTargetCost(target, { currentUiMapID = targetMapID }),
      stepCost = 1,
      label = targetPointLabel,
      mode = WALK_LOCAL_MODE,
      traversedUiMapIDs = { targetMapID },
      traversedUiMapNames = { targetName },
    }
  end

  return routeGraph
end

--- 规划当前角色前往世界地图目标的第一版路线。
---@param target table 目标，包含 `uiMapID` 与可选 `x` / `y`
---@param availabilityContext table|nil 当前角色可用性快照
---@return table|nil routeResult 成功时包含 `totalCost`、`nodePath`、`stepLabels`
---@return table|nil errorObject 失败时包含 `code`
function Toolbox.Navigation.PlanRouteToMapTarget(target, availabilityContext)
  if type(target) ~= "table" or type(target.uiMapID) ~= "number" then
    return nil, { code = "NAVIGATION_ERR_BAD_TARGET" }
  end
  local resolvedTarget = resolveConcreteTarget(target) -- 解析后的具体目标
  local targetMapID = tonumber(resolvedTarget.uiMapID) -- 目标地图 ID
  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local targetMapNode = mapNodes[targetMapID] -- 目标地图定义
  local targetMapType = tonumber(targetMapNode and targetMapNode.MapType) -- 目标地图类型
  if targetMapType and targetMapType < 3 then
    return nil, { code = "NAVIGATION_ERR_UNSUPPORTED_MAP_LEVEL" }
  end
  local routeGraph = buildMapTargetRouteGraph(resolvedTarget, availabilityContext) -- 第一版目标路径图
  return Toolbox.Navigation.PlanRoute(routeGraph, "current", "target", availabilityContext)
end
