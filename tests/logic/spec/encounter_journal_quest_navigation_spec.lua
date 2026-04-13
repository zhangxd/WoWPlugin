local Harness = dofile("tests/logic/harness/harness.lua")

local function collectVisibleRowTexts(rowButtonList)
  local textList = {} -- 可见行文本
  for _, rowButton in ipairs(rowButtonList or {}) do
    if rowButton:IsShown() and rowButton.rowFont and rowButton.rowFont.GetText then
      textList[#textList + 1] = rowButton.rowFont:GetText()
    end
  end
  return textList
end

local function assertContainsText(textList, expectedText)
  for _, currentText in ipairs(textList or {}) do
    if type(currentText) == "string" and string.find(currentText, expectedText, 1, true) ~= nil then
      return
    end
  end
  error("missing expected text: " .. tostring(expectedText))
end

local function findVisibleRowButtonByText(rowButtonList, expectedText)
  for _, rowButton in ipairs(rowButtonList or {}) do
    local rowText = rowButton.rowFont and rowButton.rowFont.GetText and rowButton.rowFont:GetText() or nil -- 当前行文本
    if rowButton:IsShown() and type(rowText) == "string" and string.find(rowText, expectedText, 1, true) ~= nil then
      return rowButton
    end
  end
  return nil
end

describe("EncounterJournal quest navigation", function()
  local harness = nil -- 测试 harness

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    harness.moduleDb.questNavExpansionID = 9
    harness.moduleDb.questNavModeKey = "map_questline"
    harness.moduleDb.questNavSelectedMapID = 2371
    harness.moduleDb.questNavSelectedTypeKey = ""
    harness.moduleDb.questNavExpandedQuestLineID = 0
    harness:loadEncounterJournalModule()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("renders_left_tree_with_expansion_mode_and_map_nodes", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

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
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                  { id = 2372, name = "欧恩哈拉平原", kind = "map" },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {
                  { key = "dungeon", name = "地下城任务", kind = "type_group" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                  { id = 2372, name = "欧恩哈拉平原", kind = "map" },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {
                  { id = "dungeon", name = "地下城任务", kind = "type_group" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {
        { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "地下城任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local leftTexts = collectVisibleRowTexts(treeView.rowButtons)
    assertContainsText(leftTexts, "Active Quests")
    assertContainsText(leftTexts, "巨龙时代")
    assertContainsText(leftTexts, "地图任务线")
    assertContainsText(leftTexts, "觉醒海岸")

    local mainTexts = collectVisibleRowTexts(treeView.rightRowButtons)
    assertContainsText(mainTexts, "觉醒海岸主线")
  end)

  it("renders_map_nodes_when_navigation_model_uses_group_entries_without_kind", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", questLineIDs = { 101 } },
                  { id = 2372, name = "欧恩哈拉平原", questLineIDs = { 102 } },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", questLineIDs = { 101 } },
                  { id = 2372, name = "欧恩哈拉平原", questLineIDs = { 102 } },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function(mapID)
      if mapID == 2371 then
        return {
          { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
        }, nil
      end
      return {
        { id = 102, name = "欧恩哈拉支线", UiMapID = 2372, questCount = 1 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local leftTexts = collectVisibleRowTexts(treeView.rowButtons)
    assertContainsText(leftTexts, "觉醒海岸")
    assertContainsText(leftTexts, "欧恩哈拉平原")
  end)

  it("clicking_grouped_map_entry_without_kind_switches_selected_map", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", questLines = { { id = 101 } } },
                  { id = 2372, name = "欧恩哈拉平原", questLines = { { id = 102 } } },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", questLines = { { id = 101 } } },
                  { id = 2372, name = "欧恩哈拉平原", questLines = { { id = 102 } } },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function(mapID)
      if mapID == 2371 then
        return {
          { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
        }, nil
      end
      return {
        { id = 102, name = "欧恩哈拉支线", UiMapID = 2372, questCount = 1 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local mapRowButton = findVisibleRowButtonByText(treeView.rowButtons, "欧恩哈拉平原") -- 欧恩哈拉地图节点
    assert.is_truthy(mapRowButton)
    mapRowButton:RunScript("OnClick")

    assert.equals(2372, treeView.selectedMapID)
    local mainTexts = collectVisibleRowTexts(treeView.rightRowButtons)
    assertContainsText(mainTexts, "欧恩哈拉支线")
  end)

  it("clicking_questline_row_expands_then_collapses_task_list", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {
        { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
        { id = 102, name = "黑龙支线", UiMapID = 2371, questCount = 1 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function(questLineID)
      if questLineID == 101 then
        return { completed = 1, total = 2 }, nil
      end
      return { completed = 0, total = 1 }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function(questLineID)
      if questLineID == 101 then
        return {
          { id = 1001, name = "任务一", status = "active", typeID = 12 },
          { id = 1002, name = "任务二", status = "pending", typeID = 12 },
        }, nil
      end
      return {
        { id = 1003, name = "任务三", status = "completed", typeID = 34 },
      }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    treeView.rightRowButtons[1]:RunScript("OnClick")
    local expandedTexts = collectVisibleRowTexts(treeView.rightRowButtons)
    assert.equals(101, treeView.expandedQuestLineID)
    assert.equals("觉醒海岸主线", treeView.breadcrumbButtons[4]:GetText())
    assert.is_true(string.find(expandedTexts[2], "任务一", 1, true) ~= nil)
    assert.is_true(string.find(expandedTexts[3], "任务二", 1, true) ~= nil)

    treeView.rightRowButtons[1]:RunScript("OnClick")
    local collapsedTexts = collectVisibleRowTexts(treeView.rightRowButtons)
    assert.equals(nil, treeView.expandedQuestLineID)
    assert.equals(2, #collapsedTexts)
  end)

  it("breadcrumb_path_updates_and_parent_segment_can_navigate_back", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {
        { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    assert.equals("巨龙时代", treeView.breadcrumbButtons[1]:GetText())
    assert.equals("地图任务线", treeView.breadcrumbButtons[2]:GetText())
    assert.equals("觉醒海岸", treeView.breadcrumbButtons[3]:GetText())

    treeView.rightRowButtons[1]:RunScript("OnClick")
    assert.equals("觉醒海岸主线", treeView.breadcrumbButtons[4]:GetText())

    treeView.breadcrumbButtons[3]:RunScript("OnClick")
    assert.equals(nil, treeView.expandedQuestLineID)
    assert.equals("觉醒海岸", treeView.breadcrumbButtons[3]:GetText())
  end)

  it("type_mode_lists_tasks_and_detail_popup_can_jump_to_map_questline", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    harness.moduleDb.questNavModeKey = "quest_type"
    harness.moduleDb.questNavSelectedMapID = 0
    harness.moduleDb.questNavSelectedTypeKey = "dungeon"

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {
                  { key = "dungeon", name = "地下城任务", kind = "type_group" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {
                  { id = "dungeon", name = "地下城任务", kind = "type_group" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetTasksForTypeGroup = function()
      return {
        { id = 1001, name = "地下城任务一", status = "active", typeID = 12, questLineID = 101, UiMapID = 2371 },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function()
      return {
        questID = 1001,
        name = "地下城任务一",
        status = "active",
        UiMapID = 2371,
        typeID = 12,
        questLineID = 101,
        questLineName = "觉醒海岸主线",
        prerequisiteQuestIDs = {},
        nextQuestIDs = {},
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {
        { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 2 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "地下城任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 1, total = 2 }, nil
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)

    local mainTexts = collectVisibleRowTexts(treeView.rightRowButtons)
    assert.is_true(string.find(mainTexts[1], "地下城任务一", 1, true) ~= nil)

    treeView.rightRowButtons[1]:RunScript("OnClick")
    assert.is_true(treeView.detailPopupFrame:IsShown())
    assert.is_true(treeView.detailPopupJumpButton:IsShown())

    treeView.detailPopupJumpButton:RunScript("OnClick")
    assert.equals("map_questline", treeView.selectedModeKey)
    assert.equals(2371, treeView.selectedMapID)
    assert.equals(101, treeView.expandedQuestLineID)
  end)

  it("clicking_quest_row_requests_async_dump_to_chat", function()
    local journalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    journalFrame:Show()
    journalFrame.instanceSelect = harness.runtime.CreateFrame("Frame", nil, journalFrame)
    journalFrame.Tabs = {}
    journalFrame.selectedTab = 4
    rawset(_G, "EncounterJournal", journalFrame)

    local dumpedQuestID = nil -- 已请求输出的任务 ID

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { id = 2371, name = "觉醒海岸", kind = "map" },
                },
              },
              quest_type = {
                key = "quest_type",
                name = "任务类型",
                entries = {},
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {
        { id = 101, name = "觉醒海岸主线", UiMapID = 2371, questCount = 1 },
      }, nil
    end
    Toolbox.Questlines.GetQuestListByQuestLineID = function()
      return {
        { id = 1001, name = "任务一", status = "active", typeID = 12 },
      }, nil
    end
    Toolbox.Questlines.GetQuestLineProgress = function()
      return { completed = 0, total = 1 }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      return {
        questID = questID,
        name = "任务一",
        status = "active",
        UiMapID = 2371,
        typeID = 12,
        questLineID = 101,
        questLineName = "觉醒海岸主线",
      }, nil
    end
    Toolbox.Questlines.RequestAndDumpQuestDetailsToChat = function(questID)
      dumpedQuestID = questID
      return true, "pending"
    end

    local treeView = Toolbox.TestHooks.EncounterJournal:getQuestlineTreeView()
    treeView:refresh()
    treeView:setSelected(true)
    treeView.rightRowButtons[1]:RunScript("OnClick")
    treeView.rightRowButtons[2]:RunScript("OnClick")

    assert.equals(1001, treeView.selectedQuestID)
    assert.equals(1001, dumpedQuestID)
  end)
end)
