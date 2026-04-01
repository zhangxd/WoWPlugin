--[[
  副本进度面板 · 数据层：冒险手册枚举全部副本（按资料片 Tier）、合并角色锁定信息、掉落扫描。
  journalMeta：手册实例 ID + 所在 Tier（与手册「资料片」分栏一致）。
]]

Toolbox.SavedInstancesData = Toolbox.SavedInstancesData or {}

local Lockouts = Toolbox.Lockouts
local EJ = Toolbox.EJ
local MJ = Toolbox.MountJournal

-- [name] = { jid = number, tier = number } | false（未找到）
local journalMetaByName = {}

--[[
  手册战利品随「当前难度」过滤：须 `EJ.SetDifficulty(DifficultyID)` 后再 `SelectInstance` / `SelectEncounter` / `GetLootInfoByIndex`
  （Warcraft Wiki：API_EJ_SetDifficulty）。下列为零售常见难度，用于扫描时避免漏掉仅某一难度掉落的坐骑/物品。
]]
local EJ_LOOT_SCAN_CANDIDATE_DIFFICULTIES = {
  16,
  15,
  14,
  17,
  23,
  2,
  1,
  8,
}

--- 对给定手册实例依次切换候选难度并调用 visitor；每次调用前已 `SetDifficulty` + `SelectInstance` 成功。
--- visitor 返回 true 时提前结束。结束时恢复进入前的手册难度（若可读取）。
---@param journalInstanceId number
---@param visitor fun(difficultyID: number): boolean|nil
local function ejForEachCandidateDifficulty(journalInstanceId, visitor)
  local prev = EJ.GetDifficulty()
  local stop = false
  for _, did in ipairs(EJ_LOOT_SCAN_CANDIDATE_DIFFICULTIES) do
    if stop then
      break
    end
    pcall(function()
      EJ.SetDifficulty(did)
    end)
    if EJ.SelectInstance(journalInstanceId) then
      if visitor(did) == true then
        stop = true
      end
    end
  end
  if type(prev) == "number" and prev > 0 then
    pcall(function()
      EJ.SetDifficulty(prev)
    end)
  end
end

--- 尝试加载 Blizzard_EncounterJournal，以便通过门面枚举实例与掉落。
---@return boolean 已加载或加载成功为 true；失败为 false。
function Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  local name = "Blizzard_EncounterJournal"
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then
    return true
  end
  if C_AddOns and C_AddOns.LoadAddOn then
    local ok = pcall(C_AddOns.LoadAddOn, name)
    return ok
  end
  if LoadAddOn then
    return LoadAddOn(name) == 1
  end
  return false
end

---@return number|nil speciesID
local function getPetSpeciesIdFromItem(itemID)
  if not itemID or not C_PetJournal or not C_PetJournal.GetPetInfoByItemID then
    return nil
  end
  local ok, r = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
  if not ok or r == nil then
    return nil
  end
  if type(r) == "number" and r > 0 then
    return r
  end
  if type(r) == "table" and r.speciesID then
    return r.speciesID
  end
  return nil
end

---@return boolean|nil
local function getPetSpeciesCollected(speciesID)
  if not speciesID or not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then
    return nil
  end
  local ok, info = pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
  if ok and type(info) == "table" and info.isCollected ~= nil then
    return info.isCollected
  end
  return nil
end

--- 用 `C_ToyBox.GetToyInfo` 判断物品是否为玩具（仅文件内归类用）。
local function isToyItem(itemID)
  if not itemID or not C_ToyBox then
    return false
  end
  if C_ToyBox.GetToyInfo then
    local ok, info = pcall(C_ToyBox.GetToyInfo, itemID)
    if ok and info ~= nil and info ~= false then
      return true
    end
  end
  return false
end

---@return boolean|nil
local function toyCollected(itemID)
  if not itemID or not PlayerHasToy then
    return nil
  end
  local ok, has = pcall(PlayerHasToy, itemID)
  if ok then
    return has
  end
  return nil
end

