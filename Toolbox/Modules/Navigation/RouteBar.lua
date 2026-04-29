--[[
  navigation 路线图组件：在屏幕顶部显示可折叠的导航胶囊与完整时间线。
  组件只管理 navigation 自己的路线状态、历史记录与轻量实时刷新，不影响其他模块。
]]

Toolbox.NavigationModule = Toolbox.NavigationModule or {}

local RouteBar = {}
Toolbox.NavigationModule.RouteBar = RouteBar

local DEFAULT_WIDGET_WIDTH = 420 -- 路线图默认宽度
local DEFAULT_CAPSULE_HEIGHT = 48 -- 精简胶囊高度
local DEFAULT_EXPANDED_HEIGHT = 312 -- 展开态高度
local DEFAULT_HISTORY_LIMIT = 10 -- 最近历史记录上限
local DEFAULT_REFRESH_INTERVAL = 0.5 -- 实时刷新节流秒数
local DEFAULT_POSITION = {
  point = "TOP",
  x = 0,
  y = -18,
} -- 默认锚点位置
local VALID_POINT_NAME = {
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  CENTER = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
} -- 允许写入存档的锚点名

local routeBarFrame = nil -- 路线图根 Frame
local activeRouteState = nil -- 当前导航路线状态

--- 读取 navigation 模块存档，兼容测试直接注入 Config 的场景。
---@return table
local function getModuleDb()
  if Toolbox.NavigationModule and type(Toolbox.NavigationModule.GetModuleDb) == "function" then
    return Toolbox.NavigationModule.GetModuleDb()
  end
  if Toolbox.Config and type(Toolbox.Config.GetModule) == "function" then
    return Toolbox.Config.GetModule("navigation")
  end
  ToolboxDB = ToolboxDB or {}
  ToolboxDB.modules = ToolboxDB.modules or {}
  ToolboxDB.modules.navigation = ToolboxDB.modules.navigation or {}
  return ToolboxDB.modules.navigation
end

--- 读取一条本地化文案；缺失时返回兜底文本。
---@param key string 文案键
---@param fallbackText string 兜底文本
---@return string
local function getLocaleText(key, fallbackText)
  local localeTable = Toolbox.L or {} -- 本地化字符串表
  local localizedText = localeTable[key] -- 本地化结果
  if type(localizedText) == "string" and localizedText ~= "" then
    return localizedText
  end
  return fallbackText
end

--- 去除首尾空白。
---@param rawText any
---@return string
local function trimText(rawText)
  local trimmedText = tostring(rawText or "") -- 待裁剪文本
  trimmedText = string.gsub(trimmedText, "^%s+", "")
  trimmedText = string.gsub(trimmedText, "%s+$", "")
  return trimmedText
end

--- 归一化导航名称，便于玩家可见文本去重。
---@param rawValue any
---@return string
local function normalizeNavigationName(rawValue)
  local normalizedValue = string.lower(trimText(rawValue)) -- 小写化名称
  normalizedValue = string.gsub(normalizedValue, "%s+", "")
  return normalizedValue
end

--- 判断一组归一化坐标是否有效。
---@param pointX any
---@param pointY any
---@return boolean
local function isNormalizedPosition(pointX, pointY)
  return type(pointX) == "number" and type(pointY) == "number" and pointX >= 0 and pointX <= 1 and pointY >= 0 and pointY <= 1
end

--- 将存档中的锚点位置归一化为可直接使用的结构。
---@param rawPosition table|nil 原始位置存档
---@return table
local function normalizeWidgetPosition(rawPosition)
  local positionTable = type(rawPosition) == "table" and rawPosition or {} -- 原始位置表
  local pointName = tostring(positionTable.point or DEFAULT_POSITION.point) -- 锚点名
  if not VALID_POINT_NAME[pointName] then
    pointName = DEFAULT_POSITION.point
  end
  return {
    point = pointName,
    x = tonumber(positionTable.x) or DEFAULT_POSITION.x,
    y = tonumber(positionTable.y) or DEFAULT_POSITION.y,
  }
end

--- 保证路线图组件相关存档字段形状正确。
---@param moduleDb table navigation 模块存档
---@return table
local function ensureWidgetDbFields(moduleDb)
  moduleDb.routeWidgetExpanded = moduleDb.routeWidgetExpanded == true
  moduleDb.routeWidgetPosition = normalizeWidgetPosition(moduleDb.routeWidgetPosition)
  if type(moduleDb.routeHistory) ~= "table" then
    moduleDb.routeHistory = {}
  end
  return moduleDb
