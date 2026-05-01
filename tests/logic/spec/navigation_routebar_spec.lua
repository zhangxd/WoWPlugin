local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")

describe("Navigation RouteBar", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalUIParent = nil -- 原始 UIParent 全局
  local originalGetCursorPosition = nil -- 原始光标位置函数
  local originalStaticPopupDialogs = nil -- 原始 StaticPopupDialogs
  local originalStaticPopupShow = nil -- 原始 StaticPopup_Show
  local originalAcceptText = nil -- 原始 ACCEPT 文案
  local originalCancelText = nil -- 原始 CANCEL 文案
  local createdFrameByName = nil -- 已创建命名 Frame
  local moduleDb = nil -- navigation 模块存档
  local cursorX = 0 -- 当前测试光标 X
  local cursorY = 0 -- 当前测试光标 Y
  local locationSnapshot = nil -- 当前角色位置快照
  local replannedTargetList = nil -- 历史确认后的重规划目标
  local popupRequestList = nil -- 弹框请求记录

  local function buildRouteNodeTable()
    return {
      [8500] = { NodeID = 8500, Kind = "map_anchor", Source = "uimap", SourceID = 85, UiMapID = 85, Name_lang = "奥格瑞玛", WalkClusterNodeID = 8500 },
      [8501] = { NodeID = 8501, Kind = "portal", Source = "portal", SourceID = 437, UiMapID = 85, Name_lang = "奥格瑞玛传送门", WalkClusterNodeID = 8500 },
      [6261] = { NodeID = 6261, Kind = "map_anchor", Source = "uimap", SourceID = 626, UiMapID = 626, Name_lang = "达拉然", WalkClusterNodeID = 6261 },
      [6262] = { NodeID = 6262, Kind = "taxi", Source = "taxi", SourceID = 1774, UiMapID = 626, Name_lang = "达拉然飞行点", WalkClusterNodeID = 6261 },
      [1201] = { NodeID = 1201, Kind = "map_anchor", Source = "uimap", SourceID = 120, UiMapID = 120, Name_lang = "风暴峭壁", WalkClusterNodeID = 1201 },
    }
  end

  local function buildComplexRouteResult()
    return {
      totalSteps = 4,
      rawNodePath = { "current", 8500, 8501, 6261, 6262, 1201, "target" },
      semanticNodes = {
        { kind = "map", text = "奥格瑞玛", uiMapID = 85 },
        { kind = "action", mode = "public_portal", text = "使用奥格瑞玛的传送门前往达拉然" },
        { kind = "map", text = "达拉然", uiMapID = 626 },
        { kind = "map", text = "风暴峭壁", uiMapID = 120 },
      },
      segments = {
        {
          mode = "walk_local",
          label = "步行：奥格瑞玛 -> 奥格瑞玛传送门",
          fromName = "奥格瑞玛",
          toName = "奥格瑞玛传送门",
          fromUiMapID = 85,
          toUiMapID = 85,
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          mode = "public_portal",
          label = "使用奥格瑞玛的传送门前往达拉然",
          fromName = "奥格瑞玛传送门",
          toName = "达拉然",
          fromUiMapID = 85,
          toUiMapID = 626,
          traversedUiMapIDs = { 85, 626 },
          traversedUiMapNames = { "奥格瑞玛", "达拉然" },
        },
        {
          mode = "taxi",
          label = "飞行前往K3，风暴峭壁",
          fromName = "达拉然飞行点",
          toName = "K3，风暴峭壁",
          fromUiMapID = 626,
          toUiMapID = 120,
          traversedUiMapIDs = { 626, 127, 120 },
          traversedUiMapNames = { "达拉然", "晶歌森林", "风暴峭壁" },
        },
        {
          mode = "walk_local",
          label = "目标位置：风暴峭壁 41.8, 84.7",
          fromName = "风暴峭壁",
          toName = "风暴峭壁目标点",
          fromUiMapID = 120,
          toUiMapID = 120,
          traversedUiMapIDs = { 120 },
          traversedUiMapNames = { "风暴峭壁" },
        },
      },
    }
  end

  local function buildSameMapRouteResult()
    return {
      totalSteps = 1,
      rawNodePath = { "current", 110, "target" },
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
    }
  end

  local function buildTaxiMapChainRouteResult()
    return {
      totalSteps = 4,
      rawNodePath = { "current", 9400, 2200, 2600, "target" },
      semanticNodes = {
        { kind = "map", text = "银月城", uiMapID = 94 },
        { kind = "map", text = "永歌森林", uiMapID = 95 },
        { kind = "map", text = "东瘟疫之地", uiMapID = 22 },
        { kind = "map", text = "辛特兰", uiMapID = 26 },
      },
      segments = {
        {
          mode = "walk_local",
          label = "步行：银月城 -> 塔奎林，永歌森林",
          fromName = "当前位置",
          toName = "塔奎林，永歌森林",
          fromUiMapID = 94,
          toUiMapID = 95,
          traversedUiMapIDs = { 94, 95 },
          traversedUiMapNames = { "银月城", "永歌森林", "塔奎林，永歌森林" },
        },
        {
          mode = "taxi",
          label = "飞行前往圣光之愿礼拜堂，东瘟疫之地",
          fromName = "塔奎林，永歌森林",
          toName = "圣光之愿礼拜堂，东瘟疫之地",
          fromUiMapID = 95,
          toUiMapID = 22,
          traversedUiMapIDs = { 95, 22 },
          traversedUiMapNames = { "永歌森林", "祖阿曼", "东瘟疫之地" },
        },
        {
          mode = "taxi",
          label = "飞行前往恶齿村，辛特兰",
          fromName = "圣光之愿礼拜堂，东瘟疫之地",
          toName = "恶齿村，辛特兰",
          fromUiMapID = 22,
          toUiMapID = 26,
          traversedUiMapIDs = { 22, 26 },
          traversedUiMapNames = { "东瘟疫之地", "辛特兰" },
        },
        {
          mode = "walk_local",
          label = "目标位置：辛特兰 57.1, 48.1",
          fromName = "恶齿村，辛特兰",
          toName = "辛特兰目标点",
          fromUiMapID = 26,
          toUiMapID = 26,
          traversedUiMapIDs = { 26 },
          traversedUiMapNames = { "恶齿村，辛特兰", "辛特兰" },
        },
      },
    }
  end

  local function buildLongCapsuleRouteResult()
    return {
      totalSteps = 1,
      rawNodePath = { "current", 9991, "target" },
      semanticNodes = {
        { kind = "map", text = "这是一段非常非常长的起始位置说明文本", uiMapID = 991 },
        { kind = "map", text = "这是一段非常非常长的终点说明文本", uiMapID = 992 },
      },
      segments = {
        {
          mode = "walk_local",
          label = "目标位置：这是一段非常非常长的终点说明文本 45.6, 78.9",
          fromName = "这是一段非常非常长的起始位置说明文本",
          toName = "这是一段非常非常长的终点说明文本",
          fromUiMapID = 991,
          toUiMapID = 992,
          traversedUiMapIDs = { 991, 992 },
          traversedUiMapNames = {
            "这是一段非常非常长的起始位置说明文本",
            "这是一段非常非常长的终点说明文本",
          },
        },
      },
    }
  end

  local function buildOverflowTimelineRouteResult()
    return {
      totalSteps = 5,
      rawNodePath = { "current", 3100, 3101, 3200, 3201, 3300, "target" },
      semanticNodes = {
        { kind = "map", text = "暴风城", uiMapID = 84 },
        { kind = "action", mode = "public_portal", text = "使用暴风城的传送门前往达拉然" },
        { kind = "map", text = "达拉然", uiMapID = 626 },
        { kind = "action", mode = "public_portal", text = "使用达拉然的传送门前往风暴峭壁" },
        { kind = "map", text = "风暴峭壁", uiMapID = 120 },
      },
      segments = {
        {
          mode = "walk_local",
          label = "步行：暴风城 -> 暴风城传送门",
          fromName = "当前位置",
          toName = "暴风城传送门",
          fromUiMapID = 84,
          toUiMapID = 84,
          traversedUiMapIDs = { 84 },
          traversedUiMapNames = { "暴风城" },
        },
        {
          mode = "public_portal",
          label = "使用暴风城的传送门前往达拉然",
          fromName = "暴风城传送门",
          toName = "达拉然",
          fromUiMapID = 84,
          toUiMapID = 626,
          traversedUiMapIDs = { 84, 626 },
          traversedUiMapNames = { "暴风城", "达拉然" },
        },
        {
          mode = "walk_local",
          label = "步行：达拉然 -> 达拉然传送门",
          fromName = "达拉然",
          toName = "达拉然传送门",
          fromUiMapID = 626,
          toUiMapID = 626,
          traversedUiMapIDs = { 626 },
          traversedUiMapNames = { "达拉然" },
        },
        {
          mode = "public_portal",
          label = "使用达拉然的传送门前往风暴峭壁",
          fromName = "达拉然传送门",
          toName = "风暴峭壁",
          fromUiMapID = 626,
          toUiMapID = 120,
          traversedUiMapIDs = { 626, 120 },
          traversedUiMapNames = { "达拉然", "风暴峭壁" },
        },
        {
          mode = "walk_local",
          label = "目标位置：风暴峭壁 41.8, 84.7",
          fromName = "风暴峭壁",
          toName = "风暴峭壁目标点",
          fromUiMapID = 120,
          toUiMapID = 120,
          traversedUiMapIDs = { 120 },
          traversedUiMapNames = { "风暴峭壁" },
        },
      },
    }
  end

  local function buildTransportLeakRouteResult()
    return {
      totalSteps = 2,
      rawNodePath = { "current", 8500, 9100, 9101, "target" },
      semanticNodes = {
        { kind = "map", text = "奥格瑞玛", uiMapID = 85 },
        { kind = "action", mode = "transport", text = "乘坐奥格瑞玛的飞艇前往北风苔原" },
        { kind = "map", text = "北风苔原", uiMapID = 114 },
      },
      segments = {
        {
          mode = "walk_local",
          label = "步行：奥格瑞玛 -> 乘坐奥格瑞玛的飞艇前往北风苔原",
          fromName = "当前位置",
          toName = "乘坐奥格瑞玛的飞艇前往北风苔原",
          fromUiMapID = 85,
          toUiMapID = 85,
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          mode = "transport",
          label = "乘坐奥格瑞玛的飞艇前往北风苔原",
          fromName = "乘坐奥格瑞玛的飞艇前往北风苔原",
          toName = "乘坐战歌要塞的飞艇前往奥格瑞玛",
          fromUiMapID = 85,
          toUiMapID = 114,
          traversedUiMapIDs = { 85, 114 },
          traversedUiMapNames = { "奥格瑞玛", "北风苔原" },
        },
        {
          mode = "walk_local",
          label = "目标位置：北风苔原 51.9, 41.6",
          fromName = "战歌要塞",
          toName = "北风苔原目标点",
          fromUiMapID = 114,
          toUiMapID = 114,
          traversedUiMapIDs = { 114 },
          traversedUiMapNames = { "北风苔原" },
        },
      },
    }
  end

  local function buildHistoryTarget(index)
    return {
      uiMapID = 100 + index,
      x = 0.1 + (index / 100),
      y = 0.2 + (index / 100),
      name = "目标" .. tostring(index),
    }
  end

  local function collectNodeLabelList(routeBarFrame)
    local labelList = {} -- 节点标签列表
    for rowIndex, rowFrame in ipairs(routeBarFrame._nodeRows or {}) do
      labelList[rowIndex] = rowFrame._labelText and rowFrame._labelText:GetText() or nil
    end
    return labelList
  end

  local function collectNodeDetailList(routeBarFrame)
    local detailList = {} -- 节点明细列表
    for rowIndex, rowFrame in ipairs(routeBarFrame._nodeRows or {}) do
      detailList[rowIndex] = rowFrame._detailText and rowFrame._detailText:GetText() or nil
    end
    return detailList
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalUIParent = rawget(_G, "UIParent")
    originalGetCursorPosition = rawget(_G, "GetCursorPosition")
    originalStaticPopupDialogs = rawget(_G, "StaticPopupDialogs")
    originalStaticPopupShow = rawget(_G, "StaticPopup_Show")
    originalAcceptText = rawget(_G, "ACCEPT")
    originalCancelText = rawget(_G, "CANCEL")
    createdFrameByName = {}
    moduleDb = {
      enabled = true,
      debug = false,
      routeWidgetExpanded = false,
      routeHistoryExpanded = false,
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
    popupRequestList = {}

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
    rawset(_G, "StaticPopupDialogs", {})
    rawset(_G, "StaticPopup_Show", function(dialogKey, textArg1, textArg2, dataObject)
      local requestObject = {
        dialogKey = dialogKey,
        textArg1 = textArg1,
        textArg2 = textArg2,
        data = dataObject,
        dialogDef = rawget(_G, "StaticPopupDialogs") and rawget(_G, "StaticPopupDialogs")[dialogKey] or nil,
      } -- 当前弹框请求
      popupRequestList[#popupRequestList + 1] = requestObject
      return requestObject
    end)
    rawset(_G, "ACCEPT", "确认")
    rawset(_G, "CANCEL", "取消")
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
            [84] = { Name_lang = "暴风城" },
            [114] = { Name_lang = "北风苔原" },
            [120] = { Name_lang = "风暴峭壁" },
            [626] = { Name_lang = "达拉然" },
            [94] = { Name_lang = "银月城" },
            [95] = { Name_lang = "永歌森林" },
            [22] = { Name_lang = "东瘟疫之地" },
            [26] = { Name_lang = "辛特兰" },
            [991] = { Name_lang = "这是一段非常非常长的起始位置说明文本" },
            [992] = { Name_lang = "这是一段非常非常长的终点说明文本" },
          },
        },
        NavigationRouteEdges = {
          nodes = buildRouteNodeTable(),
        },
      },
      L = {
        NAVIGATION_ROUTE_EMPTY = "暂无路线",
        NAVIGATION_ROUTE_WIDGET_STEP_FMT = "第%d/%d步",
        NAVIGATION_ROUTE_WIDGET_STATUS_READY = "按当前路线前进",
        NAVIGATION_ROUTE_WIDGET_STATUS_DEVIATED = "你已偏离路线",
        NAVIGATION_ROUTE_WIDGET_STATUS_ARRIVED = "已到达终点",
        NAVIGATION_ROUTE_WIDGET_START = "起始位置",
        NAVIGATION_ROUTE_WIDGET_END = "终点位置",
        NAVIGATION_ROUTE_WIDGET_CURRENT = "当前位置",
        NAVIGATION_ROUTE_WIDGET_HISTORY_TITLE = "最近路线",
        NAVIGATION_ROUTE_WIDGET_HISTORY_EMPTY = "暂无历史路线",
        NAVIGATION_ROUTE_WIDGET_HISTORY_BUTTON = "最近路线",
        NAVIGATION_ROUTE_WIDGET_HISTORY_CONFIRM = "是否重新规划到%s？",
        NAVIGATION_ROUTE_WIDGET_HISTORY_CONFIRM_DETAIL = "将以你的当前位置为起点重新规划。",
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
    rawset(_G, "StaticPopupDialogs", originalStaticPopupDialogs)
    rawset(_G, "StaticPopup_Show", originalStaticPopupShow)
    rawset(_G, "ACCEPT", originalAcceptText)
    rawset(_G, "CANCEL", originalCancelText)
    rawset(_G, "ToolboxNavigationRouteBar", nil)
  end)

  it("shows_status_and_progress_in_the_capsule_header_and_triptych_positions_by_default", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame)
    assert.is_true(routeBarFrame:IsShown())
    assert.is_false(routeBarFrame._expandedContent:IsShown())
    assert.is_table(routeBarFrame._capsuleHeaderStatus)
    assert.is_table(routeBarFrame._capsuleHeaderProgress)
    assert.is_table(routeBarFrame._capsuleStartLabel)
    assert.is_table(routeBarFrame._capsuleStartValue)
    assert.is_table(routeBarFrame._capsuleCurrentValue)
    assert.is_table(routeBarFrame._capsuleTargetValue)
    assert.is_table(routeBarFrame._capsuleDividerLeft)
    assert.is_table(routeBarFrame._capsuleDividerRight)
    assert.equals("按当前路线前进", routeBarFrame._capsuleHeaderStatus:GetText())
    assert.equals("第1/4步", routeBarFrame._capsuleHeaderProgress:GetText())
    assert.equals("起始位置", routeBarFrame._capsuleStartLabel:GetText())
    assert.equals("奥格瑞玛 45.0, 63.2", routeBarFrame._capsuleStartValue:GetText())
    assert.equals("奥格瑞玛 45.0, 63.2", routeBarFrame._capsuleCurrentValue:GetText())
    assert.equals("风暴峭壁 41.8, 84.7", routeBarFrame._capsuleTargetValue:GetText())
  end)

  it("toggles_the_expanded_navigation_page_and_renders_map_action_map_nodes_without_promoting_taxi_actions", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    assert.is_true(routeBarFrame._expandedContent:IsShown())
    assert.is_table(routeBarFrame._nodeRows)
    assert.is_true(moduleDb.routeWidgetExpanded)
    assert.is_true(routeBarFrame._timelineText == nil or routeBarFrame._timelineText:GetText() == "")
    assert.same({
      "奥格瑞玛 45.0, 63.2",
      "使用奥格瑞玛的传送门前往达拉然",
      "达拉然",
      "风暴峭壁 41.8, 84.7",
    }, collectNodeLabelList(routeBarFrame))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "奥格瑞玛传送门", 1, true))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "飞行前往", 1, true))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "K3", 1, true))

    routeBarFrame._capsuleButton:RunScript("OnClick")
    assert.is_false(routeBarFrame._expandedContent:IsShown())
    assert.is_false(moduleDb.routeWidgetExpanded)
  end)

  it("does_not_leak_return_transport_node_names_into_the_expanded_chain", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.5,
      currentY = 0.6,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildTransportLeakRouteResult(), {
      uiMapID = 114,
      x = 0.519,
      y = 0.416,
      name = "北风苔原",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    local nodePathText = table.concat(collectNodeLabelList(routeBarFrame), "\n") -- 展开态节点链文本
    assert.is_true(string.find(nodePathText, "乘坐奥格瑞玛的飞艇前往北风苔原", 1, true) ~= nil)
    assert.is_true(string.find(nodePathText, "北风苔原 51.9, 41.6", 1, true) ~= nil)
    assert.is_nil(string.find(nodePathText, "乘坐战歌要塞的飞艇前往奥格瑞玛", 1, true))
  end)

  it("falls_back_to_segment_rendering_when_semantic_nodes_are_incomplete", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    local routeResult = buildComplexRouteResult()
    routeResult.semanticNodes = {
      { kind = "action", mode = "public_portal", text = "使用奥格瑞玛的传送门前往达拉然" },
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(routeResult, {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    assert.same({
      "奥格瑞玛 45.0, 63.2",
      "奥格瑞玛传送门",
      "达拉然",
      "风暴峭壁 41.8, 84.7",
    }, collectNodeLabelList(routeBarFrame))
  end)

  it("renders_intermediate_map_nodes_in_the_expanded_chain_without_promoting_flight_point_details", function()
    locationSnapshot = {
      currentUiMapID = 94,
      currentX = 0.638,
      currentY = 0.653,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildTaxiMapChainRouteResult(), {
      uiMapID = 26,
      x = 0.571,
      y = 0.481,
      name = "辛特兰",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    assert.same({
      "银月城 63.8, 65.3",
      "永歌森林",
      "东瘟疫之地",
      "辛特兰 57.1, 48.1",
    }, collectNodeLabelList(routeBarFrame))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "塔奎林", 1, true))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "圣光之愿礼拜堂", 1, true))
    assert.is_nil(string.find(table.concat(collectNodeLabelList(routeBarFrame), "\n"), "恶齿村", 1, true))
  end)

  it("styles_the_expanded_node_chain_with_connectors_current_highlight_and_single_line_endpoint_positions", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    local nodeRowList = routeBarFrame._nodeRows -- 当前节点行列表
    local firstRow = nodeRowList[1] -- 起点节点
    local secondRow = nodeRowList[2] -- 第二个节点
    local thirdRow = nodeRowList[3] -- 当前位置切换后的中间节点
    local lastRow = nodeRowList[4] -- 终点节点
    local labelList = collectNodeLabelList(routeBarFrame) -- 节点标签文本
    local detailList = collectNodeDetailList(routeBarFrame) -- 节点明细文本

    assert.is_truthy(firstRow._backdrop)
    assert.equals("CENTER", firstRow._labelText._justifyH)
    assert.is_table(firstRow._nodeMarker)
    assert.is_table(firstRow._activeGlow)
    assert.is_true(firstRow._activeGlow:IsShown())
    assert.is_false(secondRow._activeGlow:IsShown())
    assert.is_false(firstRow._connectorTop:IsShown())
    assert.is_true(firstRow._connectorBottom:IsShown())
    assert.is_true(secondRow._connectorTop:IsShown())
    assert.is_true(secondRow._connectorBottom:IsShown())
    assert.is_false(lastRow._connectorBottom:IsShown())
    assert.equals("奥格瑞玛 45.0, 63.2", labelList[1])
    assert.equals("风暴峭壁 41.8, 84.7", labelList[4])
    assert.equals("", detailList[1] or "")
    assert.equals("", detailList[2] or "")
    assert.equals("", detailList[3] or "")
    assert.equals("", detailList[4] or "")

    locationSnapshot = {
      currentUiMapID = 626,
      currentX = 0.526,
      currentY = 0.478,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()

    assert.is_false(firstRow._activeGlow:IsShown())
    assert.is_true(thirdRow._activeGlow:IsShown())
  end)

  it("toggles_the_history_drawer_from_the_history_button_and_persists_the_state", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame._historyDrawer)
    assert.is_table(routeBarFrame._historyToggleButton)
    assert.is_false(routeBarFrame._historyDrawer:IsShown())
    assert.is_false(moduleDb.routeHistoryExpanded)

    routeBarFrame._historyToggleButton:RunScript("OnClick")
    assert.is_true(routeBarFrame._historyDrawer:IsShown())
    assert.is_true(moduleDb.routeHistoryExpanded)

    routeBarFrame._historyToggleButton:RunScript("OnClick")
    assert.is_false(routeBarFrame._historyDrawer:IsShown())
    assert.is_false(moduleDb.routeHistoryExpanded)
  end)

  it("stores_the_latest_ten_history_entries_and_replans_only_after_confirmation", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    for index = 1, 12 do
      Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), buildHistoryTarget(index))
    end

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame._historyToggleButton)
    routeBarFrame._historyToggleButton:RunScript("OnClick")

    assert.equals(10, #moduleDb.routeHistory)
    assert.equals(112, moduleDb.routeHistory[1].targetUiMapID)
    assert.equals("目标12", moduleDb.routeHistory[1].targetName)
    assert.equals(103, moduleDb.routeHistory[10].targetUiMapID)

    routeBarFrame._historyButtons[2]:RunScript("OnClick")
    assert.equals(0, #replannedTargetList)
    assert.equals(1, #popupRequestList)
    assert.is_not_nil(popupRequestList[1].dialogDef)

    popupRequestList[1].dialogDef.OnAccept(nil, popupRequestList[1].data)
    assert.equals(1, #replannedTargetList)
    assert.equals(111, replannedTargetList[1].uiMapID)
    assert.equals("目标11", replannedTargetList[1].name)
  end)

  it("does_not_replan_when_history_confirmation_is_canceled", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame._historyToggleButton)
    routeBarFrame._historyToggleButton:RunScript("OnClick")
    routeBarFrame._historyButtons[1]:RunScript("OnClick")

    assert.equals(1, #popupRequestList)
    if type(popupRequestList[1].dialogDef) == "table" and type(popupRequestList[1].dialogDef.OnCancel) == "function" then
      popupRequestList[1].dialogDef.OnCancel(nil, popupRequestList[1].data)
    end
    assert.equals(0, #replannedTargetList)
  end)

  it("refreshes_live_progress_status_and_current_position_in_the_capsule_body", function()
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame._capsuleHeaderProgress)
    assert.is_table(routeBarFrame._capsuleCurrentValue)
    assert.is_table(routeBarFrame._capsuleHeaderStatus)

    locationSnapshot = {
      currentUiMapID = 626,
      currentX = 0.526,
      currentY = 0.478,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.equals("第3/4步", routeBarFrame._capsuleHeaderProgress:GetText())
    assert.equals("达拉然 52.6, 47.8", routeBarFrame._capsuleCurrentValue:GetText())

    locationSnapshot = {
      currentUiMapID = 999,
      currentX = 0.1,
      currentY = 0.1,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.equals("你已偏离路线", routeBarFrame._capsuleHeaderStatus:GetText())

    locationSnapshot = {
      currentUiMapID = 120,
      currentX = 0.418,
      currentY = 0.847,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.equals("已到达终点", routeBarFrame._capsuleHeaderStatus:GetText())
    assert.equals("风暴峭壁 41.8, 84.7", routeBarFrame._capsuleCurrentValue:GetText())
  end)

  it("renders_same_map_start_current_and_target_with_real_map_coordinates_in_the_capsule_body", function()
    locationSnapshot = {
      currentUiMapID = 114,
      currentX = 0.41,
      currentY = 0.51,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildSameMapRouteResult(), {
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_table(routeBarFrame._capsuleStartValue)
    assert.is_table(routeBarFrame._capsuleCurrentValue)
    assert.is_table(routeBarFrame._capsuleTargetValue)
    assert.equals("北风苔原 41.0, 51.0", routeBarFrame._capsuleStartValue:GetText())
    assert.equals("北风苔原 41.0, 51.0", routeBarFrame._capsuleCurrentValue:GetText())
    assert.equals("北风苔原 52.0, 43.0", routeBarFrame._capsuleTargetValue:GetText())

    locationSnapshot = {
      currentUiMapID = 114,
      currentX = 0.45,
      currentY = 0.55,
    }
    Toolbox.NavigationModule.RouteBar.RefreshLiveState()
    assert.equals("北风苔原 41.0, 51.0", routeBarFrame._capsuleStartValue:GetText())
    assert.equals("北风苔原 45.0, 55.0", routeBarFrame._capsuleCurrentValue:GetText())
  end)

  it("adapts_the_capsule_width_to_long_position_texts", function()
    locationSnapshot = {
      currentUiMapID = 991,
      currentX = 0.123,
      currentY = 0.456,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildLongCapsuleRouteResult(), {
      uiMapID = 992,
      x = 0.789,
      y = 0.654,
      name = "这是一段非常非常长的终点说明文本",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    assert.is_true(routeBarFrame:GetWidth() > 420)
  end)

  it("expands_the_node_container_and_root_frame_to_cover_all_rendered_nodes", function()
    locationSnapshot = {
      currentUiMapID = 84,
      currentX = 0.123,
      currentY = 0.456,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildOverflowTimelineRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路线图根 Frame
    routeBarFrame._capsuleButton:RunScript("OnClick")

    assert.equals(5, #collectNodeLabelList(routeBarFrame))
    assert.is_true(routeBarFrame._nodeListContainer:GetHeight() >= 252)
    assert.is_true(routeBarFrame:GetHeight() >= 346)
  end)

  it("restores_the_saved_anchor_and_persists_dragged_position", function()
    moduleDb.routeWidgetPosition = {
      point = "TOP",
      x = 24,
      y = -30,
    }
    locationSnapshot = {
      currentUiMapID = 85,
      currentX = 0.45,
      currentY = 0.632,
    }

    Toolbox.NavigationModule.RouteBar.ShowRoute(buildComplexRouteResult(), {
      uiMapID = 120,
      x = 0.418,
      y = 0.847,
      name = "风暴峭壁",
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

  it("builds_map_path_summary_without_flight_point_details_or_action_verbs", function()
    local routeText = Toolbox.NavigationModule.RouteBar.BuildRouteText(buildComplexRouteResult())

    assert.is_true(string.find(routeText, "奥格瑞玛", 1, true) ~= nil)
    assert.is_true(string.find(routeText, "使用奥格瑞玛的传送门前往达拉然", 1, true) ~= nil)
    assert.is_true(string.find(routeText, "达拉然", 1, true) ~= nil)
    assert.is_true(string.find(routeText, "风暴峭壁", 1, true) ~= nil)
    assert.is_nil(string.find(routeText, "达拉然飞行点", 1, true))
    assert.is_nil(string.find(routeText, "K3", 1, true))
    assert.is_nil(string.find(routeText, "飞行前往", 1, true))
    assert.is_nil(string.find(routeText, "奥格瑞玛传送门", 1, true))
  end)
end)
