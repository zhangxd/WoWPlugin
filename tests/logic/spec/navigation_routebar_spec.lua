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

  it("renders_total_steps_and_segments_at_the_top_center_and_hides_when_cleared", function()
    Toolbox.NavigationModule.RouteBar.ShowRoute({
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
          toName = "杜隆塔尔目标点",
          traversedUiMapNames = { "杜隆塔尔" },
        },
      },
    })

    local routeBarFrame = createdFrameByName.ToolboxNavigationRouteBar -- 路径条 Frame
    assert.is_table(routeBarFrame)
    assert.is_true(routeBarFrame:IsShown())
    assert.equals("TOP", routeBarFrame._points[1].point)
    assert.is_true(string.find(routeBarFrame._textFontString:GetText(), "2", 1, true) ~= nil)
    assert.is_true(string.find(routeBarFrame._textFontString:GetText(), "class_teleport", 1, true) ~= nil)
    assert.is_true(string.find(routeBarFrame._textFontString:GetText(), "当前位置", 1, true) ~= nil)
    assert.is_true(string.find(routeBarFrame._textFontString:GetText(), "杜隆塔尔", 1, true) ~= nil)

    Toolbox.NavigationModule.RouteBar.ClearRoute()
    assert.is_false(routeBarFrame:IsShown())
  end)
end)
