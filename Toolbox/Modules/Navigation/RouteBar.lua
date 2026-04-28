--[[
  navigation 路径条：在屏幕顶部中间显示当前规划路线的步骤。
  第一版不使用 OnUpdate，不接入拖动；路线变化时由模块主动刷新。
]]

Toolbox.NavigationModule = Toolbox.NavigationModule or {}

local RouteBar = {}
Toolbox.NavigationModule.RouteBar = RouteBar

local routeBarFrame = nil -- 顶部路径条 Frame

--- 拼接路线步骤文本。
---@param routeResult table|nil 路线结果
---@return string
local function buildRouteText(routeResult)
  local stepLabels = type(routeResult) == "table" and routeResult.stepLabels or nil -- 路线步骤列表
  if type(stepLabels) ~= "table" or #stepLabels == 0 then
    return (Toolbox.L or {}).NAVIGATION_ROUTE_EMPTY or ""
  end
  local textParts = {} -- 可显示步骤文本
  for _, stepLabel in ipairs(stepLabels) do
    if stepLabel and stepLabel ~= "" then
      textParts[#textParts + 1] = tostring(stepLabel)
    end
  end
  if #textParts == 0 then
    return (Toolbox.L or {}).NAVIGATION_ROUTE_EMPTY or ""
  end
  return table.concat(textParts, "  >  ")
end

--- 确保顶部路径条已创建并锚定。
---@return table|nil
local function ensureRouteBarFrame()
  if routeBarFrame then
    return routeBarFrame
  end
  if not UIParent or type(CreateFrame) ~= "function" then
    return nil
  end

  routeBarFrame = CreateFrame("Frame", "ToolboxNavigationRouteBar", UIParent, "BackdropTemplate")
  routeBarFrame:SetSize(760, 34)
  routeBarFrame:SetPoint("TOP", UIParent, "TOP", 0, -18)
  routeBarFrame:SetFrameStrata("DIALOG")
  routeBarFrame:EnableMouse(false)
  routeBarFrame:Hide()

  if type(routeBarFrame.SetBackdrop) == "function" then
    routeBarFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    routeBarFrame:SetBackdropColor(0, 0, 0, 0.82)
    routeBarFrame:SetBackdropBorderColor(0.75, 0.62, 0.32, 0.9)
  end

  local textFontString = routeBarFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- 路线步骤文本
  textFontString:SetPoint("LEFT", routeBarFrame, "LEFT", 12, 0)
  textFontString:SetPoint("RIGHT", routeBarFrame, "RIGHT", -12, 0)
  textFontString:SetJustifyH("CENTER")
  textFontString:SetWordWrap(true)
  textFontString:SetText("")
  routeBarFrame._textFontString = textFontString

  return routeBarFrame
end

--- 显示并刷新当前路线。
---@param routeResult table|nil 路线结果
function RouteBar.ShowRoute(routeResult)
  local frame = ensureRouteBarFrame() -- 顶部路径条 Frame
  if not frame then
    return
  end
  local textFontString = frame._textFontString -- 路线步骤文本
  if textFontString then
    textFontString:SetText(buildRouteText(routeResult))
  end
  frame:Show()
end

--- 清除并隐藏当前路线。
function RouteBar.ClearRoute()
  if routeBarFrame and routeBarFrame._textFontString then
    routeBarFrame._textFontString:SetText("")
  end
  if routeBarFrame then
    routeBarFrame:Hide()
  end
end

--- 获取当前路径条 Frame，供测试或后续模块内部刷新使用。
---@return table|nil
function RouteBar.GetFrame()
  return routeBarFrame
end