end

--- 清理边标签里导出用的后缀节点补充，仅保留玩家需要执行的动作。
---@param rawLabel any
---@return string
local function cleanPlayerFacingLabel(rawLabel)
  local cleanedLabel = trimText(rawLabel) -- 原始显示标签
  if cleanedLabel == "" then
    return ""
  end

  local splitMarkers = {
    "→",
    "â",
  } -- 导出时可能拼入的箭头补充
  local firstSplitIndex = nil -- 最早箭头位置
  for _, marker in ipairs(splitMarkers) do
    local markerIndex = string.find(cleanedLabel, marker, 1, true) -- 箭头位置
    if markerIndex and (not firstSplitIndex or markerIndex < firstSplitIndex) then
      firstSplitIndex = markerIndex
    end
  end
  if firstSplitIndex then
    cleanedLabel = trimText(string.sub(cleanedLabel, 1, firstSplitIndex - 1))
  end
  return cleanedLabel
end

--- 生成路线段的玩家可见主文案。
---@param segment table|nil 路线段
---@return string
local function buildPrimarySegmentText(segment)
  if type(segment) ~= "table" then
    return ""
  end

  local modeText = tostring(segment.mode or "unknown") -- 路线方式
  local fromName = tostring(segment.fromName or segment.from or "?") -- 起点显示名
  local toName = tostring(segment.toName or segment.to or "?") -- 终点显示名
  if modeText == "walk_local" then
    return string.format("步行：%s -> %s", fromName, toName)
  end
  if modeText == "hearthstone" then
    return string.format("炉石：%s", toName)
  end

  local cleanedLabel = cleanPlayerFacingLabel(segment.label) -- 统一动作标签
  if cleanedLabel ~= "" then
    return cleanedLabel
  end
  return string.format("%s: %s -> %s", modeText, fromName, toName)
end

