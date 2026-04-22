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
  local originalUnitFactionGroup = nil -- 原始 UnitFactionGroup 全局
  local originalUnitRace = nil -- 原始 UnitRace 全局
  local originalUnitClass = nil -- 原始 UnitClass 全局
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
    originalUnitFactionGroup = rawget(_G, "UnitFactionGroup")
    originalUnitRace = rawget(_G, "UnitRace")
    originalUnitClass = rawget(_G, "UnitClass")

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
        EJ_QUEST_TYPE_DEFAULT = "Normal Quest",
        EJ_QUEST_TYPE_UNKNOWN_FMT = "Unknown Type (%s)",
        EJ_QUEST_EXPANSION_VERSION_FMT = "Expansion %d · %s",
        EJ_QUEST_EXPANSION_0 = "Classic",
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
    rawset(_G, "UnitFactionGroup", function()
      return "Alliance", "Alliance"
    end)
    rawset(_G, "UnitRace", function()
      return "Human", "Human", 1
    end)
    rawset(_G, "UnitClass", function()
      return "Warrior", "WARRIOR", 1
    end)
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
    rawset(_G, "UnitFactionGroup", originalUnitFactionGroup)
    rawset(_G, "UnitRace", originalUnitRace)
    rawset(_G, "UnitClass", originalUnitClass)
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
    assert.equals(2371, questEntryList[1].UiMapID)

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

  it("current_quest_log_entries_prefer_runtime_quest_and_questline_names", function()
    questLogInfoList = {
      { questID = 81002, title = "Stale Quest Log Title", isHeader = false, isHidden = false },
    }
    questTitleByID[81002] = "Runtime Quest Title"
    rawset(_G, "C_QuestLine", {
      GetQuestLineInfo = function(questID)
        if questID == 81002 then
          return {
            questLineID = 9901,
            questLineName = "Runtime QuestLine Title",
          }
        end
        return nil
      end,
    })

    local questEntryList, errorObject = Toolbox.Questlines.GetCurrentQuestLogEntries()
    assert.is_nil(errorObject)
    assert.equals(1, #questEntryList)
    assert.equals("Runtime Quest Title", questEntryList[1].name)
    assert.equals("Runtime QuestLine Title", questEntryList[1].questLineName)

    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(81002)
    assert.is_nil(detailError)
    assert.equals("Runtime QuestLine Title", detailObject.questLineName)
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
    assert.equals("Normal Quest", Toolbox.Questlines.GetQuestTypeLabel(999))
  end)

  it("quest_type_label_supports_direct_name_mapping", function()
    Toolbox.Data.QuestTypeNames[88] = "团队（10）"
    assert.equals("团队（10）", Toolbox.Questlines.GetQuestTypeLabel(88))
  end)

  it("quest_detail_includes_type_label_for_inline_display", function()
    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(81002)
    assert.is_nil(detailError)
    assert.equals(12, detailObject.typeID)
    assert.equals("Campaign", detailObject.typeLabel)
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
      { id = 34, name = "Normal Quest" },
    }, typeIndex.typeList)
    assert.same({ 81002 }, typeIndex.typeToQuestIDs[12])
    assert.same({ 81001 }, typeIndex.typeToQuestIDs[34])
    assert.same({ 9901 }, typeIndex.typeToQuestLineIDs[12])
    assert.same({ 9901 }, typeIndex.typeToQuestLineIDs[34])
    assert.same({ 2371 }, typeIndex.typeToMapIDs[12])
    assert.same({ 2371 }, typeIndex.typeToMapIDs[34])
  end)

  it("quest_navigation_expansion_label_uses_plain_expansion_name_without_version_prefix", function()
    local v6Data = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-20T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 } },
      },
      expansions = {
        [0] = { 9901 },
      },
    }

    Toolbox.Questlines.SetDataOverride(v6Data)

    local navigationModel, navigationError = Toolbox.Questlines.GetQuestNavigationModel()
    assert.is_nil(navigationError)
    assert.same({
      { id = 0, name = "Classic" },
    }, navigationModel.expansionList)
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
      { id = 2372, questLineIDs = { 9902 } },
      { id = 2371, questLineIDs = { 9901 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[9].modeByKey.map_questline.entries))
    assert.same({
      { id = 2373, questLineIDs = { 9903 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[10].modeByKey.map_questline.entries))
    assert.is_nil(navigationModel.expansionByID[9].modeByKey.quest_type)
    assert.is_nil(navigationModel.expansionByID[10].modeByKey.quest_type)
  end)

  it("quest_navigation_model_groups_questlines_by_expansion_and_campaign_for_schema_v7", function()
    local v7Data = {
      schemaVersion = 7,
      sourceMode = "mock",
      generatedAt = "2026-04-21T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
        [81002] = { ID = 81002 },
        [81003] = { ID = 81003 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 }, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81002 }, ContentExpansionID = 9 },
        [9903] = { ID = 9903, UiMapID = 2601, QuestIDs = { 81003 }, ContentExpansionID = 10 },
      },
      campaigns = {
        [5001] = { ID = 5001, Name_lang = "Dragonflight Main", QuestLineIDs = { 9901, 9902 } },
        [6001] = { ID = 6001, Name_lang = "The War Within Main", QuestLineIDs = { 9903 } },
      },
      expansions = {
        [9] = { 9901, 9902 },
        [10] = { 9903 },
      },
      expansionCampaigns = {
        [9] = { 5001 },
        [10] = { 6001 },
      },
    }

    Toolbox.Questlines.SetDataOverride(v7Data)

    local valid, validationError = Toolbox.Questlines.ValidateInstanceQuestlinesData(v7Data, true)
    assert.is_true(valid)
    assert.is_nil(validationError)

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
      { id = 2601, questLineIDs = { 9903 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[10].modeByKey.map_questline.entries))
    assert.same({
      { id = 5001, questLineIDs = { 9901, 9902 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[9].modeByKey.campaign.entries))
    assert.same({
      { id = 6001, questLineIDs = { 9903 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[10].modeByKey.campaign.entries))
    assert.equals("campaign", navigationModel.expansionByID[9].modeByKey.campaign.entries[1].kind)
    assert.equals("Dragonflight Main", navigationModel.expansionByID[9].modeByKey.campaign.entries[1].name)
  end)

  it("quest_navigation_model_filters_achievement_entries_by_player_faction_for_schema_v9", function()
    local v9Data = {
      schemaVersion = 9,
      sourceMode = "mock",
      generatedAt = "2026-04-23T00:00:00Z",
      quests = {
        [81001] = { ID = 81001 },
        [81002] = { ID = 81002 },
        [81003] = { ID = 81003 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 }, FactionTags = { "alliance" }, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81002 }, FactionTags = { "horde" }, ContentExpansionID = 9 },
        [9903] = { ID = 9903, UiMapID = 2373, QuestIDs = { 81003 }, FactionTags = { "shared" }, ContentExpansionID = 9 },
      },
      campaigns = {},
      expansions = {
        [9] = { 9901, 9902, 9903 },
      },
      expansionCampaigns = {},
      achievements = {
        [7001] = { ID = 7001, Name_lang = "Alliance Achievement", QuestLineIDs = { 9901 }, FactionTags = { "alliance" }, ContentExpansionID = 9 },
        [7002] = { ID = 7002, Name_lang = "Horde Achievement", QuestLineIDs = { 9902 }, FactionTags = { "horde" }, ContentExpansionID = 9 },
        [7003] = { ID = 7003, Name_lang = "Shared Achievement", QuestLineIDs = { 9903 }, FactionTags = { "shared" }, ContentExpansionID = 9 },
        [7004] = { ID = 7004, Name_lang = "Mixed Achievement", QuestLineIDs = { 9901, 9902 }, FactionTags = { "alliance", "horde" }, ContentExpansionID = 9 },
      },
      expansionAchievements = {
        [9] = { 7001, 7002, 7003, 7004 },
      },
    }

    Toolbox.Questlines.SetDataOverride(v9Data)

    local valid, validationError = Toolbox.Questlines.ValidateInstanceQuestlinesData(v9Data, true)
    assert.is_true(valid)
    assert.is_nil(validationError)

    local navigationModel, navigationError = Toolbox.Questlines.GetQuestNavigationModel()
    assert.is_nil(navigationError)

    local achievementEntryList = navigationModel.expansionByID[9].modeByKey.achievement.entries -- 成就条目列表
    local achievementIDList = {} -- 成就 ID 列表
    local factionTagListByAchievementID = {} -- 成就阵营标记集合
    for _, achievementEntry in ipairs(achievementEntryList or {}) do
      achievementIDList[#achievementIDList + 1] = achievementEntry.id
      factionTagListByAchievementID[achievementEntry.id] = achievementEntry.factionTags
    end
    table.sort(achievementIDList)

    -- 当前测试角色阵营固定为联盟，仅显示联盟/通用成就
    assert.same({ 7001, 7003, 7004 }, achievementIDList)
    assert.same({ "alliance" }, factionTagListByAchievementID[7001])
    assert.same({ "shared" }, factionTagListByAchievementID[7003])
    assert.same({ "alliance", "horde" }, factionTagListByAchievementID[7004])
  end)

  it("GetQuestLinesForMap scopes results to the selected expansion when provided", function()
    local v6Data = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-15T00:00:00Z",
      quests = {
        [81001] = { ID = 81001, QuestLineIDs = { 9901 }, UiMapIDs = { 2371 }, FactionTags = {}, FactionConditions = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [81002] = { ID = 81002, QuestLineIDs = { 9902 }, UiMapIDs = { 2371 }, FactionTags = {}, FactionConditions = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 10 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 }, UiMapIDs = { 2371 }, PrimaryUiMapID = 2371, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2371, QuestIDs = { 81002 }, UiMapIDs = { 2371 }, PrimaryUiMapID = 2371, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 10 },
      },
      expansions = {
        [9] = { 9901 },
        [10] = { 9902 },
      },
    }

    Toolbox.Questlines.SetDataOverride(v6Data)

    local allQuestLines, allError = Toolbox.Questlines.GetQuestLinesForMap(2371)
    assert.is_nil(allError)
    assert.same({ 9901, 9902 }, { allQuestLines[1].id, allQuestLines[2].id })

    local scopedQuestLines, scopedError = Toolbox.Questlines.GetQuestLinesForMap(2371, 9)
    assert.is_nil(scopedError)
    assert.same({ 9901 }, { scopedQuestLines[1].id })
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

  it("strict_validation_allows_shared_quest_ids_across_multiple_questlines_when_quest_declares_links", function()
    local sharedData = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-15T00:00:00Z",
      quests = {
        [81001] = { ID = 81001, QuestLineIDs = { 9901, 9902 }, UiMapIDs = { 2371 }, FactionTags = {}, FactionConditions = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 }, UiMapIDs = { 2371 }, PrimaryUiMapID = 2371, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81001 }, UiMapIDs = { 2372 }, PrimaryUiMapID = 2372, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
      },
      expansions = {
        [9] = { 9901, 9902 },
      },
    }

    local valid, errorObject = Toolbox.Questlines.ValidateInstanceQuestlinesData(sharedData, true)
    assert.is_true(valid)
    assert.is_nil(errorObject)
  end)

  it("quest_detail_prefers_context_questline_for_shared_tasks", function()
    local sharedData = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-15T00:00:00Z",
      quests = {
        [81001] = {
          ID = 81001,
          QuestLineIDs = { 9901, 9902 },
          UiMapIDs = { 2371, 2372 },
          FactionTags = {},
          FactionConditions = {},
          RaceMaskValues = {},
          ClassMaskValues = {},
          ContentExpansionID = 9,
        },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001 }, UiMapIDs = { 2371 }, PrimaryUiMapID = 2371, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81001 }, UiMapIDs = { 2372 }, PrimaryUiMapID = 2372, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = {}, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 10 },
      },
      expansions = {
        [9] = { 9901 },
        [10] = { 9902 },
      },
    }

    Toolbox.Questlines.SetDataOverride(sharedData)

    local detailObject, detailError = Toolbox.Questlines.GetQuestDetailByID(81001, {
      questLineID = 9902,
      expansionID = 10,
      mapID = 2372,
    })
    assert.is_nil(detailError)
    assert.equals(9902, detailObject.questLineID)
    assert.equals(2372, detailObject.UiMapID)
  end)

  it("filters quests and questlines by faction and class restrictions", function()
    local filteredData = {
      schemaVersion = 6,
      sourceMode = "mock",
      generatedAt = "2026-04-15T00:00:00Z",
      quests = {
        [81001] = { ID = 81001, QuestLineIDs = { 9901 }, UiMapIDs = { 2371 }, FactionTags = { "alliance" }, FactionConditions = { "alliance" }, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [81002] = { ID = 81002, QuestLineIDs = { 9901 }, UiMapIDs = { 2371 }, FactionTags = { "horde" }, FactionConditions = { "horde" }, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [81003] = { ID = 81003, QuestLineIDs = { 9901 }, UiMapIDs = { 2371 }, FactionTags = {}, FactionConditions = {}, RaceMaskValues = {}, ClassMaskValues = { 2 }, ContentExpansionID = 9 },
        [81004] = { ID = 81004, QuestLineIDs = { 9902 }, UiMapIDs = { 2372 }, FactionTags = { "horde" }, FactionConditions = { "horde" }, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
      },
      questLines = {
        [9901] = { ID = 9901, UiMapID = 2371, QuestIDs = { 81001, 81002, 81003 }, UiMapIDs = { 2371 }, PrimaryUiMapID = 2371, PrimaryMapCount = 3, PrimaryMapShare = 1, FactionTags = { "shared" }, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
        [9902] = { ID = 9902, UiMapID = 2372, QuestIDs = { 81004 }, UiMapIDs = { 2372 }, PrimaryUiMapID = 2372, PrimaryMapCount = 1, PrimaryMapShare = 1, FactionTags = { "horde" }, RaceMaskValues = {}, ClassMaskValues = {}, ContentExpansionID = 9 },
      },
      expansions = {
        [9] = { 9901, 9902 },
      },
    }

    Toolbox.Questlines.SetDataOverride(filteredData)

    local questList, listError = Toolbox.Questlines.GetQuestListByQuestLineID(9901)
    assert.is_nil(listError)
    assert.same({ 81001 }, { questList[1].id })

    local model, modelError = Toolbox.Questlines.GetQuestTabModel()
    assert.is_nil(modelError)
    assert.is_truthy(model.questLineByID[9901])
    assert.is_nil(model.questLineByID[9902])

    local navigationModel, navigationError = Toolbox.Questlines.GetQuestNavigationModel()
    assert.is_nil(navigationError)
    assert.same({
      { id = 2371, questLineIDs = { 9901 } },
    }, collectQuestLineIDs(navigationModel.expansionByID[9].modeByKey.map_questline.entries))
  end)

  it("quest_inspector_snapshot_reads_runtime_task_and_questline_fields", function()
    rawset(_G, "C_QuestLog", {
      GetTitleForQuestID = function(questID)
        if questID == 99901 then
          return "Inspector Quest"
        end
        return questTitleByID[questID] or ("Quest #" .. tostring(questID))
      end,
      GetLogIndexForQuestID = function(questID)
        if questID == 99901 then
          return 7
        end
        return questActiveByID[questID] == true and 1 or 0
      end,
      IsQuestFlaggedCompleted = function(questID)
        return questCompletedByID[questID] == true
      end,
      ReadyForTurnIn = function(questID)
        if questID == 99901 then
          return true
        end
        return questReadyByID[questID] == true
      end,
      GetQuestType = function(questID)
        if questID == 99901 then
          return 12
        end
        return questTypeByID[questID]
      end,
      GetQuestTagInfo = function(questID)
        if questID == 99901 then
          return {
            tagID = 77,
            tagName = "World Event",
            worldQuestType = 5,
          }
        end
        if questID == 81002 then
          return {
            tagID = 12,
            tagName = "Campaign",
          }
        end
        return nil
      end,
      GetQuestObjectives = function(questID)
        if questID == 99901 then
          return {
            { text = "Collect 5 widgets", finished = false, numFulfilled = 2, numRequired = 5 },
            { text = "Return to the archivist", finished = false },
          }
        end
        return {}
      end,
      GetNumQuestLogEntries = function()
        return #questLogInfoList, #questLogInfoList
      end,
      GetInfo = function(index)
        if index == 7 then
          return { questID = 99901, title = "Inspector Quest", isHeader = false, isHidden = false }
        end
        return questLogInfoList[index]
      end,
    })
    rawset(_G, "GetQuestLogQuestText", function(logIndex)
      if logIndex == 7 then
        return "Inspect description", "Inspect objective summary"
      end
      return "Quest description #" .. tostring(logIndex), "Quest objective text #" .. tostring(logIndex)
    end)
    rawset(_G, "C_QuestLine", {
      GetQuestLineInfo = function(questID, uiMapID)
        if questID == 99901 and uiMapID == 2022 then
          return {
            questLineID = 4567,
            questLineName = "Inspector QuestLine",
            questLineQuestID = 99901,
            x = 0.12,
            y = 0.34,
          }
        end
        return nil
      end,
    })

    assert.is_function(Toolbox.Questlines.GetQuestInspectorSnapshot)

    local snapshotObject, errorObject = Toolbox.Questlines.GetQuestInspectorSnapshot(99901)
    assert.is_nil(errorObject)
    assert.equals(99901, snapshotObject.questID)
    assert.equals("Inspector Quest", snapshotObject.title)
    assert.equals("active", snapshotObject.status)
    assert.equals(true, snapshotObject.readyForTurnIn)
    assert.equals(2022, snapshotObject.mapID)
    assert.equals("Quest Zone", snapshotObject.mapName)
    assert.equals("Quest Continent", snapshotObject.continentMapName)
    assert.equals("Inspect description", snapshotObject.description)
    assert.equals("Inspect objective summary", snapshotObject.objectiveText)
    assert.equals("World Event", snapshotObject.tagName)
    assert.equals(77, snapshotObject.tagID)
    assert.equals(5, snapshotObject.worldQuestType)
    assert.equals(4567, snapshotObject.questLineID)
    assert.equals("Inspector QuestLine", snapshotObject.questLineName)
    assert.is_table(snapshotObject.objectives)
    assert.equals("Collect 5 widgets", snapshotObject.objectives[1].text)
    assert.is_table(snapshotObject.flatLines)
    assert.is_true(#snapshotObject.flatLines > 0)
    assert.is_true(string.find(table.concat(snapshotObject.flatLines, "\n"), "questLine.questLineName: Inspector QuestLine", 1, true) ~= nil)
  end)
end)
