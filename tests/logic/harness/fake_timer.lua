--[[
  fake_timer：离线测试定时器驱动。
  能力：
    1. 记录创建、取消、触发行为。
    2. 提供 advance/runAll 以可控时钟推进回调执行。
]]

local FakeTimer = {}
FakeTimer.__index = FakeTimer

function FakeTimer.new(traceList)
  local self = setmetatable({}, FakeTimer) -- 定时器实例
  self.now = 0 -- 当前模拟时间（秒）
  self.sequence = 0 -- 创建序号（稳定排序）
  self.pending = {} -- 未触发任务列表
  self.traceList = traceList or {} -- 行为追踪列表
  return self
end

local function sortPending(pendingList)
  table.sort(pendingList, function(leftItem, rightItem)
    if leftItem.due == rightItem.due then
      return leftItem.sequence < rightItem.sequence
    end
    return leftItem.due < rightItem.due
  end)
end

function FakeTimer:_create(kindName, delaySeconds, callback)
  self.sequence = self.sequence + 1
  local timerRef = { -- 定时器句柄
    kind = kindName,
    due = self.now + (tonumber(delaySeconds) or 0),
    callback = callback,
    canceled = false,
    sequence = self.sequence,
  }
  function timerRef:Cancel()
    self.canceled = true
  end
  self.pending[#self.pending + 1] = timerRef
  self.traceList[#self.traceList + 1] = {
    kind = "timer_create",
    timerKind = kindName,
    due = timerRef.due,
    sequence = timerRef.sequence,
  }
  sortPending(self.pending)
  return timerRef
end

function FakeTimer:newTimer(delaySeconds, callback)
  return self:_create("new_timer", delaySeconds, callback)
end

function FakeTimer:after(delaySeconds, callback)
  return self:_create("after", delaySeconds, callback)
end

function FakeTimer:advance(seconds)
  local deltaSeconds = tonumber(seconds) or 0 -- 推进秒数
  if deltaSeconds < 0 then
    deltaSeconds = 0
  end
  self.now = self.now + deltaSeconds
  sortPending(self.pending)

  local firedCount = 0 -- 本轮触发计数
  local index = 1 -- 遍历索引
  while index <= #self.pending do
    local timerRef = self.pending[index]
    if timerRef.due > self.now then
      break
    end
    table.remove(self.pending, index)
    if timerRef.canceled then
      self.traceList[#self.traceList + 1] = {
        kind = "timer_skip_canceled",
        timerKind = timerRef.kind,
        sequence = timerRef.sequence,
      }
    else
      self.traceList[#self.traceList + 1] = {
        kind = "timer_fire",
        timerKind = timerRef.kind,
        sequence = timerRef.sequence,
      }
      if type(timerRef.callback) == "function" then
        timerRef.callback()
      end
      firedCount = firedCount + 1
      sortPending(self.pending)
    end
  end
  return firedCount
end

function FakeTimer:runAll()
  local guard = 0 -- 防止死循环
  while #self.pending > 0 do
    guard = guard + 1
    if guard > 1000 then
      error("fake_timer: too many pending timers (possible infinite loop)")
    end
    sortPending(self.pending)
    local nextDue = self.pending[1] and self.pending[1].due or self.now
    self.now = nextDue
    self:advance(0)
  end
end

return FakeTimer