--- 构建路线段需要展示的“经过地图”文本。
---@param segment table|nil 路线段
---@return string
local function buildTraversedNameText(segment)
  if type(segment) ~= "table" then
    return ""
  end
  if tostring(segment.mode or "") == "walk_local" then
    return ""
  end

  local fromName = normalizeNavigationName(segment.fromName or segment.from) -- 起点归一化名称
  local toName = normalizeNavigationName(segment.toName or segment.to) -- 终点归一化名称
  local traversedNameList = {} -- 经过地图显示名
  local seenName = {} -- 已写入地图名
  for _, traversedName in ipairs(type(segment.traversedUiMapNames) == "table" and segment.traversedUiMapNames or {}) do
    local displayName = trimText(traversedName) -- 当前经过地图名
    local normalizedName = normalizeNavigationName(displayName) -- 当前地图归一化名
    if displayName ~= "" and normalizedName ~= "" and normalizedName ~= fromName and normalizedName ~= toName and not seenName[normalizedName] then
      seenName[normalizedName] = true
      traversedNameList[#traversedNameList + 1] = displayName
    end
  end
  if #traversedNameList == 0 then
    return ""
  end
  return string.format("（途经：%s）", table.concat(traversedNameList, "、"))
end

--- 生成单段路线文本。
---@param segment table|nil 路线段
---@return string
local function buildSegmentText(segment)
  if type(segment) ~= "table" then
    return ""
  end
  local primaryText = buildPrimarySegmentText(segment) -- 玩家可见主文案
  local traversedNameText = buildTraversedNameText(segment) -- 经过地图名串
  if primaryText == "" then
    return ""
  end
  if traversedNameText ~= "" then
    return primaryText .. traversedNameText
  end
  return primaryText
end

--- 拼接路线步骤文本。
---@param routeResult table|nil 路线结果
---@return string
local function buildRouteText(routeResult)
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  if type(segmentList) ~= "table" or #segmentList == 0 then
    return getLocaleText("NAVIGATION_ROUTE_EMPTY", "暂无路线")
  end
  local textParts = {
    string.format("%s步", tostring(tonumber(routeResult.totalSteps) or #segmentList)),
  } -- 可显示步骤文本
  for _, segment in ipairs(segmentList) do
    local segmentText = buildSegmentText(segment) -- 路线段文本
    if segmentText ~= "" then
      textParts[#textParts + 1] = segmentText
    end
  end
  return table.concat(textParts, "  |  ")
end

--- 将目标快照编码为去重签名。
---@param routeTarget table|nil 路线目标
---@return string
local function buildHistorySignature(routeTarget)
  local numericMapID = tonumber(type(routeTarget) == "table" and routeTarget.uiMapID) or 0 -- 目标地图 ID
  local targetX = tonumber(type(routeTarget) == "table" and routeTarget.x) or 0 -- 目标 X
  local targetY = tonumber(type(routeTarget) == "table" and routeTarget.y) or 0 -- 目标 Y
  return string.format("%d:%.4f:%.4f", numericMapID, targetX, targetY)
end

--- 生成路线目标显示名。
---@param routeTarget table|nil 路线目标
---@param routeResult table|nil 路线结果
---@return string
local function buildTargetDisplayName(routeTarget, routeResult)
  local targetName = trimText(type(routeTarget) == "table" and routeTarget.name or nil) -- 外部传入的终点名
  if targetName ~= "" then
    return targetName
  end
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  local lastSegment = type(segmentList) == "table" and segmentList[#segmentList] or nil -- 最后一段
  local lastName = trimText(lastSegment and lastSegment.toName) -- 路线最后终点名
  if lastName ~= "" then
    return lastName
  end
  return "目标点"
end

--- 将当前路线记录进最近历史；同目标重新规划时移动到最前面。
---@param routeTarget table|nil 路线目标
---@param routeResult table|nil 路线结果
local function pushRouteHistory(routeTarget, routeResult)
  local numericMapID = tonumber(type(routeTarget) == "table" and routeTarget.uiMapID) -- 目标地图 ID
  if not numericMapID or numericMapID <= 0 then
    return
  end

  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local routeHistory = moduleDb.routeHistory -- 最近路线历史
  local historySignature = buildHistorySignature(routeTarget) -- 当前目标签名
  for historyIndex = #routeHistory, 1, -1 do
    local entry = routeHistory[historyIndex] -- 旧历史项
    local entrySignature = buildHistorySignature({
      uiMapID = entry and entry.targetUiMapID,
      x = entry and entry.targetX,
      y = entry and entry.targetY,
    }) -- 历史项签名
    if entrySignature == historySignature then
      table.remove(routeHistory, historyIndex)
    end
  end

  table.insert(routeHistory, 1, {
    targetUiMapID = numericMapID,
    targetX = tonumber(type(routeTarget) == "table" and routeTarget.x) or 0,
    targetY = tonumber(type(routeTarget) == "table" and routeTarget.y) or 0,
    targetName = buildTargetDisplayName(routeTarget, routeResult),
    summaryText = RouteBar.BuildRouteText(routeResult),
  })

  while #routeHistory > DEFAULT_HISTORY_LIMIT do
    table.remove(routeHistory)
  end
end

--- 将根 Frame 锚定到当前存档位置。
---@param frame table 路线图根 Frame
local function applyWidgetPosition(frame)
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local widgetPosition = normalizeWidgetPosition(moduleDb.routeWidgetPosition) -- 当前路线图位置
  moduleDb.routeWidgetPosition = widgetPosition
  frame:ClearAllPoints()
  frame:SetPoint(widgetPosition.point, UIParent, widgetPosition.point, widgetPosition.x, widgetPosition.y)
end

--- 根据当前位置与路线段，判断是否命中某一段的经过地图集合。
---@param segment table|nil 路线段
---@param currentUiMapID number 当前地图 ID
---@return boolean
local function isSegmentMatchedByTraversedMap(segment, currentUiMapID)
  for _, traversedMapID in ipairs(type(segment) == "table" and type(segment.traversedUiMapIDs) == "table" and segment.traversedUiMapIDs or {}) do
    if tonumber(traversedMapID) == currentUiMapID then
      return true
    end
  end
  return false
end

--- 基于当前位置推导当前步骤、到达状态与偏离状态。
---@param routeResult table|nil 路线结果
---@param routeTarget table|nil 路线目标
---@param locationSnapshot table|nil 当前位置快照
---@return number, boolean, boolean
local function resolveLiveProgress(routeResult, routeTarget, locationSnapshot)
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  local totalSteps = type(segmentList) == "table" and #segmentList or 0 -- 路线总段数
  if totalSteps == 0 then
    return 0, false, false
  end

  local currentUiMapID = tonumber(type(locationSnapshot) == "table" and locationSnapshot.currentUiMapID) -- 当前地图 ID
  local targetUiMapID = tonumber(type(routeTarget) == "table" and routeTarget.uiMapID) -- 目标地图 ID
  local currentX = tonumber(type(locationSnapshot) == "table" and locationSnapshot.currentX) -- 当前 X
  local currentY = tonumber(type(locationSnapshot) == "table" and locationSnapshot.currentY) -- 当前 Y
  local targetX = tonumber(type(routeTarget) == "table" and routeTarget.x) -- 目标 X
  local targetY = tonumber(type(routeTarget) == "table" and routeTarget.y) -- 目标 Y

  if currentUiMapID and targetUiMapID and currentUiMapID == targetUiMapID then
    if isNormalizedPosition(currentX, currentY) and isNormalizedPosition(targetX, targetY) then
      local deltaX = currentX - targetX -- 目标 X 偏差
      local deltaY = currentY - targetY -- 目标 Y 偏差
      local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY) -- 当前点与终点的距离
      if distance <= 0.04 then
        return totalSteps, true, false
      end
    else
      return totalSteps, true, false
    end
  end

  if not currentUiMapID then
    return 1, false, false
  end

  for segmentIndex, segment in ipairs(segmentList) do
    local fromUiMapID = tonumber(segment and segment.fromUiMapID) -- 当前段起点地图
    local toUiMapID = tonumber(segment and segment.toUiMapID) -- 当前段终点地图
    local nextSegment = segmentList[segmentIndex + 1] -- 下一段
    local nextFromUiMapID = tonumber(nextSegment and nextSegment.fromUiMapID) -- 下一段起点地图

    if fromUiMapID and currentUiMapID == fromUiMapID then
      return segmentIndex, false, false
    end
    if toUiMapID and currentUiMapID == toUiMapID then
      if nextFromUiMapID and nextFromUiMapID == currentUiMapID then
        return segmentIndex + 1, false, false
      end
      return segmentIndex, false, false
    end
    if isSegmentMatchedByTraversedMap(segment, currentUiMapID) then
      return segmentIndex, false, false
    end
  end

  return 1, false, true
end

--- 构建胶囊状态文案。
---@param routeState table 路线状态
---@return string
local function buildStatusText(routeState)
  if routeState.arrived then
    return getLocaleText("NAVIGATION_ROUTE_WIDGET_STATUS_ARRIVED", "已到达终点")
  end
  if routeState.deviated then
    return getLocaleText("NAVIGATION_ROUTE_WIDGET_STATUS_DEVIATED", "你已偏离路线")
  end
  return getLocaleText("NAVIGATION_ROUTE_WIDGET_STATUS_READY", "按当前路线前进")
end

--- 刷新精简胶囊文案。
---@param frame table 路线图根 Frame
---@param routeState table 路线状态
local function refreshCapsuleText(frame, routeState)
  local segmentList = type(routeState.routeResult) == "table" and routeState.routeResult.segments or {} -- 路线分段列表
  local totalSteps = tonumber(routeState.routeResult and routeState.routeResult.totalSteps) or #segmentList -- 总步数
  local stepIndex = math.max(1, math.min(tonumber(routeState.currentStepIndex) or 1, math.max(totalSteps, 1))) -- 当前步骤索引
  local currentSegment = segmentList[stepIndex] or segmentList[1] or nil -- 当前高亮段
  local stepLabel = string.format(getLocaleText("NAVIGATION_ROUTE_WIDGET_STEP_FMT", "第%d/%d步"), stepIndex, math.max(totalSteps, 1)) -- 胶囊步骤文案
  local summaryText = buildSegmentText(currentSegment) -- 当前步骤摘要
  if summaryText == "" then
    summaryText = buildTargetDisplayName(routeState.routeTarget, routeState.routeResult)
  end
  frame._capsuleSummary:SetText(stepLabel .. "  |  " .. summaryText)
  frame._capsuleStatus:SetText(buildStatusText(routeState))
end

--- 刷新展开态时间线文案。
---@param frame table 路线图根 Frame
---@param routeState table 路线状态
---@param locationSnapshot table|nil 当前位置快照
local function refreshTimelineText(frame, routeState, locationSnapshot)
  local segmentList = type(routeState.routeResult) == "table" and routeState.routeResult.segments or {} -- 路线分段列表
  local totalSteps = #segmentList -- 路线段数
  local currentSegment = segmentList[routeState.currentStepIndex] or segmentList[1] or nil -- 当前高亮段
  local firstSegment = segmentList[1] or nil -- 第一段
  local startName = trimText(firstSegment and firstSegment.fromName) -- 起始位置名
  local targetName = buildTargetDisplayName(routeState.routeTarget, routeState.routeResult) -- 目标位置名
  local currentPositionText = targetName -- 当前所处位置文案
  if routeState.deviated then
    currentPositionText = string.format("UiMap %s", tostring(tonumber(locationSnapshot and locationSnapshot.currentUiMapID) or "?"))
  elseif routeState.arrived then
    currentPositionText = targetName
  elseif trimText(currentSegment and currentSegment.fromName) ~= "" then
    currentPositionText = trimText(currentSegment.fromName)
  end

  local lineList = {
    string.format(getLocaleText("NAVIGATION_ROUTE_WIDGET_HEADER_FMT", "%s -> %s"), startName ~= "" and startName or "当前位置", targetName),
    string.format("%s：%s", getLocaleText("NAVIGATION_ROUTE_WIDGET_START", "起始位置"), startName ~= "" and startName or "当前位置"),
    string.format("%s：%s", getLocaleText("NAVIGATION_ROUTE_WIDGET_NEXT", "下一步"), buildSegmentText(currentSegment)),
    string.format("%s：%s", getLocaleText("NAVIGATION_ROUTE_WIDGET_END", "终点位置"), targetName),
    string.format("%s：%s", getLocaleText("NAVIGATION_ROUTE_WIDGET_CURRENT", "当前位置"), currentPositionText),
    string.format("%s：%s", getLocaleText("NAVIGATION_ROUTE_WIDGET_STATUS_LABEL", "路线状态"), buildStatusText(routeState)),
    getLocaleText("NAVIGATION_ROUTE_WIDGET_CHAIN", "路线链路") .. "：",
  } -- 展开态时间线文本

  for segmentIndex, segment in ipairs(segmentList) do
    local prefixText = "[ ]" -- 时间线状态前缀
    if routeState.arrived and segmentIndex == totalSteps then
      prefixText = "[完成]"
    elseif routeState.deviated and segmentIndex == routeState.currentStepIndex then
      prefixText = "[偏离]"
    elseif segmentIndex == routeState.currentStepIndex then
      prefixText = "[当前]"
    end
    lineList[#lineList + 1] = string.format("%s %d. %s", prefixText, segmentIndex, buildSegmentText(segment))
  end

  frame._timelineText:SetText(table.concat(lineList, "\n"))
end

--- 刷新历史记录按钮区。
---@param frame table 路线图根 Frame
local function refreshHistoryButtons(frame)
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local routeHistory = moduleDb.routeHistory -- 最近路线历史
  local hasHistory = false -- 是否存在可显示历史

  frame._historyTitle:SetText(getLocaleText("NAVIGATION_ROUTE_WIDGET_HISTORY_TITLE", "最近路线"))
  for historyIndex, buttonFrame in ipairs(frame._historyButtons) do
    local entry = routeHistory[historyIndex] -- 当前历史项
    if type(entry) == "table" then
      local buttonText = trimText(entry.targetName) -- 按钮目标名
      if buttonText == "" then
        buttonText = trimText(entry.summaryText)
      end
      if buttonText == "" then
        buttonText = string.format("UiMap %s", tostring(entry.targetUiMapID or "?"))
      end
      buttonFrame._historyIndex = historyIndex
      buttonFrame:SetText(string.format("%d. %s", historyIndex, buttonText))
      buttonFrame:Show()
      hasHistory = true
    else
      buttonFrame._historyIndex = nil
      buttonFrame:SetText("")
      buttonFrame:Hide()
    end
  end

  if hasHistory then
    frame._historyEmptyText:Hide()
  else
    frame._historyEmptyText:SetText(getLocaleText("NAVIGATION_ROUTE_WIDGET_HISTORY_EMPTY", "暂无历史路线"))
    frame._historyEmptyText:Show()
  end
end

--- 应用展开 / 收起状态到当前路线图。
---@param frame table 路线图根 Frame
---@param isExpanded boolean 是否展开
local function applyExpandedState(frame, isExpanded)
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local shouldExpand = isExpanded == true -- 当前是否展开
  moduleDb.routeWidgetExpanded = shouldExpand

  if shouldExpand then
    frame:SetSize(DEFAULT_WIDGET_WIDTH, DEFAULT_EXPANDED_HEIGHT)
    frame._expandedContent:Show()
  else
    frame:SetSize(DEFAULT_WIDGET_WIDTH, DEFAULT_CAPSULE_HEIGHT)
    frame._expandedContent:Hide()
  end
end

--- 刷新整个路线图组件。
---@param locationSnapshot table|nil 当前位置快照
local function refreshRouteBar(locationSnapshot)
  if not routeBarFrame or not activeRouteState then
    return
  end
  refreshCapsuleText(routeBarFrame, activeRouteState)
  refreshTimelineText(routeBarFrame, activeRouteState, locationSnapshot)
  refreshHistoryButtons(routeBarFrame)
  applyExpandedState(routeBarFrame, ensureWidgetDbFields(getModuleDb()).routeWidgetExpanded)
end

--- 根据当前光标位置更新拖动中的路线图位置。
local function updateDragPosition()
  if not routeBarFrame or type(routeBarFrame._dragState) ~= "table" then
    return
  end
  if type(GetCursorPosition) ~= "function" then
    return
  end
  local dragState = routeBarFrame._dragState -- 当前拖动状态
  local cursorX, cursorY = GetCursorPosition() -- 当前光标位置
  local deltaX = tonumber(cursorX) - tonumber(dragState.startCursorX or 0) -- 光标 X 位移
  local deltaY = tonumber(cursorY) - tonumber(dragState.startCursorY or 0) -- 光标 Y 位移
  if not deltaX or not deltaY then
    return
  end

  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  moduleDb.routeWidgetPosition = {
    point = dragState.point,
    x = tonumber(dragState.startX or 0) + deltaX,
    y = tonumber(dragState.startY or 0) + deltaY,
  }
  dragState.didMove = math.abs(deltaX) > 0 or math.abs(deltaY) > 0
  applyWidgetPosition(routeBarFrame)
end

--- 开始拖动路线图组件。
local function startWidgetDrag()
  if not routeBarFrame or type(GetCursorPosition) ~= "function" then
    return
  end
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local widgetPosition = moduleDb.routeWidgetPosition -- 当前组件位置
  local cursorX, cursorY = GetCursorPosition() -- 当前光标位置
  routeBarFrame._dragState = {
    point = widgetPosition.point,
    startX = widgetPosition.x,
    startY = widgetPosition.y,
    startCursorX = tonumber(cursorX) or 0,
    startCursorY = tonumber(cursorY) or 0,
    didMove = false,
  }
end

--- 结束拖动路线图组件。
local function stopWidgetDrag()
  if not routeBarFrame then
    return
  end
  updateDragPosition()
  local dragState = routeBarFrame._dragState -- 当前拖动状态
  routeBarFrame._dragState = nil
  if type(dragState) == "table" and dragState.didMove then
    routeBarFrame._suppressNextClick = true
  end
end

--- 创建最近历史按钮。
---@param parentFrame table 父容器
---@param historyIndex number 历史序号
---@return table
local function createHistoryButton(parentFrame, historyIndex)
  local buttonFrame = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate") -- 历史路线按钮
  buttonFrame:SetSize(DEFAULT_WIDGET_WIDTH - 36, 18)
  buttonFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 12, -210 - ((historyIndex - 1) * 20))
  buttonFrame:SetText("")
  buttonFrame:Hide()
  buttonFrame:SetScript("OnClick", function(self)
    if type(self._historyIndex) == "number" then
      RouteBar.TriggerHistoryEntry(self._historyIndex)
    end
  end)
  return buttonFrame
end

--- 确保路线图根 Frame 已创建。
---@return table|nil
local function ensureRouteBarFrame()
  if routeBarFrame then
    return routeBarFrame
  end
  if not UIParent or type(CreateFrame) ~= "function" then
    return nil
  end

  routeBarFrame = CreateFrame("Frame", "ToolboxNavigationRouteBar", UIParent, "BackdropTemplate")
  routeBarFrame:SetSize(DEFAULT_WIDGET_WIDTH, DEFAULT_CAPSULE_HEIGHT)
  routeBarFrame:SetFrameStrata("DIALOG")
  routeBarFrame:EnableMouse(true)
  routeBarFrame:Hide()
  routeBarFrame:SetScript("OnUpdate", function(self, elapsed)
    if type(self._dragState) == "table" then
      updateDragPosition()
    end
    if not activeRouteState then
      return
    end
    self._elapsedSeconds = tonumber(self._elapsedSeconds) or 0
    self._elapsedSeconds = self._elapsedSeconds + (tonumber(elapsed) or 0)
    if self._elapsedSeconds < DEFAULT_REFRESH_INTERVAL then
      return
    end
    self._elapsedSeconds = 0
    RouteBar.RefreshLiveState()
  end)
  applyWidgetPosition(routeBarFrame)

  if type(routeBarFrame.SetBackdrop) == "function" then
    routeBarFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    routeBarFrame:SetBackdropColor(0, 0, 0, 0.85)
    routeBarFrame:SetBackdropBorderColor(0.78, 0.64, 0.31, 0.9)
  end

  local capsuleButton = CreateFrame("Button", nil, routeBarFrame, "BackdropTemplate") -- 可点击精简胶囊
  capsuleButton:SetPoint("TOPLEFT", routeBarFrame, "TOPLEFT", 0, 0)
  capsuleButton:SetPoint("TOPRIGHT", routeBarFrame, "TOPRIGHT", 0, 0)
  capsuleButton:SetHeight(DEFAULT_CAPSULE_HEIGHT)
  capsuleButton:EnableMouse(true)
  capsuleButton:RegisterForClicks("LeftButtonUp")
  capsuleButton:RegisterForDrag("LeftButton")
  capsuleButton:SetScript("OnClick", function()
    if routeBarFrame._suppressNextClick then
      routeBarFrame._suppressNextClick = false
      return
    end
    RouteBar.ToggleExpanded()
  end)
  capsuleButton:SetScript("OnDragStart", startWidgetDrag)
  capsuleButton:SetScript("OnDragStop", stopWidgetDrag)
  routeBarFrame._capsuleButton = capsuleButton

  local capsuleSummary = capsuleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- 胶囊主摘要
  capsuleSummary:SetPoint("TOPLEFT", capsuleButton, "TOPLEFT", 12, -8)
  capsuleSummary:SetPoint("TOPRIGHT", capsuleButton, "TOPRIGHT", -12, -8)
  capsuleSummary:SetJustifyH("LEFT")
  capsuleSummary:SetWordWrap(false)
  capsuleSummary:SetText("")
  routeBarFrame._capsuleSummary = capsuleSummary

  local capsuleStatus = capsuleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 胶囊状态摘要
  capsuleStatus:SetPoint("TOPLEFT", capsuleSummary, "BOTTOMLEFT", 0, -6)
  capsuleStatus:SetPoint("TOPRIGHT", capsuleSummary, "BOTTOMRIGHT", 0, -6)
  capsuleStatus:SetJustifyH("LEFT")
  capsuleStatus:SetWordWrap(false)
  capsuleStatus:SetText("")
  routeBarFrame._capsuleStatus = capsuleStatus

  local expandedContent = CreateFrame("Frame", nil, routeBarFrame, "BackdropTemplate") -- 展开态内容容器
  expandedContent:SetPoint("TOPLEFT", capsuleButton, "BOTTOMLEFT", 0, -4)
  expandedContent:SetPoint("TOPRIGHT", capsuleButton, "BOTTOMRIGHT", 0, -4)
  expandedContent:SetHeight(DEFAULT_EXPANDED_HEIGHT - DEFAULT_CAPSULE_HEIGHT - 4)
  expandedContent:Hide()
  routeBarFrame._expandedContent = expandedContent

  local timelineText = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 时间线文本
  timelineText:SetPoint("TOPLEFT", expandedContent, "TOPLEFT", 12, -12)
  timelineText:SetPoint("TOPRIGHT", expandedContent, "TOPRIGHT", -12, -12)
  timelineText:SetJustifyH("LEFT")
  timelineText:SetJustifyV("TOP")
  timelineText:SetWordWrap(true)
  timelineText:SetText("")
  routeBarFrame._timelineText = timelineText

  local historyTitle = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- 历史标题
  historyTitle:SetPoint("TOPLEFT", expandedContent, "TOPLEFT", 12, -190)
  historyTitle:SetJustifyH("LEFT")
  historyTitle:SetText("")
  routeBarFrame._historyTitle = historyTitle

  local historyEmptyText = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 空历史提示
  historyEmptyText:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", 0, -8)
  historyEmptyText:SetPoint("TOPRIGHT", expandedContent, "TOPRIGHT", -12, -8)
  historyEmptyText:SetJustifyH("LEFT")
  historyEmptyText:SetWordWrap(true)
  historyEmptyText:SetText("")
  routeBarFrame._historyEmptyText = historyEmptyText

  routeBarFrame._historyButtons = {}
  for historyIndex = 1, DEFAULT_HISTORY_LIMIT do
    routeBarFrame._historyButtons[historyIndex] = createHistoryButton(expandedContent, historyIndex)
  end

  refreshHistoryButtons(routeBarFrame)
  applyExpandedState(routeBarFrame, ensureWidgetDbFields(getModuleDb()).routeWidgetExpanded)
  return routeBarFrame
end

--- 构建可显示的路线摘要文本。
---@param routeResult table|nil 路线结果
---@return string
function RouteBar.BuildRouteText(routeResult)
  return buildRouteText(routeResult)
end

--- 切换展开 / 收起状态。
function RouteBar.ToggleExpanded()
  local frame = ensureRouteBarFrame() -- 路线图根 Frame
  if not frame then
    return
  end
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  applyExpandedState(frame, moduleDb.routeWidgetExpanded ~= true)
end

--- 触发一条历史记录的重规划。
---@param historyIndex number 历史序号（1 为最近一次）
function RouteBar.TriggerHistoryEntry(historyIndex)
  local moduleDb = ensureWidgetDbFields(getModuleDb()) -- navigation 模块存档
  local historyEntry = type(moduleDb.routeHistory) == "table" and moduleDb.routeHistory[historyIndex] or nil -- 历史记录项
  local worldMap = Toolbox.NavigationModule and Toolbox.NavigationModule.WorldMap or nil -- 世界地图入口模块
  if type(historyEntry) ~= "table" or type(worldMap) ~= "table" or type(worldMap.PlanRouteToTarget) ~= "function" then
    return
  end

  worldMap.PlanRouteToTarget({
    uiMapID = tonumber(historyEntry.targetUiMapID) or 0,
    x = tonumber(historyEntry.targetX) or 0,
    y = tonumber(historyEntry.targetY) or 0,
    name = trimText(historyEntry.targetName),
  })
end

--- 显示并刷新当前路线。
---@param routeResult table|nil 路线结果
---@param routeTarget table|nil 路线目标快照
function RouteBar.ShowRoute(routeResult, routeTarget)
  local frame = ensureRouteBarFrame() -- 路线图根 Frame
  local segmentList = type(routeResult) == "table" and routeResult.segments or nil -- 路线分段列表
  if not frame or type(segmentList) ~= "table" or #segmentList == 0 then
    return
  end

  activeRouteState = {
    routeResult = routeResult,
    routeTarget = routeTarget or {},
    currentStepIndex = 1,
    deviated = false,
    arrived = false,
  }
  ensureWidgetDbFields(getModuleDb())
  applyWidgetPosition(frame)
  pushRouteHistory(routeTarget, routeResult)
  frame._elapsedSeconds = 0
  frame:Show()
  RouteBar.RefreshLiveState()
end

--- 根据当前角色位置刷新路线图状态。
function RouteBar.RefreshLiveState()
  if not activeRouteState then
    return
  end
  local locationSnapshot = nil -- 当前角色位置快照
  if Toolbox.Navigation and type(Toolbox.Navigation.GetCurrentLocationSnapshot) == "function" then
    locationSnapshot = Toolbox.Navigation.GetCurrentLocationSnapshot()
  end
  local stepIndex, arrived, deviated = resolveLiveProgress(activeRouteState.routeResult, activeRouteState.routeTarget, locationSnapshot) -- 当前步骤状态
  activeRouteState.currentStepIndex = stepIndex
  activeRouteState.arrived = arrived
  activeRouteState.deviated = deviated
  refreshRouteBar(locationSnapshot)
end

--- 清除并隐藏当前路线。
function RouteBar.ClearRoute()
  activeRouteState = nil
  if routeBarFrame then
    routeBarFrame._elapsedSeconds = 0
    routeBarFrame._dragState = nil
    routeBarFrame._suppressNextClick = false
    if routeBarFrame._capsuleSummary then
      routeBarFrame._capsuleSummary:SetText("")
    end
    if routeBarFrame._capsuleStatus then
      routeBarFrame._capsuleStatus:SetText("")
    end
    if routeBarFrame._timelineText then
      routeBarFrame._timelineText:SetText("")
    end
    routeBarFrame:Hide()
  end
end

--- 获取当前路径图 Frame，供测试或模块内部刷新使用。
---@return table|nil
function RouteBar.GetFrame()
  return routeBarFrame
end
