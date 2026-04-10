--[[
  任务线测试专用 mock 数据。
  数据来源：manual（手工维护/开发中）。
  用途：供 tests/logic/spec/questline_progress_spec.lua 注入 QuestlineProgress 进行离线测试。
  备注：不接入 wow.db 自动导出，不在 Toolbox.toc 中加载。
]]

local mockData = {
  schemaVersion = 3,
  sourceMode = "mock",
  generatedAt = "2026-01-01T00:00:00Z",

  quests = {
    [81001] = {
      ID = 81001,
      UiMapID = 2371,
      MapPos = { x = 0.11, y = 0.22 },
    },
    [81002] = {
      ID = 81002,
      UiMapID = 2371,
      MapPos = { x = 0.33, y = 0.44, UiMapID = 2371 },
    },
    [81003] = {
      ID = 81003,
      UiMapID = 2371,
    },
  },

  questLines = {
    [9901] = { ID = 9901, Name_lang = "Mock QuestLine Alpha", UiMapID = 2371 },
  },

  questLineQuestIDs = {
    [9901] = { 81001, 81002, 81003 },
  },
}

return mockData
