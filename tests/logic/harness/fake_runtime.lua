--[[
  fake_runtime：聚合 fake frame/timer/tooltip，供模块通过 Toolbox.Runtime 调用。
]]

local FakeFrame = dofile("tests/logic/harness/fake_frame.lua")
local FakeTimer = dofile("tests/logic/harness/fake_timer.lua")
local FakeTooltip = dofile("tests/logic/harness/fake_tooltip.lua")

local function buildAddOnLoadedMap(seedTable)
  local loadedMap = {} -- AddOn 加载状态映射
  if type(seedTable) == "table" then
    for addonName, loaded in pairs(seedTable) do
      loadedMap[addonName] = loaded == true
    end
  end
  return loadedMap
end

local function newFakeRuntime(options)
  local opts = options or {} -- 构造参数
  local traceList = opts.traceList or {} -- 行为追踪列表
  local fakeTimer = FakeTimer.new(traceList) -- fake 定时器
  local fakeTooltip = FakeTooltip.new(traceList) -- fake tooltip
  local addonLoadedMap = buildAddOnLoadedMap(opts.addonLoadedSeed) -- AddOn 加载映射
  local frameByName = {} -- 命名 Frame 索引

  local runtime = { -- 运行时替身
    __isTesting = true,
    traceList = traceList,
    timer = fakeTimer,
    tooltip = fakeTooltip,
    frameByName = frameByName,
    addonLoadedMap = addonLoadedMap,
  }

  function runtime.CreateFrame(frameType, frameName, parentFrame, templateName)
    local frameRef = FakeFrame.new({
      frameType = frameType,
      frameName = frameName,
      parentFrame = parentFrame,
      templateName = templateName,
      traceList = traceList,
    })
    if type(frameName) == "string" and frameName ~= "" then
      frameByName[frameName] = frameRef
      _G[frameName] = frameRef
    end
    traceList[#traceList + 1] = {
      kind = "frame_create",
      frameType = frameType,
      frameName = frameName,
      templateName = templateName,
    }
    return frameRef
  end

  function runtime.NewTimer(delaySeconds, callback)
    return fakeTimer:newTimer(delaySeconds, callback)
  end

  function runtime.After(delaySeconds, callback)
    return fakeTimer:after(delaySeconds, callback)
  end

  function runtime.IsAddOnLoaded(addonName)
    return addonLoadedMap[addonName] == true
  end

  function runtime.LoadAddOn(addonName)
    addonLoadedMap[addonName] = true
    traceList[#traceList + 1] = {
      kind = "addon_load",
      addonName = addonName,
    }
    return true
  end

  function runtime.TooltipSetOwner(tooltipObject, ownerFrame, anchorType)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:SetOwner(ownerFrame, anchorType)
  end

  function runtime.TooltipClear(tooltipObject)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:ClearLines()
  end

  function runtime.TooltipSetText(tooltipObject, text)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:SetText(text)
  end

  function runtime.TooltipAddLine(tooltipObject, text, red, green, blue, wrapText)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:AddLine(text, red, green, blue, wrapText)
  end

  function runtime.TooltipShow(tooltipObject)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:Show()
  end

  function runtime.TooltipHide(tooltipObject)
    local tooltipRef = tooltipObject or fakeTooltip -- 目标 tooltip
    tooltipRef:Hide()
  end

  return runtime
end

return newFakeRuntime
