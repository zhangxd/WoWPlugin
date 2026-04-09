local Harness = dofile("tests/logic/harness/harness.lua")

describe("EncounterJournal refresh scheduler", function()
  local harness = nil -- 测试 harness
  local scheduler = nil -- 刷新调度器

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    harness:loadEncounterJournalModule()
    scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("refresh_scheduler_debounce_keeps_latest_token", function()
    local executeCount = 0 -- 执行次数
    local originalExecute = scheduler.execute -- 原始执行函数
    scheduler.execute = function(self)
      executeCount = executeCount + 1
      return originalExecute(self)
    end

    scheduler:schedule("lockout_update")
    scheduler:schedule("list_refresh")
    harness:runAllTimers()

    scheduler.execute = originalExecute
    assert.equals(1, executeCount)
    assert.is_true(harness:getTimerCancelCount() >= 1)
  end)
end)
