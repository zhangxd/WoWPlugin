local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")

describe("Navigation RouteBar", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalUIParent = nil -- 原始 UIParent 全局
  local createdFrameByName = nil -- 已创建命名 Frame

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalUIParent = rawget(_G, "UIParent")
    createdFrameByName = {}

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
    rawset(_G, "Toolbox", {
      NavigationModule = {},
      L = {
        NAVIGATION_ROUTE_EMPTY = "暂无路线",
      },
    })

    local routeBarChunk = assert(loadfile("Toolbox/Modules/Navigation/RouteBar.lua")) -- 路径条 chunk
    routeBarChunk()
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "CreateFrame", originalCreateFrame)
    rawset(_G, "UIParent", originalUIParent)
    rawset(_G, "ToolboxNavigationRouteBar", nil)
  end)

  it("shows_route_steps_at_the_top_center_and_hides_when_cleared", function()
    Toolbox.NavigationModule.RouteBar.ShowRoute({
      stepLabels = { "传送：奥格瑞玛", "从奥格瑞玛前往杜隆塔尔目标" },
      totalCost = 35,
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路径条 Frame
    assert.is_table(routeBarFrame)
    assert.is_true(routeBarFrame:IsShown())
    assert.equals("TOP", routeBarFrame._points[1].point)
    assert.equals("传送：奥格瑞玛  >  从奥格瑞玛前往杜隆塔尔目标", routeBarFrame._textFontString:GetText())

    Toolbox.NavigationModule.RouteBar.ClearRoute()
    assert.is_false(routeBarFrame:IsShown())
  end)
end)
