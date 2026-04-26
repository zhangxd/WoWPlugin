--[[
  navigation 世界地图入口：在 WorldMapFrame 显示时创建“规划路线”按钮。
  目标坐标读取沿用 WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()；按钮点击时才取值。
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

--- 读取当前世界地图显示的 UiMapID。
---@return number|nil
local function getWorldMapID()
  local worldMapFrame = _G.WorldMapFrame -- 大地图根 Frame
  if not worldMapFrame or type(worldMapFrame.GetMapID) ~= "function" then
    return nil
  end
  local success, mapID = pcall(worldMapFrame.GetMapID, worldMapFrame) -- 地图 ID 查询结果
  if not success or type(mapID) ~= "number" or mapID <= 0 then
    return nil
  end
  return mapID
end

--- 读取当前鼠标在世界地图上的归一化坐标。
---@return number|nil, number|nil
local function getWorldMapMousePosition()
  local worldMapFrame = _G.WorldMapFrame -- 大地图根 Frame
  local scrollContainer = worldMapFrame and worldMapFrame.ScrollContainer or nil -- 地图滚动容器
  if not scrollContainer or type(scrollContainer.GetNormalizedCursorPosition) ~= "function" then
    return nil, nil
  end
  local success, x, y = pcall(scrollContainer.GetNormalizedCursorPosition, scrollContainer) -- 鼠标坐标查询结果
  if not success or type(x) ~= "number" or type(y) ~= "number" then
    return nil, nil
  end
  if x < 0 or x > 1 or y < 0 or y > 1 then
    return nil, nil
  end
  return x, y
end

--- 规划当前鼠标所指地图目标，并刷新顶部路径条。
local function planRouteFromCurrentMouseTarget()
  local mapID = getWorldMapID() -- 当前地图 ID
  local targetX, targetY = getWorldMapMousePosition() -- 当前鼠标坐标
  if not mapID or not targetX or not targetY then
    return
  end

  local moduleDb = getModuleDb() -- navigation 模块存档
  moduleDb.lastTargetUiMapID = mapID
  moduleDb.lastTargetX = targetX
  moduleDb.lastTargetY = targetY

  local spellIDList = Toolbox.Navigation.GetRequiredSpellIDList() -- 需要确认的路径技能列表
  local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability(spellIDList) -- 当前角色可用性快照
  local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
    uiMapID = mapID,
    x = targetX,
    y = targetY,
  }, availabilityContext)

  local routeBar = Toolbox.NavigationModule and Toolbox.NavigationModule.RouteBar or nil -- 顶部路径条模块
  if routeResult and routeBar and type(routeBar.ShowRoute) == "function" then
    routeBar.ShowRoute(routeResult)
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
  targetButton:SetScript("OnClick", planRouteFromCurrentMouseTarget)
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
    button:SetText((Toolbox.L or {}).NAVIGATION_WORLD_MAP_BUTTON or "Route")
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
