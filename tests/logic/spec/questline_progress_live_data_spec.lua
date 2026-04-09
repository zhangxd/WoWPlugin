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
end)
