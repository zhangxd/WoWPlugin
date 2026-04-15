local Harness = dofile("tests/logic/harness/harness.lua")

describe("Quest module split", function()
  local harness = nil -- 测试 harness

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("registers_quest_module_with_two_bottom_tabs", function()
    local moduleDef = harness:loadQuestModule() -- 任务模块定义
    assert.equals("quest", moduleDef.id)
    assert.is_function(moduleDef.GetSettingsPages)

    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    assert.is_truthy(type(questHooks) == "table")
    assert.is_function(questHooks.getView)

    local questView = questHooks:getView() -- 任务视图对象
    assert.is_truthy(type(questView) == "table")
    assert.equals("active_log", questView.selectedModeKey)

    local modeKeyList = questHooks:getBottomTabModeKeys() -- 底部分页签模式键
    assert.same({ "active_log", "map_questline" }, modeKeyList)
  end)

  it("active_log_does_not_register_breadcrumb_nodes", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象

    local journalFrame = harness.runtime.CreateFrame("Frame", "ToolboxQuestFrame") -- Quest 主界面
    journalFrame:Show()
    rawset(_G, "ToolboxQuestFrame", journalFrame)

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {},
        expansionByID = {},
      }, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {}, nil
    end

    questView:refresh()
    local breadcrumbList = questHooks:getBreadcrumbTextList() -- 导航文本列表
    assert.same({}, breadcrumbList)
  end)
end)

