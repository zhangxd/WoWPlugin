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
  self._isShown = true
end

function FakeFrame:Hide()
  self._isShown = false
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

function FakeFrame:SetChecked(value)
  self._checked = value == true
end

function FakeFrame:GetChecked()
  return self._checked == true
end

function FakeFrame:IsMouseOver()
  return false
end

function FakeFrame:SetPoint() end
function FakeFrame:SetSize() end
function FakeFrame:SetWidth() end
function FakeFrame:SetHeight() end
function FakeFrame:SetJustifyH() end
function FakeFrame:SetWordWrap() end
function FakeFrame:SetAlpha() end
function FakeFrame:SetBackdrop() end
function FakeFrame:SetBackdropColor() end
function FakeFrame:SetBackdropBorderColor() end
function FakeFrame:RegisterForDrag() end
function FakeFrame:RegisterForClicks() end
function FakeFrame:EnableMouse() end
function FakeFrame:SetFrameStrata() end
function FakeFrame:SetFrameLevel() end
function FakeFrame:ClearAllPoints() end
function FakeFrame:GetEffectiveScale() return 1 end
function FakeFrame:GetTop() return 0 end
function FakeFrame:GetVerticalScroll() return 0 end
function FakeFrame:SetVerticalScroll() end
function FakeFrame:SetScrollChild() end
function FakeFrame:SetMinMaxValues() end
function FakeFrame:SetValueStep() end
function FakeFrame:SetObeyStepOnDrag() end
function FakeFrame:SetValue() end
function FakeFrame:GetValue() return 0 end
function FakeFrame:SetEnabled() end
function FakeFrame:Disable() end
function FakeFrame:Enable() end

function FakeFrame:CreateFontString()
  local fontString = FakeFrame.new({
    frameType = "FontString",
    frameName = nil,
    parentFrame = self,
    traceList = self.traceList,
  })
  return fontString
end

return FakeFrame
