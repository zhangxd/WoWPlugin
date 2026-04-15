--[[
  fake_frame：离线测试 Frame 替身。
  目标：覆盖事件注册、脚本绑定、HookScript 与手动触发能力。
]]

local FakeFrame = {}
FakeFrame.__index = FakeFrame

function FakeFrame.new(options)
  local opts = options or {} -- 构造参数
  local self = setmetatable({}, FakeFrame) -- Frame 实例
  self.frameType = opts.frameType or "Frame" -- 框体类型
  self.frameName = opts.frameName -- 框体名
  self.parentFrame = opts.parentFrame -- 父框体
  self.templateName = opts.templateName -- 模板名
  self.traceList = opts.traceList or {} -- 行为追踪
  self.registeredEvents = {} -- 已注册事件集合
  self.scriptHandlers = {} -- SetScript 处理器
  self.hookedHandlers = {} -- HookScript 处理器列表
  self.ownedBy = nil -- Tooltip 所有者等场景标记
  self._isShown = false -- 是否显示
  self._text = "" -- 文本缓存
  self._width = 0 -- 宽度缓存
  self._height = 0 -- 高度缓存
  self._id = nil -- ID 缓存
  self._scrollChild = nil -- 滚动子容器
  self._verticalScroll = 0 -- 垂直滚动偏移
  self._highlightTexture = nil -- 高亮贴图替身
  self._textColor = nil -- 文本颜色缓存
  self._points = {} -- 锚点记录
  return self
end

function FakeFrame:RegisterEvent(eventName)
  self.registeredEvents[eventName] = true
  self.traceList[#self.traceList + 1] = {
    kind = "event_register",
    frameName = self.frameName,
    eventName = eventName,
  }
end

function FakeFrame:UnregisterEvent(eventName)
  self.registeredEvents[eventName] = nil
  self.traceList[#self.traceList + 1] = {
    kind = "event_unregister",
    frameName = self.frameName,
    eventName = eventName,
  }
end

function FakeFrame:SetScript(scriptName, handler)
  self.scriptHandlers[scriptName] = handler
  self.traceList[#self.traceList + 1] = {
    kind = "script_set",
    frameName = self.frameName,
    scriptName = scriptName,
  }
end

function FakeFrame:GetScript(scriptName)
  return self.scriptHandlers[scriptName]
end

