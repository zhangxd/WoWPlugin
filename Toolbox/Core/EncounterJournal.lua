--[[
  冒险手册（Encounter Journal）（领域对外 API）：12.0 / 至暗之夜优先使用 C_EncounterJournal。
  全局 EJ_* 仅作兜底；业务与模块代码禁止直接调用 EJ_*，应走本表。
  战利品：`GetNumLoot` / `GetLootInfoByIndex` 随「当前手册难度」变化，难度由 `SetDifficulty`（零售见 Warcraft Wiki `API_EJ_SetDifficulty`，与 `GetDifficultyInfo` 的 difficultyID 一致）。

  【接口是否「对」】本文件中的函数名与客户端导出一致：优先 `C_EncounterJournal.<同名>`，失败再回退 `EJ_*`。
  【副本信息从哪来】
  - 列表枚举：`GetInstanceByIndex` / `GetInstanceByIndexFlat`（第二参与团本/地下城 Tab 一致）。
  - 当前选中实例：`SelectInstance(journalInstanceID)` 后 `GetInstanceInfo()` / `Toolbox.EJ.GetInstanceInfoFlat()`（名称等多返回值与 table 两种形态见 `GetInstanceInfoFlat` 注释）。
  - 首领数与战利品行：`GetNumEncounters`、`GetNumLoot`、`GetLootInfoByIndex` 读的是**与手册 UI 共享的全局 EJ 状态**。
  【为何会出现首领数=0 / 扫不到战利品】仅代码里调用 `SelectInstance`+`SetDifficulty` 时，客户端有时仍未填充与「玩家在手册里点开该副本详情」等价的内部数据，因而 `GetNumEncounters` 可能长期为 0、`GetNumLoot` 为 0——这是**客户端状态未就绪**，不是「接口名写错」。要与游戏内一致，需挂在暴雪已刷新手册的时机（例如 `EncounterJournal_ListInstances` 之后、或等价于 UI 展开实例的路径），而非单靠固定秒级延迟。
]]

Toolbox.EJ = Toolbox.EJ or {}

local CJ = C_EncounterJournal

--- 从 `C_EncounterJournal` 若干 GetTab/GetSelectedTab 的返回值中取出数字 ID（部分版本返回 table：`tabID`/`id`/`ID` 或嵌套 `tab`）。
---@param t any
---@return number|nil
local function ejExtractTabIdFromReturn(t)
  if type(t) == "number" then
    return t
  end
  if type(t) == "table" then
    local id = t.tabID or t.id or t.ID or t.tabId
    if type(id) == "number" then
      return id
    end
    local inner = t.tab
    if type(inner) == "table" then
      id = inner.tabID or inner.id or inner.ID or inner.tabId
      if type(id) == "number" then
        return id
      end
    end
  end
  return nil
end

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

--- 当前选中实例、当前难度下的首领数量（需已 `SelectInstance`；与 `C_EncounterJournal.GetNumEncounters` / `EJ_GetNumEncounters` 一致）。
--- 若手册未在 UI 路径上完成该实例的数据刷新，可能返回 0；见文件头「为何会出现首领数=0」。
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

--- 当前冒险手册战利品专精过滤器。
--- 说明：该过滤器会影响 `GetNumLoot()` / `GetLootInfoByIndex()` 返回的结果；目录扫描前应清空，扫描后再恢复。
---@return number|nil classID
---@return number|nil specID
function Toolbox.EJ.GetLootFilter()
  if CJ and CJ.GetLootFilter then
    local ok, classID, specID = pcall(function()
      return CJ.GetLootFilter()
    end)
    if ok then
      return type(classID) == "number" and classID or nil, type(specID) == "number" and specID or nil
    end
  end
  if EJ_GetLootFilter then
    local ok, classID, specID = pcall(EJ_GetLootFilter)
    if ok then
      return type(classID) == "number" and classID or nil, type(specID) == "number" and specID or nil
    end
  end
  return nil, nil
end

--- 设置冒险手册战利品专精过滤器。
---@param classID number
---@param specID number
---@return boolean
function Toolbox.EJ.SetLootFilter(classID, specID)
  if type(classID) ~= "number" or type(specID) ~= "number" then
    return false
  end
  if CJ and CJ.SetLootFilter then
    local ok = pcall(function()
      CJ.SetLootFilter(classID, specID)
    end)
    if ok then
      return true
    end
  end
  if EJ_SetLootFilter then
    return pcall(EJ_SetLootFilter, classID, specID)
  end
  return false
end