--- 按副本显示名在冒险手册中查找实例 ID 与资料片分栏（Tier），结果写入 `journalMetaByName` 缓存。
---@param name string|nil 副本显示名；空或 nil 时返回 nil。
---@return number|nil journalInstanceID 手册实例 ID（EJ_SelectInstance）
---@return number|nil tierIndex 1..GetNumTiers，与冒险手册版本分栏一致；未找到时均为 nil。
function Toolbox.SavedInstancesData.FindJournalMetaByName(name)
  if not name or name == "" then
    return nil, nil
  end
  local c = journalMetaByName[name]
  if c == false then
    return nil, nil
  end
  if type(c) == "table" and type(c.jid) == "number" then
    return c.jid, c.tier
  end
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  EJ.ClearSearch()
  for tier = 1, EJ.GetNumTiers() do
    EJ.SelectTier(tier)
    for _, showRaid in ipairs({ false, true }) do
      local idx = 1
      while true do
        local jid, iname = EJ.GetInstanceByIndex(idx, showRaid)
        if not jid then
          break
        end
        if iname == name and type(jid) == "number" then
          journalMetaByName[name] = { jid = jid, tier = tier }
          return jid, tier
        end
        idx = idx + 1
      end
    end
  end
  journalMetaByName[name] = false
  return nil, nil
end

--- `FindJournalMetaByName` 的便捷封装，仅返回手册实例 ID。
---@param name string|nil 副本显示名。
---@return number|nil journalInstanceID；未找到时为 nil。
function Toolbox.SavedInstancesData.FindJournalIdByName(name)
  local jid = select(1, Toolbox.SavedInstancesData.FindJournalMetaByName(name))
  return jid
end

--- 同一副本显示名下，所有难度的锁定行（冒险手册列表多行 CD 用）。
---@return table<string, table[]> [instanceName] = { { difficultyId, difficultyName, reset, locked, numEncounters, encounterProgress }, ... }
function Toolbox.SavedInstancesData.GetLockoutsGroupedByInstanceName()
  local byName = {}
  for i = 1, Lockouts.GetNumSavedInstances() do
    local name, _, reset, difficultyId, locked, _, _, _, _, difficultyName, numEncounters, encounterProgress =
      Lockouts.GetSavedInstanceInfo(i)
    if name then
      byName[name] = byName[name] or {}
      byName[name][#byName[name] + 1] = {
        difficultyId = difficultyId,
        difficultyName = difficultyName,
        reset = reset,
        locked = locked,
        numEncounters = numEncounters or 0,
        encounterProgress = encounterProgress or 0,
      }
    end
  end
  return byName
end

--- 仅判断手册实例是否含坐骑掉落（遇第一件坐骑即返回，比 ScanInstanceDetails 轻）。
---@param journalInstanceId number
---@return boolean
function Toolbox.SavedInstancesData.ScanInstanceHasMount(journalInstanceId)
  if not journalInstanceId or journalInstanceId < 1 then
    return false
  end
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  EJ.ClearSearch()
  local found = false
  ejForEachCandidateDifficulty(journalInstanceId, function()
    local numEnc = EJ.GetNumEncounters()
    for ei = 1, numEnc do
      EJ.SelectEncounter(ei)
      local nLoot = EJ.GetNumLoot()
      for li = 1, nLoot do
        local info = EJ.GetLootInfoByIndex(li, ei)
        if info and info.itemID and MJ.GetMountFromItem(info.itemID) then
          found = true
          return true
        end
      end
    end
    return false
  end)
  return found
end

--- 按副本名合并第一条锁定（多难度同名时只取一条）。
local function buildLockoutByName()
  local byName = {}
  for i = 1, Lockouts.GetNumSavedInstances() do
    local name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid, maxPlayers,
      difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId = Lockouts.GetSavedInstanceInfo(i)
    if name and not byName[name] then
      byName[name] = {
        savedIndex = i,
        name = name,
        instanceId = instanceId,
        lockoutId = lockoutId,
        reset = reset,
        difficultyId = difficultyId,
        locked = locked,
        isRaid = isRaid,
        difficultyName = difficultyName,
        numEncounters = numEncounters or 0,
        encounterProgress = encounterProgress,
      }
    end
  end
  return byName
end

