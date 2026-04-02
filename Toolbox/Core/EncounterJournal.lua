--[[
  冒险手册（Encounter Journal）门面：12.0 / 至暗之夜优先使用 C_EncounterJournal。
  全局 EJ_* 仅作兜底；业务与模块代码禁止直接调用 EJ_*，应走本表。
  战利品：`GetNumLoot` / `GetLootInfoByIndex` 随「当前手册难度」变化，难度由 `SetDifficulty`（零售见 Warcraft Wiki `API_EJ_SetDifficulty`，与 `GetDifficultyInfo` 的 difficultyID 一致）。
]]

Toolbox.EJ = Toolbox.EJ or {}

local CJ = C_EncounterJournal

local function tryC(fn)
  if not CJ then
    return nil
  end
  local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn)
  if ok then
    return a, b, c, d, e, f, g, h, i, j
  end
  return nil
end

function Toolbox.EJ.ClearSearch()
  if CJ and CJ.ClearSearch then
    tryC(function()
      CJ.ClearSearch()
    end)
    return
  end
  if EJ_ClearSearch then
    EJ_ClearSearch()
  end
end

---@param instanceID number 冒险手册 Journal 实例 ID（与 GetSavedInstanceInfo 最后一项 instanceId **不一定**相同）
---@return boolean 是否成功（失败时绝不抛错，避免无效 ID 刷屏）
function Toolbox.EJ.SelectInstance(instanceID)
  if not instanceID or type(instanceID) ~= "number" then
    return false
  end
  if CJ and CJ.SelectInstance then
    local ok = pcall(function()
      CJ.SelectInstance(instanceID)
    end)
    if ok then
      return true
    end
  end
  if EJ_SelectInstance then
    local ok = pcall(function()
      EJ_SelectInstance(instanceID)
    end)
    return ok
  end
  return false
end

function Toolbox.EJ.SelectEncounter(encounterIndex)
  if CJ and CJ.SelectEncounter then
    local ok = pcall(function()
      CJ.SelectEncounter(encounterIndex)
    end)
    if ok then
      return true
    end
  end
  if EJ_SelectEncounter then
    local ok = pcall(function()
      EJ_SelectEncounter(encounterIndex)
    end)
    return ok
  end
  return false
end

---@return string|nil 版本/资料片名称（用于下拉筛选）；可能是 table 需取 .name
function Toolbox.EJ.GetTierInfo(tierIndex)
  if not tierIndex or type(tierIndex) ~= "number" then
    return nil
  end
  if CJ and CJ.GetTierInfo then
    local ok, info = pcall(function()
      return CJ.GetTierInfo(tierIndex)
    end)
    if ok and info ~= nil then
      if type(info) == "table" then
        return info.name or info.text or info.title
      end
      if type(info) == "string" then
        return info
      end
    end
  end
  if EJ_GetTierInfo then
    local ok, a, b, c = pcall(EJ_GetTierInfo, tierIndex)
    if ok and a ~= nil then
      if type(a) == "string" then
        return a
      end
      if type(a) == "table" then
        return a.name or a.text
      end
    end
  end
  return nil
end

function Toolbox.EJ.GetNumTiers()
  local n = tryC(function()
    return CJ.GetNumTiers()
  end)
  if type(n) == "number" and n > 0 then
    return n
  end
  if EJ_GetNumTiers then
    return EJ_GetNumTiers() or 1
  end
  return 1
end

function Toolbox.EJ.SelectTier(tier)
  if CJ and CJ.SelectTier then
    tryC(function()
      CJ.SelectTier(tier)
    end)
  elseif EJ_SelectTier then
    EJ_SelectTier(tier)
  end
end

function Toolbox.EJ.GetNumInstances()
  local n = tryC(function()
    return CJ.GetNumInstances()
  end)
  if type(n) == "number" then
    return n
  end
  if EJ_GetNumInstances then
    return EJ_GetNumInstances() or 0
  end
  return 0
end

---@param index number 从 1 递增直到返回 nil
---@param isRaid boolean|nil 与 EJ_GetInstanceByIndex 第二参一致：团本 Tab 为 true，地下城 Tab 为 false（勿传「实例数量」）
function Toolbox.EJ.GetInstanceByIndex(index, isRaid)
  if CJ and CJ.GetInstanceByIndex then
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(function()
      return CJ.GetInstanceByIndex(index, isRaid)
    end)
    if ok and a ~= nil then
      return a, b, c, d, e, f, g, h, i, j, k, l, m, n
    end
  end
  if EJ_GetInstanceByIndex then
    return EJ_GetInstanceByIndex(index, isRaid)
  end
  return nil
end