--- 清空冒险手册战利品专精过滤器。
---@return boolean
function Toolbox.EJ.ResetLootFilter()
  if CJ and CJ.ResetLootFilter then
    local ok = pcall(function()
      CJ.ResetLootFilter()
    end)
    if ok then
      return true
    end
  end
  if EJ_ResetLootFilter then
    return pcall(EJ_ResetLootFilter)
  end
  return false
end

--- 当前冒险手册槽位过滤器。
--- 说明：`NoFilter` 时会返回 `Enum.ItemSlotFilterType.NoFilter`（零售通常为 15）。
---@return number|nil
function Toolbox.EJ.GetSlotFilter()
  if CJ and CJ.GetSlotFilter then
    local ok, filterID = pcall(function()
      return CJ.GetSlotFilter()
    end)
    if ok and type(filterID) == "number" then
      return filterID
    end
  end
  if EJ_GetSlotFilter then
    local ok, filterID = pcall(EJ_GetSlotFilter)
    if ok and type(filterID) == "number" then
      return filterID
    end
  end
  return nil
end

--- 设置冒险手册槽位过滤器。
---@param filterID number
---@return boolean
function Toolbox.EJ.SetSlotFilter(filterID)
  if type(filterID) ~= "number" then
    return false
  end
  if CJ and CJ.SetSlotFilter then
    local ok = pcall(function()
      CJ.SetSlotFilter(filterID)
    end)
    if ok then
      return true
    end
  end
  if EJ_SetSlotFilter then
    return pcall(EJ_SetSlotFilter, filterID)
  end
  return false
end

--- 清空冒险手册槽位过滤器。
---@return boolean
function Toolbox.EJ.ResetSlotFilter()
  if CJ and CJ.ResetSlotFilter then
    local ok = pcall(function()
      CJ.ResetSlotFilter()
    end)
    if ok then
      return true
    end
  end
  if EJ_ResetSlotFilter then
    return pcall(EJ_ResetSlotFilter)
  end
  local noFilter = _G.Enum and _G.Enum.ItemSlotFilterType and _G.Enum.ItemSlotFilterType.NoFilter or 15
  return Toolbox.EJ.SetSlotFilter(noFilter)
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

--- 某难度 ID 是否被客户端视为「手册当前实例可用的展示难度」（Wowpedia：`API_EJ_IsValidInstanceDifficulty`）。
--- **注意**：Wiki 上该页「示例有效 ID」表未覆盖全部 `DifficultyID`（例如旧版 10/25 人团本常用 3、4 等，见 `DifficultyID` 零售表）；若仅用本函数筛掉「返回 false」的 ID，可能误伤旧资料片。坐骑扫描等场景应结合 `DifficultyID` 总表与 `EJ_SetDifficulty` 行为，而非单独依赖本函数。
---@param difficultyID number `DifficultyID`（与 `GetDifficultyInfo` / `API_EJ_SetDifficulty` 一致）
---@return boolean|nil 是否有效；`nil` 表示 `C_EncounterJournal` 与全局 API 均不可用或调用失败，调用方勿当作 `false`
function Toolbox.EJ.IsValidInstanceDifficulty(difficultyID)
  if not difficultyID or type(difficultyID) ~= "number" then
    return nil
  end
  if CJ and CJ.IsValidInstanceDifficulty then
    local ok, v = pcall(function()
      return CJ.IsValidInstanceDifficulty(difficultyID)
    end)
    if ok and type(v) == "boolean" then
      return v
    end
  end
  if EJ_IsValidInstanceDifficulty then
    local ok, v = pcall(EJ_IsValidInstanceDifficulty, difficultyID)
    if ok and type(v) == "boolean" then
      return v
    end
  end
  return nil
end

--- 当前选中首领/难度下的战利品行数（与 `C_EncounterJournal.GetNumLoot` / `EJ_GetNumLoot` 一致）；未就绪时可能为 0，见文件头说明。
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
  原始返回值须与 `Toolbox.EJ.GetInstanceInfoFlat` 的注释一致；勿与 `GetInstanceByIndex` 的「首参=journalInstanceID」混淆。
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

