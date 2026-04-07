--[[
  副本坐骑掉落静态数据。
  数据来源：wow.db 12.0.5.66741
  查询链：journalencounteritem -> itemxitemeffect -> itemeffect -> mount(SourceSpellID)
  格式：[journalInstanceID] = { itemID, ... }
]]

Toolbox.Data = Toolbox.Data or {}

--- 副本坐骑掉落表：[journalInstanceID] = { itemID, ... }
Toolbox.Data.MountDrops = {
  -- 经典旧世 (JournalTierID=68)
  [1292] = { 13335 },   -- Stratholme - Service Entrance

  -- 燃烧的远征 (JournalTierID=70)
  [249]  = { 35513 },   -- Magisters' Terrace
  [252]  = { 32768 },   -- Sethekk Halls
  [745]  = { 30480 },   -- Karazhan
  [749]  = { 32458 },   -- The Eye

  -- 巫妖王之怒 (JournalTierID=72)
  [286]  = { 44151 },           -- Utgarde Pinnacle
  [753]  = { 43959, 44083 },    -- Vault of Archavon
  [755]  = { 43954, 43986 },    -- The Obsidian Sanctum
  [756]  = { 43952, 43953 },    -- The Eye of Eternity
  [758]  = { 50818 },           -- Icecrown Citadel
  [759]  = { 45693 },           -- Ulduar
  [760]  = { 49636 },           -- Onyxia's Lair

  -- 大地的裂变 (JournalTierID=73)
  [67]   = { 63043 },           -- The Stonecore
  [68]   = { 63040 },           -- The Vortex Pinnacle
  [74]   = { 63041 },           -- Throne of the Four Winds
  [76]   = { 68823, 68824 },    -- Zul'Gurub
  [78]   = { 71665, 69224 },    -- Firelands
  [187]  = { 78919, 77067, 77069 }, -- Dragon Soul

  -- 熊猫人之谜 (JournalTierID=74)
  [317]  = { 87777 },                   -- Mogu'shan Vaults
  [322]  = { 87771, 89783, 95057, 94228 }, -- Pandaria (世界boss)
  [362]  = { 93666, 95059 },            -- Throne of Thunder
  [369]  = { 104253 },                  -- Siege of Orgrimmar

  -- 德拉诺之王 (JournalTierID=124)
  [457]  = { 116660 },          -- Blackrock Foundry
  [557]  = { 116771 },          -- Draenor (世界boss)
  [669]  = { 123890 },          -- Hellfire Citadel

  -- 军团再临 (JournalTierID=395)
  [786]  = { 137574, 137575 },  -- The Nighthold
  [860]  = { 142236 },          -- Return to Karazhan
  [875]  = { 143643 },          -- Tomb of Sargeras
  [946]  = { 152816, 152789 },  -- Antorus, the Burning Throne

  -- 争霸艾泽拉斯 (JournalTierID=396)
  [1001] = { 159842 },          -- Freehold
  [1022] = { 160829 },          -- The Underrot
  [1028] = { 174842 },          -- Azeroth (世界boss)
  [1041] = { 159921 },          -- Kings' Rest
  [1176] = { 166518, 166705 },  -- Battle of Dazar'alor
  [1178] = { 168826 },          -- Operation: Mechagon
  [1180] = { 174872 },          -- Ny'alotha, the Waking City

  -- 暗影国度 (JournalTierID=499)
  [1182] = { 181819 },          -- The Necrotic Wake
  [1193] = { 186656, 186642 },  -- Sanctum of Domination
  [1194] = { 186638 },          -- Tazavesh, the Veiled Market
  [1195] = { 190768 },          -- Sepulcher of the First Ones

  -- 巨龙时代 (JournalTierID=503)
  [1207] = { 210061 },          -- Amirdrassil, the Dream's Hope

  -- 地心之战 (JournalTierID=514)
  [1210] = { 225548 },          -- Darkflame Cleft
  [1273] = { 224147, 224151 },  -- Nerub-ar Palace
  [1296] = { 235626, 236960 },  -- Liberation of Undermine

  -- 混乱时间线/Remix (JournalTierID=505/516)
  -- 注：1194(Tazavesh) 已在暗影国度条目中定义
  [1299] = { 262914 },          -- Windrunner Spire
  [1300] = { 260231 },          -- Magisters' Terrace (Remix)
  [1302] = { 243061 },          -- Manaforge Omega
  [1308] = { 246590 },          -- March on Quel'Danas
}