function FakeFrame:HookScript(scriptName, handler)
  if type(self.hookedHandlers[scriptName]) ~= "table" then
    self.hookedHandlers[scriptName] = {}
  end
  self.hookedHandlers[scriptName][#self.hookedHandlers[scriptName] + 1] = handler
  self.traceList[#self.traceList + 1] = {
    kind = "script_hook",
    frameName = self.frameName,
    scriptName = scriptName,
  }
end

function FakeFrame:EmitEvent(eventName, ...)
  if not self.registeredEvents[eventName] then
    return false
  end
  local onEventHandler = self.scriptHandlers.OnEvent -- OnEvent 处理器
  if type(onEventHandler) == "function" then
    onEventHandler(self, eventName, ...)
  end
  return true
end

function FakeFrame:RunScript(scriptName, ...)
  local scriptHandler = self.scriptHandlers[scriptName] -- 主脚本处理器
  if type(scriptHandler) == "function" then
    scriptHandler(self, ...)
  end
  local hookList = self.hookedHandlers[scriptName] -- Hook 回调列表
  if type(hookList) == "table" then
    for _, hookHandler in ipairs(hookList) do
      if type(hookHandler) == "function" then
        hookHandler(self, ...)
      end
    end
  end
end

function FakeFrame:SetShown(shouldShow)
  self._isShown = shouldShow == true
end

function FakeFrame:Show()
  local wasShown = self._isShown == true -- 显示前状态
  self._isShown = true
  if not wasShown then
    self:RunScript("OnShow")
  end
end

function FakeFrame:Hide()
  local wasShown = self._isShown == true -- 隐藏前状态
  self._isShown = false
  if wasShown then
    self:RunScript("OnHide")
  end
end

function FakeFrame:IsShown()
  return self._isShown == true
end

function FakeFrame:SetText(text)
  self._text = text or ""
end

function FakeFrame:GetText()
  return self._text
end
function FakeFrame:GetTextWidth()
  return #(self._text or "") * 8
end
function FakeFrame:SetTitle(text)
  self._title = text or ""
end
function FakeFrame:SetPortraitToAsset(assetPath)
  self._portraitAsset = assetPath
end
function FakeFrame:SetPortraitTexture(assetPath)
  self._portraitAsset = assetPath
end
function FakeFrame:SetAutoFocus(value)
  self._autoFocus = value == true
end
function FakeFrame:SetMaxLetters(value)
  self._maxLetters = tonumber(value) or 0
end
function FakeFrame:SetTextInsets(leftValue, rightValue, topValue, bottomValue)
  self._textInsets = {
    tonumber(leftValue) or 0,
    tonumber(rightValue) or 0,
    tonumber(topValue) or 0,
    tonumber(bottomValue) or 0,
  }
end
function FakeFrame:HasFocus()
  return self._hasFocus == true
end
function FakeFrame:ClearFocus()
  self._hasFocus = false
end
function FakeFrame:SetFocus()
  self._hasFocus = true
end

function FakeFrame:SetChecked(value)
  self._checked = value == true
end

function FakeFrame:GetChecked()
  return self._checked == true
end

function FakeFrame:IsMouseOver()
  return false
end

function FakeFrame:SetPoint(pointName, arg2, arg3, arg4, arg5)
  local pointRecord = {
    point = pointName,
    relativeFrame = nil,
    relativePoint = nil,
    x = 0,
    y = 0,
  } -- 当前锚点记录

  if type(arg2) == "number" or arg2 == nil then
    pointRecord.x = tonumber(arg2) or 0
    pointRecord.y = tonumber(arg3) or 0
  else
    pointRecord.relativeFrame = arg2
    pointRecord.relativePoint = arg3
    pointRecord.x = tonumber(arg4) or 0
    pointRecord.y = tonumber(arg5) or 0
  end

  self._points[#self._points + 1] = pointRecord
end
function FakeFrame:SetSize(widthValue, heightValue)
  self._width = tonumber(widthValue) or self._width
  self._height = tonumber(heightValue) or self._height
end
function FakeFrame:SetWidth(widthValue)
  self._width = tonumber(widthValue) or self._width
end
function FakeFrame:SetHeight(heightValue)
  self._height = tonumber(heightValue) or self._height
end
function FakeFrame:GetWidth()
  return self._width
end
function FakeFrame:GetHeight()
  return self._height
end
function FakeFrame:SetJustifyH() end
function FakeFrame:SetJustifyV() end
function FakeFrame:SetWordWrap() end
function FakeFrame:SetTextColor(redValue, greenValue, blueValue)
  self._textColor = {
    tonumber(redValue) or 0,
    tonumber(greenValue) or 0,
    tonumber(blueValue) or 0,
  }
end
function FakeFrame:GetTextColor()
  if type(self._textColor) == "table" then
    return self._textColor[1], self._textColor[2], self._textColor[3]
  end
  return nil
end
function FakeFrame:GetStringWidth()
  return #(self._text or "") * 8
end
function FakeFrame:GetStringHeight()
  return 16
end
function FakeFrame:SetAlpha() end
function FakeFrame:SetBackdrop(backdropTable)
  self._backdrop = backdropTable
end
function FakeFrame:SetBackdropColor(redValue, greenValue, blueValue, alphaValue)
  self._backdropColor = {
    tonumber(redValue) or 0,
    tonumber(greenValue) or 0,
    tonumber(blueValue) or 0,
    tonumber(alphaValue) or 0,
  }
end
function FakeFrame:SetBackdropBorderColor(redValue, greenValue, blueValue, alphaValue)
  self._backdropBorderColor = {
    tonumber(redValue) or 0,
    tonumber(greenValue) or 0,
    tonumber(blueValue) or 0,
    tonumber(alphaValue) or 0,
  }
end
function FakeFrame:RegisterForDrag() end
function FakeFrame:RegisterForClicks() end
function FakeFrame:EnableMouse() end
function FakeFrame:SetFrameStrata() end
function FakeFrame:SetFrameLevel() end
function FakeFrame:ClearAllPoints()
  self._points = {}
end
function FakeFrame:GetEffectiveScale() return 1 end
function FakeFrame:GetTop() return 0 end
function FakeFrame:GetVerticalScroll()
  return self._verticalScroll or 0
end
function FakeFrame:SetVerticalScroll(scrollValue)
  self._verticalScroll = tonumber(scrollValue) or 0
end
function FakeFrame:SetScrollChild(childFrame)
  self._scrollChild = childFrame
end
function FakeFrame:GetScrollChild()
  return self._scrollChild
end
function FakeFrame:SetMinMaxValues() end
function FakeFrame:SetValueStep() end
function FakeFrame:SetObeyStepOnDrag() end
function FakeFrame:SetValue() end
function FakeFrame:GetValue() return 0 end
function FakeFrame:SetEnabled(enabled)
  self._enabled = enabled ~= false
end
function FakeFrame:IsEnabled()
  if self._enabled == nil then
    return true
  end
  return self._enabled == true
end
function FakeFrame:Disable()
  self._enabled = false
end
function FakeFrame:Enable()
  self._enabled = true
end
function FakeFrame:SetMotionScriptsWhileDisabled(enabled)
  self._motionScriptsWhileDisabled = enabled == true
end
function FakeFrame:SetID(idValue)
  self._id = idValue
end
function FakeFrame:GetID()
  return self._id
end
function FakeFrame:SetParent(parentFrame)
  self.parentFrame = parentFrame
end
function FakeFrame:SetHighlightTexture()
  self._highlightTexture = FakeFrame.new({
    frameType = "Texture",
    frameName = nil,
    parentFrame = self,
    traceList = self.traceList,
  })
  return self._highlightTexture
end
function FakeFrame:GetHighlightTexture()
  return self._highlightTexture
end

function FakeFrame:CreateFontString()
  local fontString = FakeFrame.new({
    frameType = "FontString",
    frameName = nil,
    parentFrame = self,
    traceList = self.traceList,
  })
  return fontString
end

function FakeFrame:CreateTexture()
  local textureObject = FakeFrame.new({
    frameType = "Texture",
    frameName = nil,
    parentFrame = self,
    traceList = self.traceList,
  })
  return textureObject
end

function FakeFrame:SetColorTexture(redValue, greenValue, blueValue, alphaValue)
  self._colorTexture = {
    tonumber(redValue) or 0,
    tonumber(greenValue) or 0,
    tonumber(blueValue) or 0,
    tonumber(alphaValue) or 0,
  }
end

return FakeFrame
