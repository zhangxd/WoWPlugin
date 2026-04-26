--[[
  地图导航（领域对外 API）（Toolbox.Navigation）：路径图、可用性过滤与最短路径求解。
  业务模块只负责入口与 UI，本文件不直接操作世界地图 Frame。
]]

Toolbox.Navigation = Toolbox.Navigation or {}

--- 按 from 节点为边建立索引，便于 Dijkstra 查询相邻边。
---@param edgeList table|nil 路径边列表
---@return table edgeListByFrom 按起点分组的边表
local function buildEdgeListByFrom(edgeList)
  local edgeListByFrom = {} -- 起点到边列表的索引
  for _, edge in ipairs(edgeList or {}) do
    local fromNodeId = edge and edge.from -- 边起点
    local toNodeId = edge and edge.to -- 边终点
    if fromNodeId and toNodeId then
      edgeListByFrom[fromNodeId] = edgeListByFrom[fromNodeId] or {}
      edgeListByFrom[fromNodeId][#edgeListByFrom[fromNodeId] + 1] = edge
    end
  end
  return edgeListByFrom
end

--- 从未访问节点中找出当前代价最低的节点。
---@param unvisited table 未访问节点集合
---@param costByNode table 节点总代价表
---@return any nodeId 代价最低的节点 ID
local function popLowestCostNode(unvisited, costByNode)
  local bestNodeId = nil -- 当前最低代价节点
  local bestCost = math.huge -- 当前最低代价
  for nodeId in pairs(unvisited) do
    local currentCost = costByNode[nodeId] or math.huge -- 节点总代价
    if currentCost < bestCost then
      bestCost = currentCost
      bestNodeId = nodeId
    end
  end
  if bestNodeId ~= nil then
    unvisited[bestNodeId] = nil
  end
  return bestNodeId
end

--- 回溯 Dijkstra 结果，生成节点路径与步骤文案。
---@param startNodeId any 起点节点 ID
---@param targetNodeId any 终点节点 ID
---@param previousNodeById table 前驱节点表
---@param previousEdgeById table 前驱边表
---@return table nodePath 节点路径
---@return table stepLabels 步骤文案列表
local function buildRouteResult(startNodeId, targetNodeId, previousNodeById, previousEdgeById)
  local reversedNodePath = {} -- 反向节点路径
  local reversedStepLabels = {} -- 反向步骤文案
  local currentNodeId = targetNodeId -- 当前回溯节点

  while currentNodeId ~= nil do
    reversedNodePath[#reversedNodePath + 1] = currentNodeId
    local previousEdge = previousEdgeById[currentNodeId] -- 抵达当前节点的边
    if previousEdge then
      reversedStepLabels[#reversedStepLabels + 1] = previousEdge.label or previousEdge.name or tostring(previousEdge.to or "")
    end
    if currentNodeId == startNodeId then
      break
    end
    currentNodeId = previousNodeById[currentNodeId]
  end

  local nodePath = {} -- 正向节点路径
  for i = #reversedNodePath, 1, -1 do
    nodePath[#nodePath + 1] = reversedNodePath[i]
  end

  local stepLabels = {} -- 正向步骤文案
  for i = #reversedStepLabels, 1, -1 do
    stepLabels[#stepLabels + 1] = reversedStepLabels[i]
  end

  return nodePath, stepLabels
end

--- 判断单条边是否满足当前角色可用性要求。
---@param edge table 路径边
---@param availabilityContext table|nil 当前角色可用性快照
---@return boolean
local function isEdgeAvailable(edge, availabilityContext)
  local requirements = edge and edge.requirements or nil -- 边可用性要求
  if type(requirements) ~= "table" then
    return true
  end

  local context = availabilityContext or {} -- 当前角色上下文
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

--- 在路径图中查找起点到终点的最低耗时路线。
---@param routeGraph table 路径图，包含 `nodes` 与 `edges`
---@param startNodeId any 起点节点 ID
---@param targetNodeId any 终点节点 ID
---@return table|nil routeResult 成功时包含 `totalCost`、`nodePath`、`stepLabels`
---@return table|nil errorObject 失败时包含 `code`
function Toolbox.Navigation.FindShortestPath(routeGraph, startNodeId, targetNodeId)
  if type(routeGraph) ~= "table" or type(routeGraph.nodes) ~= "table" then
    return nil, { code = "NAVIGATION_ERR_BAD_GRAPH" }
  end
  if routeGraph.nodes[startNodeId] == nil or routeGraph.nodes[targetNodeId] == nil then
    return nil, { code = "NAVIGATION_ERR_UNKNOWN_NODE" }
  end

  local edgeListByFrom = buildEdgeListByFrom(routeGraph.edges) -- 起点到边列表索引
  local unvisited = {} -- 未访问节点集合
  local costByNode = {} -- 起点到各节点的最低代价
  local previousNodeById = {} -- 最短路径前驱节点
  local previousEdgeById = {} -- 最短路径前驱边

  for nodeId in pairs(routeGraph.nodes) do
    unvisited[nodeId] = true
    costByNode[nodeId] = math.huge
  end
  costByNode[startNodeId] = 0

  while true do
    local currentNodeId = popLowestCostNode(unvisited, costByNode) -- 当前展开节点
    if currentNodeId == nil then
      break
    end
    if currentNodeId == targetNodeId then
      break
    end

    for _, edge in ipairs(edgeListByFrom[currentNodeId] or {}) do
      local toNodeId = edge.to -- 边终点
      local edgeCost = tonumber(edge.cost) -- 边耗时
      if toNodeId ~= nil and edgeCost ~= nil and edgeCost >= 0 then
        local nextCost = (costByNode[currentNodeId] or math.huge) + edgeCost -- 经过当前边后的总代价
        if nextCost < (costByNode[toNodeId] or math.huge) then
          costByNode[toNodeId] = nextCost
          previousNodeById[toNodeId] = currentNodeId
          previousEdgeById[toNodeId] = edge
        end
      end
    end
  end

  if costByNode[targetNodeId] == math.huge then
    return nil, { code = "NAVIGATION_ERR_NO_ROUTE" }
  end

  local nodePath, stepLabels = buildRouteResult(startNodeId, targetNodeId, previousNodeById, previousEdgeById) -- 路线结果
  return {
    totalCost = costByNode[targetNodeId],
    nodePath = nodePath,
    stepLabels = stepLabels,
  }, nil
end

--- 按当前角色可用性过滤路径图后规划最低耗时路线。
---@param routeGraph table 路径图，包含 `nodes` 与 `edges`
---@param startNodeId any 起点节点 ID
---@param targetNodeId any 终点节点 ID
---@param availabilityContext table|nil 当前角色可用性快照
---@return table|nil routeResult 成功时包含 `totalCost`、`nodePath`、`stepLabels`
---@return table|nil errorObject 失败时包含 `code`
function Toolbox.Navigation.PlanRoute(routeGraph, startNodeId, targetNodeId, availabilityContext)
  local filteredGraph = Toolbox.Navigation.FilterRouteGraph(routeGraph, availabilityContext) -- 可用边过滤后的路径图
  return Toolbox.Navigation.FindShortestPath(filteredGraph, startNodeId, targetNodeId)
end

--- 从路径数据中收集所有需要检查的 spellID，供运行时构建当前角色可用性快照。
---@param routeData table|nil 路径数据，默认使用 `Toolbox.Data.NavigationManualEdges`
---@return table spellIDList 去重后的技能 ID 序列
function Toolbox.Navigation.GetRequiredSpellIDList(routeData)
  local manualData = routeData or (Toolbox.Data and Toolbox.Data.NavigationManualEdges) or {} -- 手工路径数据
  local seenSpellID = {} -- 已收集技能 ID 集合
  local spellIDList = {} -- 技能 ID 序列

  for _, edge in ipairs(type(manualData.edges) == "table" and manualData.edges or {}) do
    local requirements = type(edge) == "table" and edge.requirements or nil -- 边可用性要求
    local spellID = type(requirements) == "table" and tonumber(requirements.spellID) or nil -- 技能 ID
    if spellID and not seenSpellID[spellID] then
      seenSpellID[spellID] = true
      spellIDList[#spellIDList + 1] = spellID
    end
  end

  return spellIDList
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
    knownSpellByID = {},
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

  local spellBookApi = type(C_SpellBook) == "table" and C_SpellBook or nil -- spellbook API 表
  local spellCheckFn = spellBookApi and (spellBookApi.IsSpellInSpellBook or spellBookApi.IsSpellKnown) or nil -- 技能已学判定
  if type(spellCheckFn) ~= "function" then
    return availabilityContext
  end

  for _, spellID in ipairs(spellIDList or {}) do
    local numericSpellID = tonumber(spellID) -- 技能 ID
    if numericSpellID then
      local success, isKnown = pcall(spellCheckFn, numericSpellID) -- 技能已学查询结果
      if success and isKnown == true then
        availabilityContext.knownSpellByID[numericSpellID] = true
      end
    end
  end

  return availabilityContext
end

--- 为目标规则添加一个候选中转点到目标的连接边。
---@param routeGraph table 正在构建的路径图
---@param viaNodeDef table 候选中转点定义
---@param targetNodeId string 目标节点 ID
---@param targetName string 目标显示名
local function addTargetViaNodeEdge(routeGraph, viaNodeDef, targetNodeId, targetName)
  local viaNodeId = type(viaNodeDef) == "table" and viaNodeDef.node or nil -- 中转节点 ID
  if not viaNodeId or not routeGraph.nodes[viaNodeId] then
    return
  end

  routeGraph.edges[#routeGraph.edges + 1] = {
    from = viaNodeId,
    to = targetNodeId,
    cost = tonumber(viaNodeDef.cost) or 0,
    label = viaNodeDef.label or ("前往" .. targetName),
  }
end

--- 若当前角色已在某个手工路径节点对应地图，添加零成本起点边。
---@param routeGraph table 正在构建的路径图
---@param manualData table 手工路径数据
---@param availabilityContext table|nil 当前角色可用性快照
local function addCurrentLocationEdges(routeGraph, manualData, availabilityContext)
  local currentMapID = tonumber(availabilityContext and availabilityContext.currentUiMapID) -- 当前角色所在地图
  if not currentMapID then
    return
  end

  for nodeId, nodeDef in pairs(type(manualData.nodes) == "table" and manualData.nodes or {}) do
    local nodeMapID = tonumber(nodeDef and nodeDef.UiMapID) -- 手工节点对应地图
    if nodeMapID == currentMapID then
      routeGraph.edges[#routeGraph.edges + 1] = {
        from = "current",
        to = nodeId,
        cost = 0,
        label = "当前位置：" .. tostring(nodeDef.Name_lang or nodeId),
      }
    end
  end
end

--- 构建第一版地图目标路径图。
---@param target table 目标，包含 `uiMapID` 与可选 `x` / `y`
---@param availabilityContext table|nil 当前角色可用性快照
---@return table routeGraph 路径图
local function buildMapTargetRouteGraph(target, availabilityContext)
  local targetMapID = tonumber(target and target.uiMapID) or 0 -- 目标地图 ID
  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local manualData = Toolbox.Data and Toolbox.Data.NavigationManualEdges or {} -- 手工玩法路径数据
  local targetRules = type(manualData.targetRules) == "table" and manualData.targetRules or {} -- 目标规则表
  local targetRule = targetRules[targetMapID] or {} -- 当前目标规则
  local targetNodeId = "target" -- 目标节点 ID
  local targetNode = mapNodes[targetMapID] -- 目标地图节点
  local targetName = tostring((target and target.name) or (targetNode and targetNode.Name_lang) or ("Map #" .. tostring(targetMapID))) -- 目标显示名
  local directLabel = "前往" .. targetName -- 直接前往步骤文案
  local routeGraph = {
    nodes = {
      current = { id = "current", name = "当前位置" },
      target = { id = targetNodeId, name = targetName },
    },
    edges = {
      { from = "current", to = targetNodeId, cost = tonumber(targetRule.directCost) or 180, label = directLabel },
    },
  } -- 第一版目标路径图

  for nodeId, nodeDef in pairs(type(manualData.nodes) == "table" and manualData.nodes or {}) do
    if type(nodeDef) == "table" then
      routeGraph.nodes[nodeId] = {
        id = nodeId,
        name = nodeDef.Name_lang or tostring(nodeId),
      }
    end
  end

  for _, edge in ipairs(type(manualData.edges) == "table" and manualData.edges or {}) do
    routeGraph.edges[#routeGraph.edges + 1] = edge
  end

  addCurrentLocationEdges(routeGraph, manualData, availabilityContext)

  for _, viaNodeDef in ipairs(type(targetRule.viaNodes) == "table" and targetRule.viaNodes or {}) do
    addTargetViaNodeEdge(routeGraph, viaNodeDef, targetNodeId, targetName)
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
  local routeGraph = buildMapTargetRouteGraph(target, availabilityContext) -- 第一版目标路径图
  return Toolbox.Navigation.PlanRoute(routeGraph, "current", "target", availabilityContext)
end
