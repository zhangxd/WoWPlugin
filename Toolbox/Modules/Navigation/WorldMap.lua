--[[
  navigation 世界地图入口：在 WorldMapFrame 显示时创建“规划路线”按钮。
  目标坐标读取当前用户 waypoint；历史重规划则直接接收显式目标快照。
]]

Toolbox.NavigationModule = Toolbox.NavigationModule or {}

local WorldMap = {}
Toolbox.NavigationModule.WorldMap = WorldMap

local worldMapHookInstalled = false -- WorldMapFrame OnShow 是否已挂接
local targetButton = nil -- 世界地图规划按钮

--- 读取 navigation 模块存档。
---@return table
local function getModuleDb()
  return Toolbox.Config.GetModule("navigation")
end

--- 输出一条导航相关聊天提示。
---@param messageText string|nil 玩家提示文案
local function printNavigationMessage(messageText)
  if not messageText or messageText == "" then
    return
  end
  if Toolbox.Chat and type(Toolbox.Chat.PrintAddonMessage) == "function" then
    Toolbox.Chat.PrintAddonMessage(messageText)
  end
end

--- 读取当前用户 waypoint。
---@return number|nil, number|nil, number|nil
local function getUserWaypointTarget()
  local mapApi = type(C_Map) == "table" and C_Map or nil -- 地图 API 表
  local getUserWaypoint = mapApi and mapApi.GetUserWaypoint or nil -- 用户 waypoint 查询
  if type(getUserWaypoint) ~= "function" then
    return nil, nil, nil
  end

  local success, pointValue = pcall(getUserWaypoint) -- waypoint 查询结果
  if not success or type(pointValue) ~= "table" then
    return nil, nil, nil
  end

  local mapID = tonumber(pointValue.uiMapID) -- waypoint 地图 ID
  local targetX, targetY = Toolbox.Navigation.ReadVectorXY(pointValue.position) -- waypoint 坐标
  if not mapID or mapID <= 0 or type(targetX) ~= "number" or type(targetY) ~= "number" then
    return nil, nil, nil
  end
  if targetX < 0 or targetX > 1 or targetY < 0 or targetY > 1 then
    return nil, nil, nil
  end
  return mapID, targetX, targetY
end

--- 将路线规划错误转换成玩家可见文案。
---@param errorObject table|nil 路线规划错误对象
---@return string|nil
local function getRouteFailureMessage(errorObject)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local errorCode = type(errorObject) == "table" and errorObject.code or nil -- 路线错误码
  if errorCode == "NAVIGATION_ERR_UNSUPPORTED_MAP_LEVEL" or errorCode == "NAVIGATION_ERR_BAD_TARGET" then
    return localeTable.NAVIGATION_ROUTE_UNSUPPORTED_TARGET or "当前目标层级暂不支持规划路线，请缩放到区域或子地图后再试。"
  end
  if errorCode == "NAVIGATION_ERR_NO_ROUTE" then
    return localeTable.NAVIGATION_ROUTE_NO_ROUTE or "当前目标暂无可用路线。"
  end
  if errorCode then
    return localeTable.NAVIGATION_ROUTE_PLAN_FAILED or "路线规划失败。"
  end
  return nil
end

--- 去除首尾空白，避免诊断输出里混入空节点名。
---@param rawText any 原始文本
---@return string
local function trimText(rawText)
  local trimmedText = tostring(rawText or "") -- 待裁剪文本
  trimmedText = string.gsub(trimmedText, "^%s+", "")
  trimmedText = string.gsub(trimmedText, "%s+$", "")
  return trimmedText
end

--- 从可用性快照里提取规划起点位置。
---@param availabilityContext table|nil 当前角色可用性快照
---@return table|nil
local function buildStartLocationSnapshot(availabilityContext)
  if type(availabilityContext) ~= "table" then
    return nil
  end
  local currentMapID = tonumber(availabilityContext.currentUiMapID) -- 当前地图 ID
  local currentX = tonumber(availabilityContext.currentX) -- 当前 X
  local currentY = tonumber(availabilityContext.currentY) -- 当前 Y
  if currentMapID == nil and currentX == nil and currentY == nil then
    return nil
  end
  return {
    currentUiMapID = currentMapID,
    currentX = currentX,
    currentY = currentY,
  }
end

