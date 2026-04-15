--[[
  任务线测试专用 mock 数据。
  数据来源：manual（手工维护/开发中）。
  用途：供 tests/logic/spec/questline_progress_spec.lua 注入 QuestlineProgress 进行离线测试。
  备注：不接入 wow.db 自动导出，不在 Toolbox.toc 中加载。
]]

local mockData = {
  schemaVersion = 6,
  sourceMode = "mock",
  generatedAt = "2026-01-01T00:00:00Z",

  quests = {
    [81001] = {
      ID = 81001,
      QuestLineIDs = { 9901 },
      UiMapIDs = { 2371 },
      FactionTags = {},
      FactionConditions = {},
      RaceMaskValues = {},
      ClassMaskValues = {},
      ContentExpansionID = 0,
    },
    [81002] = {
      ID = 81002,
      QuestLineIDs = { 9901 },
      UiMapIDs = { 2371 },
      FactionTags = {},
      FactionConditions = {},
      RaceMaskValues = {},
      ClassMaskValues = {},
      ContentExpansionID = 0,
    },
    [81003] = {
      ID = 81003,
      QuestLineIDs = { 9901 },
      UiMapIDs = { 2371 },
      FactionTags = {},
      FactionConditions = {},
      RaceMaskValues = {},
      ClassMaskValues = {},
      ContentExpansionID = 0,
    },
  },

  questLines = {
    [9901] = {
      ID = 9901,
      UiMapID = 2371,
      QuestIDs = { 81001, 81002, 81003 },
      UiMapIDs = { 2371 },
      PrimaryUiMapID = 2371,
      PrimaryMapCount = 3,
      PrimaryMapShare = 1,
      FactionTags = {},
      RaceMaskValues = {},
      ClassMaskValues = {},
      ContentExpansionID = 0,
    },
  },

  expansions = {
    [0] = { 9901 },
  },
}

return mockData
