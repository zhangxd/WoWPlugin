describe("QuestlineProgress live data validation", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCQuestLog = nil -- 原始 C_QuestLog 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local originalQuestUtilsGetQuestName = nil -- 原始 QuestUtils_GetQuestName 全局
  local originalGetQuestLogIndexByID = nil -- 原始 GetQuestLogIndexByID 全局
  local originalIsQuestFlaggedCompleted = nil -- 原始 IsQuestFlaggedCompleted 全局

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCQuestLog = rawget(_G, "C_QuestLog")
    originalCMap = rawget(_G, "C_Map")
    originalQuestUtilsGetQuestName = rawget(_G, "QuestUtils_GetQuestName")
    originalGetQuestLogIndexByID = rawget(_G, "GetQuestLogIndexByID")
    originalIsQuestFlaggedCompleted = rawget(_G, "IsQuestFlaggedCompleted")

    rawset(_G, "Toolbox", {
      Data = {},
      Questlines = {},
      L = {
        EJ_QUEST_EXPANSION_UNKNOWN_FMT = "Expansion #%s",
        EJ_QUEST_EXPANSION_0 = "Classic",
        EJ_QUEST_EXPANSION_1 = "The Burning Crusade",
        EJ_QUEST_EXPANSION_2 = "Wrath of the Lich King",
        EJ_QUEST_EXPANSION_3 = "Cataclysm",
        EJ_QUEST_EXPANSION_4 = "Mists of Pandaria",
        EJ_QUEST_EXPANSION_5 = "Warlords of Draenor",
        EJ_QUEST_EXPANSION_6 = "Legion",
        EJ_QUEST_EXPANSION_7 = "Battle for Azeroth",
        EJ_QUEST_EXPANSION_8 = "Shadowlands",
        EJ_QUEST_EXPANSION_9 = "Dragonflight",
        EJ_QUEST_EXPANSION_10 = "The War Within",
      },
    })
    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        return "Quest #" .. tostring(questID)
      end,
      GetLogIndexForQuestID = function()
        return 0
      end,
      IsQuestFlaggedCompleted = function()
        return false
      end,
    })
    rawset(_G, "C_Map", {
      GetMapInfo = function(uiMapID)
        return { name = "Map #" .. tostring(uiMapID) }
      end,
    })
    rawset(_G, "QuestUtils_GetQuestName", nil)
    rawset(_G, "GetQuestLogIndexByID", function()
      return 0
    end)
    rawset(_G, "IsQuestFlaggedCompleted", function()
      return false
    end)

    local dataChunk = assert(loadfile("Toolbox/Data/InstanceQuestlines.lua")) -- live 数据 chunk
    dataChunk()

    local apiChunk = assert(loadfile("Toolbox/Core/API/QuestlineProgress.lua")) -- 任务线 API chunk
    apiChunk()
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "C_QuestLog", originalCQuestLog)
    rawset(_G, "C_Map", originalCMap)
    rawset(_G, "QuestUtils_GetQuestName", originalQuestUtilsGetQuestName)
    rawset(_G, "GetQuestLogIndexByID", originalGetQuestLogIndexByID)
    rawset(_G, "IsQuestFlaggedCompleted", originalIsQuestFlaggedCompleted)
  end)

  it("get_quest_tab_model_stays_available_even_if_live_data_has_bad_refs", function()
    local dataTable = Toolbox.Data and Toolbox.Data.InstanceQuestlines -- live 根数据
    assert.is_truthy(type(dataTable) == "table")

    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 任务页签模型
    if errorObject ~= nil then
      local messageText = string.format(
        "live model build failed: code=%s path=%s message=%s",
        tostring(errorObject and errorObject.code),
        tostring(errorObject and errorObject.path),
        tostring(errorObject and errorObject.message)
      )
      error(messageText)
    end
    assert.is_truthy(type(model) == "table")
    assert.is_truthy(type(model.maps) == "table")
  end)

  it("db_shape_live_data_uses_schema_v9_core_blocks", function()
    local dataTable = Toolbox.Data and Toolbox.Data.InstanceQuestlines -- live 根数据
    assert.is_truthy(type(dataTable) == "table")

    assert.equals(9, dataTable.schemaVersion)
    assert.is_truthy(type(dataTable.quests) == "table")
    assert.is_truthy(type(dataTable.questLines) == "table")
    assert.is_truthy(type(dataTable.campaigns) == "table")
    assert.is_truthy(type(dataTable.expansions) == "table")
    assert.is_truthy(type(dataTable.expansionCampaigns) == "table")
    assert.is_truthy(type(dataTable.achievements) == "table")
    assert.is_truthy(type(dataTable.expansionAchievements) == "table")
    assert.is_nil(dataTable.questLineXQuest)
    assert.is_nil(dataTable.questPOIBlobs)
    assert.is_nil(dataTable.questPOIPoints)

    for _, questEntry in pairs(dataTable.quests or {}) do
      assert.is_truthy(type(questEntry) == "table")
      assert.is_truthy(type(questEntry.ID) == "number")
      assert.is_nil(questEntry.UiMapID)
    end

    for _, questLineEntry in pairs(dataTable.questLines or {}) do
      assert.is_truthy(type(questLineEntry) == "table")
      assert.is_truthy(type(questLineEntry.ID) == "number")
      assert.is_truthy(type(questLineEntry.UiMapID) == "number")
      assert.is_truthy(type(questLineEntry.QuestIDs) == "table")
    end

    for _, achievementEntry in pairs(dataTable.achievements or {}) do
      assert.is_truthy(type(achievementEntry) == "table")
      assert.is_truthy(type(achievementEntry.ID) == "number")
      assert.is_truthy(type(achievementEntry.FactionTags) == "table")
      assert.is_true(#achievementEntry.FactionTags > 0)
    end
  end)

  it("quest_navigation_model_uses_live_expansion_ids", function()
    local navigationModel, errorObject = Toolbox.Questlines.GetQuestNavigationModel() -- 资料片导航模型
    if errorObject ~= nil then
      local messageText = string.format(
        "live navigation build failed: code=%s path=%s message=%s",
        tostring(errorObject and errorObject.code),
        tostring(errorObject and errorObject.path),
        tostring(errorObject and errorObject.message)
      )
      error(messageText)
    end

    assert.is_truthy(type(navigationModel) == "table")
    assert.is_truthy(type(navigationModel.expansionList) == "table")
    assert.is_true(#navigationModel.expansionList > 0)
    assert.is_truthy(type(navigationModel.expansionByID) == "table")

    local firstExpansion = navigationModel.expansionList[1] -- 首个资料片入口
    assert.is_truthy(type(firstExpansion) == "table")
    assert.is_truthy(type(firstExpansion.id) == "number")
    assert.is_truthy(type(firstExpansion.name) == "string" and firstExpansion.name ~= "")

    local expansionEntry = navigationModel.expansionByID[firstExpansion.id] -- 首个资料片详情
    assert.is_truthy(type(expansionEntry) == "table")
    assert.is_truthy(type(expansionEntry.modes) == "table")
    assert.is_truthy(type(expansionEntry.modeByKey) == "table")
  end)
end)
