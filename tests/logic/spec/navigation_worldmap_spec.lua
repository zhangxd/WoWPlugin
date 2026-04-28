local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")

describe("Navigation WorldMap integration", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalWorldMapFrame = nil -- 原始 WorldMapFrame 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local shownRoute = nil -- RouteBar 显示的路线
  local chatMessages = nil -- 聊天提示记录

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalWorldMapFrame = rawget(_G, "WorldMapFrame")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalCMap = rawget(_G, "C_Map")
    shownRoute = nil
    chatMessages = {}

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
          ShowRoute = function(routeResult)
            shownRoute = routeResult
          end,
        },
      },
      Chat = {
        PrintAddonMessage = function(messageText)
          chatMessages[#chatMessages + 1] = messageText
        end,
      },
      Config = {
        GetModule = function()
          return {
            enabled = true,
            lastTargetUiMapID = 0,
            lastTargetX = 0,
            lastTargetY = 0,
          }
        end,
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
