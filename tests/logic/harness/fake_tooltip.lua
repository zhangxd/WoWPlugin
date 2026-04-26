--[[
  fake_tooltip：记录 tooltip 行内容与展示状态。
]]

local FakeTooltip = {}
FakeTooltip.__index = FakeTooltip

function FakeTooltip.new(traceList)
  local self = setmetatable({}, FakeTooltip) -- Tooltip 实例
  self.traceList = traceList or {} -- 行为追踪
  self.lines = {} -- AddLine 记录
  self.titleText = nil -- SetText 标题
  self.ownerFrame = nil -- Owner 框体
  self.ownerAnchor = nil -- Owner 锚点
  self.setOwnerCount = 0 -- SetOwner 调用次数
  self.anchorType = nil -- SetAnchorType 锚点类型
  self.anchorOffsetX = nil -- SetAnchorType X 偏移
  self.anchorOffsetY = nil -- SetAnchorType Y 偏移
  self.setAnchorTypeCount = 0 -- SetAnchorType 调用次数
  self.showCount = 0 -- Show 调用次数
  self.hideCount = 0 -- Hide 调用次数
  return self
end

function FakeTooltip:SetOwner(ownerFrame, anchorType)
  self.setOwnerCount = self.setOwnerCount + 1
  self.ownerFrame = ownerFrame
  self.ownerAnchor = anchorType
  self.traceList[#self.traceList + 1] = {
    kind = "tooltip_set_owner",
    anchorType = anchorType,
  }
end

function FakeTooltip:SetAnchorType(anchorType, offsetX, offsetY)
  self.setAnchorTypeCount = self.setAnchorTypeCount + 1
  self.anchorType = anchorType
  self.anchorOffsetX = offsetX
  self.anchorOffsetY = offsetY
  self.traceList[#self.traceList + 1] = {
    kind = "tooltip_set_anchor_type",
    anchorType = anchorType,
    offsetX = offsetX,
    offsetY = offsetY,
  }
end

function FakeTooltip:ClearLines()
  self.lines = {}
  self.titleText = nil
  self.traceList[#self.traceList + 1] = { kind = "tooltip_clear" }
end

function FakeTooltip:SetText(text)
  self.titleText = text
  self.traceList[#self.traceList + 1] = {
    kind = "tooltip_set_text",
    text = text,
  }
end

function FakeTooltip:AddLine(text, red, green, blue, wrapText)
  local normalizedText = text == nil and "" or tostring(text) -- 文本行
  self.lines[#self.lines + 1] = normalizedText
  self.traceList[#self.traceList + 1] = {
    kind = "tooltip_add_line",
    text = normalizedText,
    red = red,
    green = green,
    blue = blue,
    wrapText = wrapText,
  }
end

function FakeTooltip:Show()
  self.showCount = self.showCount + 1
  self.traceList[#self.traceList + 1] = { kind = "tooltip_show" }
end

function FakeTooltip:Hide()
  self.hideCount = self.hideCount + 1
  self.traceList[#self.traceList + 1] = { kind = "tooltip_hide" }
end

function FakeTooltip:IsOwned(ownerFrame)
  return self.ownerFrame == ownerFrame
end

return FakeTooltip
