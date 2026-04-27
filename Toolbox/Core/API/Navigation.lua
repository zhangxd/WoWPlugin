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

--- 判断归一化坐标是否合法。
---@param x number|nil 坐标 X
---@param y number|nil 坐标 Y
---@return boolean
local function isNormalizedPosition(x, y)
  return type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
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

--- 计算中转落点到目标点的终段成本。
---@param viaNodeDef table 候选中转点定义
---@param target table 地图目标
---@return number
local function buildTerminalTravelCost(viaNodeDef, target)
  local arrivalMapID = tonumber(viaNodeDef and (viaNodeDef.arrivalUiMapID or target and target.uiMapID)) -- 中转落点地图 ID
  local targetMapID = tonumber(target and target.uiMapID) -- 目标地图 ID
  if not arrivalMapID or not targetMapID or arrivalMapID ~= targetMapID then
    return 0
  end
  local arrivalX = tonumber(viaNodeDef and viaNodeDef.arrivalX) -- 中转落点 X
  local arrivalY = tonumber(viaNodeDef and viaNodeDef.arrivalY) -- 中转落点 Y
  local targetX = tonumber(target and target.x) -- 目标 X
  local targetY = tonumber(target and target.y) -- 目标 Y
  local travelCost = estimateInMapTravelCost(arrivalMapID, arrivalX, arrivalY, targetX, targetY) -- 终段移动成本
  return tonumber(travelCost) or 0
end

--- 为目标规则添加一个候选中转点到目标的连接边。
---@param routeGraph table 正在构建的路径图
---@param viaNodeDef table 候选中转点定义
---@param target table 地图目标
---@param targetNodeId string 目标节点 ID
---@param targetName string 目标显示名
local function addTargetViaNodeEdge(routeGraph, viaNodeDef, target, targetNodeId, targetName)
  local viaNodeId = type(viaNodeDef) == "table" and viaNodeDef.node or nil -- 中转节点 ID
  if not viaNodeId or not routeGraph.nodes[viaNodeId] then
    return
  end
  local baseCost = tonumber(viaNodeDef.cost) or 0 -- 中转规则固定成本
  local terminalCost = buildTerminalTravelCost(viaNodeDef, target) -- 中转落点到目标点的终段成本

  routeGraph.edges[#routeGraph.edges + 1] = {
    from = viaNodeId,
    to = targetNodeId,
    cost = baseCost + terminalCost,
    label = viaNodeDef.label or ("前往" .. targetName),
  }
end

--- 将世界坐标转换为指定 UiMap 的归一化坐标。
---@param worldMapID number|nil 世界坐标所属 MapID
---@param worldX number|nil 世界坐标 X
---@param worldY number|nil 世界坐标 Y
---@param hintUiMapID number|nil 目标 UiMap 提示
---@return number|nil, number|nil
local function convertWorldPositionToUiMapPosition(worldMapID, worldX, worldY, hintUiMapID)
  if not tonumber(worldMapID) or tonumber(worldMapID) <= 0 or type(CreateVector2D) ~= "function" then
    return nil, nil
  end
  local mapApi = type(C_Map) == "table" and C_Map or nil -- 地图 API 表
  local getMapPosFromWorldPos = mapApi and mapApi.GetMapPosFromWorldPos or nil -- 世界坐标转地图坐标
  if type(getMapPosFromWorldPos) ~= "function" then
    return nil, nil
  end

  local vectorSuccess, worldPosition = pcall(CreateVector2D, worldX, worldY) -- 世界坐标向量
  if not vectorSuccess or not worldPosition then
    return nil, nil
  end

  local convertSuccess = false -- 坐标转换是否成功
  local targetUiMapID = nil -- 转换得到的地图 ID
  local targetPosition = nil -- 转换得到的归一化坐标
  if tonumber(hintUiMapID) and tonumber(hintUiMapID) > 0 then
    convertSuccess, targetUiMapID, targetPosition = pcall(getMapPosFromWorldPos, worldMapID, worldPosition, hintUiMapID)
  else
    convertSuccess, targetUiMapID, targetPosition = pcall(getMapPosFromWorldPos, worldMapID, worldPosition)
  end
  if not convertSuccess or not tonumber(targetUiMapID) or tonumber(targetUiMapID) <= 0 or not targetPosition then
    return nil, nil
  end

  return readVectorXY(targetPosition)
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
    local score = string.format("%d:%d:%05d", mapTypeRank, degree > 0 and 0 or 1, candidateMapID) -- 候选排序分数
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

