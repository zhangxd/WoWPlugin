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
      },
      Questlines = {},
    })

    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        return "Quest #" .. tostring(questID)
      end,
      GetLogIndexForQuestID = function()
        return 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questID == 81001
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
end)
