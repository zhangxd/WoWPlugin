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

local function collectQuestLineIDs(groupList)
  local resultList = {} -- 分组内任务线 ID 列表
  for _, groupEntry in ipairs(groupList or {}) do
    local questLineIDList = {} -- 当前分组任务线 ID 列表
    for _, questLineEntry in ipairs(groupEntry.questLines or {}) do
      questLineIDList[#questLineIDList + 1] = questLineEntry.id
    end
    resultList[#resultList + 1] = {
      id = groupEntry.id,
      questLineIDs = questLineIDList,
    }
  end
  return resultList
end

describe("QuestlineProgress mock data injection", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalCQuestLog = nil -- 原始 C_QuestLog 全局
  local originalCQuestLine = nil -- 原始 C_QuestLine 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local originalQuestUtilsGetQuestName = nil -- 原始 QuestUtils_GetQuestName 全局
  local originalGetQuestLogIndexByID = nil -- 原始 GetQuestLogIndexByID 全局
  local originalIsQuestFlaggedCompleted = nil -- 原始 IsQuestFlaggedCompleted 全局
  local originalGetQuestLogQuestText = nil -- 原始 GetQuestLogQuestText 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalCTaskQuest = nil -- 原始 C_TaskQuest 全局
  local originalEnum = nil -- 原始 Enum 全局
  local injectedMockData = nil -- 当前用例注入的 mock 数据
  local questLogInfoList = nil -- Quest Log 条目列表
  local questActiveByID = nil -- 进行中任务集合
  local questCompletedByID = nil -- 已完成任务集合
  local questReadyByID = nil -- 可交付任务集合
  local questTypeByID = nil -- 任务类型集合
  local questTitleByID = nil -- 任务标题集合
  local chatMessageList = nil -- 聊天输出记录
  local eventFrameList = nil -- 事件框体记录

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalCQuestLog = rawget(_G, "C_QuestLog")
    originalCQuestLine = rawget(_G, "C_QuestLine")
    originalCMap = rawget(_G, "C_Map")
    originalQuestUtilsGetQuestName = rawget(_G, "QuestUtils_GetQuestName")
    originalGetQuestLogIndexByID = rawget(_G, "GetQuestLogIndexByID")
    originalIsQuestFlaggedCompleted = rawget(_G, "IsQuestFlaggedCompleted")
    originalGetQuestLogQuestText = rawget(_G, "GetQuestLogQuestText")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalCTaskQuest = rawget(_G, "C_TaskQuest")
    originalEnum = rawget(_G, "Enum")

    chatMessageList = {}
    eventFrameList = {}
    rawset(_G, "Toolbox", {
      Data = {
        InstanceQuestlines = nil,
        QuestTypeNames = {
          [12] = "EJ_QUEST_TYPE_CAMPAIGN",
          [34] = "EJ_QUEST_TYPE_SIDE_STORY",
        },
      },
      Questlines = {},
      Chat = {
        PrintAddonMessage = function(messageText)
          chatMessageList[#chatMessageList + 1] = tostring(messageText or "")
        end,
      },
      L = {
        EJ_QUEST_TYPE_CAMPAIGN = "Campaign",
        EJ_QUEST_TYPE_SIDE_STORY = "Side Story",
        EJ_QUEST_TYPE_UNKNOWN_FMT = "Unknown Type (%s)",
        EJ_QUEST_EXPANSION_9 = "Dragonflight",
        EJ_QUEST_EXPANSION_10 = "The War Within",
        EJ_QUEST_EXPANSION_UNKNOWN_FMT = "Expansion #%s",
      },
    })

    questLogInfoList = {
      { questID = 81002, title = "Quest #81002", isHeader = false, isHidden = false },
      { questID = 81003, title = "Quest #81003", isHeader = false, isHidden = false },
    }
    questActiveByID = {
      [81002] = true,
      [81003] = true,
    }
    questCompletedByID = {
      [81001] = true,
    }
    questReadyByID = {
      [81003] = true,
    }
    questTypeByID = {
      [81001] = 34,
      [81002] = 12,
    }
    questTitleByID = {
      [81001] = "Quest #81001",
      [81002] = "Quest #81002",
      [81003] = "Quest #81003",
    }

    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        return questTitleByID[questID] or ("Quest #" .. tostring(questID))
      end,
      GetLogIndexForQuestID = function(questID)
        return questActiveByID[questID] == true and 1 or 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questCompletedByID[questID] == true
      end,
      ReadyForTurnIn = function(questID)
        return questReadyByID[questID] == true
      end,
      GetQuestType = function(questID)
        return questTypeByID[questID]
      end,
      GetQuestTagInfo = function(questID)
        if questID == 81002 then
          return {
            tagID = 12,
            tagName = "Campaign",
          }
        end
        return nil
      end,
      GetNumQuestLogEntries = function()
        return #questLogInfoList, #questLogInfoList
      end,
      GetInfo = function(index)
        return questLogInfoList[index]
      end,
    })
    rawset(_G, "GetQuestLogQuestText", function(logIndex)
      return "Quest description #" .. tostring(logIndex), "Quest objective text #" .. tostring(logIndex)
    end)
    rawset(_G, "C_Map", {
      GetMapInfo = function(uiMapID)
        if uiMapID == 2022 then
          return { mapID = 2022, name = "Quest Zone", parentMapID = 2023, mapType = 3 }
        end
        if uiMapID == 2023 then
          return { mapID = 2023, name = "Quest Parent", parentMapID = 2024, mapType = 3 }
        end
        if uiMapID == 2024 then
          return { mapID = 2024, name = "Quest Continent", parentMapID = 0, mapType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2 }
        end
        return { mapID = uiMapID, name = "Map #" .. tostring(uiMapID), parentMapID = 0, mapType = 3 }
      end,
    })
    rawset(_G, "C_TaskQuest", {
      GetQuestZoneID = function(questID)
        if questID == 99901 then
          return 2022
        end
        return nil
      end,
    })
    rawset(_G, "Enum", rawget(_G, "Enum") or { UIMapType = { Continent = 2 } })
    rawset(_G, "QuestUtils_GetQuestName", nil)
    rawset(_G, "GetQuestLogIndexByID", function()
      return 0
    end)
    rawset(_G, "IsQuestFlaggedCompleted", function()
      return false
    end)
    rawset(_G, "CreateFrame", function()
      local frameObject = {
        registeredEvents = {},
        scriptMap = {},
      }
      function frameObject:RegisterEvent(eventName)
        self.registeredEvents[eventName] = true
      end
      function frameObject:UnregisterEvent(eventName)
        self.registeredEvents[eventName] = nil
      end
      function frameObject:SetScript(scriptName, handler)
        self.scriptMap[scriptName] = handler
      end
      eventFrameList[#eventFrameList + 1] = frameObject
      return frameObject
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
    rawset(_G, "C_QuestLine", originalCQuestLine)
    rawset(_G, "C_Map", originalCMap)
    rawset(_G, "QuestUtils_GetQuestName", originalQuestUtilsGetQuestName)
    rawset(_G, "GetQuestLogIndexByID", originalGetQuestLogIndexByID)
    rawset(_G, "IsQuestFlaggedCompleted", originalIsQuestFlaggedCompleted)
    rawset(_G, "GetQuestLogQuestText", originalGetQuestLogQuestText)
    rawset(_G, "CreateFrame", originalCreateFrame)
    rawset(_G, "C_TaskQuest", originalCTaskQuest)
    rawset(_G, "Enum", originalEnum)
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

  it("quest_line_display_name_prefers_runtime_api_name", function()
    rawset(_G, "C_QuestLine", {
      GetQuestLineInfo = function(questID)
        if questID == 81002 then
          return {
            questLineID = 9901,
            questLineName = "Live QuestLine Alpha",
          }
        end
        return nil
      end,
    })

    assert.is_function(Toolbox.Questlines.GetQuestLineDisplayName)

    local displayName, errorObject = Toolbox.Questlines.GetQuestLineDisplayName(9901)
    assert.is_nil(errorObject)
    assert.equals("Live QuestLine Alpha", displayName)
  end)

  it("quest_line_display_name_falls_back_to_static_name_when_runtime_name_missing", function()
    rawset(_G, "C_QuestLine", {
      GetQuestLineInfo = function()
        return {
          questLineID = 9901,
          questLineName = nil,
        }
      end,
    })

    assert.is_function(Toolbox.Questlines.GetQuestLineDisplayName)

    local displayName, errorObject = Toolbox.Questlines.GetQuestLineDisplayName(9901)
    assert.is_nil(errorObject)
    assert.equals("QuestLine #9901", displayName)
  end)

  it("supports_v6_without_questline_name_field_and_falls_back_to_id_label", function()
    local v6Data = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-01-03T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
        [81002] = { ID = 81002 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001, 81002 } },
      },
      expansions = {
        [0] = { 9901 },
      },
    }

    rawset(_G, "C_QuestLine", nil)
    Toolbox.Questlines.SetDataOverride(v6Data)

    local valid, errorObject = Toolbox.Questlines.ValidateInstanceQuestlinesData(v6Data, true)
    assert.is_true(valid)
    assert.is_nil(errorObject)

    local model, modelError = Toolbox.Questlines.GetQuestTabModel()
    assert.is_nil(modelError)
    assert.is_nil(model.questLineByID[9901].name)

    local displayName, displayError = Toolbox.Questlines.GetQuestLineDisplayName(9901)
    assert.is_nil(displayError)
    assert.equals("QuestLine #9901", displayName)
  end)

  it("current_quest_log_entries_include_mapped_and_unmapped_quests", function()
    assert.is_function(Toolbox.Questlines.GetCurrentQuestLogEntries)

    questLogInfoList = {
      { questID = 81002, title = "Quest #81002", isHeader = false, isHidden = false },
      { title = "Campaign Header", isHeader = true, isHidden = false },
      { questID = 99901, title = "Live Quest #99901", isHeader = false, isHidden = false },
      { questID = 81003, title = "Quest #81003", isHeader = false, isHidden = false },
    }
    questActiveByID[99901] = true
    questTitleByID[99901] = "Live Quest #99901"

    local questEntryList, errorObject = Toolbox.Questlines.GetCurrentQuestLogEntries()
    assert.is_nil(errorObject)
    assert.equals(3, #questEntryList)

    assert.equals(81002, questEntryList[1].questID)
    assert.equals(9901, questEntryList[1].questLineID)
    assert.is_nil(questEntryList[1].UiMapID)

    assert.equals(99901, questEntryList[2].questID)
    assert.equals("Live Quest #99901", questEntryList[2].name)
    assert.is_nil(questEntryList[2].questLineID)
    assert.is_nil(questEntryList[2].questLineName)
    assert.is_nil(questEntryList[2].UiMapID)

    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(99901)
    assert.is_nil(detailError)
    assert.equals(99901, detailObject.questID)
    assert.equals("Live Quest #99901", detailObject.name)
    assert.is_nil(detailObject.questLineID)
    assert.is_nil(detailObject.questLineName)

    assert.equals(81003, questEntryList[3].questID)
    assert.equals(true, questEntryList[3].readyForTurnIn)
  end)

  it("request_and_dump_quest_details_to_chat_waits_for_async_load_result", function()
    local requestQuestIDList = {} -- 已请求加载的任务 ID 列表

    questActiveByID = {}
    questTitleByID[99901] = nil
    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        return questTitleByID[questID]
      end,
      GetLogIndexForQuestID = function(questID)
        if questID == 99901 then
          return 0
        end
        return questActiveByID[questID] == true and 1 or 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questCompletedByID[questID] == true
      end,
      ReadyForTurnIn = function(questID)
        return questReadyByID[questID] == true
      end,
      GetQuestType = function(questID)
        return questTypeByID[questID]
      end,
      GetQuestTagInfo = function()
        return {
          tagID = 77,
          tagName = "World Quest",
          worldQuestType = 3,
        }
      end,
      GetQuestObjectives = function(questID)
        if questID ~= 99901 then
          return nil
        end
        return {
          {
            text = "Collect 5 fragments",
            type = "monster",
            finished = false,
            numFulfilled = 2,
            numRequired = 5,
          },
        }
      end,
      RequestLoadQuestByID = function(questID)
        requestQuestIDList[#requestQuestIDList + 1] = questID
        return true
      end,
      GetNumQuestLogEntries = function()
        return 0, 0
      end,
      GetInfo = function()
        return nil
      end,
    })
    rawset(_G, "C_QuestLine", {
      GetQuestLineInfo = function(questID, uiMapID)
        if questID == 99901 and uiMapID == 2022 then
          return {
            questLineID = 7001,
            questLineName = "Async API QuestLine",
            campaignID = 55,
          }
        end
        return nil
      end,
    })

    assert.is_function(Toolbox.Questlines.RequestAndDumpQuestDetailsToChat)
    local accepted, requestState = Toolbox.Questlines.RequestAndDumpQuestDetailsToChat(99901)
    assert.is_true(accepted)
    assert.equals("pending", requestState)
    assert.same({ 99901 }, requestQuestIDList)
    assert.equals(0, #chatMessageList)
    assert.equals(1, #eventFrameList)
    assert.is_true(eventFrameList[1].registeredEvents.QUEST_DATA_LOAD_RESULT == true)

    questTitleByID[99901] = "Async Quest #99901"
    local onEventHandler = eventFrameList[1].scriptMap.OnEvent -- 异步事件处理器
    assert.is_function(onEventHandler)
    onEventHandler(eventFrameList[1], "QUEST_DATA_LOAD_RESULT", 99901, true)

    assert.is_true(#chatMessageList >= 3)
    local outputText = table.concat(chatMessageList, "\n") -- 汇总聊天输出
    assert.is_true(string.find(outputText, "Async Quest #99901", 1, true) ~= nil)
    assert.is_true(string.find(outputText, "Collect 5 fragments", 1, true) ~= nil)
    assert.is_true(string.find(outputText, "Quest Zone(2022)", 1, true) ~= nil)
    assert.is_true(string.find(outputText, "Quest Continent(2024)", 1, true) ~= nil)
    assert.is_true(string.find(outputText, "Async API QuestLine", 1, true) ~= nil)
  end)

  it("quest_type_label_uses_mapping_and_fallback", function()
    assert.is_function(Toolbox.Questlines.GetQuestTypeLabel)
    assert.equals("Campaign", Toolbox.Questlines.GetQuestTypeLabel(12))
    assert.equals("Unknown Type (999)", Toolbox.Questlines.GetQuestTypeLabel(999))
  end)

  it("quest_tab_model_keeps_structure_static_without_full_runtime_queries", function()
    local titleCallCount = 0 -- 任务名查询次数
    local logIndexCallCount = 0 -- 任务日志查询次数
    local readyCallCount = 0 -- 可交付查询次数
    local typeCallCount = 0 -- 类型查询次数

    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        titleCallCount = titleCallCount + 1
        return "Quest #" .. tostring(questID)
      end,
      GetLogIndexForQuestID = function(questID)
        logIndexCallCount = logIndexCallCount + 1
        if questID == 81002 or questID == 81003 then
          return 1
        end
        return 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questID == 81001
      end,
      ReadyForTurnIn = function(questID)
        readyCallCount = readyCallCount + 1
        return questID == 81003
      end,
      GetQuestType = function(questID)
        typeCallCount = typeCallCount + 1
        if questID == 81001 then
          return 34
        end
        if questID == 81002 then
          return 12
        end
        return nil
      end,
    })

    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 查询模型
    assert.is_nil(errorObject)
    assert.equals(0, titleCallCount)
    assert.equals(0, logIndexCallCount)
    assert.equals(0, readyCallCount)
    assert.equals(0, typeCallCount)
    assert.same({ 81001, 81002, 81003 }, model.questLineByID[9901].questIDs)
    assert.equals(3, model.questLineByID[9901].questCount)
  end)

  it("quest_type_index_builds_type_indexes_from_runtime_fields_on_demand", function()
    assert.is_function(Toolbox.Questlines.GetQuestTypeIndex)

    local typeIndex, errorObject = Toolbox.Questlines.GetQuestTypeIndex()
    assert.is_nil(errorObject)
    assert.same({
      { id = 12, name = "Campaign" },
      { id = 34, name = "Unknown Type (34)" },
    }, typeIndex.typeList)
    assert.same({ 81002 }, typeIndex.typeToQuestIDs[12])
    assert.same({ 81001 }, typeIndex.typeToQuestIDs[34])
    assert.same({ 9901 }, typeIndex.typeToQuestLineIDs[12])
    assert.same({ 9901 }, typeIndex.typeToQuestLineIDs[34])
    assert.same({ 2371 }, typeIndex.typeToMapIDs[12])
    assert.same({ 2371 }, typeIndex.typeToMapIDs[34])
  end)

  it("quest_navigation_model_groups_questlines_by_expansion_and_category", function()
    local v6Data = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-12T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
        [81002] = { ID = 81002 },
        [81003] = { ID = 81003 },
        [81004] = { ID = 81004 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001, 81002 } },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81003 } },
        [9903] = { ID = 9903, UiMapID = 2373, QuestIDs = { 81004 } },
      },
      expansions = {
        [9] = { 9901, 9902 },
        [10] = { 9903 },
      },
    }

    questTypeByID = {
      [81001] = 12,
      [81002] = 12,
      [81003] = 34,
      [81004] = 12,
    }
    rawset(_G, "C_Map", {
      GetMapInfo = function(uiMapID)
        local nameByMapID = {
          [2371] = "Waking Shores",
          [2372] = "Ohn'ahran Plains",
          [2373] = "Isle of Dorn",
        }
        return { name = nameByMapID[uiMapID] or ("Map #" .. tostring(uiMapID)) }
      end,
    })

    Toolbox.Questlines.SetDataOverride(v6Data)

    local valid, validationError = Toolbox.Questlines.ValidateInstanceQuestlinesData(v6Data, true)
    assert.is_true(valid)
    assert.is_nil(validationError)

    assert.is_function(Toolbox.Questlines.GetQuestNavigationModel)
    local navigationModel, navigationError = Toolbox.Questlines.GetQuestNavigationModel()
    assert.is_nil(navigationError)
    assert.same({
      { id = 9, name = "Dragonflight" },
      { id = 10, name = "The War Within" },
    }, navigationModel.expansionList)

    assert.same({
      { id = 2371, questLineIDs = { 9901 } },
      { id = 2372, questLineIDs = { 9902 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[9].modeByKey.map_questline.entries))
    assert.same({
      { id = "type:12", questLineIDs = { 9901 } },
      { id = "type:34", questLineIDs = { 9902 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[9].modeByKey.quest_type.entries))
    assert.same({
      { id = 2373, questLineIDs = { 9903 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[10].modeByKey.map_questline.entries))
    assert.same({
      { id = "type:12", questLineIDs = { 9903 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[10].modeByKey.quest_type.entries))
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
    assert.same({ 81001, 81002, 81003 }, questLineEntry.questIDs)
    assert.equals(3, questLineEntry.questCount)
  end)

  it("clearing_override_falls_back_to_live_data", function()
    local liveData = deepCopyTable(mockFixtureData) -- live 数据样本
    liveData.sourceMode = "live"
    liveData.generatedAt = "2026-01-02T00:00:00Z"
    liveData.quests[81010] = { ID = 81010 }
    liveData.questLines[9910] = { ID = 9910, UiMapID = 2371, QuestIDs = { 81010 } }
    liveData.expansions[0][#liveData.expansions[0] + 1] = 9910
    Toolbox.Data.InstanceQuestlines = liveData

    Toolbox.Questlines.SetDataOverride(nil)
    local model, errorObject = Toolbox.Questlines.GetQuestTabModel() -- 清除覆盖后的模型
    assert.is_nil(errorObject)
    assert.is_truthy(model.questLineByID[9910])
  end)

  it("supports_db_shape_static_data_v6", function()
    local v6Data = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-01-03T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
        [81002] = { ID = 81002 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001, 81002 } },
      },
      expansions = {
        [0] = { 9901 },
      },
    }

    Toolbox.Questlines.SetDataOverride(v6Data)
    local valid, errorObject = Toolbox.Questlines.ValidateInstanceQuestlinesData(v6Data, true)
    assert.is_true(valid)
    assert.is_nil(errorObject)

    local model, modelError = Toolbox.Questlines.GetQuestTabModel()
    assert.is_nil(modelError)
    assert.same({ 81001, 81002 }, model.questLineByID[9901].questIDs)
    assert.equals(2, model.questLineByID[9901].questCount)

    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(81001)
    assert.is_nil(detailError)
    assert.is_nil(detailObject.mapPos)
  end)
end)
