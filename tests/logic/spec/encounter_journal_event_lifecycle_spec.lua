local Harness = dofile("tests/logic/harness/harness.lua")

describe("EncounterJournal event lifecycle", function()
  local harness = nil -- 测试 harness
  local moduleDef = nil -- 模块定义

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    moduleDef = harness:loadEncounterJournalModule()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("load_registers_expected_events", function()
    assert.is_true(harness:isEventRegistered("ADDON_LOADED"))
    assert.is_true(harness:isEventRegistered("PLAYER_ENTERING_WORLD"))
    assert.is_true(harness:isEventRegistered("UPDATE_INSTANCE_INFO"))
  end)

  it("disable_unregisters_lockout_event_and_cancels_scheduler", function()
    local hooks = Toolbox.TestHooks.EncounterJournal -- 模块测试 hook
    local scheduler = hooks:getRefreshScheduler() -- 刷新调度器
    scheduler:schedule("lockout_update")
    assert.is_true(#harness.runtime.timer.pending > 0)

    moduleDef.OnEnabledSettingChanged(false)
    assert.is_false(harness:isEventRegistered("UPDATE_INSTANCE_INFO"))
    harness:runAllTimers()
    assert.is_true(harness:getTimerCancelCount() >= 1)
  end)

  it("addon_loaded_blizzard_encounterjournal_init_once", function()
    local beforeCount = harness:getRequestRaidInfoCallCount() -- 触发前调用次数
    harness:emit("ADDON_LOADED", "Blizzard_EncounterJournal")
    local afterFirstCount = harness:getRequestRaidInfoCallCount() -- 首次触发后次数
    harness:emit("ADDON_LOADED", "Blizzard_EncounterJournal")
    local afterSecondCount = harness:getRequestRaidInfoCallCount() -- 二次触发后次数

    assert.equals(beforeCount + 1, afterFirstCount)
    assert.equals(afterFirstCount, afterSecondCount)
    assert.is_false(harness:isEventRegistered("ADDON_LOADED"))
  end)

  it("player_entering_world_requests_raidinfo_once", function()
    local beforeCount = harness:getRequestRaidInfoCallCount() -- 触发前调用次数
    harness:emit("PLAYER_ENTERING_WORLD")
    local afterFirstCount = harness:getRequestRaidInfoCallCount() -- 首次触发后次数
    harness:emit("PLAYER_ENTERING_WORLD")
    local afterSecondCount = harness:getRequestRaidInfoCallCount() -- 二次触发后次数

    assert.equals(beforeCount + 1, afterFirstCount)
    assert.equals(afterFirstCount, afterSecondCount)
    assert.is_false(harness:isEventRegistered("PLAYER_ENTERING_WORLD"))
  end)

  it("refresh_reloads_saved_view_state_after_widgets_exist", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = {},
            progress = { completed = 0, total = 0 },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {},
            progress = { completed = 0, total = 0 },
          },
        },
        questLineByID = {},
        questToQuestLineID = {},
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end

    local hooks = Toolbox.TestHooks.EncounterJournal -- 模块测试 hook
    assert.is_function(hooks.getQuestlineTreeView)
    local treeView = hooks.getQuestlineTreeView()
    treeView:refresh()
    assert.equals("status", treeView.selectedView)

    harness.moduleDb.questViewMode = "map"
    harness.moduleDb.questViewSelectedMapID = 1
    treeView:refresh()
    assert.equals("map", treeView.selectedView)
    assert.equals(1, treeView.selectedMapID)
  end)
end)
