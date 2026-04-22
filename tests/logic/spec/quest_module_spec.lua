local Harness = dofile("tests/logic/harness/harness.lua")
local questDumpCallCount = 0 -- 任务详情聊天输出调用次数

local function buildQuestNavigationFixture()
  local mapMode = {
    key = "map_questline",
    name = "地图任务线",
    entries = {
      { kind = "map", id = 2371, name = "欧恩哈拉平原" },
    },
  } -- 任务线模式导航

  return {
    expansionList = {
      { id = 9, name = "巨龙时代" },
    },
    expansionByID = {
      [9] = {
        id = 9,
        name = "巨龙时代",
        modes = { mapMode },
        modeByKey = {
          map_questline = mapMode,
        },
      },
    },
  }
end

local function installQuestDataStubs()
  questDumpCallCount = 0
  Toolbox.Questlines.GetQuestNavigationModel = function()
    return buildQuestNavigationFixture(), nil
  end
  Toolbox.Questlines.GetCurrentQuestLogEntries = function()
    return {
      { questID = 81001, name = "觉醒的角兽", questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = 12 },
      { questID = 81002, name = "立即回报", questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = true, typeID = 12 },
    }, nil
  end
  Toolbox.Questlines.GetQuestLinesForMap = function(mapID)
    if mapID ~= 2371 then
      return {}, nil
    end
    return {
      { id = 9901, name = "欧恩哈拉开端", questCount = 2 },
    }, nil
  end
  Toolbox.Questlines.GetQuestLineProgress = function(questLineID)
    if questLineID == 9901 then
      return {
        completed = 1,
        total = 2,
        nextQuestName = "继续深入",
        isCompleted = false,
      }, nil
    end
    return nil, "unknown questLine"
  end
  Toolbox.Questlines.GetQuestListByQuestLineID = function(questLineID)
    if questLineID ~= 9901 then
      return {}, nil
    end
    return {
      { id = 81001, name = "觉醒的角兽", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = 12 },
      { id = 81003, name = "山谷回音", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "pending", readyForTurnIn = false, typeID = 12 },
    }, nil
  end
  Toolbox.Questlines.GetQuestTabModel = function()
    return {
      questLineByID = {
        [9901] = { id = 9901, name = "欧恩哈拉开端", questCount = 2, UiMapID = 2371 },
      },
    }, nil
  end
  Toolbox.Questlines.GetQuestDetailByID = function(questID)
    return {
      questID = questID,
      name = "测试任务",
      questLineName = "欧恩哈拉开端",
      questLineID = 9901,
      UiMapID = 2371,
      questLineExpansionID = 9,
      typeID = 12,
      typeLabel = "Campaign",
      prerequisiteQuestIDs = { 80001 },
      nextQuestIDs = { 80002 },
    }, nil
  end
  Toolbox.Questlines.RequestAndDumpQuestDetailsToChat = function()
    questDumpCallCount = questDumpCallCount + 1
  end
