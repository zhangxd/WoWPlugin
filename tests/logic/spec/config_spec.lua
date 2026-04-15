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

describe("Toolbox.Config quest module migration", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalToolboxDB = nil -- 原始 ToolboxDB 全局
  local originalCopyTable = nil -- 原始 CopyTable 全局

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalToolboxDB = rawget(_G, "ToolboxDB")
    originalCopyTable = rawget(_G, "CopyTable")

    rawset(_G, "Toolbox", {
      Config = {},
    })
    rawset(_G, "CopyTable", deepCopyTable)
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "ToolboxDB", originalToolboxDB)
    rawset(_G, "CopyTable", originalCopyTable)
  end)

  it("migrates_legacy_encounter_journal_quest_state_into_quest_module", function()
    rawset(_G, "ToolboxDB", {
      version = 2,
      global = {},
      modules = {
        encounter_journal = {
          enabled = true,
          debug = false,
          questlineTreeEnabled = true,
          questViewMode = "type",
          questViewSelectedMapID = 2371,
          questViewSelectedTypeID = 12,
          questViewSelectedQuestLineID = 9901,
          questViewSelectedQuestID = 81002,
          questlineTreeCollapsed = {
            ["map:2371"] = true,
          },
          questlineTreeSelection = {
            selectedMapID = 2371,
            selectedTypeID = 12,
            selectedQuestLineID = 9901,
            selectedQuestID = 81002,
          },
        },
      },
    })

    local configChunk = assert(loadfile("Toolbox/Core/Foundation/Config.lua")) -- Config chunk
    configChunk()
    Toolbox.Config.Init()

    local moduleDb = ToolboxDB.modules.quest -- 迁移后的 quest 模块存档
    assert.equals("map_questline", moduleDb.questNavModeKey)
    assert.equals(0, moduleDb.questNavExpansionID)
    assert.equals(2371, moduleDb.questNavSelectedMapID)
    assert.equals("type:12", moduleDb.questNavSelectedTypeKey)
    assert.equals(9901, moduleDb.questNavExpandedQuestLineID)
    assert.is_nil(moduleDb.questNavCategoryKey)
    assert.is_nil(moduleDb.questNavSelectedQuestLineID)
    assert.is_nil(moduleDb.questViewSelectedMapID)
    assert.is_nil(moduleDb.questViewSelectedTypeID)
    assert.is_nil(moduleDb.questViewSelectedQuestLineID)
    assert.is_nil(moduleDb.questViewSelectedQuestID)
    assert.same({
      ["map:2371"] = true,
    }, moduleDb.questlineTreeCollapsed)
    assert.is_nil(moduleDb.questlineTreeSelection)
  end)

  it("defaults_non_type_legacy_view_to_map_questline_mode_in_quest_module", function()
    rawset(_G, "ToolboxDB", {
      version = 2,
      global = {},
      modules = {
        encounter_journal = {
          questViewMode = "status",
          questViewSelectedQuestLineID = 0,
        },
      },
    })

    local configChunk = assert(loadfile("Toolbox/Core/Foundation/Config.lua")) -- Config chunk
    configChunk()
    Toolbox.Config.Init()

    local moduleDb = ToolboxDB.modules.quest -- 迁移后的模块存档
    assert.equals("map_questline", moduleDb.questNavModeKey)
    assert.equals(0, moduleDb.questNavExpandedQuestLineID)
  end)

  it("creates_quest_module_defaults_and_clears_encounter_journal_quest_keys", function()
    rawset(_G, "ToolboxDB", {
      version = 2,
      global = {},
      modules = {
        encounter_journal = {
          enabled = true,
          questlineTreeEnabled = true,
          questNavExpansionID = 9,
          questNavModeKey = "map_questline",
          questNavSelectedMapID = 2371,
          questNavSelectedTypeKey = "type:12",
          questNavExpandedQuestLineID = 9901,
          questInspectorLastQuestID = 99901,
          questRecentCompletedList = {
            { questID = 1, questName = "A", completedAt = 12345 },
          },
          questRecentCompletedMax = 10,
          questlineTreeCollapsed = {
            ["expansion:9"] = true,
          },
        },
      },
    })

    local configChunk = assert(loadfile("Toolbox/Core/Foundation/Config.lua")) -- Config chunk
    configChunk()
    Toolbox.Config.Init()

    local encounterDb = ToolboxDB.modules.encounter_journal -- 拆分后的冒险指南存档
    local questDb = ToolboxDB.modules.quest -- 拆分后的任务模块存档
    assert.is_truthy(type(questDb) == "table")
    assert.equals("map_questline", questDb.questNavModeKey)
    assert.equals(9, questDb.questNavExpansionID)
    assert.equals(2371, questDb.questNavSelectedMapID)
    assert.equals(9901, questDb.questNavExpandedQuestLineID)
    assert.same({
      ["expansion:9"] = true,
    }, questDb.questlineTreeCollapsed)

    assert.is_nil(encounterDb.questlineTreeEnabled)
    assert.is_nil(encounterDb.questNavExpansionID)
    assert.is_nil(encounterDb.questNavModeKey)
    assert.is_nil(encounterDb.questNavSelectedMapID)
    assert.is_nil(encounterDb.questNavSelectedTypeKey)
    assert.is_nil(encounterDb.questNavExpandedQuestLineID)
    assert.is_nil(encounterDb.questInspectorLastQuestID)
    assert.is_nil(encounterDb.questRecentCompletedList)
    assert.is_nil(encounterDb.questRecentCompletedMax)
    assert.is_nil(encounterDb.questlineTreeCollapsed)
  end)
end)