--- 拼接一段路线的 traversedUiMapNames 调试文本。
---@param segment table|nil 路线段
---@return string
local function buildTraversedMapNamesText(segment)
  local textList = {} -- 经过地图名列表
  local traversedNameList = type(segment) == "table" and segment.traversedUiMapNames or nil -- 原始经过地图名
  for _, mapName in ipairs(type(traversedNameList) == "table" and traversedNameList or {}) do
    local trimmedName = trimText(mapName) -- 当前地图名
    if trimmedName ~= "" then
      textList[#textList + 1] = trimmedName
    end
  end
  if #textList == 0 then
    return "-"
  end
  return table.concat(textList, " -> ")
end

--- 提取一段路线的有效经过地图名列表。
---@param segment table|nil 路线段
---@return table
local function buildTraversedMapNameList(segment)
  local textList = {} -- 清洗后的经过地图名
  local traversedNameList = type(segment) == "table" and segment.traversedUiMapNames or nil -- 原始经过地图名
  for _, mapName in ipairs(type(traversedNameList) == "table" and traversedNameList or {}) do
    local trimmedName = trimText(mapName) -- 当前地图名
    if trimmedName ~= "" then
      textList[#textList + 1] = trimmedName
    end
  end
  return textList
end

--- 归一化节点文案，便于规划节点摘要去重。
---@param rawText any 原始文案
---@return string
local function normalizeNodeText(rawText)
  local normalizedText = string.lower(trimText(rawText)) -- 归一化前的节点文案
  normalizedText = string.gsub(normalizedText, "%s+", "")
  return normalizedText
end

--- 向规划诊断节点列表追加一个节点，避免相邻重复。
---@param nodeList table 节点列表
---@param nodeText any 待追加节点
local function appendPlanningNode(nodeList, nodeText)
  local trimmedText = trimText(nodeText) -- 去空白后的节点文案
  if trimmedText == "" then
    return
  end
  local lastNodeText = nodeList[#nodeList] -- 最近一个节点
  if normalizeNodeText(lastNodeText) == normalizeNodeText(trimmedText) then
    return
  end
  nodeList[#nodeList + 1] = trimmedText
end

--- 生成地图级节点文案；规划诊断摘要里不带坐标。
---@param routeBar table|nil 路线图模块
---@param uiMapID any 地图 ID
---@param fallbackText any 兜底文案
---@return string
local function buildMapNodeText(routeBar, uiMapID, fallbackText)
  if type(routeBar) == "table" and type(routeBar.BuildPositionDisplayText) == "function" then
    local mapText = trimText(routeBar.BuildPositionDisplayText(uiMapID, nil, nil, fallbackText)) -- RouteBar 格式化后的地图文案
    if mapText ~= "" then
      return mapText
    end
  end
  return trimText(fallbackText)
end

--- 基于路线段构建规划期诊断节点摘要。
---@param routeBar table|nil 路线图模块
---@param routeResult table|nil 路线结果
---@param routeTarget table|nil 路线目标
---@param startLocationSnapshot table|nil 规划起点快照
---@return string
local function buildPlanningNodeSummaryText(routeBar, routeResult, routeTarget, startLocationSnapshot)
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  if type(segmentList) ~= "table" or #segmentList == 0 then
    return ""
  end

  local firstSegment = segmentList[1] or nil -- 第一段路线
  local targetMapText = buildMapNodeText(
    routeBar,
    routeTarget and routeTarget.uiMapID,
    routeTarget and routeTarget.name
  ) -- 终点地图节点文案
  local nodeList = {} -- 规划期诊断节点列表
  appendPlanningNode(nodeList, buildMapNodeText(
    routeBar,
    startLocationSnapshot and startLocationSnapshot.currentUiMapID or (firstSegment and firstSegment.fromUiMapID),
    firstSegment and firstSegment.fromName
  ))

  for segmentIndex, segment in ipairs(segmentList) do
    local modeText = tostring(type(segment) == "table" and segment.mode or "") -- 当前路线方式
    local nextSegment = segmentList[segmentIndex + 1] -- 下一段路线
    local traversedMapNameList = buildTraversedMapNameList(segment) -- 当前段经过地图名
    if modeText == "walk_local" then
      for traversedIndex = 2, math.max(#traversedMapNameList - 1, 1) do
        appendPlanningNode(nodeList, traversedMapNameList[traversedIndex])
      end
      if nextSegment then
        appendPlanningNode(nodeList, segment and segment.toName)
      else
        appendPlanningNode(nodeList, targetMapText ~= "" and targetMapText or (segment and segment.toName))
      end
    else
      local lastTraversedMapName = traversedMapNameList[#traversedMapNameList] -- 当前段落点所在地图
      if normalizeNodeText(lastTraversedMapName) ~= normalizeNodeText(segment and segment.toName) then
        appendPlanningNode(nodeList, lastTraversedMapName)
      end
      appendPlanningNode(nodeList, segment and segment.toName)
    end
  end

  if #nodeList == 0 then
    return ""
  end
  return table.concat(nodeList, " -> ")
end

--- 构建规划成功后的聊天诊断输出。
---@param routeBar table|nil 路线图模块
---@param routeResult table|nil 路线结果
---@param routeTarget table|nil 路线目标
---@param availabilityContext table|nil 当前角色可用性快照
---@return table
local function buildPlanningDiagnosticMessages(routeBar, routeResult, routeTarget, availabilityContext)
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  if type(segmentList) ~= "table" or #segmentList == 0 then
    return {}
  end

  local startLocationSnapshot = buildStartLocationSnapshot(availabilityContext) -- 规划起点快照
  local firstSegment = segmentList[1] or nil -- 第一段路线
  local finalSegment = segmentList[#segmentList] or nil -- 最后一段路线
  local startText = "" -- 起点调试文本
  local targetText = "" -- 终点调试文本
  local nodeSummaryText = "" -- 节点摘要文本

  if type(routeBar) == "table" and type(routeBar.BuildPositionDisplayText) == "function" then
    startText = routeBar.BuildPositionDisplayText(
      startLocationSnapshot and startLocationSnapshot.currentUiMapID or (firstSegment and firstSegment.fromUiMapID),
      startLocationSnapshot and startLocationSnapshot.currentX,
      startLocationSnapshot and startLocationSnapshot.currentY,
      firstSegment and firstSegment.fromName
    )
    targetText = routeBar.BuildPositionDisplayText(
      routeTarget and routeTarget.uiMapID,
      routeTarget and routeTarget.x,
      routeTarget and routeTarget.y,
      routeTarget and routeTarget.name
    )
  end
  nodeSummaryText = buildPlanningNodeSummaryText(routeBar, routeResult, routeTarget, startLocationSnapshot)

  if startText == "" then
    startText = trimText(firstSegment and firstSegment.fromName) ~= "" and trimText(firstSegment.fromName) or "未知"
  end
  if targetText == "" then
    targetText = trimText(routeTarget and routeTarget.name) ~= "" and trimText(routeTarget.name) or trimText(finalSegment and finalSegment.toName)
    if targetText == "" then
      targetText = "未知"
    end
  end
  if nodeSummaryText == "" then
    if type(routeBar) == "table" and type(routeBar.BuildRouteNodePathText) == "function" then
      nodeSummaryText = trimText(routeBar.BuildRouteNodePathText(routeResult, routeTarget, startLocationSnapshot))
    end
  end
  if nodeSummaryText == "" then
    nodeSummaryText = trimText(type(routeBar) == "table" and type(routeBar.BuildRouteText) == "function" and routeBar.BuildRouteText(routeResult) or "")
    nodeSummaryText = string.gsub(nodeSummaryText, "^%s*%d+步%s*|%s*", "")
    if nodeSummaryText == "" then
      nodeSummaryText = "暂无路线"
    end
  end

  local messageList = {
    string.format(
      "规划成功 | 起点：%s | 终点：%s | 总步数：%d | 节点：%s",
      startText,
      targetText,
      tonumber(routeResult and routeResult.totalSteps) or #segmentList,
      nodeSummaryText
    ),
  } -- 规划成功后的诊断文本列表
  for segmentIndex, segment in ipairs(segmentList) do
    messageList[#messageList + 1] = string.format(
      "第%d段 | mode=%s | from=%s | to=%s | traversedUiMapNames=%s",
      segmentIndex,
      tostring(segment and segment.mode or ""),
      tostring(segment and (segment.fromName or segment.from) or ""),
      tostring(segment and (segment.toName or segment.to) or ""),
      buildTraversedMapNamesText(segment)
    )
  end
  return messageList
end

--- 规划指定世界地图目标，并刷新顶部路线图。
---@param routeTarget table|nil 目标快照，至少包含 uiMapID/x/y
---@return table|nil, table|nil
function WorldMap.PlanRouteToTarget(routeTarget)
  local target = type(routeTarget) == "table" and routeTarget or nil -- 规划目标
  local numericMapID = tonumber(target and target.uiMapID) -- 目标地图 ID
  local targetX = tonumber(target and target.x) -- 目标 X
  local targetY = tonumber(target and target.y) -- 目标 Y
  local routeBar = Toolbox.NavigationModule and Toolbox.NavigationModule.RouteBar or nil -- 顶部路线图模块
  if not numericMapID or not targetX or not targetY then
    if routeBar and type(routeBar.ClearRoute) == "function" then
      routeBar.ClearRoute()
    end
    printNavigationMessage((Toolbox.L or {}).NAVIGATION_ROUTE_NEEDS_WAYPOINT or "请先在世界地图上放置目标标记。")
    return nil, { code = "NAVIGATION_ERR_BAD_TARGET" }
  end

  local moduleDb = getModuleDb() -- navigation 模块存档
  moduleDb.lastTargetUiMapID = numericMapID
  moduleDb.lastTargetX = targetX
  moduleDb.lastTargetY = targetY

  local spellIDList = Toolbox.Navigation.GetRequiredSpellIDList(Toolbox.Data and Toolbox.Data.NavigationRouteEdges) -- 需要确认的统一路线边技能列表
  local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability(spellIDList) -- 当前角色可用性快照
  local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
    uiMapID = numericMapID,
    x = targetX,
    y = targetY,
    name = target.name,
  }, availabilityContext)

  if routeResult and routeBar and type(routeBar.ShowRoute) == "function" then
    routeBar.ShowRoute(routeResult, {
      uiMapID = numericMapID,
      x = targetX,
      y = targetY,
      name = target.name,
    })
    local planningMessageList = buildPlanningDiagnosticMessages(routeBar, routeResult, {
      uiMapID = numericMapID,
      x = targetX,
      y = targetY,
      name = target.name,
    }, availabilityContext) -- 规划成功后的诊断输出
    if #planningMessageList > 0 then
      for _, messageText in ipairs(planningMessageList) do
        printNavigationMessage(messageText)
      end
    elseif type(routeBar.BuildRouteText) == "function" then
      printNavigationMessage(routeBar.BuildRouteText(routeResult))
    end
    return routeResult, nil
  end

  if routeBar and type(routeBar.ClearRoute) == "function" then
    routeBar.ClearRoute()
  end
  local failureMessage = getRouteFailureMessage(errorObject) -- 规划失败提示
  if failureMessage then
    printNavigationMessage(failureMessage)
  end
  return nil, errorObject
end

--- 规划当前用户 waypoint 目标，并刷新顶部路线图。
local function planRouteFromCurrentWaypointTarget()
  local mapID, targetX, targetY = getUserWaypointTarget() -- 当前用户 waypoint
  if not mapID or not targetX or not targetY then
    local routeBar = Toolbox.NavigationModule and Toolbox.NavigationModule.RouteBar or nil -- 顶部路线图模块
    if routeBar and type(routeBar.ClearRoute) == "function" then
      routeBar.ClearRoute()
    end
    printNavigationMessage((Toolbox.L or {}).NAVIGATION_ROUTE_NEEDS_WAYPOINT or "请先在世界地图上放置目标标记。")
    return
  end
  WorldMap.PlanRouteToTarget({
    uiMapID = mapID,
    x = targetX,
    y = targetY,
  })
end

--- 确保世界地图规划按钮已创建。
---@return table|nil
local function ensureTargetButton()
  local worldMapFrame = _G.WorldMapFrame -- 大地图根 Frame
  if not worldMapFrame or type(CreateFrame) ~= "function" then
    return nil
  end
  if targetButton then
    return targetButton
  end

  local parentFrame = worldMapFrame.BorderFrame or worldMapFrame -- 按钮父级
  targetButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
  targetButton:SetSize(96, 24)
  targetButton:SetPoint("TOP", parentFrame, "TOP", 0, -36)
  targetButton:SetText((Toolbox.L or {}).NAVIGATION_WORLD_MAP_BUTTON or "Route")
  targetButton:SetScript("OnClick", planRouteFromCurrentWaypointTarget)
  targetButton:Show()
  return targetButton
end

--- 刷新世界地图入口可见性。
function WorldMap.Refresh()
  local moduleDb = getModuleDb() -- navigation 模块存档
  local button = ensureTargetButton() -- 世界地图规划按钮
  if not button then
    return
  end
  if moduleDb.enabled == false then
    button:Hide()
  else
    local localeTable = Toolbox.L or {} -- 本地化字符串表
    local mapID = getUserWaypointTarget() -- 当前用户 waypoint 地图 ID
    if mapID then
      button:SetText(localeTable.NAVIGATION_WORLD_MAP_BUTTON or "Route")
      if type(button.Enable) == "function" then
        button:Enable()
      else
        button:SetEnabled(true)
      end
    else
      button:SetText(localeTable.NAVIGATION_WORLD_MAP_BUTTON_NEEDS_WAYPOINT or "Set waypoint")
      if type(button.Disable) == "function" then
        button:Disable()
      else
        button:SetEnabled(false)
      end
    end
    button:Show()
  end
end

--- 安装 WorldMapFrame 显示生命周期挂接。
function WorldMap.Install()
  if worldMapHookInstalled then
    return
  end
  local worldMapFrame = _G.WorldMapFrame -- 大地图根 Frame
  if not worldMapFrame or type(worldMapFrame.HookScript) ~= "function" then
    return
  end
  worldMapFrame:HookScript("OnShow", function()
    WorldMap.Refresh()
  end)
  worldMapHookInstalled = true
  if type(worldMapFrame.IsShown) == "function" and worldMapFrame:IsShown() then
    WorldMap.Refresh()
  end
end

--- 隐藏世界地图入口。
function WorldMap.Hide()
  if targetButton then
    targetButton:Hide()
  end
end

--- 获取世界地图规划按钮，供测试使用。
---@return table|nil
function WorldMap.GetTargetButton()
  return targetButton
end
