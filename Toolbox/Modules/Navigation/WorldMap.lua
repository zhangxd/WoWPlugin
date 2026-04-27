--[[
  navigation 世界地图入口：在 WorldMapFrame 显示时创建“规划路线”按钮。
  目标坐标读取当前用户 waypoint；若不存在有效 waypoint 或规划失败，需要给玩家明确反馈。
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

--- 从 Vector2DMixin 或普通表读取归一化坐标。
---@param vectorValue table|nil 地图坐标对象
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
  local targetX, targetY = readVectorXY(pointValue.position) -- waypoint 坐标
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

--- 规划当前用户 waypoint 目标，并刷新顶部路径条。
local function planRouteFromCurrentWaypointTarget()
  local routeBar = Toolbox.NavigationModule and Toolbox.NavigationModule.RouteBar or nil -- 顶部路径条模块
  local mapID, targetX, targetY = getUserWaypointTarget() -- 当前用户 waypoint
  if not mapID or not targetX or not targetY then
    if routeBar and type(routeBar.ClearRoute) == "function" then
      routeBar.ClearRoute()
    end
    printNavigationMessage((Toolbox.L or {}).NAVIGATION_ROUTE_NEEDS_WAYPOINT or "请先在世界地图上放置目标标记。")
    return
  end

  local moduleDb = getModuleDb() -- navigation 模块存档
  moduleDb.lastTargetUiMapID = mapID
  moduleDb.lastTargetX = targetX
  moduleDb.lastTargetY = targetY

  local spellIDList = Toolbox.Navigation.GetRequiredSpellIDList(Toolbox.Data and Toolbox.Data.NavigationRouteEdges) -- 需要确认的统一路线边技能列表
  local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability(spellIDList) -- 当前角色可用性快照
  local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
    uiMapID = mapID,
    x = targetX,
    y = targetY,
  }, availabilityContext)

  if routeResult and routeBar and type(routeBar.ShowRoute) == "function" then
    routeBar.ShowRoute(routeResult)
    return
  end
  if routeBar and type(routeBar.ClearRoute) == "function" then
    routeBar.ClearRoute()
  end
  local failureMessage = getRouteFailureMessage(errorObject) -- 规划失败提示
  if failureMessage then
    printNavigationMessage(failureMessage)
  end
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
