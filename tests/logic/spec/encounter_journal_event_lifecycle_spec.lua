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

  it("quest_module_refresh_reloads_saved_navigation_state_after_widgets_exist", function()
    harness:loadQuestModule()
    local questFrame = harness.runtime.CreateFrame("Frame", "ToolboxQuestFrame") -- quest 根框体
    questFrame:Show()
    rawset(_G, "ToolboxQuestFrame", questFrame)

    harness.questModuleDb.questNavExpansionID = 10
    harness.questModuleDb.questNavModeKey = "map_questline"
    harness.questModuleDb.questNavSelectedMapID = 2472
    harness.questModuleDb.questNavExpandedQuestLineID = 101

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
          { id = 10, name = "地心之战" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              { key = "map_questline", name = "地图任务线", entries = {} },
            },
            modeByKey = {
              map_questline = { key = "map_questline", name = "地图任务线", entries = {} },
            },
          },
          [10] = {
            id = 10,
            name = "地心之战",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2472, name = "多恩岛", kind = "map" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2472, name = "多恩岛", kind = "map" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "任务一", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function(mapID)
      if mapID == 2472 then
        return {
          { id = 101, name = "多恩岛起始线", UiMapID = 2472, questCount = 1 },
        }, nil
      end
      return {}, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 1 }, nil
    end

    local treeView = Toolbox.TestHooks.Quest:getView()
    treeView:setSelected(true)
    treeView:refresh()

    assert.equals(10, treeView.selectedExpansionID)
    assert.equals("map_questline", treeView.selectedModeKey)
    assert.equals(2472, treeView.selectedMapID)
    assert.equals(101, treeView.expandedQuestLineID)
  end)
end)
