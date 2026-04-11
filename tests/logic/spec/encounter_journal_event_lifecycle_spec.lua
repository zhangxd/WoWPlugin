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

  it("refresh_defaults_left_tree_to_collapsed_nodes", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)
    harness.moduleDb.questViewMode = "map"

    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002 },
            questCount = 2,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForSelection = function()
      return {
        {
          id = 101,
          name = "QuestLine #101",
          UiMapID = 1,
          questCount = 2,
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "pending", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 0, total = 2 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local visibleCount = 0 -- 左树可见行数量
    for _, rowButton in ipairs(treeView.rowButtons) do
      if rowButton:IsShown() then
        visibleCount = visibleCount + 1
      end
    end

    assert.equals(1, visibleCount)
    assert.equals("map", treeView.rowButtons[1].rowData.kind)
  end)

  it("status_view_lists_current_tasks_and_renders_selected_questline", function()
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
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002, 1003 },
                questCount = 3,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002, 1003 },
                questCount = 3,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002, 1003 },
            questCount = 3,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
          [1003] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "active", readyForTurnIn = true, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 1003, name = "Quest #1003", status = "pending", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {
        { questID = 1001, name = "Quest #1001", status = "active", readyForTurnIn = true, questLineID = 101, questLineName = "QuestLine #101", UiMapID = 1 },
        { questID = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, questLineID = 101, questLineName = "QuestLine #101", UiMapID = 1 },
        { questID = 1004, name = "Quest #1004", status = "active", readyForTurnIn = false, questLineID = nil, questLineName = nil, UiMapID = nil },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      local detailByID = {
        [1001] = {
          questID = 1001,
          name = "Quest #1001",
          status = "active",
          readyForTurnIn = true,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        },
        [1002] = {
          questID = 1002,
          name = "Quest #1002",
          status = "active",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        },
        [1003] = {
          questID = 1003,
          name = "Quest #1003",
          status = "pending",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        },
      }
      return detailByID[questID], nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 0, total = 3 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 3 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local leftTexts = {} -- 状态视图左侧当前任务文本
    for _, rowButton in ipairs(treeView.rowButtons) do
      if rowButton:IsShown() then
        leftTexts[#leftTexts + 1] = rowButton.rowFont:GetText()
      end
    end

    assert.equals(3, #leftTexts)
    assert.is_true(string.find(leftTexts[1], "Quest #1001", 1, true) ~= nil)
    assert.is_true(string.find(leftTexts[2], "Quest #1002", 1, true) ~= nil)
    assert.is_true(string.find(leftTexts[3], "Quest #1004", 1, true) ~= nil)
    assert.equals("quest", treeView.selectedKind)
    assert.equals(1001, treeView.selectedQuestID)

    local rightRowList = {} -- 右侧完整任务线行
    for _, rowButton in ipairs(treeView.rightRowButtons) do
      if rowButton:IsShown() then
        rightRowList[#rightRowList + 1] = rowButton.rowData
      end
    end

    assert.equals(3, #rightRowList)
    assert.equals(1001, rightRowList[1].questID)
    assert.equals(true, rightRowList[1].selected)
    assert.equals(1002, rightRowList[2].questID)
    assert.equals(false, rightRowList[2].selected == true)
    assert.equals(1003, rightRowList[3].questID)
  end)

  it("completed_tasks_render_in_green", function()
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
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002, 1003 },
                questCount = 3,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002, 1003 },
                questCount = 3,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002, 1003 },
            questCount = 3,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
          [1003] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {
        { questID = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, questLineID = 101, questLineName = "QuestLine #101", UiMapID = 1 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "completed", readyForTurnIn = false, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 1003, name = "Quest #1003", status = "pending", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 1002 then
        return {
          questID = 1002,
          name = "Quest #1002",
          status = "active",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        }, nil
      end
      return nil, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local completedRowButton = treeView.rightRowButtons[1]
    assert.is_truthy(completedRowButton)
    local redValue, greenValue, blueValue = completedRowButton.rowFont:GetTextColor()

    assert.equals(0.2, redValue)
    assert.equals(0.8, greenValue)
    assert.equals(0.2, blueValue)
  end)

  it("map_view_left_completed_task_renders_in_green", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    harness.moduleDb.questViewMode = "map"
    harness.moduleDb.questViewSelectedMapID = 1
    harness.moduleDb.questViewSelectedQuestLineID = 101
    harness.moduleDb.questViewSelectedQuestID = 1002

    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002 },
            questCount = 2,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "completed", readyForTurnIn = false, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 1001 or questID == 1002 then
        return {
          questID = questID,
          name = "Quest #" .. tostring(questID),
          status = questID == 1001 and "completed" or "active",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        }, nil
      end
      return nil, nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 1, total = 2 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local completedRowButton = nil -- 已完成任务行按钮
    for _, rowButton in ipairs(treeView.rowButtons) do
      if rowButton:IsShown() and type(rowButton.rowData) == "table" and rowButton.rowData.questID == 1001 then
        completedRowButton = rowButton
        break
      end
    end

    assert.is_truthy(completedRowButton)
    local redValue, greenValue, blueValue = completedRowButton.rowFont:GetTextColor()
    assert.equals(0.2, redValue)
    assert.equals(0.8, greenValue)
    assert.equals(0.2, blueValue)
  end)

  it("type_view_completed_task_renders_in_green", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    harness.moduleDb.questViewMode = "type"
    harness.moduleDb.questViewSelectedTypeID = 12
    harness.moduleDb.questViewSelectedMapID = 1
    harness.moduleDb.questViewSelectedQuestLineID = 101

    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002 },
            questCount = 2,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetQuestTypeIndex = function()
      return {
        typeList = { 12 },
        typeToQuestIDs = {
          [12] = { 1001, 1002 },
        },
        typeToQuestLineIDs = {
          [12] = { 101 },
        },
        typeToMapIDs = {
          [12] = { 1 },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestTypeLabel = function(typeID)
      return "Type #" .. tostring(typeID)
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "completed", readyForTurnIn = false, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 1001 or questID == 1002 then
        return {
          questID = questID,
          name = "Quest #" .. tostring(questID),
          status = questID == 1001 and "completed" or "active",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        }, nil
      end
      return nil, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local completedRowButton = nil -- 未选中的已完成任务行按钮
    for _, rowButton in ipairs(treeView.rightRowButtons) do
      if rowButton:IsShown() and type(rowButton.rowData) == "table" and rowButton.rowData.questID == 1001 then
        completedRowButton = rowButton
        break
      end
    end

    assert.is_truthy(completedRowButton)
    local redValue, greenValue, blueValue = completedRowButton.rowFont:GetTextColor()
    assert.equals(0.2, redValue)
    assert.equals(0.8, greenValue)
    assert.equals(0.2, blueValue)
  end)

  it("status_view_falls_back_to_detail_for_unmapped_current_quest", function()
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
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001 },
                questCount = 1,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001 },
                questCount = 1,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001 },
            questCount = 1,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {
        { questID = 1001, name = "Quest #1001", status = "active", readyForTurnIn = false, questLineID = 101, questLineName = "QuestLine #101", UiMapID = 1 },
        { questID = 1004, name = "Quest #1004", status = "active", readyForTurnIn = false, questLineID = nil, questLineName = nil, UiMapID = nil },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 1001 then
        return {
          questID = 1001,
          name = "Quest #1001",
          status = "active",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        }, nil
      end
      if questID == 1004 then
        return {
          questID = 1004,
          name = "Quest #1004",
          status = "active",
          readyForTurnIn = false,
          UiMapID = 7777,
          typeID = 88,
          questLineID = nil,
          questLineName = nil,
        }, nil
      end
      return nil, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local fallbackRowButton = treeView.rowButtons[2] -- 未映射当前任务
    assert.is_truthy(fallbackRowButton)
    fallbackRowButton:RunScript("OnClick")

    assert.equals(1004, treeView.selectedQuestID)
    assert.is_true(treeView.detailText:IsShown())
    assert.is_false(treeView.rightScrollFrame:IsShown())
    assert.is_true(string.find(treeView.detailText:GetText(), "Quest #1004", 1, true) ~= nil)
  end)

  it("refresh_expands_saved_quest_selection_path", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    harness.moduleDb.questViewMode = "map"
    harness.moduleDb.questViewSelectedMapID = 1
    harness.moduleDb.questViewSelectedQuestLineID = 101
    harness.moduleDb.questViewSelectedQuestID = 1002

    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001, 1002 },
                questCount = 2,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001, 1002 },
            questCount = 2,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
          [1002] = 101,
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForSelection = function()
      return {
        {
          id = 101,
          name = "QuestLine #101",
          UiMapID = 1,
          questCount = 2,
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 1002, name = "Quest #1002", status = "pending", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 1002 then
        return {
          questID = 1002,
          name = "Quest #1002",
          status = "pending",
          readyForTurnIn = false,
          UiMapID = 1,
          typeID = 12,
          questLineID = 101,
          questLineName = "QuestLine #101",
        }, nil
      end
      return nil, nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 0, total = 2 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local visibleCount = 0 -- 左树可见行数量
    for _, rowButton in ipairs(treeView.rowButtons) do
      if rowButton:IsShown() then
        visibleCount = visibleCount + 1
      end
    end

    assert.equals(4, visibleCount)
    assert.equals("quest", treeView.selectedKind)
    assert.equals(1002, treeView.selectedQuestID)
  end)

  it("toggle_tree_node_preserves_left_scroll_offset", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)
    harness.moduleDb.questViewMode = "map"

    harness.moduleDb.questlineTreeCollapsed = {
      ["map:1"] = false,
    }

    Toolbox.Questlines.GetQuestTabModel = function()
      local questLineList = {} -- 地图下任务线列表
      local questLineByID = {} -- 任务线索引
      for index = 1, 12 do
        local questLineID = 100 + index -- 当前任务线 ID
        local questLineEntry = {
          id = questLineID,
          name = "QuestLine #" .. tostring(questLineID),
          UiMapID = 1,
          questIDs = { 1000 + index },
          questCount = 1,
        }
        questLineList[#questLineList + 1] = questLineEntry
        questLineByID[questLineID] = questLineEntry
      end

      return {
        maps = {
          {
            id = 1,
            name = "Map #1",
            questLines = questLineList,
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = questLineList,
          },
        },
        questLineByID = questLineByID,
        questToQuestLineID = {},
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 0, total = 12 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 1 }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function(questLineID)
      return {
        {
          id = 1000 + (tonumber(questLineID) or 0),
          name = "Quest #" .. tostring(questLineID),
          status = "active",
          readyForTurnIn = false,
          typeID = 12,
        },
      }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)
    treeView.scrollFrame:SetVerticalScroll(84)

    local toggleRowButton = treeView.rowButtons[6] -- 中部任务线节点
    assert.is_truthy(toggleRowButton)
    assert.equals("questline", toggleRowButton.rowData.kind)
    toggleRowButton:RunScript("OnClick")

    assert.equals(84, treeView.scrollFrame:GetVerticalScroll())
    assert.equals("questline", treeView.selectedKind)
    assert.equals(toggleRowButton.rowData.questLineID, treeView.selectedQuestLineID)
  end)

  it("view_buttons_refresh_layout_immediately", function()
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
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001 },
                questCount = 1,
              },
            },
          },
        },
        mapByID = {
          [1] = {
            id = 1,
            name = "Map #1",
            questLines = {
              {
                id = 101,
                name = "QuestLine #101",
                UiMapID = 1,
                questIDs = { 1001 },
                questCount = 1,
              },
            },
          },
        },
        questLineByID = {
          [101] = {
            id = 101,
            name = "QuestLine #101",
            UiMapID = 1,
            questIDs = { 1001 },
            questCount = 1,
          },
        },
        questToQuestLineID = {
          [1001] = 101,
        },
        typeList = {},
        typeToQuestIDs = {},
        typeToQuestLineIDs = {},
        typeToMapIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetQuestTypeIndex = function()
      return {
        typeList = { 12 },
        typeToQuestIDs = {
          [12] = { 1001 },
        },
        typeToQuestLineIDs = {
          [12] = { 101 },
        },
        typeToMapIDs = {
          [12] = { 1 },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestTypeLabel = function(typeID)
      return "Type #" .. tostring(typeID)
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "Quest #1001", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetMapProgress = function()
      return { completed = 0, total = 1 }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 1 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    assert.is_true(treeView.leftTree:IsShown())
    assert.is_false(treeView.typeModeButton:IsShown())

    treeView.viewButtons.type:RunScript("OnClick")

    assert.equals("type", treeView.selectedView)
    assert.is_false(treeView.leftTree:IsShown())
    assert.is_true(treeView.typeModeButton:IsShown())
  end)
end)