--- 解析 `GetInstanceInfo()`，语义与 `GetInstanceByIndex` **不同**。
--- 多返回值（无参 `EJ_GetInstanceInfo`）：`instanceName, instanceDesc, backgroundTexture, buttonTexture, titleBackground, iconTexture, mapID, instanceLink`（见 wowprogramming `EJ_GetInstanceInfo`）；**不含** journalInstanceID。
--- 首参为 table（部分版本 `C_EncounterJournal`）：取 `name`/`instanceName`、`journalInstanceID`/`instanceID`/`id`、`isRaid`/`instanceType`。
---@return string|nil name
---@return number|nil journalInstanceID 仅首参为 table 时可能得到；多返回值形态下 API 不返回此项，为 nil。
---@return boolean|nil isRaid
function Toolbox.EJ.GetInstanceInfoFlat()
  local a, b, c, d, e, f, g, h, i, j = Toolbox.EJ.GetInstanceInfo()
  if a == nil then
    return nil, nil, nil
  end
  if type(a) == "table" then
    local t = a
    local jid = t.journalInstanceID or t.instanceID or t.id
    local name = t.name or t.instanceName
    if type(t.isRaid) == "boolean" then
      return name, type(jid) == "number" and jid or nil, t.isRaid
    end
    if type(t.instanceType) == "number" then
      if t.instanceType == 1 then
        return name, type(jid) == "number" and jid or nil, true
      end
      if t.instanceType == 2 then
        return name, type(jid) == "number" and jid or nil, false
      end
    end
    return name, type(jid) == "number" and jid or nil, nil
  end
  if type(a) == "string" then
    if a == "" then
      return nil, nil, nil
    end
    return a, nil, nil
  end
  return nil, nil, nil
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

--- 当前冒险手册顶层页签 ID（`C_EncounterJournal` 若提供 GetTab / GetSelectedTab 等）。
--- 不同版本函数名或返回值形态可能不同（有的返回 number，有的返回带 `tabID` 的 table）；均失败时返回 nil。
--- 与 `EncounterJournal.selectedTab`（内容区）及 `GetContentTabId`（内容子页签）可能不是同一套数字，见 `IsRaidOrDungeonInstanceListTab`。
---@return number|nil
function Toolbox.EJ.GetJournalTabId()
  if not CJ then
    return nil
  end
  -- 正式服各版本方法名不一，依次尝试（与 FrameXML 中 C_EncounterJournal 导出一致者优先）。
  local names = {
    "GetTab",
    "GetTabID",
    "GetTabId",
    "GetSelectedTab",
    "GetSelectedTabID",
    "GetSelectedTabId",
    "GetCurrentTab",
    "GetCurrentTabID",
    "GetJournalTabId",
    "GetSelectedTabIndex",
  }
  for _, name in ipairs(names) do
    local fn = CJ[name]
    if type(fn) == "function" then
      local ok, t = pcall(function()
        return fn(CJ)
      end)
      local id = ejExtractTabIdFromReturn(t)
      if ok and id then
        return id
      end
      ok, t = pcall(function()
        return fn()
      end)
      id = ejExtractTabIdFromReturn(t)
      if ok and id then
        return id
      end
    end
  end
  return nil
end

--- Mainline 冒险手册「内容」页签 ID（地下城/团队副本等列表与 `GetJournalTab` 可能不是同一套）。
---@return number|nil
function Toolbox.EJ.GetContentTabId()
  if not CJ then
    return nil
  end
  local names = {
    "GetSelectedContentTab",
    "GetSelectedContentTabID",
    "GetSelectedContentTabId",
    "GetContentTabID",
    "GetContentTabId",
    "GetCurrentContentTabID",
    "GetContentTab",
  }
  for _, name in ipairs(names) do
    local fn = CJ[name]
    if type(fn) == "function" then
      local ok, t = pcall(function()
        return fn(CJ)
      end)
      local id = ejExtractTabIdFromReturn(t)
      if ok and id then
        return id
      end
      ok, t = pcall(function()
        return fn()
      end)
      id = ejExtractTabIdFromReturn(t)
      if ok and id then
        return id
      end
    end
  end
  return nil
end

--- 给定 **C_EncounterJournal 风格** 的页签 ID（见 `GetJournalTabId`），是否为团本或地下城（与 UI 上 `EJ_ContentTab_Select` / `EncounterJournal.selectedTab` **可能不是同一套数字**）。
--- **不要**把 `EJ_ContentTab_Select` 的 id 或 `GetContentTabId` 的 ID 传进来当「Journal 页签」。
--- 优先对照 `Enum.EncounterJournalTab` 键名是否含 raid/dungeon；无 Enum 时 1/2 视为团本/地下城（弱兜底）。
---@param tabId number|nil
---@return boolean|nil tabId 为 nil 时 nil；能对照 Enum 但未命中任一键时 nil（与旧版一致，避免误杀）。
function Toolbox.EJ.IsRaidOrDungeonJournalTabId(tabId)
  if tabId == nil then
    return nil
  end
  if type(tabId) ~= "number" then
    return nil
  end
  local E = _G.Enum and _G.Enum.EncounterJournalTab
  if E then
    for key, val in pairs(E) do
      if type(val) == "number" and val == tabId then
        local kl = string.lower(tostring(key))
        if kl:find("raid", 1, true) or kl:find("dungeon", 1, true) then
          return true
        end
        return false
      end
    end
    return nil
  end
  if tabId == 1 or tabId == 2 then
    return true
  end
  return false