--- 为含 portal 点位的路线边补充地图坐标文案。
---@param edge table|nil 路线边
---@return string|nil
local function buildRouteEdgeLabel(edge)
  local baseLabel = type(edge) == "table" and edge.label or nil -- 原始步骤文案
  if type(baseLabel) ~= "string" or baseLabel == "" then
    return baseLabel
  end
  if edge.mode ~= "WAYPOINT_LINK" then
    return baseLabel
  end

  local portalWorldMapID = tonumber(edge.portalWorldMapID) -- portal 世界坐标 MapID
  local portalWorldX = tonumber(edge.portalWorldX) -- portal 世界坐标 X
  local portalWorldY = tonumber(edge.portalWorldY) -- portal 世界坐标 Y
  local fromUiMapID = tonumber(edge.fromUiMapID) -- 边起点 UiMapID
  local fromX, fromY = convertWorldPositionToUiMapPosition(portalWorldMapID, portalWorldX, portalWorldY, fromUiMapID) -- portal 在起点地图上的归一化坐标
  if not isNormalizedPosition(fromX, fromY) then
    return baseLabel
  end

  local routeGraphNode = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local fromNode = routeGraphNode[fromUiMapID] -- 起点地图定义
  local fromName = tostring((fromNode and fromNode.Name_lang) or ("Map #" .. tostring(fromUiMapID))) -- 起点地图显示名
  return string.format("%s %.1f, %.1f；%s", fromName, fromX * 100, fromY * 100, baseLabel)
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
        label = "当前位置：" .. tostring(nodeDef.Name_lang or nodeId),
      }
    end
  end
end

--- 计算当前位置直接前往目标点的成本。
---@param target table 地图目标
---@param availabilityContext table|nil 当前角色可用性快照
---@param targetRule table 目标规则
---@return number
local function buildDirectTargetCost(target, availabilityContext, targetRule)
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
  return tonumber(targetRule and targetRule.directCost) or 180
end

--- 构建第一版地图目标路径图。
---@param target table 目标，包含 `uiMapID` 与可选 `x` / `y`
---@param availabilityContext table|nil 当前角色可用性快照
---@return table routeGraph 路径图
local function buildMapTargetRouteGraph(target, availabilityContext)
  local targetMapID = tonumber(target and target.uiMapID) or 0 -- 目标地图 ID
  local mapNodes = Toolbox.Data and Toolbox.Data.NavigationMapNodes and Toolbox.Data.NavigationMapNodes.nodes or {} -- 地图基础节点
  local routeEdgeData = Toolbox.Data and Toolbox.Data.NavigationRouteEdges or {} -- 契约导出的统一路线边数据
  local targetRules = type(routeEdgeData.targetRules) == "table" and routeEdgeData.targetRules or {} -- 契约导出的目标规则表
  local targetRule = targetRules[targetMapID] or {} -- 当前目标规则
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
  addCurrentLocationEdges(routeGraph, mergedNodes, availabilityContext)

  if routeGraph.nodes[targetMapNodeId] ~= nil then
    routeGraph.edges[#routeGraph.edges + 1] = {
      from = targetMapNodeId,
      to = targetNodeId,
      cost = buildDirectTargetCost(target, { currentUiMapID = targetMapID }, targetRule),
      label = targetPointLabel,
      mode = "TARGET_POINT",
    }
  end

  for _, viaNodeDef in ipairs(type(targetRule.viaNodes) == "table" and targetRule.viaNodes or {}) do
    addTargetViaNodeEdge(routeGraph, viaNodeDef, target, targetNodeId, targetName)
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
