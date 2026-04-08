--[[
  副本坐骑掉落静态数据。
  数据来源：wow.db。
  查询链：journalencounteritem -> itemxitemeffect -> itemeffect -> mount(SourceSpellID)。
  格式：[journalInstanceID] = { itemID, ... }
  生成方式：WoWDB/scripts/export_toolbox_all.py 或 export_toolbox_one.py。
  注意：此文件由脚本生成，手改会被覆盖。
]]

Toolbox.Data = Toolbox.Data or {}

--- 副本坐骑掉落表：[journalInstanceID] = { itemID, ... }
Toolbox.Data.MountDrops = {
  [67] = { 63043 }, -- The Stonecore
  [68] = { 63040 }, -- The Vortex Pinnacle
  [74] = { 63041 }, -- Throne of the Four Winds
  [76] = { 68823, 68824 }, -- Zul'Gurub
  [78] = { 69224, 71665 }, -- Firelands
  [187] = { 77067, 77069, 78919 }, -- Dragon Soul
  [249] = { 35513 }, -- Magisters' Terrace
  [252] = { 32768 }, -- Sethekk Halls
  [286] = { 44151 }, -- Utgarde Pinnacle
  [317] = { 87777 }, -- Mogu'shan Vaults
  [322] = { 87771, 89783, 94228, 95057 }, -- Pandaria
  [362] = { 93666, 95059 }, -- Throne of Thunder
  [369] = { 104253 }, -- Siege of Orgrimmar
  [457] = { 116660 }, -- Blackrock Foundry
  [557] = { 116771 }, -- Draenor
  [669] = { 123890 }, -- Hellfire Citadel
  [745] = { 30480 }, -- Karazhan
  [749] = { 32458 }, -- The Eye
  [753] = { 43959, 44083 }, -- Vault of Archavon
  [755] = { 43954, 43986 }, -- The Obsidian Sanctum
  [756] = { 43952, 43953 }, -- The Eye of Eternity
  [758] = { 50818 }, -- Icecrown Citadel
  [759] = { 45693 }, -- Ulduar
  [760] = { 49636 }, -- Onyxia's Lair
  [786] = { 137574, 137575 }, -- The Nighthold
  [860] = { 142236 }, -- Return to Karazhan
  [875] = { 143643 }, -- Tomb of Sargeras
  [946] = { 152789, 152816 }, -- Antorus, the Burning Throne
  [1001] = { 159842 }, -- Freehold
  [1022] = { 160829 }, -- The Underrot
  [1028] = { 174842 }, -- Azeroth
  [1041] = { 159921 }, -- Kings' Rest
  [1176] = { 166518, 166705 }, -- Battle of Dazar'alor
  [1178] = { 168826 }, -- Operation: Mechagon
  [1180] = { 174872 }, -- Ny'alotha, the Waking City
  [1182] = { 181819 }, -- The Necrotic Wake
  [1193] = { 186642, 186656 }, -- Sanctum of Domination
  [1194] = { 186638 }, -- Tazavesh, the Veiled Market
  [1195] = { 190768 }, -- Sepulcher of the First Ones
  [1207] = { 210061 }, -- Amirdrassil, the Dream's Hope
  [1210] = { 225548 }, -- Darkflame Cleft
  [1273] = { 224147, 224151 }, -- Nerub-ar Palace
  [1292] = { 13335 }, -- Stratholme - Service Entrance
  [1296] = { 235626, 236960 }, -- Liberation of Undermine
  [1299] = { 262914 }, -- Windrunner Spire
  [1300] = { 260231 }, -- Magisters' Terrace
  [1302] = { 243061 }, -- Manaforge Omega
  [1308] = { 246590 }, -- March on Quel'Danas
}
