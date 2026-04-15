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

describe("Quest module navigation", function()
  local harness = nil -- 测试 harness

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    harness.questModuleDb.questNavExpansionID = 9
    harness.questModuleDb.questNavModeKey = "map_questline"
    harness.questModuleDb.questNavSelectedMapID = 2371
    harness.questModuleDb.questNavExpandedQuestLineID = 0
    harness:loadQuestModule()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("renders_left_tree_with_expansion_and_map_nodes", function()
    local questFrame = harness.runtime.CreateFrame("Frame", "ToolboxQuestFrame") -- quest 根框体
    questFrame:Show()
    rawset(_G, "ToolboxQuestFrame", questFrame)

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
                  { id = 2372, name = "欧恩哈拉平原", kind = "map" },
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

    local questView = Toolbox.TestHooks.Quest:getView() -- quest 视图对象
    questView:setSelected(true)
    questView:refresh()

    local leftTexts = collectVisibleRowTexts(questView.rowButtons)
    assertContainsText(leftTexts, "巨龙时代")
    assertContainsText(leftTexts, "觉醒海岸")
  end)

  it("active_log_mode_registers_current_task_root_breadcrumb", function()
    local questFrame = harness.runtime.CreateFrame("Frame", "ToolboxQuestFrame") -- quest 根框体
    questFrame:Show()
    rawset(_G, "ToolboxQuestFrame", questFrame)

    harness.questModuleDb.questNavModeKey = "active_log"
    Toolbox.Questlines.GetQuestNavigationModel = function()
      return { expansionList = {}, expansionByID = {} }, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {}, nil
    end

    local questView = Toolbox.TestHooks.Quest:getView() -- quest 视图对象
    questView:setSelected(true)
    questView:refresh()

    local breadcrumbList = Toolbox.TestHooks.Quest:getBreadcrumbTextList() -- breadcrumb 文本列表
    assert.same({ Toolbox.L.QUEST_VIEW_TAB_ACTIVE or "当前任务" }, breadcrumbList)
  end)

  it("does_not_render_quest_type_mode_in_left_tree", function()
    local questFrame = harness.runtime.CreateFrame("Frame", "ToolboxQuestFrame") -- quest 根框体
    questFrame:Show()
    rawset(_G, "ToolboxQuestFrame", questFrame)

    harness.questModuleDb.questNavModeKey = "map_questline"
    harness.questModuleDb.questNavExpansionID = 9
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
                  { id = "type:12", name = "主线任务", kind = "type_group" },
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
                  { id = "type:12", name = "主线任务", kind = "type_group" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function()
      return {}, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {}, nil
    end

    local questView = Toolbox.TestHooks.Quest:getView() -- quest 视图对象
    questView:setSelected(true)
    questView:refresh()

    local leftTexts = collectVisibleRowTexts(questView.rowButtons)
    for _, currentText in ipairs(leftTexts) do
      assert.is_false(type(currentText) == "string" and string.find(currentText, "任务类型", 1, true) ~= nil)
    end
  end)
end)
