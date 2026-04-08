--[[
  Instance questline tree data for Encounter Journal.
  Structure:
    journalInstanceID -> expansion -> types -> nodes -> chains -> quests

  Notes:
  - This table is intentionally small for the first iteration.
  - It is designed for extension by expansion/type without schema changes.
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.InstanceQuestlines = {
  -- Nerub-ar Palace
  [1273] = {
    expansion = {
      id = 10,
      name = "The War Within",
    },
    types = {
      map = {
        {
          id = "azj_kahet",
          name = "Azj-Kahet",
          chains = {
            {
              id = "tww_the_machines_march_to_war",
              name = "The Machines March to War",
              quests = {
                79022, 79023, 79024, 79217, 79025, 79324, 79026,
                79027, 79325, 79028, 80145, 80517, 79029, 79030,
              },
            },
            {
              id = "tww_to_kill_a_queen",
              name = "To Kill a Queen",
              quests = {
                83587, 82124, 82125, 82126, 82127, 82130, 82141,
              },
            },
          },
        },
      },
    },
  },

  -- Liberation of Undermine
  [1296] = {
    expansion = {
      id = 10,
      name = "The War Within",
    },
    types = {
      map = {
        {
          id = "undermine",
          name = "Undermine",
          chains = {
            {
              id = "tww_trust_issues",
              name = "Trust Issues",
              quests = {
                83137, 83139, 83140, 83141, 83142, 83143, 83144,
                84683, 83145, 85409, 83146, 83147, 85444, 83148,
                83149, 83150, 85410, 83151,
              },
            },
            {
              id = "tww_undermine_awaits",
              name = "Undermine Awaits",
              quests = {
                83096, 83109, 86297, 85941, 83163, 83167, 83168,
                83169, 83170, 83171, 83172, 83173, 83174, 83175, 83176,
              },
            },
          },
        },
      },
    },
  },

  -- Manaforge Omega
  [1302] = {
    expansion = {
      id = 10,
      name = "The War Within",
    },
    types = {
      map = {
        {
          id = "karesh",
          name = "K'aresh",
          chains = {
            {
              id = "tww_a_shadowy_invitation",
              name = "A Shadowy Invitation",
              quests = {
                84956, 84957, 85003, 85039, 84958, 84959, 84960, 84961,
                84963, 84964, 84965, 86835, 84967,
              },
            },
            {
              id = "tww_void_alliance",
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
}
