--[[
  Instance questline tree data for Encounter Journal.
  Structure:
    expansions -> types -> nodes -> chains -> quests

  Notes:
  - This table is intentionally small for the first iteration.
  - It is designed for extension by expansion/type without schema changes.
  - 该数据仅用于在冒险手册任务页签内展示，不与冒险手册副本 ID 建立硬关联。
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 1,
  expansions = {
    [10] = {
      name = "The War Within",
      order = 10,
      types = {
        map = {
          order = 10,
          nodeOrder = {
            "azj_kahet",
            "undermine",
            "karesh",
          },
          nodes = {
            azj_kahet = {
              name = "Azj-Kahet",
              chainOrder = {
                "tww_the_machines_march_to_war",
                "tww_to_kill_a_queen",
              },
              chains = {
                tww_the_machines_march_to_war = {
                  name = "The Machines March to War",
                  quests = {
                    79022, 79023, 79024, 79217, 79025, 79324, 79026,
                    79027, 79325, 79028, 80145, 80517, 79029, 79030,
                  },
                },
                tww_to_kill_a_queen = {
                  name = "To Kill a Queen",
                  quests = {
                    83587, 82124, 82125, 82126, 82127, 82130, 82141,
                  },
                },
              },
            },
            undermine = {
              name = "Undermine",
              chainOrder = {
                "tww_trust_issues",
                "tww_undermine_awaits",
              },
              chains = {
                tww_trust_issues = {
                  name = "Trust Issues",
                  quests = {
                    83137, 83139, 83140, 83141, 83142, 83143, 83144,
                    84683, 83145, 85409, 83146, 83147, 85444, 83148,
                    83149, 83150, 85410, 83151,
                  },
                },
                tww_undermine_awaits = {
                  name = "Undermine Awaits",
                  quests = {
                    83096, 83109, 86297, 85941, 83163, 83167, 83168,
                    83169, 83170, 83171, 83172, 83173, 83174, 83175, 83176,
                  },
                },
              },
            },
            karesh = {
              name = "K'aresh",
              chainOrder = {
                "tww_a_shadowy_invitation",
                "tww_void_alliance",
              },
              chains = {
                tww_a_shadowy_invitation = {
                  name = "A Shadowy Invitation",
                  quests = {
                    84956, 84957, 85003, 85039, 84958, 84959, 84960, 84961,
                    84963, 84964, 84965, 86835, 84967,
                  },
                },
                tww_void_alliance = {
                  name = "Void Alliance",
                  quests = {
                    85032, 85961, 84855, 86495, 84856, 84857, 84858, 84859,
                    84860, 84861, 84862, 84863, 84864, 84865, 84866,
                  },
                },
              },
            },
          },
        },
      },
    },
  },
  indexes = {
    chainById = {
      tww_the_machines_march_to_war = {expansionID = 10, typeID = "map", nodeID = "azj_kahet"},
      tww_to_kill_a_queen = {expansionID = 10, typeID = "map", nodeID = "azj_kahet"},
      tww_trust_issues = {expansionID = 10, typeID = "map", nodeID = "undermine"},
      tww_undermine_awaits = {expansionID = 10, typeID = "map", nodeID = "undermine"},
      tww_a_shadowy_invitation = {expansionID = 10, typeID = "map", nodeID = "karesh"},
      tww_void_alliance = {expansionID = 10, typeID = "map", nodeID = "karesh"},
    },
    questToChain = {
      [79022] = "tww_the_machines_march_to_war",
      [79023] = "tww_the_machines_march_to_war",
      [79024] = "tww_the_machines_march_to_war",
      [79217] = "tww_the_machines_march_to_war",
      [79025] = "tww_the_machines_march_to_war",
      [79324] = "tww_the_machines_march_to_war",
      [79026] = "tww_the_machines_march_to_war",
      [79027] = "tww_the_machines_march_to_war",
      [79325] = "tww_the_machines_march_to_war",
      [79028] = "tww_the_machines_march_to_war",
      [80145] = "tww_the_machines_march_to_war",
      [80517] = "tww_the_machines_march_to_war",
      [79029] = "tww_the_machines_march_to_war",
      [79030] = "tww_the_machines_march_to_war",
      [83587] = "tww_to_kill_a_queen",
      [82124] = "tww_to_kill_a_queen",
      [82125] = "tww_to_kill_a_queen",
      [82126] = "tww_to_kill_a_queen",
      [82127] = "tww_to_kill_a_queen",
      [82130] = "tww_to_kill_a_queen",
      [82141] = "tww_to_kill_a_queen",
      [83137] = "tww_trust_issues",
      [83139] = "tww_trust_issues",
      [83140] = "tww_trust_issues",
      [83141] = "tww_trust_issues",
      [83142] = "tww_trust_issues",
      [83143] = "tww_trust_issues",
      [83144] = "tww_trust_issues",
      [84683] = "tww_trust_issues",
      [83145] = "tww_trust_issues",
      [85409] = "tww_trust_issues",
      [83146] = "tww_trust_issues",
      [83147] = "tww_trust_issues",
      [85444] = "tww_trust_issues",
      [83148] = "tww_trust_issues",
      [83149] = "tww_trust_issues",
      [83150] = "tww_trust_issues",
      [85410] = "tww_trust_issues",
      [83151] = "tww_trust_issues",
      [83096] = "tww_undermine_awaits",
      [83109] = "tww_undermine_awaits",
      [86297] = "tww_undermine_awaits",
      [85941] = "tww_undermine_awaits",
      [83163] = "tww_undermine_awaits",
      [83167] = "tww_undermine_awaits",
      [83168] = "tww_undermine_awaits",
      [83169] = "tww_undermine_awaits",
      [83170] = "tww_undermine_awaits",
      [83171] = "tww_undermine_awaits",
      [83172] = "tww_undermine_awaits",
      [83173] = "tww_undermine_awaits",
      [83174] = "tww_undermine_awaits",
      [83175] = "tww_undermine_awaits",
      [83176] = "tww_undermine_awaits",
      [84956] = "tww_a_shadowy_invitation",
      [84957] = "tww_a_shadowy_invitation",
      [85003] = "tww_a_shadowy_invitation",
      [85039] = "tww_a_shadowy_invitation",
      [84958] = "tww_a_shadowy_invitation",
      [84959] = "tww_a_shadowy_invitation",
      [84960] = "tww_a_shadowy_invitation",
      [84961] = "tww_a_shadowy_invitation",
      [84963] = "tww_a_shadowy_invitation",
      [84964] = "tww_a_shadowy_invitation",
      [84965] = "tww_a_shadowy_invitation",
      [86835] = "tww_a_shadowy_invitation",
      [84967] = "tww_a_shadowy_invitation",
      [85032] = "tww_void_alliance",
      [85961] = "tww_void_alliance",
      [84855] = "tww_void_alliance",
      [86495] = "tww_void_alliance",
      [84856] = "tww_void_alliance",
      [84857] = "tww_void_alliance",
      [84858] = "tww_void_alliance",
      [84859] = "tww_void_alliance",
      [84860] = "tww_void_alliance",
      [84861] = "tww_void_alliance",
      [84862] = "tww_void_alliance",
      [84863] = "tww_void_alliance",
      [84864] = "tww_void_alliance",
      [84865] = "tww_void_alliance",
      [84866] = "tww_void_alliance",
    },
  },
}