end

--- 当前是否处于「团队副本」或「地下城」顶层页签（用于挂件是否显示）。
--- 无法取得页签 ID 时返回 nil，由调用方决定默认行为。
---@return boolean|nil
function Toolbox.EJ.IsRaidOrDungeonJournalTab()
  return Toolbox.EJ.IsRaidOrDungeonJournalTabId(Toolbox.EJ.GetJournalTabId())
end

--- 与 `EncounterJournal.selectedTab` 比较的「团队副本 / 地下城」内容按钮 ID（`raidsTab` / `dungeonsTab` 的 `GetID()`）。
--- 与 `C_EncounterJournal` 的 `GetJournalTabId` / `GetContentTabId` **不是**同一套数字；挂件与列表语境判定以本函数 + `selectedTab` 为准。
---@return number|nil raidId
---@return number|nil dungeonId
function Toolbox.EJ.GetEncounterJournalInstanceListButtonIds()
  local ej = _G.EncounterJournal
  if not ej then
    return nil, nil
  end
  local raidsTab = ej.raidsTab
  local dungeonsTab = ej.dungeonsTab
  if not raidsTab or not dungeonsTab then
    return nil, nil
  end
  local okR, rid = pcall(function()
    return raidsTab:GetID()
  end)
  local okD, did = pcall(function()
    return dungeonsTab:GetID()
  end)
  if not okR or not okD or type(rid) ~= "number" or type(did) ~= "number" then
    return nil, nil
  end
  return rid, did
end

--- 当前 `EncounterJournal.selectedTab` 的内容按钮 ID。
--- 说明：这是 Blizzard_EncounterJournal 维护的“地下城 / 团队副本 / 其它内容页”选中状态，
--- 与 `C_EncounterJournal.GetJournalTabId()` / `GetContentTabId()` 不是同一套数字。
---@return number|nil
function Toolbox.EJ.GetEncounterJournalSelectedTabId()
  local ej = _G.EncounterJournal
  if not ej then
    return nil
  end
  local selectedTab = ej.selectedTab
  if type(selectedTab) == "number" then
    return selectedTab
  end
  return nil
end

--- 切换 Blizzard 冒险手册“地下城 / 团队副本”内容页签。
--- 说明：目录扫描需与 `SelectInstance` 使用同一套 EJ 共享状态；若当前页签不对，某些实例的难度/战利品上下文可能读错。
---@param isRaid boolean true=团队副本页签，false=地下城页签
---@return boolean
function Toolbox.EJ.SelectEncounterJournalInstanceListTab(isRaid)
  if type(isRaid) ~= "boolean" then
    return false
  end

  local selectedTab = Toolbox.EJ.GetEncounterJournalSelectedTabId()
  local raidId, dungeonId = Toolbox.EJ.GetEncounterJournalInstanceListButtonIds()
  local targetId = isRaid and raidId or dungeonId
  if type(targetId) ~= "number" then
    return false
  end
  if selectedTab == targetId then
    return true
  end

  local selectFn = _G.EJ_ContentTab_Select
  if type(selectFn) ~= "function" then
    return false
  end

  local ok = pcall(selectFn, targetId)
  if not ok then
    return false
  end

  return Toolbox.EJ.GetEncounterJournalSelectedTabId() == targetId
end

--- Mainline 冒险手册「内容页」：是否为 **团队副本 / 地下城** 列表（资料片下拉 + 副本 ScrollBox）。
--- 依据 `Blizzard_EncounterJournal` 中 `EJ_ContentTab_Select` 写入的 `EncounterJournal.selectedTab` 与
--- `raidsTab` / `dungeonsTab` 的 `GetID()` 比较（与 `EncounterJournal_SetTab` **无关**——后者是副本详情内首领/战利品等子页签）。
---@return boolean|nil 框架未就绪时 nil
function Toolbox.EJ.IsRaidOrDungeonInstanceListTab()
  local ej = _G.EncounterJournal
  if not ej then
    return nil
  end
  local rid, did = Toolbox.EJ.GetEncounterJournalInstanceListButtonIds()
  if rid == nil or did == nil then
    return nil
  end
  local sid = Toolbox.EJ.GetEncounterJournalSelectedTabId()
  if type(sid) ~= "number" then
    return nil
  end
  return sid == rid or sid == did
end
