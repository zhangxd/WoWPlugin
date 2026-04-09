--[[
  冒险手册任务页签静态数据（第一阶段）。
  数据来源：manual（手工维护/开发中）。
  用途：供 EncounterJournal 任务页签读取任务线、任务顺序与归属关系。
  备注：当前使用 schemaVersion=2，后续按 wow.db 导出能力迭代字段。
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 2,
  sourceMode = "mock",
  generatedAt = "2026-04-09T16:30:00Z",

  quests = {
    [79022] = { questID = 79022, mapID = 2255 },
    [79023] = { questID = 79023, mapID = 2255 },
    [79024] = { questID = 79024, mapID = 2255 },
    [79217] = { questID = 79217, mapID = 2255 },
    [79025] = { questID = 79025, mapID = 2255 },
    [79324] = { questID = 79324, mapID = 2255 },
    [79026] = { questID = 79026, mapID = 2255 },
    [79027] = { questID = 79027, mapID = 2255 },
    [79325] = { questID = 79325, mapID = 2255 },
    [79028] = { questID = 79028, mapID = 2255 },
    [80145] = { questID = 80145, mapID = 2255 },
    [80517] = { questID = 80517, mapID = 2255 },
    [79029] = { questID = 79029, mapID = 2255 },
    [79030] = { questID = 79030, mapID = 2255 },

    [83587] = { questID = 83587, mapID = 2255 },
    [82124] = { questID = 82124, mapID = 2255 },
    [82125] = { questID = 82125, mapID = 2255 },
    [82126] = { questID = 82126, mapID = 2255 },
    [82127] = { questID = 82127, mapID = 2255 },
    [82130] = { questID = 82130, mapID = 2255 },
    [82141] = { questID = 82141, mapID = 2255 },

    [83137] = { questID = 83137, mapID = 2346 },
    [83139] = { questID = 83139, mapID = 2346 },
    [83140] = { questID = 83140, mapID = 2346 },
    [83141] = { questID = 83141, mapID = 2346 },
    [83142] = { questID = 83142, mapID = 2346 },
    [83143] = { questID = 83143, mapID = 2346 },
    [83144] = { questID = 83144, mapID = 2346 },
    [84683] = { questID = 84683, mapID = 2346 },
    [83145] = { questID = 83145, mapID = 2346 },
    [85409] = { questID = 85409, mapID = 2346 },
    [83146] = { questID = 83146, mapID = 2346 },
    [83147] = { questID = 83147, mapID = 2346 },
    [85444] = { questID = 85444, mapID = 2346 },
    [83148] = { questID = 83148, mapID = 2346 },
    [83149] = { questID = 83149, mapID = 2346 },
    [83150] = { questID = 83150, mapID = 2346 },
    [85410] = { questID = 85410, mapID = 2346 },
    [83151] = { questID = 83151, mapID = 2346 },

    [83096] = { questID = 83096, mapID = 2346 },
    [83109] = { questID = 83109, mapID = 2346 },
    [86297] = { questID = 86297, mapID = 2346 },
    [85941] = { questID = 85941, mapID = 2346 },
    [83163] = { questID = 83163, mapID = 2346 },
    [83167] = { questID = 83167, mapID = 2346 },
    [83168] = { questID = 83168, mapID = 2346 },
    [83169] = { questID = 83169, mapID = 2346 },
    [83170] = { questID = 83170, mapID = 2346 },
    [83171] = { questID = 83171, mapID = 2346 },
    [83172] = { questID = 83172, mapID = 2346 },
    [83173] = { questID = 83173, mapID = 2346 },
    [83174] = { questID = 83174, mapID = 2346 },
    [83175] = { questID = 83175, mapID = 2346 },
    [83176] = { questID = 83176, mapID = 2346 },

    [84956] = { questID = 84956, mapID = 2371 },
    [84957] = { questID = 84957, mapID = 2371 },
    [85003] = { questID = 85003, mapID = 2371 },
    [85039] = { questID = 85039, mapID = 2371 },
    [84958] = { questID = 84958, mapID = 2371 },
    [84959] = { questID = 84959, mapID = 2371 },
    [84960] = { questID = 84960, mapID = 2371 },
    [84961] = { questID = 84961, mapID = 2371 },
    [84963] = { questID = 84963, mapID = 2371 },
    [84964] = { questID = 84964, mapID = 2371 },
    [84965] = { questID = 84965, mapID = 2371 },
    [86835] = { questID = 86835, mapID = 2371 },
    [84967] = { questID = 84967, mapID = 2371 },

    [85032] = { questID = 85032, mapID = 2371 },
    [85961] = { questID = 85961, mapID = 2371 },
    [84855] = { questID = 84855, mapID = 2371 },
    [86495] = { questID = 86495, mapID = 2371 },
    [84856] = { questID = 84856, mapID = 2371 },
    [84857] = { questID = 84857, mapID = 2371 },
    [84858] = { questID = 84858, mapID = 2371 },
    [84859] = { questID = 84859, mapID = 2371 },
    [84860] = { questID = 84860, mapID = 2371 },
    [84861] = { questID = 84861, mapID = 2371 },
    [84862] = { questID = 84862, mapID = 2371 },
    [84863] = { questID = 84863, mapID = 2371 },
    [84864] = { questID = 84864, mapID = 2371 },
    [84865] = { questID = 84865, mapID = 2371 },
    [84866] = { questID = 84866, mapID = 2371 },
  },

  questLines = {
    [100101] = { questLineID = 100101, name = "The Machines March to War", expansionID = 10, primaryMapID = 2255 },
    [100102] = { questLineID = 100102, name = "To Kill a Queen", expansionID = 10, primaryMapID = 2255 },
    [100201] = { questLineID = 100201, name = "Trust Issues", expansionID = 10, primaryMapID = 2346 },
    [100202] = { questLineID = 100202, name = "Undermine Awaits", expansionID = 10, primaryMapID = 2346 },
    [100301] = { questLineID = 100301, name = "A Shadowy Invitation", expansionID = 10, primaryMapID = 2371 },
    [100302] = { questLineID = 100302, name = "Void Alliance", expansionID = 10, primaryMapID = 2371 },
  },

  questLineQuestIDs = {
    [100101] = {
      79022, 79023, 79024, 79217, 79025, 79324, 79026,
      79027, 79325, 79028, 80145, 80517, 79029, 79030,
    },
    [100102] = {
      83587, 82124, 82125, 82126, 82127, 82130, 82141,
    },
    [100201] = {
      83137, 83139, 83140, 83141, 83142, 83143, 83144,
      84683, 83145, 85409, 83146, 83147, 85444, 83148,
      83149, 83150, 85410, 83151,
    },
    [100202] = {
      83096, 83109, 86297, 85941, 83163, 83167, 83168,
      83169, 83170, 83171, 83172, 83173, 83174, 83175, 83176,
    },
    [100301] = {
      84956, 84957, 85003, 85039, 84958, 84959, 84960, 84961,
      84963, 84964, 84965, 86835, 84967,
    },
    [100302] = {
      85032, 85961, 84855, 86495, 84856, 84857, 84858, 84859,
      84860, 84861, 84862, 84863, 84864, 84865, 84866,
    },
  },

  expansionQuestLineIDs = {
    [10] = { 100101, 100102, 100201, 100202, 100301, 100302 },
  },
}