--- 解析 GetInstanceByIndex：journalInstanceID、名称、是否团队副本（资料片下列表筛选用）。
---@return number|nil journalInstanceID
---@return string|nil name
---@return boolean|nil isRaid true=团本 false=地下城 nil=客户端未给出（仅「全部」筛选可靠）
function Toolbox.EJ.GetInstanceByIndexFlat(index, isRaid)
  local function parseMulti(a, b, c, d, e, f, g, h, i, j, k, l, m, n)
    if a == nil then
      return nil, nil, nil
    end
    if type(a) == "table" then
      local t = a
      local jid = t.journalInstanceID or t.instanceID or t.id
      local name = t.name
      if type(t.isRaid) == "boolean" then
        return jid, name, t.isRaid
      end
      if type(t.instanceType) == "number" then
        if t.instanceType == 1 then
          return jid, name, true
        end
        if t.instanceType == 2 then
          return jid, name, false
        end
      end
      return jid, name, nil
    end
    local jid, name = a, b
    if type(n) == "boolean" then
      return jid, name, n
    end
    if type(m) == "boolean" then
      return jid, name, m
    end
    if type(l) == "number" then
      if l == 1 then
        return jid, name, true
      end
      if l == 2 then
        return jid, name, false
      end
    end
    return jid, name, nil
  end

  if CJ and CJ.GetInstanceByIndex then
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(function()
      return CJ.GetInstanceByIndex(index, isRaid)
    end)
    if ok then
      return parseMulti(a, b, c, d, e, f, g, h, i, j, k, l, m, n)
    end
  end
  if EJ_GetInstanceByIndex then
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(function()
      return EJ_GetInstanceByIndex(index, isRaid)
    end)
    if ok then
      return parseMulti(a, b, c, d, e, f, g, h, i, j, k, l, m, n)
    end
  end
  return nil, nil, nil
end

--- 当前已选实例下，第 encounterIndex 个首领名称（需先 SelectInstance）。
function Toolbox.EJ.GetEncounterName(encounterIndex)
  if not encounterIndex then
    return nil
  end
  if CJ and CJ.GetEncounterInfo then
    local ok, info = pcall(function()
      return CJ.GetEncounterInfo(encounterIndex)
    end)
    if ok and info ~= nil then
      if type(info) == "table" then
        return info.name or info.encounterName
      end
      if type(info) == "string" then
        return info
      end
    end
  end
  if EJ_GetEncounterInfo then
    local ok, a = pcall(EJ_GetEncounterInfo, encounterIndex)
    if ok and a ~= nil then
      if type(a) == "table" then
        return a.name
      end
      if type(a) == "string" then
        return a
      end
    end
  end
  return nil
end

function Toolbox.EJ.GetNumEncounters()
  local n = tryC(function()
    return CJ.GetNumEncounters()
  end)
  if type(n) == "number" then
    return n
  end
  if EJ_GetNumEncounters then
    return EJ_GetNumEncounters() or 0
  end
  return 0
end

--- 当前冒险手册选中的难度 ID（`DifficultyID`），与 `GetDifficultyInfo` 一致。
---@return number|nil
function Toolbox.EJ.GetDifficulty()
  local d = tryC(function()
    return CJ.GetDifficulty()
  end)
  if type(d) == "number" and d > 0 then
    return d
  end
  if EJ_GetDifficulty then
    local ok, x = pcall(EJ_GetDifficulty)
    if ok and type(x) == "number" and x > 0 then
      return x
    end
  end
  return nil
end

--- 设置冒险手册展示用难度；影响首领与**战利品表**等（官方说明见 Warcraft Wiki `API_EJ_SetDifficulty`，会触发 `EJ_DIFFICULTY_UPDATE`）。
---@param difficultyID number 难度 ID，取值范围与 `GetDifficultyInfo` 相同
---@return boolean 是否已成功调用客户端接口
function Toolbox.EJ.SetDifficulty(difficultyID)
  if not difficultyID or type(difficultyID) ~= "number" then
    return false
  end
  if CJ and CJ.SetDifficulty then
    local ok = pcall(function()
      CJ.SetDifficulty(difficultyID)
    end)
    if ok then
      return true
    end
  end
  if EJ_SetDifficulty then
    return pcall(function()
      EJ_SetDifficulty(difficultyID)
    end)
  end
  return false
end

function Toolbox.EJ.GetNumLoot()
  local n = tryC(function()
    return CJ.GetNumLoot()
  end)
  if type(n) == "number" then
    return n
  end
  if EJ_GetNumLoot then
    return EJ_GetNumLoot() or 0
  end
  return 0
end

---@return EncounterJournalItemInfo|nil
function Toolbox.EJ.GetLootInfoByIndex(lootIndex, encounterIndex)
  local info = tryC(function()
    if encounterIndex ~= nil then
      return CJ.GetLootInfoByIndex(lootIndex, encounterIndex)
    end
    return CJ.GetLootInfoByIndex(lootIndex)
  end)
  if info ~= nil then
    return info
  end
  -- C_ 返回空时回退全局 EJ_GetLootInfoByIndex（与 GetInstanceInfo 等一致）
  if EJ_GetLootInfoByIndex then
    local ok, t = pcall(function()
      if encounterIndex ~= nil then
        return EJ_GetLootInfoByIndex(lootIndex, encounterIndex)
      end
      return EJ_GetLootInfoByIndex(lootIndex)
    end)
    if ok and t ~= nil then
      return t
    end
  end
  return nil
end

--[[
  当前选中实例的信息（与手册 UI 共享全局 EJ 状态）。
  常见返回值：name, description, bgImage, loreBgImage, buttonImage1, buttonImage2, titleImage,
  instanceID, mapID, areaID, ...
]]
function Toolbox.EJ.GetInstanceInfo()
  local a, b, c, d, e, f, g, h, i, j = tryC(function()
    return CJ.GetInstanceInfo()
  end)
  if a ~= nil then
    return a, b, c, d, e, f, g, h, i, j
  end
  if EJ_GetInstanceInfo then
    return EJ_GetInstanceInfo()
  end
  return nil
end

---@param uiMapID number
---@return number|nil journalInstanceID
function Toolbox.EJ.GetInstanceForMap(uiMapID)
  if not uiMapID then
    return nil
  end
  local jid = tryC(function()
    return CJ.GetInstanceForMap(uiMapID)
  end)
  if type(jid) == "number" then
    return jid
  end
  return nil
end
