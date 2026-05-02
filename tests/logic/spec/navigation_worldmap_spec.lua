local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")

describe("Navigation WorldMap integration", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalWorldMapFrame = nil -- 原始 WorldMapFrame 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local shownRoute = nil -- RouteBar 显示的路线
  local shownTarget = nil -- RouteBar 记录的目标
  local chatMessages = nil -- 聊天提示记录
  local moduleDb = nil -- navigation 模块存档

  local function assertPlanningDiagnostics(messageList)
    assert.equals(3, #messageList)
    assert.equals("规划成功 | 起点：杜隆塔尔 61.0, 44.0 | 终点：北风苔原 52.0, 43.0 | 总步数：2 | 节点：杜隆塔尔 -> 奥格瑞玛 -> 北风苔原", messageList[1])
    assert.equals("第1段 | mode=class_teleport | from=当前位置 | to=奥格瑞玛 | traversedUiMapNames=奥格瑞玛", messageList[2])
    assert.equals("第2段 | mode=walk_local | from=奥格瑞玛 | to=北风苔原目标点 | traversedUiMapNames=北风苔原", messageList[3])
  end

  local function assertTaxiPlanningDiagnostics(messageList)
    assert.equals("规划成功 | 起点：银月城 64.1, 65.2 | 终点：辛特兰 57.1, 48.1 | 总步数：4 | 节点：银月城 -> 永歌森林 -> 塔奎林，永歌森林 -> 东瘟疫之地 -> 圣光之愿礼拜堂，东瘟疫之地 -> 辛特兰 -> 恶齿村，辛特兰 -> 辛特兰", messageList[1])
    assert.equals("第1段 | mode=walk_local | from=当前位置 | to=塔奎林，永歌森林 | traversedUiMapNames=银月城 -> 永歌森林 -> 塔奎林，永歌森林", messageList[2])
    assert.equals("第2段 | mode=taxi | from=塔奎林，永歌森林 | to=圣光之愿礼拜堂，东瘟疫之地 | traversedUiMapNames=永歌森林 -> 祖阿曼 -> 东瘟疫之地", messageList[3])
    assert.equals("第3段 | mode=taxi | from=圣光之愿礼拜堂，东瘟疫之地 | to=恶齿村，辛特兰 | traversedUiMapNames=东瘟疫之地 -> 辛特兰", messageList[4])
    assert.equals("第4段 | mode=walk_local | from=恶齿村，辛特兰 | to=辛特兰 | traversedUiMapNames=恶齿村，辛特兰 -> 辛特兰", messageList[5])
  end

  local function assertTransportArrivalPlanningDiagnostics(messageList)
    assert.equals("规划成功 | 起点：奥格瑞玛 50.0, 60.0 | 终点：北风苔原 51.9, 41.6 | 总步数：3 | 节点：奥格瑞玛 -> 乘坐奥格瑞玛的飞艇前往北风苔原 -> 北风苔原", messageList[1])
    assert.equals("第1段 | mode=walk_local | from=当前位置 | to=奥格瑞玛飞艇塔 | traversedUiMapNames=奥格瑞玛", messageList[2])
    assert.equals("第2段 | mode=transport | from=乘坐奥格瑞玛的飞艇前往北风苔原 | to=北风苔原 | traversedUiMapNames=奥格瑞玛 -> 北风苔原", messageList[3])
    assert.equals("第3段 | mode=walk_local | from=战歌要塞 | to=北风苔原 | traversedUiMapNames=北风苔原", messageList[4])
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalWorldMapFrame = rawget(_G, "WorldMapFrame")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalCMap = rawget(_G, "C_Map")
    shownRoute = nil
    shownTarget = nil
    chatMessages = {}
    moduleDb = {
      enabled = true,
      lastTargetUiMapID = 0,
      lastTargetX = 0,
      lastTargetY = 0,
    }

    local worldMapFrame = FakeFrame.new({ frameType = "Frame", frameName = "WorldMapFrame" }) -- 大地图 Frame
    worldMapFrame.BorderFrame = FakeFrame.new({ frameType = "Frame", parentFrame = worldMapFrame })
    function worldMapFrame:GetMapID()
      return 947
    end
    rawset(_G, "WorldMapFrame", worldMapFrame)
    rawset(_G, "CreateFrame", function(frameType, frameName, parentFrame, templateName)
      return FakeFrame.new({
        frameType = frameType,
        frameName = frameName,
        parentFrame = parentFrame,
        templateName = templateName,
      })
    end)
    rawset(_G, "C_Map", {
      GetUserWaypoint = function()
        return {
          uiMapID = 114,
          position = {
            x = 0.52,
            y = 0.43,
          },
        }
      end,
    })
    rawset(_G, "Toolbox", {
      Navigation = {
        GetRequiredSpellIDList = function()
          return { 3567, 32272, 3566, 3563, 35715, 50977, 193753, 18960, 126892 }
        end,
        ReadVectorXY = function(vectorValue)
          if type(vectorValue) ~= "table" then
            return nil, nil
          end
          return vectorValue.x, vectorValue.y
        end,
        BuildCurrentCharacterAvailability = function(spellIDList)
          assert.same({ 3567, 32272, 3566, 3563, 35715, 50977, 193753, 18960, 126892 }, spellIDList)
          return {
            classFile = "MAGE",
            faction = "Horde",
            currentUiMapID = 1,
            currentX = 0.61,
            currentY = 0.44,
            knownSpellByID = {
              [spellIDList[1]] = true,
            },
          }
        end,
        PlanRouteToMapTarget = function(target, availabilityContext)
          assert.equals(114, target.uiMapID)
          assert.equals(0.52, target.x)
          assert.equals(0.43, target.y)
          assert.equals("MAGE", availabilityContext.classFile)
          return {
            totalSteps = 2,
            segments = {
              {
                mode = "class_teleport",
                fromName = "当前位置",
                toName = "奥格瑞玛",
                traversedUiMapNames = { "奥格瑞玛" },
              },
              {
                mode = "walk_local",
                fromName = "奥格瑞玛",
                toName = "北风苔原目标点",
                traversedUiMapNames = { "北风苔原" },
              },
            },
          }, nil
        end,
      },
      NavigationModule = {
        RouteBar = {
          ShowRoute = function(routeResult, target)
            shownRoute = routeResult
            shownTarget = target
          end,
          BuildPositionDisplayText = function(uiMapID, pointX, pointY, fallbackText)
            local mapNameByID = {
              [1] = "杜隆塔尔",
              [85] = "奥格瑞玛",
              [114] = "北风苔原",
            }
            local mapName = mapNameByID[tonumber(uiMapID)] or tostring(fallbackText or "")
            if type(pointX) == "number" and type(pointY) == "number" then
              return string.format("%s %.1f, %.1f", mapName, pointX * 100, pointY * 100)
            end
            return mapName
          end,
          BuildRouteNodePathText = function()
            return "杜隆塔尔 -> 奥格瑞玛 -> 北风苔原"
          end,
          BuildRouteText = function(routeResult)
            return string.format("%d步 | %s", tonumber(routeResult and routeResult.totalSteps) or 0, tostring(routeResult and routeResult.segments and routeResult.segments[1] and routeResult.segments[1].mode or ""))
          end,
          ClearRoute = function() end,
        },
      },
      Chat = {
        PrintAddonMessage = function(messageText)
          chatMessages[#chatMessages + 1] = messageText
        end,
      },
      Config = {
        GetModule = function()
          return moduleDb
        end,
      },
      Data = {
        NavigationMapNodes = {
          nodes = {
            [1] = { Name_lang = "杜隆塔尔" },
            [85] = { Name_lang = "奥格瑞玛" },
            [114] = { Name_lang = "北风苔原" },
          },
        },
      },
      L = {
        NAVIGATION_WORLD_MAP_BUTTON = "规划路线",
        NAVIGATION_WORLD_MAP_BUTTON_NEEDS_WAYPOINT = "先放地图标记",
        NAVIGATION_ROUTE_NEEDS_WAYPOINT = "请先在世界地图上放置目标标记。",
        NAVIGATION_ROUTE_NO_ROUTE = "当前目标暂无可用路线。",
        NAVIGATION_ROUTE_UNSUPPORTED_TARGET = "当前目标层级暂不支持规划路线，请缩放到区域或子地图后再试。",
        NAVIGATION_ROUTE_PLAN_FAILED = "路线规划失败。",
      },
    })

    local worldMapChunk = assert(loadfile("Toolbox/Modules/Navigation/WorldMap.lua")) -- 世界地图入口 chunk
    worldMapChunk()
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "WorldMapFrame", originalWorldMapFrame)
    rawset(_G, "CreateFrame", originalCreateFrame)
    rawset(_G, "C_Map", originalCMap)
  end)

  it("creates_one_world_map_button_and_plans_route_from_user_waypoint", function()
    Toolbox.NavigationModule.WorldMap.Install()
    Toolbox.NavigationModule.WorldMap.Install()

    local hookList = WorldMapFrame.hookedHandlers.OnShow -- OnShow hook 列表
    assert.equals(1, #hookList)

    WorldMapFrame:Show()
    local targetButton = Toolbox.NavigationModule.WorldMap.GetTargetButton() -- 规划按钮
    assert.is_table(targetButton)
    assert.equals("规划路线", targetButton:GetText())
    assert.is_true(targetButton:IsEnabled())

    targetButton:RunScript("OnClick")
    assert.is_table(shownRoute)
    assert.equals(2, shownRoute.totalSteps)
    assert.equals("class_teleport", shownRoute.segments[1].mode)
    assert.equals(114, shownTarget.uiMapID)
    assert.equals(0.52, shownTarget.x)
    assertPlanningDiagnostics(chatMessages)
  end)

  it("supports_replanning_to_an_explicit_history_target_without_reading_the_user_waypoint", function()
    rawset(_G, "C_Map", {
      GetUserWaypoint = function()
        return nil
      end,
    })

    Toolbox.NavigationModule.WorldMap.PlanRouteToTarget({
      uiMapID = 114,
      x = 0.52,
      y = 0.43,
      name = "北风苔原目标点",
    })

    assert.is_table(shownRoute)
    assert.equals(114, shownTarget.uiMapID)
    assert.equals(114, moduleDb.lastTargetUiMapID)
    assert.equals(0.52, moduleDb.lastTargetX)
    assert.equals(0.43, moduleDb.lastTargetY)
    assertPlanningDiagnostics(chatMessages)
  end)

  it("builds_planning_node_summary_from_segment_maps_instead_of_the_player_facing_routebar_summary", function()
    Toolbox.Navigation.BuildCurrentCharacterAvailability = function()
      return {
        classFile = "PALADIN",
        faction = "Horde",
        currentUiMapID = 2393,
        currentX = 0.641,
        currentY = 0.652,
        knownSpellByID = {},
      }
    end
    Toolbox.Navigation.PlanRouteToMapTarget = function()
      return {
        totalSteps = 4,
        segments = {
          {
            mode = "walk_local",
            fromName = "当前位置",
            toName = "塔奎林，永歌森林",
            traversedUiMapNames = { "银月城", "永歌森林", "塔奎林，永歌森林" },
          },
          {
            mode = "taxi",
            fromName = "塔奎林，永歌森林",
            toName = "圣光之愿礼拜堂，东瘟疫之地",
            traversedUiMapNames = { "永歌森林", "祖阿曼", "东瘟疫之地" },
          },
          {
            mode = "taxi",
            fromName = "圣光之愿礼拜堂，东瘟疫之地",
            toName = "恶齿村，辛特兰",
            traversedUiMapNames = { "东瘟疫之地", "辛特兰" },
          },
          {
            mode = "walk_local",
            fromName = "恶齿村，辛特兰",
            toName = "辛特兰",
            traversedUiMapNames = { "恶齿村，辛特兰", "辛特兰" },
          },
        },
      }, nil
    end
    Toolbox.NavigationModule.RouteBar.BuildPositionDisplayText = function(uiMapID, pointX, pointY, fallbackText)
      local mapNameByID = {
        [26] = "辛特兰",
        [2393] = "银月城",
      }
      local mapName = mapNameByID[tonumber(uiMapID)] or tostring(fallbackText or "")
      if type(pointX) == "number" and type(pointY) == "number" then
        return string.format("%s %.1f, %.1f", mapName, pointX * 100, pointY * 100)
      end
      return mapName
    end
    Toolbox.NavigationModule.RouteBar.BuildRouteNodePathText = function()
      return "银月城 -> 东瘟疫之地 -> 辛特兰"
    end

    Toolbox.NavigationModule.WorldMap.PlanRouteToTarget({
      uiMapID = 26,
      x = 0.571,
      y = 0.481,
      name = "辛特兰",
    })

    assert.equals(5, #chatMessages)
    assertTaxiPlanningDiagnostics(chatMessages)
  end)

  it("uses_arrival_semantics_in_planning_diagnostics_instead_of_return_transport_node_names", function()
    Toolbox.Navigation.BuildCurrentCharacterAvailability = function()
      return {
        classFile = "WARRIOR",
        faction = "Horde",
        currentUiMapID = 85,
        currentX = 0.5,
        currentY = 0.6,
        knownSpellByID = {},
      }
    end
    Toolbox.Navigation.PlanRouteToMapTarget = function()
      return {
        totalSteps = 3,
        semanticNodes = {
          { kind = "map", text = "奥格瑞玛" },
          { kind = "transport", text = "乘坐奥格瑞玛的飞艇前往北风苔原" },
          { kind = "map", text = "北风苔原" },
        },
        segments = {
          {
            mode = "walk_local",
            fromName = "当前位置",
            toName = "奥格瑞玛飞艇塔",
            traversedUiMapNames = { "奥格瑞玛" },
          },
          {
            mode = "transport",
            fromName = "乘坐奥格瑞玛的飞艇前往北风苔原",
            toName = "乘坐战歌要塞的飞艇前往奥格瑞玛",
            traversedUiMapNames = { "奥格瑞玛", "北风苔原" },
          },
          {
            mode = "walk_local",
            fromName = "战歌要塞",
            toName = "北风苔原",
            traversedUiMapNames = { "北风苔原" },
          },
        },
      }, nil
    end
    Toolbox.NavigationModule.RouteBar.BuildPositionDisplayText = function(uiMapID, pointX, pointY, fallbackText)
      local mapNameByID = {
        [85] = "奥格瑞玛",
        [114] = "北风苔原",
      }
      local mapName = mapNameByID[tonumber(uiMapID)] or tostring(fallbackText or "")
      if type(pointX) == "number" and type(pointY) == "number" then
        return string.format("%s %.1f, %.1f", mapName, pointX * 100, pointY * 100)
      end
      return mapName
    end
    Toolbox.NavigationModule.RouteBar.BuildRouteNodePathText = function()
      return "奥格瑞玛 -> 乘坐奥格瑞玛的飞艇前往北风苔原 -> 北风苔原"
    end

    Toolbox.NavigationModule.WorldMap.PlanRouteToTarget({
      uiMapID = 114,
      x = 0.519,
      y = 0.416,
      name = "北风苔原",
    })

    assert.equals(4, #chatMessages)
    assertTransportArrivalPlanningDiagnostics(chatMessages)
  end)

  it("falls_back_to_segment_summary_when_semantic_nodes_are_incomplete", function()
    Toolbox.Navigation.BuildCurrentCharacterAvailability = function()
      return {
        classFile = "WARRIOR",
        faction = "Horde",
        currentUiMapID = 85,
        currentX = 0.5,
        currentY = 0.6,
        knownSpellByID = {},
      }
    end
    Toolbox.Navigation.PlanRouteToMapTarget = function()
      return {
        totalSteps = 3,
        semanticNodes = {
          { kind = "transport", text = "乘坐奥格瑞玛的飞艇前往北风苔原" },
        },
        segments = {
          {
            mode = "walk_local",
            fromName = "当前位置",
            toName = "奥格瑞玛飞艇塔",
            traversedUiMapNames = { "奥格瑞玛" },
          },
          {
            mode = "transport",
            fromName = "乘坐奥格瑞玛的飞艇前往北风苔原",
            toName = "乘坐战歌要塞的飞艇前往奥格瑞玛",
            traversedUiMapNames = { "奥格瑞玛", "北风苔原" },
          },
          {
            mode = "walk_local",
            fromName = "战歌要塞",
            toName = "北风苔原",
            traversedUiMapNames = { "北风苔原" },
          },
        },
      }, nil
    end
    Toolbox.NavigationModule.RouteBar.BuildPositionDisplayText = function(uiMapID, pointX, pointY, fallbackText)
      local mapNameByID = {
        [85] = "奥格瑞玛",
        [114] = "北风苔原",
      }
      local mapName = mapNameByID[tonumber(uiMapID)] or tostring(fallbackText or "")
      if type(pointX) == "number" and type(pointY) == "number" then
        return string.format("%s %.1f, %.1f", mapName, pointX * 100, pointY * 100)
      end
      return mapName
    end
    Toolbox.NavigationModule.RouteBar.BuildRouteNodePathText = function()
      return "奥格瑞玛 -> 奥格瑞玛飞艇塔 -> 北风苔原"
    end

    Toolbox.NavigationModule.WorldMap.PlanRouteToTarget({
      uiMapID = 114,
      x = 0.519,
      y = 0.416,
      name = "北风苔原",
    })

    assert.equals(4, #chatMessages)
    assert.equals("规划成功 | 起点：奥格瑞玛 50.0, 60.0 | 终点：北风苔原 51.9, 41.6 | 总步数：3 | 节点：奥格瑞玛 -> 奥格瑞玛飞艇塔 -> 北风苔原", chatMessages[1])
  end)

  it("shows_disabled_button_and_chat_hint_when_user_waypoint_is_missing", function()
    rawset(_G, "C_Map", {
      GetUserWaypoint = function()
        return nil
      end,
    })

    Toolbox.NavigationModule.WorldMap.Install()
    WorldMapFrame:Show()

    local targetButton = Toolbox.NavigationModule.WorldMap.GetTargetButton() -- 规划按钮
    assert.equals("先放地图标记", targetButton:GetText())
    assert.is_false(targetButton:IsEnabled())
    targetButton:RunScript("OnClick")

    assert.same({ "请先在世界地图上放置目标标记。" }, chatMessages)
    assert.is_nil(shownRoute)
  end)

  it("prints_reason_when_route_planning_returns_an_error", function()
    Toolbox.Navigation.PlanRouteToMapTarget = function()
      return nil, { code = "NAVIGATION_ERR_UNSUPPORTED_MAP_LEVEL" }
    end

    Toolbox.NavigationModule.WorldMap.Install()
    WorldMapFrame:Show()

    local targetButton = Toolbox.NavigationModule.WorldMap.GetTargetButton() -- 规划按钮
    targetButton:RunScript("OnClick")

    assert.same({ "当前目标层级暂不支持规划路线，请缩放到区域或子地图后再试。" }, chatMessages)
    assert.is_nil(shownRoute)
  end)
end)