--- 按冒险手册当前 Tier 与地城/团本列表枚举实例，并与角色锁定合并为行数据（用于列表 UI）。
---@param filter string|"all"|"dungeon"|"raid" `"all"` 全部；`"dungeon"` 仅地下城；`"raid"` 仅团本。
---@param tierFilter string|"all"|number|nil 默认 `"all"`；为数字时表示 EJ 资料片分栏索引（`SelectTier`），仅枚举该栏。
---@return table[] 行表项含 `name`、`journalInstanceId`、`ejTier`、锁定字段等（无锁定时部分字段为 nil 或占位）。
function Toolbox.SavedInstancesData.BuildRowList(filter, tierFilter)
  tierFilter = tierFilter or "all"
  local rows = {}
  local lockByName = buildLockoutByName()
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  EJ.ClearSearch()

  local nT = EJ.GetNumTiers()
  if type(nT) ~= "number" or nT < 1 then
    nT = 1
  end
  local tierStart, tierEnd = 1, nT
  if tierFilter ~= "all" then
    local want = tierFilter
    if type(want) == "string" then
      want = tonumber(want)
    end
    if type(want) == "number" then
      tierStart = want
      tierEnd = want
    end
  end

  local seenJid = {}

  for tier = tierStart, tierEnd do
    EJ.SelectTier(tier)
    for _, showRaid in ipairs({ false, true }) do
      local idx = 1
      while true do
        local jid, iname, ejIsRaid = EJ.GetInstanceByIndexFlat(idx, showRaid)
        if not jid then
          break
        end
        idx = idx + 1
        if iname and not seenJid[jid] then
          seenJid[jid] = true
          journalMetaByName[iname] = { jid = jid, tier = tier }

          local lock = lockByName[iname]
          local isRaid = ejIsRaid
          if showRaid == true then
            isRaid = true
          elseif showRaid == false then
            isRaid = false
          end

          local include = false
          if filter == "all" then
            include = true
          elseif filter == "raid" then
            include = (isRaid == true)
          elseif filter == "dungeon" then
            include = (isRaid == false)
          end

          if include then
            local r = {
              savedIndex = lock and lock.savedIndex,
              name = iname,
              instanceId = lock and lock.instanceId,
              lockoutId = lock and lock.lockoutId,
              reset = lock and lock.reset or 0,
              difficultyName = lock and lock.difficultyName or "—",
              numEncounters = lock and lock.numEncounters or 0,
              encounterProgress = lock and lock.encounterProgress or 0,
              isRaid = isRaid,
              locked = lock and lock.locked,
              ejTier = tier,
              journalInstanceId = jid,
            }
            rows[#rows + 1] = r
          end
        end
      end
    end
  end

  EJ.ClearSearch()
  return rows
end

--- 从行数据解析手册实例 ID：优先 `row.journalInstanceId`，否则按 `row.name` 查手册。
---@param row table|nil 行数据；nil 时返回 nil。
---@return number|nil journalInstanceID 手册 `EJ_SelectInstance` 用的 ID（与锁定 API 的 `instanceId` 不是同一套）。
function Toolbox.SavedInstancesData.ResolveJournalInstanceId(row)
  if not row then
    return nil
  end
  if type(row.journalInstanceId) == "number" and row.journalInstanceId > 0 then
    return row.journalInstanceId
  end
  return Toolbox.SavedInstancesData.FindJournalIdByName(row.name)
end

--- 从已保存的锁定索引读取首领列表与击杀状态（需 `GetSavedInstanceEncounterInfo` 有效）。
---@param savedIndex number `GetSavedInstanceInfo` 对应下标。
---@param numEncounters number|nil 首领数量上限；nil 或 0 时返回空表。
---@return table[] `{ name, killed, fileDataID }` 列表。
function Toolbox.SavedInstancesData.GetBossList(savedIndex, numEncounters)
  local list = {}
  local maxE = numEncounters or 0
  for e = 1, maxE do
    local bossName, fileDataID, isKilled = Lockouts.GetSavedInstanceEncounterInfo(savedIndex, e)
    if bossName then
      list[#list + 1] = {
        name = bossName,
        killed = isKilled,
        fileDataID = fileDataID,
      }
    end
  end
  return list
end

--- 无角色锁定时从冒险手册枚举首领（无击杀状态，仅展示名）。
---@param journalInstanceId number|nil 手册实例 ID；无效时返回空表。
---@return table[] `{ name, killed=false, fileDataID=nil }` 列表。
function Toolbox.SavedInstancesData.GetBossListFromJournal(journalInstanceId)
  local list = {}
  if not journalInstanceId or journalInstanceId < 1 then
    return list
  end
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  EJ.ClearSearch()
  if not EJ.SelectInstance(journalInstanceId) then
    return list
  end
  local n = EJ.GetNumEncounters()
  for e = 1, n do
    local bossName = EJ.GetEncounterName(e)
    list[#list + 1] = {
      name = bossName or ("#" .. tostring(e)),
      killed = false,
      fileDataID = nil,
    }
  end
  return list
end

--- 按行数据返回首领列表：有锁定且 `numEncounters>0` 时用锁定 API，否则用手册枚举。
---@param row table|nil 行数据（含 `savedIndex`、`numEncounters`、`journalInstanceId`、`name` 等）。
---@return table[] 与 `GetBossList` / `GetBossListFromJournal` 相同结构的列表。
function Toolbox.SavedInstancesData.GetBossListForRow(row)
  if not row then
    return {}
  end
  if row.savedIndex and (row.numEncounters or 0) > 0 then
    return Toolbox.SavedInstancesData.GetBossList(row.savedIndex, row.numEncounters)
  end
  if row.journalInstanceId then
    return Toolbox.SavedInstancesData.GetBossListFromJournal(row.journalInstanceId)
  end
  return {}
end

--- 扫描手册实例掉落：坐骑 / 宠物 / 玩具 / 其余装备；宠物与玩具归类依赖客户端 API。
---@param journalInstanceId number|nil 手册实例 ID；无效或无法选中时返回 nil。
---@return table|nil 含 `instanceName`、`mapID`、`mounts`/`pets`/`toys`/`lootOther` 等；失败为 nil。
function Toolbox.SavedInstancesData.ScanInstanceDetails(journalInstanceId)
  if not journalInstanceId or journalInstanceId < 1 then
    return nil
  end
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  EJ.ClearSearch()
  local name, desc, bgImage, loreBg, buttonImage1, buttonImage2, titleImage, ejInstId, mapID
  local gotMeta = false
  local mounts = {}
  local pets = {}
  local toys = {}
  local lootOther = {}
  local seen = {}
  ejForEachCandidateDifficulty(journalInstanceId, function()
    if not gotMeta then
      name, desc, bgImage, loreBg, buttonImage1, buttonImage2, titleImage, ejInstId, mapID = EJ.GetInstanceInfo()
      gotMeta = true
    end
    local numEnc = EJ.GetNumEncounters()
    for ei = 1, numEnc do
      EJ.SelectEncounter(ei)
      local nLoot = EJ.GetNumLoot()
      for li = 1, nLoot do
        local info = EJ.GetLootInfoByIndex(li, ei)
        if info and info.itemID then
          local itemID = info.itemID
          if not seen[itemID] then
            seen[itemID] = true
            local mountID = MJ.GetMountFromItem(itemID)
            if mountID then
              mounts[#mounts + 1] = {
                itemID = itemID,
                mountID = mountID,
                name = info.name,
                collected = MJ.IsCollected(mountID),
                icon = info.icon,
              }
            else
              local speciesID = getPetSpeciesIdFromItem(itemID)
              if speciesID then
                pets[#pets + 1] = {
                  itemID = itemID,
                  speciesID = speciesID,
                  name = info.name,
                  collected = getPetSpeciesCollected(speciesID),
                  icon = info.icon,
                }
              elseif isToyItem(itemID) then
                toys[#toys + 1] = {
                  itemID = itemID,
                  name = info.name,
                  collected = toyCollected(itemID),
                  icon = info.icon,
                }
              else
                lootOther[#lootOther + 1] = {
                  itemID = itemID,
                  name = info.name,
                  link = info.link,
                  icon = info.icon,
                  slot = info.slot,
                }
              end
            end
          end
        end
      end
    end
    return false
  end)
  if not gotMeta then
    return nil
  end
  return {
    instanceName = name,
    description = desc,
    mapID = mapID,
    bgImage = bgImage,
    titleImage = titleImage,
    buttonImage1 = buttonImage1,
    journalInstanceId = journalInstanceId,
    mounts = mounts,
    pets = pets,
    toys = toys,
    lootOther = lootOther,
  }
end

--- 清空 `FindJournalMetaByName` / `BuildRowList` 使用的按名缓存（版本切换或需强制重算时调用）。
function Toolbox.SavedInstancesData.ClearJournalNameCache()
  wipe(journalMetaByName)
end
