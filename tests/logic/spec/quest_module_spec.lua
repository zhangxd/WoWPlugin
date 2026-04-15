local Harness = dofile("tests/logic/harness/harness.lua")

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
  Toolbox.Questlines.GetQuestNavigationModel = function()
    return buildQuestNavigationFixture(), nil
  end
  Toolbox.Questlines.GetCurrentQuestLogEntries = function()
    return {
      { questID = 81001, name = "觉醒的角兽", status = "active", readyForTurnIn = false },
      { questID = 81002, name = "立即回报", status = "active", readyForTurnIn = true },
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
      { id = 81001, name = "觉醒的角兽", status = "active", readyForTurnIn = false },
      { id = 81003, name = "山谷回音", status = "pending", readyForTurnIn = false },
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
      questLineID = 9901,
      UiMapID = 2371,
    }, nil
  end
  Toolbox.Questlines.RequestAndDumpQuestDetailsToChat = function() end
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

    installQuestDataStubs()

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    local activeButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.active_log or nil -- 当前任务页签按钮
    local mapButton = questView.modeTabButtonByKey and questView.modeTabButtonByKey.map_questline or nil -- 任务线页签按钮
    assert.is_truthy(activeButton)
    assert.is_truthy(mapButton)
    assert.is_true(activeButton.parentFrame == hostFrame)
    assert.is_true(mapButton.parentFrame == hostFrame)
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_ACTIVE or "当前任务", activeButton:GetText())
    assert.equals(Toolbox.L.QUEST_VIEW_TAB_QUESTLINE or "任务线", mapButton:GetText())
    assert.is_true(activeButton:IsShown())
    assert.is_true(mapButton:IsShown())
    assert.is_false(questView.tabButton and questView.tabButton:IsShown() or false)
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
    assert.is_true(questView.breadcrumbFrame.parentFrame == questView.rightContent)
    local navBarLeftPoint = questView.breadcrumbFrame._points and questView.breadcrumbFrame._points[1] or nil -- 顶部路径左锚点
    assert.is_truthy(navBarLeftPoint)
    assert.is_true(navBarLeftPoint.relativeFrame == questView.rightContent)
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

    local mapButton = questView.modeTabButtonByKey.map_questline -- 任务线页签按钮
    assert.is_truthy(mapButton)
    mapButton:RunScript("OnClick")

    local leftTreeBottomPoint = questView.leftTree._points and questView.leftTree._points[2] or nil -- 任务线左树底部锚点
    local mapViewBottomPoint = questView.rightContent._points and questView.rightContent._points[2] or nil -- 任务线主区底部锚点
    assert.is_truthy(leftTreeBottomPoint)
    assert.is_truthy(mapViewBottomPoint)
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
    assert.is_true(navBarLeftPoint.relativeFrame == questView.rightContent)
    assert.is_true(navBarRightPoint.relativeFrame == questView.searchBoxFrame)
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

  it("detail_popup_jump_to_questline_updates_expansion_before_switching_view", function()
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
          questLineID = 9902,
          UiMapID = 2601,
          questLineExpansionID = 10,
        }, nil
      end
      return nil, nil
    end
    Toolbox.Questlines.RequestAndDumpQuestDetailsToChat = function() end

    local hostFrame = questHooks:getHostFrame() -- quest 主界面
    assert.is_truthy(hostFrame)
    hostFrame:Show()
    questView:setSelected(true)
    questView:refresh()

    questView.selectedModeKey = "active_log"
    questView.selectedExpansionID = 9
    questView.selectedMapID = nil
    questView.expandedQuestLineID = nil

    questView:showQuestDetailPopup(82001)
    assert.is_true(questView.detailPopupJumpButton:IsShown())

    questView.detailPopupJumpButton:RunScript("OnClick")

    assert.equals("map_questline", questView.selectedModeKey)
    assert.equals(10, questView.selectedExpansionID)
    assert.equals(2601, questView.selectedMapID)
    assert.equals(9902, questView.expandedQuestLineID)
  end)
end)

