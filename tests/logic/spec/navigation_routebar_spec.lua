local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")

describe("Navigation RouteBar", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalUIParent = nil -- 原始 UIParent 全局
  local originalGetCursorPosition = nil -- 原始光标位置函数
  local createdFrameByName = nil -- 已创建命名 Frame
  local moduleDb = nil -- navigation 模块存档
  local cursorX = 0 -- 当前测试光标 X
  local cursorY = 0 -- 当前测试光标 Y
  local locationSnapshot = nil -- 当前角色位置快照
  local replannedTargetList = nil -- 历史记录重规划目标

  local function buildSampleRouteResult()
    return {
      totalSteps = 2,
      segments = {
        {
          mode = "class_teleport",
          label = "传送：奥格瑞玛",
          fromName = "当前位置",
          toName = "奥格瑞玛",
          fromUiMapID = 1,
          toUiMapID = 85,
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          mode = "walk_local",
          label = "步行：奥格瑞玛 -> 北风苔原目标点",
          fromName = "奥格瑞玛",
          toName = "北风苔原目标点",
          fromUiMapID = 85,
          toUiMapID = 114,
          traversedUiMapIDs = { 114 },
          traversedUiMapNames = { "北风苔原" },
        },
      },
    }
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalUIParent = rawget(_G, "UIParent")
    originalGetCursorPosition = rawget(_G, "GetCursorPosition")
    createdFrameByName = {}
    moduleDb = {
      enabled = true,
      debug = false,
      routeWidgetExpanded = false,
      routeWidgetPosition = {
        point = "TOP",
        x = 0,
        y = -18,
      },
      routeHistory = {},
    }
    cursorX = 0
    cursorY = 0
    locationSnapshot = nil
    replannedTargetList = {}

    rawset(_G, "UIParent", FakeFrame.new({ frameType = "Frame", frameName = "UIParent" }))
    rawset(_G, "CreateFrame", function(frameType, frameName, parentFrame, templateName)
      local frameObject = FakeFrame.new({
        frameType = frameType,
        frameName = frameName,
        parentFrame = parentFrame,
        templateName = templateName,
      }) -- 测试 Frame
      if type(frameName) == "string" and frameName ~= "" then
        createdFrameByName[frameName] = frameObject
        rawset(_G, frameName, frameObject)
      end
      return frameObject
    end)
    rawset(_G, "GetCursorPosition", function()
      return cursorX, cursorY
    end)
    rawset(_G, "Toolbox", {
      Config = {
        GetModule = function(moduleId)
          assert.equals("navigation", moduleId)
          return moduleDb
        end,
      },
      Navigation = {
        GetCurrentLocationSnapshot = function()
          return locationSnapshot
        end,
      },
      NavigationModule = {
        WorldMap = {
          PlanRouteToTarget = function(target)
            replannedTargetList[#replannedTargetList + 1] = target
          end,
        },
      },
      Data = {
        NavigationMapNodes = {
          nodes = {
            [85] = { Name_lang = "奥格瑞玛" },
            [114] = { Name_lang = "北风苔原" },
          },
        },
      },
      L = {
        NAVIGATION_ROUTE_EMPTY = "暂无路线",
        NAVIGATION_ROUTE_WIDGET_STEP_FMT = "第%d/%d步",
        NAVIGATION_ROUTE_WIDGET_STATUS_READY = "按当前路线前进",
        NAVIGATION_ROUTE_WIDGET_STATUS_DEVIATED = "你已偏离路线",
        NAVIGATION_ROUTE_WIDGET_STATUS_ARRIVED = "已到达终点",
        NAVIGATION_ROUTE_WIDGET_HEADER_FMT = "%s -> %s",
        NAVIGATION_ROUTE_WIDGET_HISTORY_TITLE = "最近路线",
        NAVIGATION_ROUTE_WIDGET_HISTORY_EMPTY = "暂无历史路线",
        NAVIGATION_ROUTE_WIDGET_REPLAN = "重规划",
      },
    })

    local routeBarChunk = assert(loadfile("Toolbox/Modules/Navigation/RouteBar.lua")) -- 路径条 chunk
    routeBarChunk()
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "CreateFrame", originalCreateFrame)
    rawset(_G, "UIParent", originalUIParent)
    rawset(_G, "GetCursorPosition", originalGetCursorPosition)
    rawset(_G, "ToolboxNavigationRouteBar", nil)
  end)

  it("shows_a_compact_capsule_by_default_and_toggles_the_expanded_timeline_on_click", function()
    Toolbox.NavigationModule.RouteBar.ShowRoute(buildSampleRouteResult(), {
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
      name = "北风苔原目标点",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame)
    assert.is_true(routeBarFrame:IsShown())
    assert.equals("TOP", routeBarFrame._points[1].point)
    assert.is_false(routeBarFrame._expandedContent:IsShown())
    assert.is_true(string.find(routeBarFrame._capsuleSummary:GetText(), "第1/2步", 1, true) ~= nil)
    assert.is_true(string.find(routeBarFrame._capsuleSummary:GetText(), "传送：奥格瑞玛", 1, true) ~= nil)

    routeBarFrame._capsuleButton:RunScript("OnClick")
    assert.is_true(routeBarFrame._expandedContent:IsShown())
    assert.is_true(moduleDb.routeWidgetExpanded)
    assert.is_true(string.find(routeBarFrame._timelineText:GetText(), "起始位置", 1, true) ~= nil)
    assert.is_true(string.find(routeBarFrame._timelineText:GetText(), "终点位置", 1, true) ~= nil)

    routeBarFrame._capsuleButton:RunScript("OnClick")
    assert.is_false(routeBarFrame._expandedContent:IsShown())
    assert.is_false(moduleDb.routeWidgetExpanded)
  end)

  it("restores_the_saved_anchor_and_persists_dragged_position", function()
    moduleDb.routeWidgetPosition = {
      point = "TOP",
      x = 24,
      y = -30,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildSampleRouteResult(), {
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
      name = "北风苔原目标点",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.equals(24, routeBarFrame._points[1].x)
    assert.equals(-30, routeBarFrame._points[1].y)

    cursorX = 100
    cursorY = 200
    routeBarFrame._capsuleButton:RunScript("OnDragStart")
    cursorX = 130
    cursorY = 250
    routeBarFrame:RunScript("OnUpdate", 0.2)
    routeBarFrame._capsuleButton:RunScript("OnDragStop")

    assert.equals(54, moduleDb.routeWidgetPosition.x)
    assert.equals(20, moduleDb.routeWidgetPosition.y)
    assert.equals(54, routeBarFrame._points[#routeBarFrame._points].x)
    assert.equals(20, routeBarFrame._points[#routeBarFrame._points].y)
  end)

  it("stores_the_latest_ten_history_entries_and_replans_from_the_saved_destination", function()
    for index = 1, 12 do
      Toolbox.NavigationModule.RouteBar.ShowRoute(buildSampleRouteResult(), {
        uiMapID = 100 + index,
        x = 0.1 + (index / 100),
        y = 0.2 + (index / 100),
        name = "目标" .. tostring(index),
      })
    end

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    assert.equals(10, #moduleDb.routeHistory)
    assert.equals(112, moduleDb.routeHistory[1].targetUiMapID)
    assert.equals("目标12", moduleDb.routeHistory[1].targetName)
    assert.equals(103, moduleDb.routeHistory[10].targetUiMapID)

    routeBarFrame._historyButtons[2]:RunScript("OnClick")

    assert.equals(1, #replannedTargetList)
    assert.equals(111, replannedTargetList[1].uiMapID)
    assert.equals("目标11", replannedTargetList[1].name)
  end)

  it("refreshes_live_progress_and_deviation_status_from_the_current_location_snapshot", function()
    Toolbox.NavigationModule.RouteBar.ShowRoute(buildSampleRouteResult(), {
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
      name = "北风苔原目标点",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.4,
      currentY = 0.5,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.is_true(string.find(routeBarFrame._capsuleSummary:GetText(), "第2/2步", 1, true) ~= nil)

    locationSnapshot = {
      currentUiMapID = 999,
      currentX = 0.1,
      currentY = 0.1,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.is_true(string.find(routeBarFrame._capsuleStatus:GetText(), "偏离路线", 1, true) ~= nil)

    locationSnapshot = {
      currentUiMapID = 114,
      currentX = 0.52,
      currentY = 0.43,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.is_true(string.find(routeBarFrame._capsuleStatus:GetText(), "已到达终点", 1, true) ~= nil)
  end)

  it("shows_same_map_start_current_and_target_with_real_map_coordinates", function()
    locationSnapshot = {
      currentUiMapID = 114,
      currentX = 0.41,
      currentY = 0.51,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute({
      totalSteps = 1,
      segments = {
        {
          mode = "walk_local",
          label = "目标位置：北风苔原 52.0, 43.0",
          fromName = "当前位置",
          toName = "北风苔原目标点",
          fromUiMapID = 114,
          toUiMapID = 114,
          traversedUiMapIDs = { 114 },
          traversedUiMapNames = { "北风苔原" },
        },
      },
    }, {
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    local timelineText = routeBarFrame._timelineText:GetText() -- 展开态时间线文本
    assert.is_true(string.find(timelineText, "起始位置：北风苔原 41.0, 51.0", 1, true) ~= nil)
    assert.is_true(string.find(timelineText, "终点位置：北风苔原 52.0, 43.0", 1, true) ~= nil)
    assert.is_true(string.find(timelineText, "当前位置：北风苔原 41.0, 51.0", 1, true) ~= nil)

    locationSnapshot = {
      currentUiMapID = 114,
      currentX = 0.45,
      currentY = 0.55,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()

    timelineText = routeBarFrame._timelineText:GetText()
    assert.is_true(string.find(timelineText, "起始位置：北风苔原 41.0, 51.0", 1, true) ~= nil)
    assert.is_true(string.find(timelineText, "当前位置：北风苔原 45.0, 55.0", 1, true) ~= nil)
  end)

  it("prefers_cleaned_segment_labels_for_player_facing_route_text", function()
    local routeText = Toolbox.NavigationModule.RouteBar.BuildRouteText({
      totalSteps = 2,
      segments = {
        {
          mode = "public_portal",
          label = "使用西部大地神殿的传送门前往海加尔山→海加尔山",
          fromName = "奥格瑞玛",
          toName = "海加尔山",
          traversedUiMapNames = { "奥格瑞玛", "海加尔山" },
        },
        {
          mode = "hearthstone",
          label = "炉石",
          fromName = "海加尔山",
          toName = "奥格瑞玛",
          traversedUiMapNames = { "海加尔山", "奥格瑞玛" },
        },
      },
    })

    assert.is_true(string.find(routeText, "使用西部大地神殿的传送门前往海加尔山", 1, true) ~= nil)
    assert.is_nil(string.find(routeText, "→海加尔山", 1, true))
    assert.is_true(string.find(routeText, "炉石：奥格瑞玛", 1, true) ~= nil)
  end)
end)
