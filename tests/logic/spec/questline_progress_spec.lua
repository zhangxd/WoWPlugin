local mockFixtureData = dofile("tests/logic/fixtures/InstanceQuestlines_Mock.lua")

local function deepCopyTable(sourceTable)
  if type(sourceTable) ~= "table" then
    return sourceTable
  end

  local copiedTable = {} -- 深拷贝结果
  for keyName, valueObject in pairs(sourceTable) do
    copiedTable[keyName] = deepCopyTable(valueObject)
  end
  return copiedTable
end

describe("QuestlineProgress mock data injection", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCQuestLog = nil -- 原始 C_QuestLog 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local originalQuestUtilsGetQuestName = nil -- 原始 QuestUtils_GetQuestName 全局
  local originalGetQuestLogIndexByID = nil -- 原始 GetQuestLogIndexByID 全局
  local originalIsQuestFlaggedCompleted = nil -- 原始 IsQuestFlaggedCompleted 全局
  local injectedMockData = nil -- 当前用例注入的 mock 数据

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCQuestLog = rawget(_G, "C_QuestLog")
    originalCMap = rawget(_G, "C_Map")
    originalQuestUtilsGetQuestName = rawget(_G, "QuestUtils_GetQuestName")
    originalGetQuestLogIndexByID = rawget(_G, "GetQuestLogIndexByID")
    originalIsQuestFlaggedCompleted = rawget(_G, "IsQuestFlaggedCompleted")

    rawset(_G, "Toolbox", {
      Data = {
        InstanceQuestlines = nil,
        QuestTypeNames = {
          [12] = "EJ_QUEST_TYPE_CAMPAIGN",
          [34] = "EJ_QUEST_TYPE_SIDE_STORY",
        },
      },
      Questlines = {},
      L = {
        EJ_QUEST_TYPE_CAMPAIGN = "Campaign",
        EJ_QUEST_TYPE_SIDE_STORY = "Side Story",
        EJ_QUEST_TYPE_UNKNOWN_FMT = "Unknown Type (%s)",
      },
    })

    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        return "Quest #" .. tostring(questID)
      end,
      GetLogIndexForQuestID = function(questID)
        if questID == 81002 or questID == 81003 then
          return 1
        end
        return 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questID == 81001
      end,
      ReadyForTurnIn = function(questID)
        return questID == 81003
      end,
      GetQuestType = function(questID)
        if questID == 81001 then
          return 34
        end
        if questID == 81002 then
          return 12
        end
        return nil
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

    local moduleChunk = assert(loadfile("Toolbox/Core/API/QuestlineProgress.lua")) -- 任务线 API chunk
    moduleChunk()

    injectedMockData = deepCopyTable(mockFixtureData)
    Toolbox.Questlines.SetDataOverride(injectedMockData)
  end)

  after_each(function()
    if rawget(_G, "Toolbox")
      and Toolbox.Questlines
      and type(Toolbox.Questlines.SetDataOverride) == "function"
    then
      Toolbox.Questlines.SetDataOverride(nil)
    end

    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "C_QuestLog", originalCQuestLog)
    rawset(_G, "C_Map", originalCMap)
    rawset(_G, "QuestUtils_GetQuestName", originalQuestUtilsGetQuestName)
    rawset(_G, "GetQuestLogIndexByID", originalGetQuestLogIndexByID)
    rawset(_G, "IsQuestFlaggedCompleted", originalIsQuestFlaggedCompleted)
  end)

  it("strict_validation_accepts_mock_fixture", function()
    local valid, errorObject = Toolbox.Questlines.ValidateInstanceQuestlinesData(injectedMockData, true) -- strict 校验结果
    assert.is_true(valid)
    assert.is_nil(errorObject)
  end)

  it("quest_runtime_state_uses_runtime_apis", function()
    assert.is_function(Toolbox.Questlines.GetQuestRuntimeState)

    local runtimeState = Toolbox.Questlines.GetQuestRuntimeState(81003)
    assert.equals("Quest #81003", runtimeState.name)
    assert.equals("active", runtimeState.status)
    assert.equals(true, runtimeState.readyForTurnIn)
    assert.is_nil(runtimeState.typeID)

    local typedState = Toolbox.Questlines.GetQuestRuntimeState(81002)
    assert.equals(12, typedState.typeID)
  end)

  it("quest_type_label_uses_mapping_and_fallback", function()
    assert.is_function(Toolbox.Questlines.GetQuestTypeLabel)
    assert.equals("Campaign", Toolbox.Questlines.GetQuestTypeLabel(12))
    assert.equals("Unknown Type (999)", Toolbox.Questlines.GetQuestTypeLabel(999))
  end)

  it("quest_tab_model_builds_type_indexes_from_runtime_fields", function()
    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 查询模型
    assert.is_nil(errorObject)
    assert.same({ 12, 34 }, model.typeList)
    assert.same({ 81002 }, model.typeToQuestIDs[12])
    assert.same({ 81001 }, model.typeToQuestIDs[34])
    assert.same({ 9901 }, model.typeToQuestLineIDs[12])
    assert.same({ 9901 }, model.typeToQuestLineIDs[34])
    assert.same({ 2371 }, model.typeToMapIDs[12])
    assert.same({ 2371 }, model.typeToMapIDs[34])
  end)

  it("quest_tab_model_uses_injected_mock_data", function()
    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 查询模型
    assert.is_nil(errorObject)
    assert.equals(1, #model.maps)

    local mapEntry = model.maps[1] -- 地图模型
    assert.equals(2371, mapEntry.id)
    assert.equals(1, #mapEntry.questLines)

    local questLineEntry = mapEntry.questLines[1] -- 任务线模型
    assert.equals(9901, questLineEntry.id)
    assert.equals(3, #questLineEntry.quests)
  end)

  it("clearing_override_falls_back_to_live_data", function()
    local liveData = deepCopyTable(mockFixtureData) -- live 数据样本
    liveData.sourceMode = "live"
    liveData.generatedAt = "2026-01-02T00:00:00Z"
    liveData.quests[81010] = { ID = 81010, UiMapID = 2371 }
    liveData.questLines[9910] = { ID = 9910, Name_lang = "Live QuestLine Beta", UiMapID = 2371 }
    liveData.questLineQuestIDs[9910] = { 81010 }
    Toolbox.Data.InstanceQuestlines = liveData

    Toolbox.Questlines.SetDataOverride(nil)
    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 清除覆盖后的模型
    assert.is_nil(errorObject)
    assert.is_truthy(model.questLineByID[9910])
  end)

  it("supports_db_shape_static_data_v4", function()
    local v4Data = {
      schemaVersion = 4,
      sourceMode = "mock",
      generatedAt = "2026-01-03T00:00:00Z",
      quests = {
        [81001] = { ID = 81001, UiMapID = 2371 },
        [81002] = { ID = 81002, UiMapID = 2371 },
      },
      questLines = {
        [9901] = { ID = 9901, Name_lang = "Mock QuestLine Alpha", UiMapID = 2371 },
      },
      questLineXQuest = {
        [9901] = {
          { QuestID = 81001, OrderIndex = 1 },
          { QuestID = 81002, OrderIndex = 2 },
        },
      },
      questPOIBlobs = {
        [81001] = {
          { BlobID = 7001, UiMapID = 2371, ObjectiveID = 17 },
        },
      },
      questPOIPoints = {
        [7001] = {
          { x = 0.11, y = 0.22, z = 0 },
        },
      },
    }

    Toolbox.Questlines.SetDataOverride(v4Data)
    local valid, errorObject = Toolbox.Questlines.ValidateInstanceQuestlinesData(v4Data, true)
    assert.is_true(valid)
    assert.is_nil(errorObject)

    local model, modelError = Toolbox.Questlines.GetQuestTabModel()
    assert.is_nil(modelError)
    assert.equals(2, #model.questLineByID[9901].quests)
    assert.same({ x = 0.11, y = 0.22, z = 0 }, model.questLineByID[9901].quests[1].mapPos)
  end)
end)