end

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

  it("registers_quest_module_with_four_bottom_tabs", function()
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
    assert.same({ "active_log", "map_questline", "campaign", "achievement" }, modeKeyList)

    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local activeButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.active_log or nil -- 当前任务页签按钮
    local mapButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.map_questline or nil -- 任务线页签按钮
    local campaignButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.campaign or nil -- 战役页签按钮
    local achievementButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.achievement or nil -- 成就页签按钮
    assert.is_truthy(activeButton)
    assert.is_truthy(mapButton)
    assert.is_truthy(campaignButton)
    assert.is_truthy(achievementButton)
    assert.is_true(activeButton.parentFrame == hostFrame)
    assert.is_true(mapButton.parentFrame == hostFrame)
    assert.is_true(campaignButton.parentFrame == hostFrame)
    assert.is_true(achievementButton.parentFrame == hostFrame)
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_ACTIVE or "当前任务", activeButton:GetText())
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_QUESTLINE or "任务线", mapButton:GetText())
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_CAMPAIGN or "战役", campaignButton:GetText())
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_ACHIEVEMENT or "成就", achievementButton:GetText())
    assert.is_true(activeButton:IsShown())
    assert.is_true(mapButton:IsShown())
    assert.is_true(campaignButton:IsShown())
    assert.is_true(achievementButton:IsShown())
    assert.is_false(questView.tabButton and questView.tabButton:IsShown() or false)
  end)

  it("achievement_tab_left_tree_and_right_panel_follow_expansion_to_achievement_flow", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local mapMode = { key = "map_questline", name = "地图任务线", entries = {} } -- 地图任务线模式
    local campaignMode = { key = "campaign", name = "战役", entries = {} } -- 战役模式
    local achievementMode = {
      key = "achievement",
      name = "成就",
      entries = {
        {
          kind = "achievement",
          id = 7001,
          name = "群岛探险家",
          questLines = {
            { id = 9901, name = "欧恩哈拉开端", questCount = 2, UiMapID = 2371 },
          },
        },
      },
    } -- 成就模式

    local expansionEntry = {
      id = 9,
      name = "巨龙时代",
      modes = { mapMode, campaignMode, achievementMode },
      modeByKey = {
        map_questline = mapMode,
        campaign = campaignMode,
        achievement = achievementMode,
      },
    } -- 资料片导航详情

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = expansionEntry,
        },
      }, nil
    end

    Toolbox.Questlines.GetQuestLinesForAchievement = function(achievementID, expansionID)
      if achievementID == 7001 and expansionID == 9 then
        return {
          { id = 9901, name = "欧恩哈拉开端", questCount = 2, UiMapID = 2371 },
        }, nil
      end
      return {}, nil
    end

    Toolbox.Questlines.GetQuestLineProgress = function(questLineID)
      if questLineID == 9901 then
        return {
          completed = 1,
          total = 2,
          nextQuestName = "继续深入",
          isCompleted = false,
        }, nil
      end
      return nil, "unknown questLine"
    end

    Toolbox.Questlines.GetQuestListByQuestLineID = function(questLineID)
      if questLineID ~= 9901 then
        return {}, nil
      end
      return {
        { id = 81001, name = "觉醒的角兽", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 81003, name = "山谷回音", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "pending", readyForTurnIn = false, typeID = 12 },
      }, nil
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local achievementButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.achievement or nil -- 成就页签按钮
    assert.is_truthy(achievementButton)
    achievementButton:RunScript("OnClick")

    local function collectVisibleRows(rowButtonList)
      local rowDataList = {} -- 可见行数据
      for _, rowButton in ipairs(rowButtonList or {}) do
        local rowData = rowButton and rowButton.rowData or nil -- 当前行数据
        if rowButton and rowButton.IsShown and rowButton:IsShown() and type(rowData) == "table" then
          rowDataList[#rowDataList + 1] = rowData
        end
      end
      return rowDataList
    end

    local leftRowDataList = collectVisibleRows(questView.rowButtons) -- 左侧树可见行
    local foundExpansionNode = false -- 是否找到资料片节点
    local foundAchievementNode = false -- 是否找到成就节点
    for _, rowData in ipairs(leftRowDataList) do
      if rowData.kind == "expansion" and string.find(tostring(rowData.text or ""), "巨龙时代", 1, true) ~= nil then
        foundExpansionNode = true
      end
      if rowData.kind == "achievement" and rowData.text == "群岛探险家" then
        foundAchievementNode = true
      end
    end
    assert.is_true(foundExpansionNode)
    assert.is_true(foundAchievementNode)

    local initialRightRows = collectVisibleRows(questView.rightRowButtons) -- 右侧初始行
    assert.equals("questline", initialRightRows[1] and initialRightRows[1].kind)
    assert.is_true(string.find(tostring(initialRightRows[1] and initialRightRows[1].text or ""), "欧恩哈拉开端", 1, true) ~= nil)

    local firstQuestlineButton = questView.rightRowButtons and questView.rightRowButtons[1] or nil -- 第一条任务线按钮
    assert.is_truthy(firstQuestlineButton)
    firstQuestlineButton:RunScript("OnClick")

    local expandedRightRows = collectVisibleRows(questView.rightRowButtons) -- 右侧展开后行
    local foundQuestRow = false -- 是否出现任务行
    for _, rowData in ipairs(expandedRightRows) do
      if rowData.kind == "quest" and rowData.text == "觉醒的角兽" then
        foundQuestRow = true
      end
    end
    assert.is_true(foundQuestRow)
  end)

  it("registers_quest_host_frame_into_mover_with_title_drag_region", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    assert.is_truthy(hostFrame.TitleContainer)

    local moverRegisterCalls = harness:getMoverRegisterCalls() -- mover 登记调用列表
    assert.equals(1, #moverRegisterCalls)

    local firstCall = moverRegisterCalls[1] -- 首次拖动登记调用
    assert.is_true(firstCall.frame == hostFrame)
    assert.equals("ToolboxQuestFrame", firstCall.key)
    assert.is_truthy(type(firstCall.opts) == "table")
    assert.is_true(firstCall.opts.dragRegion == hostFrame.TitleContainer)
  end)

  it("open_main_frame_does_not_reopen_when_module_disabled", function()
    local moduleDef = harness:loadQuestModule() -- 任务模块定义
    installQuestDataStubs()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    assert.is_false(hostFrame:IsShown())

    harness.questModuleDb.enabled = false
    moduleDef.OnEnabledSettingChanged(false)

    assert.has_no.errors(function()
      Toolbox.Quest.OpenMainFrame()
    end)
    assert.is_false(hostFrame:IsShown())
  end)

  it("active_log_uses_stacked_panels_and_registers_root_navigation_node", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local breadcrumbList = questHooks:getBreadcrumbTextList() -- 导航文本列表
    assert.same({ Toolbox.L.QUEST_VIEW_TAB_ACTIVE or "当前任务" }, breadcrumbList)
    assert.equals("NavBarTemplate", questView.breadcrumbFrame.templateName)
    assert.is_truthy(questView.headerFrame)
    assert.is_true(questView.headerFrame.parentFrame == hostFrame)
    assert.is_true(questView.breadcrumbFrame.parentFrame == questView.headerFrame)
    assert.is_true(questView.searchBoxFrame.parentFrame == questView.headerFrame)
    local headerTopLeftPoint = questView.headerFrame._points and questView.headerFrame._points[1] or nil -- 头部带左上锚点
    assert.is_truthy(headerTopLeftPoint)
    assert.is_true(headerTopLeftPoint.relativeFrame == hostFrame)
    assert.equals(58, headerTopLeftPoint.x)
    assert.equals(-26, headerTopLeftPoint.y)
    assert.equals(34, questView.headerFrame:GetHeight())
    local navBarLeftPoint = questView.breadcrumbFrame._points and questView.breadcrumbFrame._points[1] or nil -- 顶部路径左锚点
    assert.is_truthy(navBarLeftPoint)
    assert.is_true(navBarLeftPoint.relativeFrame == questView.headerFrame)
    assert.equals(34, questView.breadcrumbFrame:GetHeight())
    local navBarRightPoint = questView.breadcrumbFrame._points and questView.breadcrumbFrame._points[2] or nil -- 顶部路径右锚点
    assert.is_truthy(navBarRightPoint)
    assert.equals("TOPRIGHT", navBarRightPoint.point)
    assert.is_true(navBarRightPoint.relativeFrame == questView.searchBoxFrame)
    assert.equals("TOPLEFT", navBarRightPoint.relativePoint)
    local firstBreadcrumbButton = questView.breadcrumbButtons[1] -- 第一段导航按钮
    assert.is_truthy(firstBreadcrumbButton)
    local firstBreadcrumbPoint = firstBreadcrumbButton._points and firstBreadcrumbButton._points[1] or nil -- 第一段导航按钮锚点
    assert.is_truthy(firstBreadcrumbPoint)
    assert.equals("LEFT", firstBreadcrumbPoint.point)
    assert.is_true(firstBreadcrumbPoint.relativeFrame == questView.breadcrumbFrame)
    assert.equals("LEFT", firstBreadcrumbPoint.relativePoint)
    assert.equals("LEFT", firstBreadcrumbButton._justifyH)
    assert.equals(34, firstBreadcrumbButton:GetHeight())
    assert.equals("InputBoxTemplate", questView.searchBox.templateName)
    assert.is_nil(questView.searchBoxFrame._backdrop)
    assert.is_nil(questView.searchBoxFrame._backdropBorderColor)
    assert.equals(32, questView.searchBoxFrame:GetHeight())
    assert.equals(24, questView.searchBox:GetHeight())
    local activeContentTopPoint = questView.rightContent._points and questView.rightContent._points[1] or nil -- 当前任务视图顶部锚点
    assert.is_truthy(activeContentTopPoint)
    assert.is_true(activeContentTopPoint.relativeFrame == questView.panelFrame)
    assert.equals("TOPLEFT", activeContentTopPoint.relativePoint)
    assert.equals(-8, activeContentTopPoint.y)
    assert.is_false(questView.leftTree:IsShown())
    assert.is_true(questView.activeLogCurrentPanel:IsShown())
    assert.is_true(questView.activeLogRecentPanel:IsShown())

    local collapseButton = questView.activeLogRecentToggleButton -- 历史完成折叠按钮
    assert.is_truthy(collapseButton)
    collapseButton:RunScript("OnClick")

    assert.is_true(questView.activeLogRecentCollapsed == true)
    assert.is_false(questView.activeLogRecentPanel:IsShown())
    assert.is_true(questView.activeLogCurrentPanel:IsShown())
  end)

  it("active_log_task_rows_show_questline_and_expand_inline_without_tooltip_or_chat_dump", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local firstRow = questView.activeLogCurrentRowButtons[1] -- 当前任务第一行
    assert.is_truthy(firstRow)
    assert.equals(81002, firstRow.rowData.questID)
    assert.equals("欧恩哈拉开端", firstRow.questLineFont:GetText())

    firstRow:RunScript("OnEnter")
    assert.same({}, harness:getTooltipLines())

    firstRow:RunScript("OnClick")

    assert.equals(0, questDumpCallCount)
    assert.is_false(questView.detailPopupFrame and questView.detailPopupFrame:IsShown() or false)

    local detailRow = questView.activeLogCurrentRowButtons[2] -- 行内展开详情行
    assert.is_truthy(detailRow)
    assert.equals("quest_detail", detailRow.rowData.kind)
    assert.is_true(string.find(detailRow.detailText:GetText() or "", "欧恩哈拉开端", 1, true) ~= nil)
    assert.is_true(string.find(detailRow.detailText:GetText() or "", "Campaign(12)", 1, true) ~= nil)
  end)

  it("hides_quests_with_blocked_or_missing_type_in_all_tabs", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local detailByQuestID = {
      [91001] = {
        questID = 91001,
        name = "可见当前任务",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = 12,
      },
      [91002] = {
        questID = 91002,
        name = "隐藏类型265",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = 265,
      },
      [91003] = {
        questID = 91003,
        name = "隐藏空类型当前",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = nil,
      },
      [91021] = {
        questID = 91021,
        name = "最近可见任务",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = 12,
      },
      [91022] = {
        questID = 91022,
        name = "最近隐藏291",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = 291,
      },
      [91023] = {
        questID = 91023,
        name = "最近隐藏空类型",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = nil,
      },
    } -- 任务详情测试数据

    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {
        {
          questID = 91001,
          name = "可见当前任务",
          questLineName = "欧恩哈拉开端",
          status = "active",
          readyForTurnIn = false,
          typeID = 12,
          questLineID = 9901,
          UiMapID = 2371,
          questLineExpansionID = 9,
        },
        {
          questID = 91002,
          name = "隐藏类型265",
          questLineName = "欧恩哈拉开端",
          status = "active",
          readyForTurnIn = false,
          typeID = 265,
          questLineID = 9901,
          UiMapID = 2371,
          questLineExpansionID = 9,
        },
        {
          questID = 91003,
          name = "隐藏空类型当前",
          questLineName = "欧恩哈拉开端",
          status = "active",
          readyForTurnIn = false,
          typeID = nil,
          questLineID = 9901,
          UiMapID = 2371,
          questLineExpansionID = 9,
        },
      }, nil
    end

    Toolbox.Questlines.GetQuestListByQuestLineID = function(questLineID)
      if questLineID ~= 9901 then
        return {}, nil
      end
      return {
        { id = 91101, name = "可见地图任务", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = 12 },
        { id = 91102, name = "隐藏类型291地图", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = 291 },
        { id = 91103, name = "隐藏空类型地图", questLineID = 9901, questLineName = "欧恩哈拉开端", status = "active", readyForTurnIn = false, typeID = nil },
      }, nil
    end

    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      local detailObject = detailByQuestID[questID] -- 指定任务详情
      if type(detailObject) == "table" then
        return detailObject, nil
      end
      return {
        questID = questID,
        name = "可见地图任务",
        questLineName = "欧恩哈拉开端",
        questLineID = 9901,
        UiMapID = 2371,
        questLineExpansionID = 9,
        typeID = 12,
      }, nil
    end

    harness.questModuleDb.questRecentCompletedList = {
      { questID = 91021, questName = "最近可见任务", completedAt = 1700000000 },
      { questID = 91022, questName = "最近隐藏291", completedAt = 1700000001 },
      { questID = 91023, questName = "最近隐藏空类型", completedAt = 1700000002 },
    }

    local function collectVisibleQuestText(rowButtonList)
      local textList = {} -- 可见文本列表
      for _, rowButton in ipairs(rowButtonList or {}) do
        local rowData = rowButton and rowButton.rowData or nil -- 当前行数据
        if rowButton and rowButton.IsShown and rowButton:IsShown() and type(rowData) == "table" and type(rowData.text) == "string" then
          textList[#textList + 1] = rowData.text
        end
      end
      return textList
    end

    local function hasText(textList, expectedText)
      for _, currentText in ipairs(textList or {}) do
        if currentText == expectedText then
          return true
        end
      end
      return false
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local activeCurrentTexts = collectVisibleQuestText(questView.activeLogCurrentRowButtons) -- 当前任务可见文本
    assert.is_true(hasText(activeCurrentTexts, "可见当前任务"))
    assert.is_false(hasText(activeCurrentTexts, "隐藏类型265"))
    assert.is_false(hasText(activeCurrentTexts, "隐藏空类型当前"))

    local activeRecentTexts = collectVisibleQuestText(questView.activeLogRecentRowButtons) -- 最近完成可见文本
    assert.is_true(hasText(activeRecentTexts, "最近可见任务"))
    assert.is_false(hasText(activeRecentTexts, "最近隐藏291"))
    assert.is_false(hasText(activeRecentTexts, "最近隐藏空类型"))

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = 2371
    questView.expandedQuestLineID = 9901
    questView.selectedQuestID = nil
    questView:render()

    local mapQuestTexts = collectVisibleQuestText(questView.rightRowButtons) -- 地图任务线可见文本
    assert.is_true(hasText(mapQuestTexts, "可见地图任务"))
    assert.is_false(hasText(mapQuestTexts, "隐藏类型291地图"))
    assert.is_false(hasText(mapQuestTexts, "隐藏空类型地图"))
  end)

  it("standalone_quest_layout_keeps_only_one_inset_view_container", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    assert.equals("InsetFrameTemplate", questView.panelFrame.templateName)
    assert.is_nil(questView.leftTree.templateName)
    assert.is_nil(questView.rightContent.templateName)
    assert.is_nil(questView.activeLogCurrentPanel.templateName)
    assert.is_nil(questView.activeLogRecentPanel.templateName)
    assert.is_true(questView.modeTabButtonByKey.active_log.parentFrame == hostFrame)
    assert.is_true(questView.modeTabButtonByKey.map_questline.parentFrame == hostFrame)
  end)

  it("bottom_tabs_anchor_outside_panel_frame_and_do_not_consume_inner_height", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local activeButton = questView.modeTabButtonByKey.active_log -- 当前任务页签按钮
    local activeAnchor = activeButton and activeButton._points and activeButton._points[1] or nil -- 当前任务页签锚点
    assert.is_truthy(activeAnchor)
    assert.equals("TOPLEFT", activeAnchor.point)
    assert.is_true(activeAnchor.relativeFrame == hostFrame)
    assert.equals("BOTTOMLEFT", activeAnchor.relativePoint)

    local activeLogBottomPoint = questView.rightContent._points and questView.rightContent._points[2] or nil -- 当前任务视图底部锚点
    assert.is_truthy(activeLogBottomPoint)
    assert.equals("BOTTOMRIGHT", activeLogBottomPoint.point)
    assert.equals("BOTTOMRIGHT", activeLogBottomPoint.relativePoint)
    assert.is_true(activeLogBottomPoint.relativeFrame == questView.panelFrame)
    assert.equals(8, activeLogBottomPoint.y)
    local activeLogTopPoint = questView.rightContent._points and questView.rightContent._points[1] or nil -- 当前任务视图顶部锚点
    assert.is_truthy(activeLogTopPoint)
    assert.is_true(activeLogTopPoint.relativeFrame == questView.panelFrame)
    assert.equals("TOPLEFT", activeLogTopPoint.relativePoint)
    assert.equals(-8, activeLogTopPoint.y)

    local mapButton = questView.modeTabButtonByKey.map_questline -- 任务线页签按钮
    assert.is_truthy(mapButton)
    mapButton:RunScript("OnClick")

    local leftTreeTopPoint = questView.leftTree._points and questView.leftTree._points[1] or nil -- 任务线左树顶部锚点
    local leftTreeBottomPoint = questView.leftTree._points and questView.leftTree._points[2] or nil -- 任务线左树底部锚点
    local mapViewTopPoint = questView.rightContent._points and questView.rightContent._points[1] or nil -- 任务线主区顶部锚点
    local mapViewBottomPoint = questView.rightContent._points and questView.rightContent._points[2] or nil -- 任务线主区底部锚点
    assert.is_truthy(leftTreeTopPoint)
    assert.is_truthy(leftTreeBottomPoint)
    assert.is_truthy(mapViewTopPoint)
    assert.is_truthy(mapViewBottomPoint)
    assert.is_true(leftTreeTopPoint.relativeFrame == questView.panelFrame)
    assert.equals("TOPLEFT", leftTreeTopPoint.relativePoint)
    assert.is_true(mapViewTopPoint.relativeFrame == questView.leftTree)
    assert.equals("TOPRIGHT", mapViewTopPoint.relativePoint)
    assert.equals(-8, leftTreeTopPoint.y)
    assert.equals(0, mapViewTopPoint.y)
    assert.equals(8, leftTreeBottomPoint.y)
    assert.equals(8, mapViewBottomPoint.y)
  end)

  it("quest_host_frame_uses_portrait_frame_title_style_and_compact_inset_layout", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    assert.equals("PortraitFrameTemplate", hostFrame.templateName)
    assert.equals(Toolbox.L.MODULE_QUEST or "Quest", hostFrame._title)
    assert.is_truthy(hostFrame._portraitAsset)
    assert.is_nil(hostFrame._backdropColor)

    local topLeftPoint = questView.panelFrame._points and questView.panelFrame._points[1] or nil -- 外层视图左上锚点
    local bottomRightPoint = questView.panelFrame._points and questView.panelFrame._points[2] or nil -- 外层视图右下锚点
    assert.is_truthy(topLeftPoint)
    assert.is_truthy(bottomRightPoint)
    assert.equals(4, topLeftPoint.x)
    assert.equals(-60, topLeftPoint.y)
    assert.equals(-4, bottomRightPoint.x)
    assert.equals(5, bottomRightPoint.y)

    assert.is_nil(questView.leftTree._backdropColor)
    assert.is_nil(questView.rightContent._backdropColor)
  end)

  it("map_questline_breadcrumb_supports_clickable_ancestor_backtrack", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = 2371
    questView.expandedQuestLineID = 9901
    questView:render()

    assert.is_true(questView.leftTree:IsShown())
    assert.equals("NavBarTemplate", questView.breadcrumbFrame.templateName)
    local navBarLeftPoint = questView.breadcrumbFrame._points and questView.breadcrumbFrame._points[1] or nil -- 顶部路径左锚点
    local navBarRightPoint = questView.breadcrumbFrame._points and questView.breadcrumbFrame._points[2] or nil -- 顶部路径右锚点
    assert.is_truthy(navBarLeftPoint)
    assert.is_truthy(navBarRightPoint)
    assert.is_true(questView.breadcrumbFrame.parentFrame == questView.headerFrame)
    assert.is_true(navBarLeftPoint.relativeFrame == questView.headerFrame)
    assert.is_true(navBarRightPoint.relativeFrame == questView.searchBoxFrame)
    assert.equals("TOPRIGHT", navBarRightPoint.point)
    assert.equals("TOPLEFT", navBarRightPoint.relativePoint)
    local headerTopLeftPoint = questView.headerFrame._points and questView.headerFrame._points[1] or nil -- 头部带左上锚点
    assert.is_truthy(headerTopLeftPoint)
    assert.is_true(headerTopLeftPoint.relativeFrame == hostFrame)
    assert.equals(58, headerTopLeftPoint.x)
    assert.equals(-26, headerTopLeftPoint.y)
    assert.equals(34, questView.headerFrame:GetHeight())
    local firstQuestlineRow = questView.rightRowButtons[1] -- 主视图第一条任务线行
    assert.is_truthy(firstQuestlineRow)
    assert.equals("RIGHT", firstQuestlineRow.rowMetaFont._justifyH)
    assert.is_false(firstQuestlineRow.rowMetaFont._wordWrap)
    assert.equals(156, firstQuestlineRow.rowMetaFont:GetWidth())
    assert.equals("", firstQuestlineRow.rowMetaFont:GetText() or "")
    assert.equals(37, firstQuestlineRow:GetHeight())
    assert.same({
      Toolbox.L.QUEST_VIEW_TAB_QUESTLINE or "任务线",
      "巨龙时代",
      "欧恩哈拉平原",
      "欧恩哈拉开端",
    }, questHooks:getBreadcrumbTextList())

    local expansionCrumb = questView.breadcrumbButtons[2] -- 资料片路径按钮
    assert.is_truthy(expansionCrumb)
    expansionCrumb:RunScript("OnClick")

    assert.equals("map_questline", questView.selectedModeKey)
    assert.is_nil(questView.selectedMapID)
    assert.is_nil(questView.expandedQuestLineID)
    assert.same({
      Toolbox.L.QUEST_VIEW_TAB_QUESTLINE or "任务线",
      "巨龙时代",
    }, questHooks:getBreadcrumbTextList())
  end)

  it("direct_questline_in_main_view_toggles_without_disappearing", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    Toolbox.Questlines.GetQuestNavigationModel = function()
      local mapMode = {
        key = "map_questline",
        name = "地图任务线",
        entries = {
          { kind = "questline", id = 9901, name = "欧恩哈拉开端" },
        },
      } -- 直连任务线导航

      return {
        expansionList = {
          { id = 9, name = "巨龙时代" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代",
            modes = { mapMode },
            modeByKey = {
              map_questline = mapMode,
            },
          },
        },
      }, nil
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = nil
    questView.expandedQuestLineID = 9901
    questView.selectedQuestID = nil
    questView:render()

    local questLineRow = questView.rightRowButtons[1] -- 主区任务线行
    local firstQuestRow = questView.rightRowButtons[2] -- 展开后的第一条任务行
    assert.is_truthy(questLineRow)
    assert.equals("questline", questLineRow.rowData.kind)
    assert.is_truthy(string.find(questLineRow.rowFont:GetText() or "", "%[-%]"))
    assert.is_truthy(firstQuestRow)
    assert.equals("quest", firstQuestRow.rowData.kind)
    assert.is_true(firstQuestRow:IsShown())

    questLineRow:RunScript("OnClick")

    local collapsedQuestLineRow = questView.rightRowButtons[1] -- 折叠后的任务线行
    local hiddenQuestRow = questView.rightRowButtons[2] -- 折叠后隐藏的任务行
    assert.is_truthy(collapsedQuestLineRow)
    assert.equals("questline", collapsedQuestLineRow.rowData.kind)
    assert.is_true(collapsedQuestLineRow:IsShown())
    assert.is_truthy(string.find(collapsedQuestLineRow.rowFont:GetText() or "", "%[%+%]"))
    assert.is_truthy(hiddenQuestRow)
    assert.is_false(hiddenQuestRow:IsShown())

    collapsedQuestLineRow:RunScript("OnClick")

    local reexpandedQuestLineRow = questView.rightRowButtons[1] -- 再次展开后的任务线行
    local restoredQuestRow = questView.rightRowButtons[2] -- 再次展开后的任务行
    assert.is_truthy(reexpandedQuestLineRow)
    assert.equals("questline", reexpandedQuestLineRow.rowData.kind)
    assert.is_truthy(string.find(reexpandedQuestLineRow.rowFont:GetText() or "", "%[-%]"))
    assert.is_truthy(restoredQuestRow)
    assert.equals("quest", restoredQuestRow.rowData.kind)
    assert.is_true(restoredQuestRow:IsShown())
  end)

  it("map_questline_expanded_rows_use_single_line_quests_and_remove_active_view_button", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = 2371
    questView.expandedQuestLineID = 9901
    questView.selectedQuestID = nil
    questView:render()

    local firstQuestRow = questView.rightRowButtons[2] -- 展开后的第一条任务行
    assert.is_truthy(firstQuestRow)
    assert.equals("quest", firstQuestRow.rowData.kind)
    assert.equals(21, firstQuestRow:GetHeight())
    assert.is_false(firstQuestRow.questLineFont:IsShown())
    assert.equals("", firstQuestRow.questLineFont:GetText() or "")

    firstQuestRow:RunScript("OnClick")

    local detailRow = questView.rightRowButtons[3] -- 行内详情行
    assert.is_truthy(detailRow)
    assert.equals("quest_detail", detailRow.rowData.kind)
    assert.is_true(detailRow.jumpActionButton:IsShown())
    assert.is_nil(detailRow.activeActionButton)
  end)

  it("completed_questline_shows_only_short_completed_status", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()
    Toolbox.Questlines.GetQuestLineProgress = function(questLineID)
      if questLineID == 9901 then
        return {
          completed = 2,
          total = 2,
          nextQuestName = "不应显示",
          isCompleted = true,
        }, nil
      end
      return nil, "unknown questLine"
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = 2371
    questView.expandedQuestLineID = 9901
    questView.selectedQuestID = nil
    questView:render()

    local firstQuestlineRow = questView.rightRowButtons[1] -- 已完成任务线行
    assert.is_truthy(firstQuestlineRow)
    assert.equals(Toolbox.L.EJ_QUEST_STATUS_COMPLETED or "Completed", firstQuestlineRow.rowMetaFont:GetText())
  end)

  it("map_questline_long_breadcrumb_stays_within_search_box_boundary", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()

    Toolbox.Questlines.GetQuestNavigationModel = function()
      return {
        expansionList = {
          { id = 9, name = "巨龙时代超长资料片标题示例" },
        },
        expansionByID = {
          [9] = {
            id = 9,
            name = "巨龙时代超长资料片标题示例",
            modes = {
              {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { kind = "map", id = 2371, name = "欧恩哈拉平原超长地图标题示例" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { kind = "map", id = 2371, name = "欧恩哈拉平原超长地图标题示例" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestLinesForMap = function(mapID)
      if mapID ~= 2371 then
        return {}, nil
      end
      return {
        { id = 9901, name = "欧恩哈拉开端超长任务线标题示例", questCount = 2 },
      }, nil
    end
    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        questLineByID = {
          [9901] = { id = 9901, name = "欧恩哈拉开端超长任务线标题示例", questCount = 2, UiMapID = 2371 },
        },
      }, nil
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = 2371
    questView.expandedQuestLineID = 9901
    questView:render()

    local breadcrumbFrameWidth = questView.breadcrumbFrame:GetWidth() -- 导航容器宽度
    assert.is_true(type(breadcrumbFrameWidth) == "number" and breadcrumbFrameWidth > 0)

    local breadcrumbUsedWidth = 0 -- 导航按钮总占用宽度
    for buttonIndex, buttonObject in ipairs(questView.breadcrumbButtons or {}) do
      if buttonObject and buttonObject.IsShown and buttonObject:IsShown() then
        if buttonIndex > 1 then
          breadcrumbUsedWidth = breadcrumbUsedWidth + 2
        end
        breadcrumbUsedWidth = breadcrumbUsedWidth + (buttonObject:GetWidth() or 0)
      end
    end

    assert.is_true(breadcrumbUsedWidth <= breadcrumbFrameWidth)
  end)

  it("map_questline_breadcrumb_resolves_parent_map_from_expanded_questline_without_error", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象
    installQuestDataStubs()
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
                  { kind = "questline", id = 9901, name = "欧恩哈拉开端" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { kind = "questline", id = 9901, name = "欧恩哈拉开端" },
                },
              },
            },
          },
        },
      }, nil
    end

    rawset(_G, "C_Map", {
      GetMapInfo = function(uiMapID)
        if uiMapID == 2371 then
          return { name = "欧恩哈拉平原" }
        end
        return nil
      end,
    })

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "map_questline"
    questView.selectedExpansionID = 9
    questView.selectedMapID = nil
    questView.expandedQuestLineID = 9901

    assert.has_no.errors(function()
      questView:render()
    end)
    assert.same({
      Toolbox.L.QUEST_VIEW_TAB_QUESTLINE or "任务线",
      "巨龙时代",
      "欧恩哈拉平原",
      "欧恩哈拉开端",
    }, questHooks:getBreadcrumbTextList())
  end)

  it("inline_detail_jump_to_questline_updates_expansion_before_switching_view", function()
    harness:loadQuestModule()
    local questHooks = Toolbox.TestHooks and Toolbox.TestHooks.Quest -- quest 测试 hook
    local questView = questHooks:getView() -- 任务视图对象

    installQuestDataStubs()

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
                  { kind = "map", id = 2371, name = "欧恩哈拉平原" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { kind = "map", id = 2371, name = "欧恩哈拉平原" },
                },
              },
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
                  { kind = "map", id = 2601, name = "多恩诺嘉尔" },
                },
              },
            },
            modeByKey = {
              map_questline = {
                key = "map_questline",
                name = "地图任务线",
                entries = {
                  { kind = "map", id = 2601, name = "多恩诺嘉尔" },
                },
              },
            },
          },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestTabModel = function()
      return {
        questLineByID = {
          [9901] = { id = 9901, name = "欧恩哈拉开端", questCount = 2, UiMapID = 2371, ExpansionID = 9 },
          [9902] = { id = 9902, name = "多恩诺嘉尔召集", questCount = 1, UiMapID = 2601, ExpansionID = 10 },
        },
      }, nil
    end
    Toolbox.Questlines.GetQuestDetailByID = function(questID)
      if questID == 82001 then
        return {
          questID = questID,
          name = "新的召集",
          questLineName = "多恩诺嘉尔召集",
          questLineID = 9902,
          UiMapID = 2601,
          questLineExpansionID = 10,
          typeID = 12,
        }, nil
      end
      return nil, nil
    end
    Toolbox.Questlines.GetCurrentQuestLogEntries = function()
      return {
        { questID = 82001, name = "新的召集", questLineName = "多恩诺嘉尔召集", status = "active", readyForTurnIn = false, typeID = 12 },
      }, nil
    end
    questDumpCallCount = 0
    Toolbox.Questlines.RequestAndDumpQuestDetailsToChat = function()
      questDumpCallCount = questDumpCallCount + 1
    end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "active_log"
    questView.selectedExpansionID = 9
    questView.selectedMapID = nil
    questView.expandedQuestLineID = nil

    local firstRow = questView.activeLogCurrentRowButtons[1] -- 当前任务第一行
    assert.is_truthy(firstRow)
    firstRow:RunScript("OnClick")
    assert.equals(0, questDumpCallCount)

    local detailRow = questView.activeLogCurrentRowButtons[2] -- 行内详情行
    assert.is_truthy(detailRow)
    assert.is_true(detailRow.jumpActionButton:IsShown())
    detailRow.jumpActionButton:RunScript("OnClick")

    assert.equals("map_questline", questView.selectedModeKey)
    assert.equals(10, questView.selectedExpansionID)
    assert.equals(2601, questView.selectedMapID)
    assert.equals(9902, questView.expandedQuestLineID)
  end)
end)

