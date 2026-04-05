--[[
  地下城 / 团队副本目录（领域对外 API）。
  以冒险手册（Encounter Journal）为事实源，统一维护：
  - 全部地下城 / 团队副本基础目录
  - 每个副本支持的难度集合
  - 坐骑掉落摘要（仅摘要，不存完整 loot 树）
  - 当前角色锁定的运行时覆盖层
  - 异步构建状态、进度与手动重建入口

  设计要点：
  - 持久化缓存仅落在 `ToolboxDB.global.dungeonRaidDirectory`
  - 角色锁定与构建游标仅保存在运行时，不写入账号级 SavedVariables
  - 与冒险手册共享 EJ 全局选中状态，所有扫描均通过 `EJStateDriver` 捕获并恢复
]]

Toolbox.DungeonRaidDirectory = Toolbox.DungeonRaidDirectory or {}

local Directory = Toolbox.DungeonRaidDirectory
local SETTINGS_MODULE_ID = "dungeon_raid_directory"

-- 目录扫描语义已调整（补齐 EJ 内容页签、loot/slot filter、无数据重试）；
-- 旧缓存中的 hasMountLoot 结论不再可靠，需强制失效后重建。
local CACHE_SCHEMA_VERSION = 2
local BUILD_BUDGET_MS = 4
local MOUNT_SUMMARY_RETRY_LIMIT = 6
local MOUNT_SCAN_NOT_READY = {}

local RAID_DIFFICULTY_CANDIDATES = { 16, 15, 14, 17, 33, 151, 7, 9, 3, 4, 5, 6 }
local DUNGEON_DIFFICULTY_CANDIDATES = { 23, 8, 24, 2, 1 }
local TARGET_DEBUG_INSTANCE_NAMES = {
  "风行者之塔",
  "斯坦索姆 - 仆从入口",
}

local cache
local runtime = Directory._runtime or {
  state = "idle",
  currentStage = nil,
  totalUnits = 0,
  completedUnits = 0,
  stageTotalUnits = 0,
  stageCompletedUnits = 0,
  currentLabel = nil,
  failureMessage = nil,
  isManualRebuild = false,
  token = 0,
  driverFrame = nil,
  eventFrame = nil,
  initialized = false,
  recordOrder = {},
  cursor = {},
  skeletonDescriptors = {},
  difficultyUnitTotal = 0,
  mountUnitTotal = 0,
  startedAtSec = 0,
  lockoutsByJournalInstanceID = {},
  isEncounterJournalPaused = false,
  pausedByEncounterJournalThisBuild = false,
  pendingEncounterJournalReadyNotice = false,
  pendingSkeletonEnumeration = false,
  mountSummaryRetryCounts = {},
  priorityTierIndex = nil,
  summariesNormalizedAt = 0,
}

Directory._runtime = runtime

local getOrderedJournalInstanceIDs
local getCurrentTierIndex

local function getCurrentInterfaceBuild()
  local _, _, _, tocVersion = GetBuildInfo()
  return tonumber(tocVersion) or 0
end

local function getDifficultyName(difficultyID)
  if type(difficultyID) ~= "number" then
    return ""
  end
  if GetDifficultyInfo then
    local name = GetDifficultyInfo(difficultyID)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  return tostring(difficultyID)
end

---@param tierIndex number|nil
---@return string
local function getTierNameForProgress(tierIndex)
  if type(tierIndex) ~= "number" or tierIndex <= 0 then
    return "?"
  end

  local cached = cache and cache.tierNames and cache.tierNames[tierIndex]
  if type(cached) == "string" and cached ~= "" then
    return cached
  end

  local name = Toolbox.EJ.GetTierInfo(tierIndex)
  if type(name) == "string" and name ~= "" then
    if cache and type(cache.tierNames) == "table" then
      cache.tierNames[tierIndex] = name
    end
    return name
  end

  return tostring(tierIndex)
end

---@param tierIndex number|nil
---@param recordName string|nil
---@param detail string|nil
---@return string
local function formatProgressRecordLabel(tierIndex, recordName, detail)
  local tierName = getTierNameForProgress(tierIndex)
  local name = type(recordName) == "string" and recordName ~= "" and recordName or "?"
  if type(detail) == "string" and detail ~= "" then
    return string.format("%s / %s / %s", tierName, name, detail)
  end
  return string.format("%s / %s", tierName, name)
end

local function normalizeName(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local value = string.lower(name)
  value = value:gsub("[%s%p]", "")
  if value == "" then
    return nil
  end
  return value
end

local MOUNT_SUMMARY_SUPPLEMENTS_BY_NAME = {
  [normalizeName("风行者之塔")] = {
    hasAnyMountLoot = true,
    source = "manual_name_override",
    mountDifficultyIDs = {},
  },
}

local function getTargetDebugNameSet()
  local out = {}
  for _, name in ipairs(TARGET_DEBUG_INSTANCE_NAMES) do
    local normalized = normalizeName(name)
    if normalized then
      out[normalized] = true
    end
  end
  return out
end

local TARGET_DEBUG_NAME_SET = getTargetDebugNameSet()

---@param name string|nil
---@return boolean
local function isTargetDebugName(name)
  local normalized = normalizeName(name)
  return normalized ~= nil and TARGET_DEBUG_NAME_SET[normalized] == true
end

local function createEmptyCache()
  return {
    schemaVersion = CACHE_SCHEMA_VERSION,
    interfaceBuild = getCurrentInterfaceBuild(),
    lastBuildAt = 0,
    tierNames = {},
    difficultyMeta = {},
    records = {},
  }
end

local function ensureCacheShape(t)
  if type(t) ~= "table" then
    t = createEmptyCache()
  end
  t.schemaVersion = tonumber(t.schemaVersion) or CACHE_SCHEMA_VERSION
  t.interfaceBuild = tonumber(t.interfaceBuild) or 0
  t.lastBuildAt = tonumber(t.lastBuildAt) or 0
  t.tierNames = type(t.tierNames) == "table" and t.tierNames or {}
  t.difficultyMeta = type(t.difficultyMeta) == "table" and t.difficultyMeta or {}
  t.records = type(t.records) == "table" and t.records or {}
  return t
end

local function saveCacheToDb()
  Toolbox.DB.Init()
  local g = Toolbox.DB.GetGlobal()
  g.dungeonRaidDirectory = ensureCacheShape(cache)
  cache = g.dungeonRaidDirectory
end

local function rebuildRecordOrderFromCache()
  runtime.recordOrder = {}
  if not cache or type(cache.records) ~= "table" then
    return
  end

  for jid, record in pairs(cache.records) do
    if type(jid) == "number" and type(record) == "table" and type(record.base) == "table" then
      runtime.recordOrder[#runtime.recordOrder + 1] = jid
    end
  end

  table.sort(runtime.recordOrder, function(a, b)
    local ra = cache.records[a]
    local rb = cache.records[b]
    local ba = ra and ra.base or {}
    local bb = rb and rb.base or {}
    local ta = tonumber(ba.tierIndex) or 0
    local tb = tonumber(bb.tierIndex) or 0
    if ta ~= tb then
      return ta < tb
    end
    local ka = ba.kind == "raid" and 2 or 1
    local kb = bb.kind == "raid" and 2 or 1
    if ka ~= kb then
      return ka < kb
    end
    local na = tostring(ba.name or "")
    local nb = tostring(bb.name or "")
    if na ~= nb then
      return na < nb
    end
    return a < b
  end)
end

local function loadCacheFromDb()
  Toolbox.DB.Init()
  local g = Toolbox.DB.GetGlobal()
  g.dungeonRaidDirectory = ensureCacheShape(g.dungeonRaidDirectory)
  cache = g.dungeonRaidDirectory
  rebuildRecordOrderFromCache()
end

-- 读路径在构建进行中应优先读取内存工作缓存，避免把尚未落盘的扫描进度回退成旧 DB 快照。
local function loadCacheForRead()
  if runtime.state == "building" and type(cache) == "table" then
    -- 构建中的工作缓存仅存在内存里；读路径若此时强制回表，会把当前扫描进度覆盖成旧 DB 快照。
    return
  end
  loadCacheFromDb()
end

local function ensureCacheLoaded()
  if type(cache) ~= "table" then
    loadCacheFromDb()
  end
end

local function getSettingsDb()
  Toolbox.DB.Init()
  return Toolbox.DB.GetModule(SETTINGS_MODULE_ID)
end

local function isFeatureEnabled()
  return getSettingsDb().enabled ~= false
end

local function isDebugChatEnabled()
  return getSettingsDb().debug == true
end

local function debugPrint(message)
  if not isDebugChatEnabled() then
    return
  end
  -- 当前目录调试切换为“目标副本定向追踪”，泛化阶段日志暂时静音，
  -- 避免构建进度与锁定刷新把真正的问题链路淹没。
end

---@param difficultyID number|nil
---@return string
local function formatDifficultyLabelForDebug(difficultyID)
  if type(difficultyID) ~= "number" then
    return "?"
  end
  return string.format("%s(%s)", getDifficultyName(difficultyID), tostring(difficultyID))
end

---@param record table|nil
---@return boolean
local function isTargetDebugRecord(record)
  local base = record and record.base
  return type(base) == "table" and isTargetDebugName(base.name)
end

---@param record table|nil
---@return string
local function formatTargetDebugRecordName(record)
  local base = record and record.base
  if type(base) == "table" and type(base.name) == "string" and base.name ~= "" then
    return base.name
  end
  return "?"
end

---@param values number[]|nil
---@return string
local function formatDifficultyListForDebug(values)
  if type(values) ~= "table" or #values == 0 then
    return "[]"
  end
  local parts = {}
  for _, difficultyID in ipairs(values) do
    parts[#parts + 1] = formatDifficultyLabelForDebug(difficultyID)
  end
  return "[" .. table.concat(parts, "，") .. "]"
end

---@param primary number[]|nil
---@param secondary number[]|nil
---@return number[]
local function mergeDifficultyIDLists(primary, secondary)
  local out = {}
  local seen = {}
  for _, list in ipairs({ primary, secondary }) do
    if type(list) == "table" then
      for _, difficultyID in ipairs(list) do
        if type(difficultyID) == "number" and not seen[difficultyID] then
          seen[difficultyID] = true
          out[#out + 1] = difficultyID
        end
      end
    end
  end
  return out
end

---@param record table|nil
---@return table|nil
local function getMountSummarySupplement(record)
  local base = record and record.base
  local normalizedName = base and normalizeName(base.name)
  if not normalizedName then
    return nil
  end
  return MOUNT_SUMMARY_SUPPLEMENTS_BY_NAME[normalizedName]
end

---@param record table|nil
local function applyMountSummarySupplement(record)
  if type(record) ~= "table" then
    return
  end
  record.summary = type(record.summary) == "table" and record.summary or {
    hasAnyMountLoot = nil,
    mountDifficultyIDs = {},
  }

  local summary = record.summary
  local supplement = getMountSummarySupplement(record)
  if type(supplement) ~= "table" then
    summary.supplementSource = nil
    return
  end

  summary.supplementSource = tostring(supplement.source or "manual_name_override")
  if supplement.hasAnyMountLoot == true then
    summary.hasAnyMountLoot = true
    summary.mountDifficultyIDs = mergeDifficultyIDLists(summary.mountDifficultyIDs, supplement.mountDifficultyIDs)
  end
end

---@param itemID number|nil
---@param fallbackName string|nil
---@return string
local function getItemNameForDebug(itemID, fallbackName)
  if type(fallbackName) == "string" and fallbackName ~= "" then
    return fallbackName
  end
  if type(itemID) ~= "number" or itemID <= 0 then
    return ""
  end

  local ok, name = pcall(function()
    if C_Item and C_Item.GetItemNameByID then
      return C_Item.GetItemNameByID(itemID)
    end
    if GetItemInfo then
      return (GetItemInfo(itemID))
    end
    return nil
  end)
  if ok and type(name) == "string" and name ~= "" then
    return name
  end
  return ""
end

---@param key string
---@param ... any
local function debugPrintTarget(key, ...)
  if not isDebugChatEnabled() then
    return
  end
  local L = Toolbox.L or {}
  local pattern = L[key]
  if type(pattern) ~= "string" or pattern == "" then
    return
  end
  Toolbox.Chat.PrintAddonMessage(string.format(pattern, ...))
end

local function debugPrintMissingTargetRecords()
  ensureCacheLoaded()
  local missing = {}

  for _, targetName in ipairs(TARGET_DEBUG_INSTANCE_NAMES) do
    local found = false
    for _, journalInstanceID in ipairs(getOrderedJournalInstanceIDs()) do
      local record = cache.records and cache.records[journalInstanceID]
      if record and record.base and normalizeName(record.base.name) == normalizeName(targetName) then
        found = true
        break
      end
    end
    if not found then
      missing[#missing + 1] = targetName
    end
  end

  if #missing > 0 then
    debugPrintTarget("DRD_DEBUG_TARGET_MISSING", table.concat(missing, "，"))
  end
end

local function getStageLabelForDebug(stage)
  local L = Toolbox.L or {}
  if stage == "record_pipeline" then
    return L.DRD_STAGE_RECORD_PIPELINE or tostring(stage)
  end
  if stage == "skeleton" then
    return L.DRD_STAGE_SKELETON or tostring(stage)
  end
  if stage == "difficulty" then
    return L.DRD_STAGE_DIFFICULTY or tostring(stage)
  end
  if stage == "mount_summary" then
    return L.DRD_STAGE_MOUNT_SUMMARY or tostring(stage)
  end
  return tostring(stage or "")
end

local function getBuildModeLabel(isManual)
  local L = Toolbox.L or {}
  if isManual == true then
    return L.DRD_DEBUG_MODE_MANUAL or "manual"
  end
  return L.DRD_DEBUG_MODE_AUTO or "auto"
end

local function getNowSeconds()
  if GetTimePreciseSec then
    return GetTimePreciseSec()
  end
  return GetTime()
end

local function countRecordTotal()
  ensureCacheLoaded()
  local total = 0
  for _ in pairs(cache and cache.records or {}) do
    total = total + 1
  end
  return total
end

local function countSupportedDifficultyTotal()
  ensureCacheLoaded()
  local total = 0
  for _, record in pairs(cache and cache.records or {}) do
    total = total + #(record and record.difficultyOrder or {})
  end
  return total
end

local function countMountPositiveRecordTotal()
  ensureCacheLoaded()
  local total = 0
  for _, record in pairs(cache and cache.records or {}) do
    if record and record.summary and record.summary.hasAnyMountLoot == true then
      total = total + 1
    end
  end
  return total
end

local function countMappedLockoutTotal()
  local total = 0
  for _, difficulties in pairs(runtime.lockoutsByJournalInstanceID or {}) do
    if type(difficulties) == "table" then
      for _ in pairs(difficulties) do
        total = total + 1
      end
    end
  end
  return total
end

local function copyArray(source)
  local out = {}
  if type(source) ~= "table" then
    return out
  end
  for index, value in ipairs(source) do
    out[index] = value
  end
  return out
end

local function copyLockoutRecord(lockout)
  if type(lockout) ~= "table" then
    return nil
  end
  return {
    instanceId = lockout.instanceId,
    difficultyId = lockout.difficultyId,
    reset = lockout.reset,
    locked = lockout.locked,
    extended = lockout.extended,
    encounterProgress = lockout.encounterProgress,
    numEncounters = lockout.numEncounters,
    name = lockout.name,
  }
end

local function copyDifficultyMeta()
  ensureCacheLoaded()
  local out = {}
  for difficultyID, meta in pairs(cache and cache.difficultyMeta or {}) do
    out[difficultyID] = {
      name = type(meta) == "table" and meta.name or getDifficultyName(difficultyID),
    }
  end
  return out
end

local function copyTierNames()
  ensureCacheLoaded()
  local out = {}
  for tierIndex, name in pairs(cache and cache.tierNames or {}) do
    out[tierIndex] = name
  end
  return out
end

local function buildDifficultyDebugSnapshot(journalInstanceID, record, difficultyID)
  local difficultyRecord = record and record.difficulties and record.difficulties[difficultyID] or nil
  local lockouts = runtime.lockoutsByJournalInstanceID[journalInstanceID]
  return {
    difficultyID = difficultyID,
    name = cache.difficultyMeta[difficultyID] and cache.difficultyMeta[difficultyID].name or getDifficultyName(difficultyID),
    hasMountLoot = difficultyRecord and difficultyRecord.hasMountLoot or nil,
    lockout = copyLockoutRecord(lockouts and lockouts[difficultyID] or nil),
  }
end

local function buildRecordDebugSnapshot(journalInstanceID, record)
  local base = record and record.base or {}
  local summary = record and record.summary or {}
  local difficulties = {}

  for _, difficultyID in ipairs(record and record.difficultyOrder or {}) do
    difficulties[#difficulties + 1] = buildDifficultyDebugSnapshot(journalInstanceID, record, difficultyID)
  end

  return {
    journalInstanceID = journalInstanceID,
    base = {
      journalInstanceID = base.journalInstanceID,
      name = base.name,
      kind = base.kind,
      tierIndex = base.tierIndex,
      tierName = cache.tierNames and cache.tierNames[base.tierIndex] or nil,
      mapID = base.mapID,
      worldInstanceID = base.worldInstanceID,
    },
    summary = {
      hasAnyMountLoot = summary.hasAnyMountLoot,
      mountDifficultyIDs = copyArray(summary.mountDifficultyIDs),
    },
    difficulties = difficulties,
  }
end

local function collectRecordDebugSnapshots()
  ensureCacheLoaded()
  local out = {}
  for _, journalInstanceID in ipairs(getOrderedJournalInstanceIDs()) do
    local record = cache.records and cache.records[journalInstanceID]
    if record and record.summary and record.summary.hasAnyMountLoot == true then
      out[#out + 1] = buildRecordDebugSnapshot(journalInstanceID, record)
    end
  end
  return out
end

local function sortDebugKeys(keys)
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then
      return a < b
    end
    return tostring(a) < tostring(b)
  end)
end

local function formatDebugScalar(value)
  if value == nil then
    return "nil"
  end
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  return tostring(value)
end

local function formatDebugArray(values)
  if values == nil then
    return "nil"
  end
  if type(values) ~= "table" then
    return "[" .. tostring(values) .. "]"
  end
  if #values == 0 then
    return "[]"
  end

  local parts = {}
  for _, value in ipairs(values) do
    parts[#parts + 1] = formatDebugScalar(value)
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function formatDebugNamedMap(values, valueKey)
  if values == nil then
    return "nil"
  end
  if type(values) ~= "table" then
    return tostring(values)
  end

  local keys = {}
  for key in pairs(values) do
    keys[#keys + 1] = key
  end
  if #keys == 0 then
    return "{}"
  end

  sortDebugKeys(keys)

  local parts = {}
  for _, key in ipairs(keys) do
    local value = values[key]
    if type(value) == "table" and valueKey then
      value = value[valueKey]
    end
    parts[#parts + 1] = tostring(key) .. "=" .. formatDebugScalar(value)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function formatLockoutProgress(lockout)
  if type(lockout) ~= "table" then
    return "nil"
  end
  return string.format(
    "%s/%s",
    formatDebugScalar(lockout.encounterProgress),
    formatDebugScalar(lockout.numEncounters)
  )
end

local function formatDebugLockout(lockout)
  if type(lockout) ~= "table" then
    return "nil"
  end

  local parts = {
    "instanceId=" .. formatDebugScalar(lockout.instanceId),
    "difficultyId=" .. formatDebugScalar(lockout.difficultyId),
    "reset=" .. formatDebugScalar(lockout.reset),
    "locked=" .. formatDebugScalar(lockout.locked),
    "extended=" .. formatDebugScalar(lockout.extended),
    "progress=" .. formatLockoutProgress(lockout),
    "name=" .. formatDebugScalar(lockout.name),
  }
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function isCacheInvalid()
  if type(cache) ~= "table" then
    return true
  end
  if cache.schemaVersion ~= CACHE_SCHEMA_VERSION then
    return true
  end
  if cache.interfaceBuild ~= getCurrentInterfaceBuild() then
    return true
  end
  if cache.lastBuildAt <= 0 then
    return true
  end
  if type(cache.records) ~= "table" or next(cache.records) == nil then
    return true
  end
  return false
end

getOrderedJournalInstanceIDs = function()
  if #runtime.recordOrder == 0 then
    rebuildRecordOrderFromCache()
  end
  return runtime.recordOrder
end

local function getStageCandidates(record)
  local kind = record and record.base and record.base.kind
  if kind == "raid" then
    return RAID_DIFFICULTY_CANDIDATES
  end
  return DUNGEON_DIFFICULTY_CANDIDATES
end

---@generic T
---@param values T[]|nil
---@param priorityTierIndex number|nil
---@param getTierIndex fun(value:T):number|nil
---@return T[]
local function buildTierPrioritizedList(values, priorityTierIndex, getTierIndex)
  if type(values) ~= "table" or #values == 0 or type(priorityTierIndex) ~= "number" or priorityTierIndex <= 0 then
    return values or {}
  end

  local prioritized = {}
  local remainder = {}
  for _, value in ipairs(values) do
    if getTierIndex(value) == priorityTierIndex then
      prioritized[#prioritized + 1] = value
    else
      remainder[#remainder + 1] = value
    end
  end

  if #prioritized == 0 or #remainder == 0 then
    return values
  end

  local out = {}
  for _, value in ipairs(prioritized) do
    out[#out + 1] = value
  end
  for _, value in ipairs(remainder) do
    out[#out + 1] = value
  end
  return out
end

---@param priorityTierIndex number|nil
---@return boolean
local function reprioritizePendingSkeletonDescriptors(priorityTierIndex)
  if type(priorityTierIndex) ~= "number" or priorityTierIndex <= 0 then
    return false
  end
  if type(runtime.skeletonDescriptors) ~= "table" or #runtime.skeletonDescriptors <= 1 then
    return false
  end

  local startIndex = math.max(tonumber(runtime.cursor and runtime.cursor.skeletonIndex) or 1, 1)
  if runtime.currentStage == "record_pipeline" then
    local currentRecordIndex = math.max(tonumber(runtime.cursor and runtime.cursor.recordIndex) or 1, 1)
    if currentRecordIndex <= #runtime.skeletonDescriptors then
      startIndex = currentRecordIndex + 1
    else
      startIndex = #runtime.skeletonDescriptors + 1
    end
  end
  if startIndex > #runtime.skeletonDescriptors then
    return false
  end

  local tail = {}
  for index = startIndex, #runtime.skeletonDescriptors do
    tail[#tail + 1] = runtime.skeletonDescriptors[index]
  end

  local reorderedTail = buildTierPrioritizedList(tail, priorityTierIndex, function(descriptor)
    return descriptor and descriptor.tierIndex or nil
  end)

  if reorderedTail == tail then
    return false
  end

  for index = startIndex, #runtime.skeletonDescriptors do
    runtime.skeletonDescriptors[index] = nil
  end
  for offset, descriptor in ipairs(reorderedTail) do
    runtime.skeletonDescriptors[startIndex + offset - 1] = descriptor
  end
  return true
end

---@param priorityTierIndex number|nil
---@return boolean
local function reprioritizePendingRecordOrder(priorityTierIndex)
  if type(priorityTierIndex) ~= "number" or priorityTierIndex <= 0 then
    return false
  end
  local ordered = getOrderedJournalInstanceIDs()
  if type(ordered) ~= "table" or #ordered <= 1 then
    return false
  end

  local currentStage = runtime.currentStage
  local startIndex = 1
  if currentStage == "record_pipeline" then
    local currentRecordIndex = math.max(tonumber(runtime.cursor and runtime.cursor.recordIndex) or 1, 1)
    if currentRecordIndex <= #ordered then
      startIndex = currentRecordIndex + 1
    else
      startIndex = #ordered + 1
    end
  elseif currentStage == "difficulty" or currentStage == "mount_summary" then
    local currentRecordIndex = math.max(tonumber(runtime.cursor and runtime.cursor.recordIndex) or 1, 1)
    if currentRecordIndex <= #ordered then
      startIndex = currentRecordIndex + 1
    else
      startIndex = #ordered + 1
    end
  end

  if startIndex > #ordered then
    return false
  end

  local tail = {}
  for index = startIndex, #ordered do
    tail[#tail + 1] = ordered[index]
  end

  local reorderedTail = buildTierPrioritizedList(tail, priorityTierIndex, function(journalInstanceID)
    local record = cache and cache.records and cache.records[journalInstanceID] or nil
    return record and record.base and record.base.tierIndex or nil
  end)

  if reorderedTail == tail then
    return false
  end

  for index = startIndex, #ordered do
    ordered[index] = nil
  end
  for offset, journalInstanceID in ipairs(reorderedTail) do
    ordered[startIndex + offset - 1] = journalInstanceID
  end
  return true
end

---@param priorityTierIndex number|nil
---@return boolean
local function setPriorityTierIndex(priorityTierIndex)
  if type(priorityTierIndex) ~= "number" or priorityTierIndex <= 0 then
    return false
  end
  runtime.priorityTierIndex = priorityTierIndex
  local changed = false
  if reprioritizePendingSkeletonDescriptors(priorityTierIndex) then
    changed = true
  end
  if reprioritizePendingRecordOrder(priorityTierIndex) then
    changed = true
  end
  return changed
end

local function resetRuntimeForBuild(isManual)
  runtime.state = "building"
  runtime.currentStage = nil
  runtime.totalUnits = 0
  runtime.completedUnits = 0
  runtime.stageTotalUnits = 0
  runtime.stageCompletedUnits = 0
  runtime.currentLabel = nil
  runtime.failureMessage = nil
  runtime.isManualRebuild = isManual == true
  runtime.token = (runtime.token or 0) + 1
  runtime.recordOrder = {}
  runtime.cursor = {
    skeletonIndex = 1,
    recordIndex = 1,
    difficultyIndex = 1,
    mountIndex = 1,
    recordPhase = "difficulty",
  }
  runtime.skeletonDescriptors = {}
  runtime.difficultyUnitTotal = 0
  runtime.mountUnitTotal = 0
  runtime.startedAtSec = getNowSeconds()
  runtime.pausedByEncounterJournalThisBuild = false
  runtime.pendingEncounterJournalReadyNotice = false
  runtime.pendingSkeletonEnumeration = false
  runtime.mountSummaryRetryCounts = {}
  runtime.priorityTierIndex = getCurrentTierIndex()
  runtime.summariesNormalizedAt = 0
end

local function resetRuntimeToIdle()
  runtime.state = "idle"
  runtime.currentStage = nil
  runtime.totalUnits = 0
  runtime.completedUnits = 0
  runtime.stageTotalUnits = 0
  runtime.stageCompletedUnits = 0
  runtime.currentLabel = nil
  runtime.failureMessage = nil
  runtime.isManualRebuild = false
  runtime.recordOrder = {}
  runtime.cursor = {}
  runtime.skeletonDescriptors = {}
  runtime.difficultyUnitTotal = 0
  runtime.mountUnitTotal = 0
  runtime.startedAtSec = 0
  runtime.pendingEncounterJournalReadyNotice = false
  runtime.pendingSkeletonEnumeration = false
  runtime.mountSummaryRetryCounts = {}
  runtime.priorityTierIndex = nil
  runtime.summariesNormalizedAt = 0
end

local function clearDriver()
  if runtime.driverFrame then
    runtime.driverFrame:Hide()
  end
end

local function ensureDriverFrame()
  if runtime.driverFrame then
    return
  end

  local driver = CreateFrame("Frame")
  driver:Hide()
  runtime.driverFrame = driver
end

getCurrentTierIndex = function()
  local CJ = C_EncounterJournal
  local names = {
    "GetCurrentTier",
    "GetSelectedTier",
    "GetTier",
    "GetCurrentTierIndex",
    "GetSelectedTierIndex",
  }

  if CJ then
    for _, name in ipairs(names) do
      local fn = CJ[name]
      if type(fn) == "function" then
        local ok, value = pcall(function()
          return fn(CJ)
        end)
        if ok and type(value) == "number" and value > 0 then
          return value
        end
        ok, value = pcall(fn)
        if ok and type(value) == "number" and value > 0 then
          return value
        end
      end
    end
  end

  if EJ_GetCurrentTier then
    local ok, value = pcall(EJ_GetCurrentTier)
    if ok and type(value) == "number" and value > 0 then
      return value
    end
  end

  return nil
end

local function getCurrentJournalInstanceID()
  local _, jid = Toolbox.EJ.GetInstanceInfoFlat()
  if type(jid) == "number" and jid > 0 then
    return jid
  end

  local CJ = C_EncounterJournal
  local names = {
    "GetSelectedInstance",
    "GetCurrentInstance",
    "GetSelectedInstanceID",
    "GetCurrentInstanceID",
  }

  if CJ then
    for _, name in ipairs(names) do
      local fn = CJ[name]
      if type(fn) == "function" then
        local ok, value = pcall(function()
          return fn(CJ)
        end)
        if ok then
          if type(value) == "number" and value > 0 then
            return value
          end
          if type(value) == "table" then
            local resolved = value.journalInstanceID or value.id or value.instanceID
            if type(resolved) == "number" and resolved > 0 then
              return resolved
            end
          end
        end

        ok, value = pcall(fn)
        if ok then
          if type(value) == "number" and value > 0 then
            return value
          end
          if type(value) == "table" then
            local resolved = value.journalInstanceID or value.id or value.instanceID
            if type(resolved) == "number" and resolved > 0 then
              return resolved
            end
          end
        end
      end
    end
  end

  return nil
end

local function getCurrentEncounterIndex()
  local ej = _G.EncounterJournal
  if type(ej) == "table" and type(ej.encounter) == "table" then
    local info = ej.encounter.info
    if type(info) == "table" then
      local index = info.index or info.encounterIndex or info.journalEncounterID
      if type(index) == "number" and index > 0 then
        return index
      end
    end
  end
  return nil
end

local EJStateDriver = {}

--- 确保冒险手册脚本已加载，但绝不主动触发 `OnOpen` 一类 UI 生命周期。
--- 目录层后台扫描只允许使用 EJ 数据 API，避免在登录期碰受保护的暴雪界面逻辑。
function EJStateDriver.Initialize()
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
  elseif LoadAddOn then
    pcall(LoadAddOn, "Blizzard_EncounterJournal")
  end
end

--- 捕获当前 EJ 共享选中状态；若客户端不提供某一项则返回 nil。
---@return table
function EJStateDriver.Capture()
  local lootFilterClassID, lootFilterSpecID = Toolbox.EJ.GetLootFilter()
  return {
    tierIndex = getCurrentTierIndex(),
    selectedTabID = Toolbox.EJ.GetEncounterJournalSelectedTabId(),
    journalInstanceID = getCurrentJournalInstanceID(),
    difficultyID = Toolbox.EJ.GetDifficulty(),
    encounterIndex = getCurrentEncounterIndex(),
    lootFilterClassID = lootFilterClassID,
    lootFilterSpecID = lootFilterSpecID,
    slotFilterID = Toolbox.EJ.GetSlotFilter(),
  }
end

--- 恢复先前保存的 EJ 共享选中状态。
---@param snapshot table|nil
function EJStateDriver.Restore(snapshot)
  if type(snapshot) ~= "table" then
    return
  end
  if type(snapshot.selectedTabID) == "number" then
    local raidId, dungeonId = Toolbox.EJ.GetEncounterJournalInstanceListButtonIds()
    if snapshot.selectedTabID == raidId then
      Toolbox.EJ.SelectEncounterJournalInstanceListTab(true)
    elseif snapshot.selectedTabID == dungeonId then
      Toolbox.EJ.SelectEncounterJournalInstanceListTab(false)
    end
  end
  if type(snapshot.tierIndex) == "number" and snapshot.tierIndex > 0 then
    Toolbox.EJ.SelectTier(snapshot.tierIndex)
  end
  if type(snapshot.journalInstanceID) == "number" and snapshot.journalInstanceID > 0 then
    Toolbox.EJ.SelectInstance(snapshot.journalInstanceID)
  end
  if type(snapshot.difficultyID) == "number" and snapshot.difficultyID > 0 then
    Toolbox.EJ.SetDifficulty(snapshot.difficultyID)
  end
  if type(snapshot.encounterIndex) == "number" and snapshot.encounterIndex > 0 then
    Toolbox.EJ.SelectEncounter(snapshot.encounterIndex)
  end
  if type(snapshot.lootFilterClassID) == "number" and type(snapshot.lootFilterSpecID) == "number" then
    Toolbox.EJ.SetLootFilter(snapshot.lootFilterClassID, snapshot.lootFilterSpecID)
  else
    Toolbox.EJ.ResetLootFilter()
  end
  if type(snapshot.slotFilterID) == "number" then
    Toolbox.EJ.SetSlotFilter(snapshot.slotFilterID)
  else
    Toolbox.EJ.ResetSlotFilter()
  end
end

--- 在捕获/恢复 EJ 共享状态的保护下执行一个最小工作单元。
---@param workFn fun(): ...
---@return boolean ok
---@return any ...
function EJStateDriver.WithSnapshot(workFn)
  local snapshot = EJStateDriver.Capture()
  local ok, a, b, c, d, e = pcall(workFn)
  pcall(EJStateDriver.Restore, snapshot)
  if not ok then
    return false, a
  end
  return true, a, b, c, d, e
end

--- 将会影响战利品读取的过滤器归一到“不过滤”状态。
--- 说明：玩家上次浏览 EJ 时留下的专精/槽位过滤器会污染 `GetNumLoot()` / `GetLootInfoByIndex()`，目录扫描前必须清空。
local function normalizeLootFiltersForDirectoryScan()
  Toolbox.EJ.ResetLootFilter()
  Toolbox.EJ.ResetSlotFilter()
end

local function parseInstanceDescriptorFromResult(tierIndex, requestedRaidFlag, a, b, c, d, e, f, g, h, i, j, k, l, m, n)
  if a == nil then
    return nil
  end

  if type(a) == "table" then
    local t = a
    local jid = t.journalInstanceID or t.journalInstanceId or t.id
    local worldInstanceID = t.worldInstanceID
    if worldInstanceID == nil and t.journalInstanceID ~= nil and t.instanceID ~= t.journalInstanceID then
      worldInstanceID = t.instanceID or t.instanceId
    end
    local isRaid = requestedRaidFlag == true
    if type(t.isRaid) == "boolean" then
      isRaid = t.isRaid
    elseif type(t.instanceType) == "number" then
      if t.instanceType == 1 then
        isRaid = true
      elseif t.instanceType == 2 then
        isRaid = false
      end
    end
    if type(jid) ~= "number" or jid <= 0 then
      return nil
    end
    return {
      journalInstanceID = jid,
      name = t.name or t.instanceName or "",
      kind = isRaid and "raid" or "dungeon",
      tierIndex = tierIndex,
      mapID = t.mapID or t.uiMapID or t.dungeonAreaMapID or t.mapId,
      worldInstanceID = type(worldInstanceID) == "number" and worldInstanceID or nil,
    }
  end

  local jid = type(a) == "number" and a or nil
  if not jid or jid <= 0 then
    return nil
  end

  local isRaid = requestedRaidFlag == true
  if type(n) == "boolean" then
    isRaid = n
  elseif type(m) == "boolean" then
    isRaid = m
  elseif type(l) == "number" then
    if l == 1 then
      isRaid = true
    elseif l == 2 then
      isRaid = false
    end
  end

  local mapID
  for _, value in ipairs({ k, h, g }) do
    if type(value) == "number" and value > 0 and value ~= jid then
      mapID = value
      break
    end
  end

  local worldInstanceID
  for _, value in ipairs({ n, m, l }) do
    if type(value) == "number" and value > 0 and value ~= jid and value ~= mapID then
      worldInstanceID = value
      break
    end
  end

  return {
    journalInstanceID = jid,
    name = type(b) == "string" and b or "",
    kind = isRaid and "raid" or "dungeon",
    tierIndex = tierIndex,
    mapID = mapID,
    worldInstanceID = worldInstanceID,
  }
end

local function enumerateSkeletonDescriptors()
  EJStateDriver.Initialize()

  local descriptors = {}
  local tierNames = {}
  local seen = {}
  local numTiers = Toolbox.EJ.GetNumTiers()
  if type(numTiers) ~= "number" or numTiers < 1 then
    return descriptors, tierNames
  end

  for tierIndex = 1, numTiers do
    Toolbox.EJ.SelectTier(tierIndex)
    tierNames[tierIndex] = Toolbox.EJ.GetTierInfo(tierIndex) or tostring(tierIndex)

    for _, requestedRaidFlag in ipairs({ false, true }) do
      local instanceIndex = 1
      while true do
        local a, b, c, d, e, f, g, h, i, j, k, l, m, n = Toolbox.EJ.GetInstanceByIndex(instanceIndex, requestedRaidFlag)
        local descriptor = parseInstanceDescriptorFromResult(tierIndex, requestedRaidFlag, a, b, c, d, e, f, g, h, i, j, k, l, m, n)
        if not descriptor then
          break
        end
        if not seen[descriptor.journalInstanceID] then
          seen[descriptor.journalInstanceID] = true
          descriptors[#descriptors + 1] = descriptor
        end
        instanceIndex = instanceIndex + 1
      end
    end
  end

  return descriptors, tierNames
end

--- 准备本次构建的副本骨架与阶段总量。
--- 说明：若当前因冒险手册浏览而暂停，则允许延后到恢复后的首个 driver tick 再执行，
--- 避免 `SelectTier` / `SelectInstance` 在玩家浏览列表时与共享 EJ 选中状态打架。
---@return boolean ok
---@return string|nil err
local function createRecordFromDescriptor(descriptor)
  local jid = descriptor.journalInstanceID
  return {
    base = {
      journalInstanceID = jid,
      name = descriptor.name,
      kind = descriptor.kind,
      tierIndex = descriptor.tierIndex,
      mapID = descriptor.mapID,
      worldInstanceID = descriptor.worldInstanceID,
    },
    difficultyOrder = {},
    difficulties = {},
    summary = {
      hasAnyMountLoot = nil,
      mountDifficultyIDs = {},
    },
  }
end

local function prepareBuildSkeleton()
  local ok, descriptors, tierNames = EJStateDriver.WithSnapshot(enumerateSkeletonDescriptors)
  if not ok then
    return false, tostring(descriptors)
  end

  runtime.skeletonDescriptors = descriptors or {}
  reprioritizePendingSkeletonDescriptors(runtime.priorityTierIndex)
  cache.tierNames = type(tierNames) == "table" and tierNames or {}
  cache.records = {}
  runtime.recordOrder = {}

  runtime.difficultyUnitTotal = 0
  runtime.mountUnitTotal = 0
  for _, descriptor in ipairs(runtime.skeletonDescriptors) do
    local jid = descriptor and descriptor.journalInstanceID
    if type(jid) == "number" and jid > 0 then
      cache.records[jid] = createRecordFromDescriptor(descriptor)
      runtime.recordOrder[#runtime.recordOrder + 1] = jid
    end
    if descriptor.kind == "raid" then
      runtime.difficultyUnitTotal = runtime.difficultyUnitTotal + #RAID_DIFFICULTY_CANDIDATES
    else
      runtime.difficultyUnitTotal = runtime.difficultyUnitTotal + #DUNGEON_DIFFICULTY_CANDIDATES
    end
  end

  runtime.currentStage = "record_pipeline"
  runtime.stageCompletedUnits = 0
  runtime.stageTotalUnits = runtime.difficultyUnitTotal
  runtime.totalUnits = runtime.difficultyUnitTotal
  runtime.currentLabel = nil
  runtime.cursor.recordIndex = 1
  runtime.cursor.difficultyIndex = 1
  runtime.cursor.mountIndex = 1
  runtime.cursor.recordPhase = "difficulty"
  runtime.pendingSkeletonEnumeration = false

  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.DRD_DEBUG_BUILD_START_FMT or "%s",
    getBuildModeLabel(runtime.isManualRebuild == true),
    #runtime.skeletonDescriptors,
    tonumber(runtime.difficultyUnitTotal) or 0
  ))
  debugPrint(string.format(
    L.DRD_DEBUG_STAGE_FMT or "%s",
    getStageLabelForDebug(runtime.currentStage),
    tonumber(runtime.stageTotalUnits) or 0
  ))
  return true
end

local function createRecordFromDescriptor(descriptor)
  local jid = descriptor.journalInstanceID
  return {
    base = {
      journalInstanceID = jid,
      name = descriptor.name,
      kind = descriptor.kind,
      tierIndex = descriptor.tierIndex,
      mapID = descriptor.mapID,
      worldInstanceID = descriptor.worldInstanceID,
    },
    difficultyOrder = {},
    difficulties = {},
    summary = {
      hasAnyMountLoot = nil,
      mountDifficultyIDs = {},
    },
  }
end

local function rebuildMountSummary(record)
  local positives = {}
  local hasUnknown = false

  for _, difficultyID in ipairs(record.difficultyOrder or {}) do
    local difficultyRecord = record.difficulties and record.difficulties[difficultyID]
    local value = difficultyRecord and difficultyRecord.hasMountLoot
    if value == true then
      positives[#positives + 1] = difficultyID
    elseif value == nil then
      hasUnknown = true
    end
  end

  record.summary = record.summary or {}
  record.summary.mountDifficultyIDs = positives
  if #positives > 0 then
    record.summary.hasAnyMountLoot = true
  elseif hasUnknown then
    record.summary.hasAnyMountLoot = nil
  else
    record.summary.hasAnyMountLoot = false
  end
  applyMountSummarySupplement(record)
end

---@param allowEmptyDifficultyOrder boolean
local function normalizeAllRecordMountSummaries(allowEmptyDifficultyOrder)
  if type(cache) ~= "table" or type(cache.records) ~= "table" then
    return
  end

  for _, record in pairs(cache.records) do
    if type(record) == "table" then
      local difficultyCount = #(record.difficultyOrder or {})
      if difficultyCount > 0 or allowEmptyDifficultyOrder == true then
        rebuildMountSummary(record)
      else
        applyMountSummarySupplement(record)
      end
    end
  end
end

local function ensureCompletedCacheMountSummariesNormalized()
  if runtime.state == "building" or runtime.state == "failed" then
    return
  end
  if type(cache) ~= "table" or tonumber(cache.lastBuildAt) <= 0 then
    return
  end

  local token = tonumber(cache.lastBuildAt) or 0
  if runtime.summariesNormalizedAt == token then
    return
  end

  normalizeAllRecordMountSummaries(true)
  runtime.summariesNormalizedAt = token
end

local function updateProgressLabel(record, difficultyID)
  local base = record and record.base or nil
  local tierIndex = base and base.tierIndex or nil
  local recordName = base and base.name or nil
  if type(difficultyID) == "number" then
    runtime.currentLabel = formatProgressRecordLabel(tierIndex, recordName, getDifficultyName(difficultyID))
  elseif base then
    runtime.currentLabel = formatProgressRecordLabel(tierIndex, recordName, nil)
  else
    runtime.currentLabel = nil
  end
end

local function scanLootRow(info)
  if type(info) ~= "table" then
    return false
  end
  local itemID = info.itemID or info.id
  if type(itemID) ~= "number" or itemID <= 0 then
    return false
  end
  local mountID = Toolbox.MountJournal.GetMountFromItem(itemID)
  return type(mountID) == "number" and mountID > 0
end

---@param info table|nil
---@return boolean
local function hasLootRowData(info)
  return type(info) == "table" and next(info) ~= nil
end

---@param record table|nil
---@param difficultyID number|nil
---@param encounterIndex number
---@param encounterName string
---@param lootIndex number
---@param source string
---@param info table|nil
local function debugPrintTargetLoot(record, difficultyID, encounterIndex, encounterName, lootIndex, source, info)
  if not isTargetDebugRecord(record) or type(info) ~= "table" then
    return
  end

  local itemID = info.itemID or info.id
  local mountID = type(itemID) == "number" and itemID > 0 and Toolbox.MountJournal.GetMountFromItem(itemID) or nil
  debugPrintTarget(
    "DRD_DEBUG_TARGET_SCAN_LOOT",
    formatTargetDebugRecordName(record),
    formatDifficultyLabelForDebug(difficultyID),
    tostring(encounterIndex),
    tostring(encounterName or "?"),
    tostring(lootIndex),
    tostring(itemID or 0),
    tostring(getItemNameForDebug(itemID, info.name)),
    tostring(mountID or ""),
    tostring(source or "")
  )
end

---@param record table|nil
---@param difficultyID number|nil
---@return boolean|table
local function scanCurrentSelectionForMount(record, difficultyID)
  local sawAnyLootData = false
  if isTargetDebugRecord(record) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_SCAN_BEGIN",
      formatTargetDebugRecordName(record),
      formatDifficultyLabelForDebug(difficultyID)
    )
  end

  local listLootCount = Toolbox.EJ.GetNumLoot()
  if isTargetDebugRecord(record) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_SCAN_LIST",
      formatTargetDebugRecordName(record),
      formatDifficultyLabelForDebug(difficultyID),
      tostring(type(listLootCount) == "number" and listLootCount or -1)
    )
  end
  if type(listLootCount) == "number" and listLootCount > 0 then
    sawAnyLootData = true
    for lootIndex = 1, listLootCount do
      local info = Toolbox.EJ.GetLootInfoByIndex(lootIndex)
      if hasLootRowData(info) then
        sawAnyLootData = true
        debugPrintTargetLoot(record, difficultyID, 0, "列表级", lootIndex, "GetLootInfoByIndex(l)", info)
      end
      if scanLootRow(info) then
        return true
      end
    end
  else
    for lootIndex = 1, 50 do
      local info = Toolbox.EJ.GetLootInfoByIndex(lootIndex)
      if info == nil then
        break
      end
      sawAnyLootData = true
      if scanLootRow(info) then
        return true
      end
    end
  end

  local numEncounters = Toolbox.EJ.GetNumEncounters()
  if type(numEncounters) ~= "number" or numEncounters < 1 then
    numEncounters = 16
  else
    numEncounters = math.min(numEncounters, 40)
  end

  for encounterIndex = 1, numEncounters do
    Toolbox.EJ.SelectEncounter(encounterIndex)
    local encounterName = Toolbox.EJ.GetEncounterName(encounterIndex)
    if type(encounterName) ~= "string" or encounterName == "" then
      encounterName = "?"
    end
    local numLoot = Toolbox.EJ.GetNumLoot()
    if isTargetDebugRecord(record) then
      debugPrintTarget(
        "DRD_DEBUG_TARGET_SCAN_ENCOUNTER",
        formatTargetDebugRecordName(record),
        formatDifficultyLabelForDebug(difficultyID),
        tostring(encounterIndex),
        tostring(encounterName),
        tostring(type(numLoot) == "number" and numLoot or -1)
      )
    end
    if type(numLoot) ~= "number" or numLoot < 1 then
      numLoot = 40
    else
      sawAnyLootData = true
    end
    for lootIndex = 1, numLoot do
      local info = Toolbox.EJ.GetLootInfoByIndex(lootIndex, encounterIndex)
      local fallbackInfo = Toolbox.EJ.GetLootInfoByIndex(lootIndex)
      if info == nil and numLoot == 40 then
        break
      end
      if hasLootRowData(info) then
        sawAnyLootData = true
        debugPrintTargetLoot(record, difficultyID, encounterIndex, encounterName, lootIndex, "GetLootInfoByIndex(l,e)", info)
      end
      if hasLootRowData(fallbackInfo) then
        sawAnyLootData = true
        debugPrintTargetLoot(record, difficultyID, encounterIndex, encounterName, lootIndex, "GetLootInfoByIndex(l)", fallbackInfo)
      end
      if scanLootRow(info) or scanLootRow(fallbackInfo) then
        return true
      end
    end
  end

  if not sawAnyLootData then
    return MOUNT_SCAN_NOT_READY
  end

  return false
end

local function beginDifficultyStage()
  runtime.currentStage = "difficulty"
  runtime.stageCompletedUnits = 0
  runtime.stageTotalUnits = runtime.difficultyUnitTotal
  runtime.currentLabel = nil
  runtime.cursor.recordIndex = 1
  runtime.cursor.difficultyIndex = 1
  runtime.totalUnits = math.max(runtime.totalUnits, runtime.completedUnits + runtime.stageTotalUnits)
  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.DRD_DEBUG_STAGE_FMT or "%s",
    getStageLabelForDebug(runtime.currentStage),
    tonumber(runtime.stageTotalUnits) or 0
  ))
end

local function beginMountStage()
  runtime.mountUnitTotal = 0
  for _, jid in ipairs(getOrderedJournalInstanceIDs()) do
    local record = cache.records[jid]
    runtime.mountUnitTotal = runtime.mountUnitTotal + #(record and record.difficultyOrder or {})
  end

  runtime.currentStage = "mount_summary"
  runtime.stageCompletedUnits = 0
  runtime.stageTotalUnits = runtime.mountUnitTotal
  runtime.currentLabel = nil
  runtime.cursor.recordIndex = 1
  runtime.cursor.difficultyIndex = 1
  runtime.totalUnits = runtime.completedUnits + runtime.stageTotalUnits
  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.DRD_DEBUG_STAGE_FMT or "%s",
    getStageLabelForDebug(runtime.currentStage),
    tonumber(runtime.stageTotalUnits) or 0
  ))
end

local function finishBuild()
  cache.interfaceBuild = getCurrentInterfaceBuild()
  cache.lastBuildAt = time()
  normalizeAllRecordMountSummaries(true)
  saveCacheToDb()
  runtime.summariesNormalizedAt = tonumber(cache.lastBuildAt) or 0

  runtime.state = "completed"
  runtime.currentStage = nil
  runtime.failureMessage = nil
  runtime.currentLabel = nil
  runtime.stageCompletedUnits = runtime.stageTotalUnits
  runtime.completedUnits = runtime.totalUnits
  runtime.pendingSkeletonEnumeration = false

  clearDriver()
  local elapsed = math.max(0, (getNowSeconds() or 0) - (runtime.startedAtSec or 0))
  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.DRD_DEBUG_BUILD_DONE_FMT or "%s",
    #getOrderedJournalInstanceIDs(),
    countSupportedDifficultyTotal(),
    countMountPositiveRecordTotal(),
    elapsed
  ))
  debugPrintMissingTargetRecords()
  if runtime.pausedByEncounterJournalThisBuild then
    runtime.pendingEncounterJournalReadyNotice = true
  end
  runtime.pausedByEncounterJournalThisBuild = false
  Directory.RefreshLockouts()
end

local function failBuild(err)
  runtime.state = "failed"
  runtime.failureMessage = tostring(err or "unknown")
  runtime.currentLabel = nil
  runtime.pendingSkeletonEnumeration = false
  clearDriver()
  local L = Toolbox.L or {}
  debugPrint(string.format(L.DRD_BUILD_FAILED_FMT or "%s", runtime.failureMessage))
end

local function processSkeletonUnit()
  local descriptor = runtime.skeletonDescriptors[runtime.cursor.skeletonIndex]
  if not descriptor then
    return true
  end

  local jid = descriptor.journalInstanceID
  cache.records[jid] = createRecordFromDescriptor(descriptor)
  cache.tierNames[descriptor.tierIndex] = cache.tierNames[descriptor.tierIndex] or (Toolbox.EJ.GetTierInfo(descriptor.tierIndex) or tostring(descriptor.tierIndex))
  runtime.recordOrder[#runtime.recordOrder + 1] = jid
  if isTargetDebugName(descriptor.name) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_SKELETON",
      tostring(descriptor.name or "?"),
      tostring(jid),
      tostring(descriptor.kind or ""),
      tostring(cache.tierNames[descriptor.tierIndex] or descriptor.tierIndex or ""),
      tostring(descriptor.mapID or ""),
      tostring(descriptor.worldInstanceID or "")
    )
  end
  runtime.currentLabel = formatProgressRecordLabel(descriptor.tierIndex, descriptor.name, nil)
  runtime.cursor.skeletonIndex = runtime.cursor.skeletonIndex + 1
  runtime.completedUnits = runtime.completedUnits + 1
  runtime.stageCompletedUnits = runtime.stageCompletedUnits + 1
  return false
end

local function probeDifficultySupport(record, difficultyID)
  local validBefore = nil
  local setResult = nil
  local currentDifficulty = nil
  local ok, supported = EJStateDriver.WithSnapshot(function()
    local wantRaidTab = record
      and record.base
      and record.base.kind == "raid"
    if type(wantRaidTab) == "boolean" then
      Toolbox.EJ.SelectEncounterJournalInstanceListTab(wantRaidTab)
    end
    Toolbox.EJ.SelectTier(record.base.tierIndex)
    Toolbox.EJ.SelectInstance(record.base.journalInstanceID)

    validBefore = Toolbox.EJ.IsValidInstanceDifficulty(difficultyID)
    if validBefore == true then
      currentDifficulty = Toolbox.EJ.GetDifficulty()
      return true
    end

    setResult = Toolbox.EJ.SetDifficulty(difficultyID)
    currentDifficulty = Toolbox.EJ.GetDifficulty()
    if not setResult then
      return false
    end

    return currentDifficulty == difficultyID
  end)

  if not ok then
    return nil, supported
  end
  if isTargetDebugRecord(record) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_DIFFICULTY",
      formatTargetDebugRecordName(record),
      formatDifficultyLabelForDebug(difficultyID),
      tostring(validBefore == true),
      tostring(setResult == true),
      tostring(currentDifficulty and formatDifficultyLabelForDebug(currentDifficulty) or "?"),
      tostring(supported == true)
    )
  end
  return supported == true
end

local function processDifficultyUnit()
  local ordered = getOrderedJournalInstanceIDs()
  local jid = ordered[runtime.cursor.recordIndex]
  if not jid then
    return true
  end

  local record = cache.records[jid]
  local candidates = getStageCandidates(record)
  local difficultyID = candidates[runtime.cursor.difficultyIndex]
  if not difficultyID then
    runtime.cursor.recordIndex = runtime.cursor.recordIndex + 1
    runtime.cursor.difficultyIndex = 1
    return false
  end

  updateProgressLabel(record, difficultyID)
  local supported, err = probeDifficultySupport(record, difficultyID)
  if supported == nil then
    return nil, err
  end

  if supported and not record.difficulties[difficultyID] then
    record.difficulties[difficultyID] = {
      hasMountLoot = nil,
    }
    record.difficultyOrder[#record.difficultyOrder + 1] = difficultyID
    cache.difficultyMeta[difficultyID] = cache.difficultyMeta[difficultyID] or {
      name = getDifficultyName(difficultyID),
    }
  end

  runtime.cursor.difficultyIndex = runtime.cursor.difficultyIndex + 1
  runtime.completedUnits = runtime.completedUnits + 1
  runtime.stageCompletedUnits = runtime.stageCompletedUnits + 1
  return false
end

local function scanMountSummary(record, difficultyID)
  local ok, hasMount = EJStateDriver.WithSnapshot(function()
    local wantRaidTab = record
      and record.base
      and record.base.kind == "raid"
    if type(wantRaidTab) == "boolean" then
      Toolbox.EJ.SelectEncounterJournalInstanceListTab(wantRaidTab)
    end
    Toolbox.EJ.SelectTier(record.base.tierIndex)
    Toolbox.EJ.SelectInstance(record.base.journalInstanceID)
    local setResult = Toolbox.EJ.SetDifficulty(difficultyID)
    local currentDifficulty = Toolbox.EJ.GetDifficulty()
    if isTargetDebugRecord(record) then
      debugPrintTarget(
        "DRD_DEBUG_TARGET_SCAN_CONTEXT",
        formatTargetDebugRecordName(record),
        formatDifficultyLabelForDebug(difficultyID),
        tostring(setResult == true),
        tostring(currentDifficulty and formatDifficultyLabelForDebug(currentDifficulty) or "?")
      )
    end
    normalizeLootFiltersForDirectoryScan()
    return scanCurrentSelectionForMount(record, difficultyID)
  end)

  if not ok then
    return nil, hasMount
  end
  if hasMount == MOUNT_SCAN_NOT_READY then
    return MOUNT_SCAN_NOT_READY
  end
  return hasMount == true
end

---@param record table
---@param difficultyID number
---@return string
local function getMountSummaryRetryKey(record, difficultyID)
  return string.format("%s:%s", tostring(record.base and record.base.journalInstanceID or "?"), tostring(difficultyID))
end

---@param record table
---@param difficultyID number
---@return number
local function incrementMountSummaryRetryCount(record, difficultyID)
  local key = getMountSummaryRetryKey(record, difficultyID)
  local count = (runtime.mountSummaryRetryCounts[key] or 0) + 1
  runtime.mountSummaryRetryCounts[key] = count
  return count
end

---@param record table
---@param difficultyID number
local function clearMountSummaryRetryCount(record, difficultyID)
  local key = getMountSummaryRetryKey(record, difficultyID)
  runtime.mountSummaryRetryCounts[key] = nil
end

-- 当前副本处理完成后，切到下一个副本，并把副本内游标复位。
local function moveToNextPipelineRecord()
  runtime.cursor.recordIndex = (tonumber(runtime.cursor and runtime.cursor.recordIndex) or 1) + 1
  runtime.cursor.difficultyIndex = 1
  runtime.cursor.mountIndex = 1
  runtime.cursor.recordPhase = "difficulty"
end

---@param record table|nil
---@param includeCurrent boolean
-- 单副本流水线里若已能确定“该副本有坐骑”，则把剩余坐骑扫描单元一次性记为已完成。
local function skipRemainingPipelineMountUnitsForRecord(record, includeCurrent)
  local total = #(record and record.difficultyOrder or {})
  local currentIndex = math.max(tonumber(runtime.cursor and runtime.cursor.mountIndex) or 1, 1)
  local remaining = total - currentIndex
  if includeCurrent then
    remaining = remaining + 1
  end
  if remaining < 0 then
    remaining = 0
  end
  if remaining > 0 then
    runtime.completedUnits = runtime.completedUnits + remaining
    runtime.stageCompletedUnits = runtime.stageCompletedUnits + remaining
  end
  moveToNextPipelineRecord()
end

-- 逐副本流水线：对同一副本先探测支持难度，再立刻扫描该副本的坐骑摘要，避免跨资料片/跨副本来回跳。
local function processRecordPipelineUnit()
  local ordered = getOrderedJournalInstanceIDs()
  local jid = ordered[runtime.cursor.recordIndex]
  if not jid then
    return true
  end

  local record = cache.records and cache.records[jid] or nil
  if not record then
    moveToNextPipelineRecord()
    return false
  end

  local recordPhase = runtime.cursor and runtime.cursor.recordPhase or "difficulty"
  if recordPhase == "difficulty" then
    local candidates = getStageCandidates(record)
    local difficultyID = candidates[runtime.cursor.difficultyIndex]
    if not difficultyID then
      rebuildMountSummary(record)
      runtime.cursor.recordPhase = "mount_summary"
      runtime.cursor.mountIndex = 1
      if record.summary and record.summary.hasAnyMountLoot == true then
        skipRemainingPipelineMountUnitsForRecord(record, true)
        return false
      end
      if #(record.difficultyOrder or {}) == 0 then
        moveToNextPipelineRecord()
        return false
      end
      return false
    end

    updateProgressLabel(record, difficultyID)
    local supported, err = probeDifficultySupport(record, difficultyID)
    if supported == nil then
      return nil, err
    end

    if supported and not record.difficulties[difficultyID] then
      record.difficulties[difficultyID] = {
        hasMountLoot = nil,
      }
      record.difficultyOrder[#record.difficultyOrder + 1] = difficultyID
      cache.difficultyMeta[difficultyID] = cache.difficultyMeta[difficultyID] or {
        name = getDifficultyName(difficultyID),
      }
      runtime.mountUnitTotal = runtime.mountUnitTotal + 1
      runtime.totalUnits = runtime.totalUnits + 1
      runtime.stageTotalUnits = runtime.stageTotalUnits + 1
    end

    runtime.cursor.difficultyIndex = runtime.cursor.difficultyIndex + 1
    runtime.completedUnits = runtime.completedUnits + 1
    runtime.stageCompletedUnits = runtime.stageCompletedUnits + 1
    return false
  end

  local difficultyID = record.difficultyOrder and record.difficultyOrder[runtime.cursor.mountIndex]
  if not difficultyID then
    moveToNextPipelineRecord()
    return false
  end

  updateProgressLabel(record, difficultyID)
  local hasMount, err = scanMountSummary(record, difficultyID)
  if hasMount == MOUNT_SCAN_NOT_READY then
    local retryCount = incrementMountSummaryRetryCount(record, difficultyID)
    if isTargetDebugRecord(record) then
      debugPrintTarget(
        "DRD_DEBUG_TARGET_NOT_READY",
        formatTargetDebugRecordName(record),
        formatDifficultyLabelForDebug(difficultyID),
        tostring(retryCount),
        tostring(MOUNT_SUMMARY_RETRY_LIMIT)
      )
    end
    if retryCount < MOUNT_SUMMARY_RETRY_LIMIT then
      return false, nil, true
    end
    hasMount = false
  end
  if hasMount == nil then
    return nil, err
  end

  clearMountSummaryRetryCount(record, difficultyID)
  record.difficulties[difficultyID].hasMountLoot = hasMount
  rebuildMountSummary(record)
  if isTargetDebugRecord(record) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_RESULT",
      formatTargetDebugRecordName(record),
      formatDifficultyLabelForDebug(difficultyID),
      tostring(hasMount == true),
      tostring(record.summary and record.summary.hasAnyMountLoot),
      formatDifficultyListForDebug(record.summary and record.summary.mountDifficultyIDs)
    )
  end

  runtime.completedUnits = runtime.completedUnits + 1
  runtime.stageCompletedUnits = runtime.stageCompletedUnits + 1
  if hasMount == true then
    skipRemainingPipelineMountUnitsForRecord(record, false)
  else
    runtime.cursor.mountIndex = runtime.cursor.mountIndex + 1
  end
  return false
end

---@param record table|nil
---@param includeCurrent boolean
local function skipRemainingMountSummaryUnitsForRecord(record, includeCurrent)
  local total = #(record and record.difficultyOrder or {})
  local currentIndex = math.max(tonumber(runtime.cursor and runtime.cursor.difficultyIndex) or 1, 1)
  local remaining = total - currentIndex
  if includeCurrent then
    remaining = remaining + 1
  end
  if remaining < 0 then
    remaining = 0
  end
  if remaining > 0 then
    runtime.completedUnits = runtime.completedUnits + remaining
    runtime.stageCompletedUnits = runtime.stageCompletedUnits + remaining
  end
  runtime.cursor.recordIndex = (tonumber(runtime.cursor and runtime.cursor.recordIndex) or 1) + 1
  runtime.cursor.difficultyIndex = 1
end

local function processMountSummaryUnit()
  local ordered = getOrderedJournalInstanceIDs()
  local jid = ordered[runtime.cursor.recordIndex]
  if not jid then
    return true
  end

  local record = cache.records[jid]
  if record and record.summary and record.summary.hasAnyMountLoot == true then
    -- 已由补源或前序难度命中坐骑时，不再继续扫描该副本剩余难度；
    -- 这些难度在进度上视为“逻辑完成”，避免重复工作拖慢当前资料片可用时间。
    skipRemainingMountSummaryUnitsForRecord(record, true)
    return false
  end

  local difficultyID = record and record.difficultyOrder and record.difficultyOrder[runtime.cursor.difficultyIndex]
  if not difficultyID then
    runtime.cursor.recordIndex = runtime.cursor.recordIndex + 1
    runtime.cursor.difficultyIndex = 1
    return false
  end

  updateProgressLabel(record, difficultyID)
  local hasMount, err = scanMountSummary(record, difficultyID)
  if hasMount == MOUNT_SCAN_NOT_READY then
    local retryCount = incrementMountSummaryRetryCount(record, difficultyID)
    if isTargetDebugRecord(record) then
      debugPrintTarget(
        "DRD_DEBUG_TARGET_NOT_READY",
        formatTargetDebugRecordName(record),
        formatDifficultyLabelForDebug(difficultyID),
        tostring(retryCount),
        tostring(MOUNT_SUMMARY_RETRY_LIMIT)
      )
    end
    if retryCount < MOUNT_SUMMARY_RETRY_LIMIT then
      return false, nil, true
    end
    hasMount = false
  end
  if hasMount == nil then
    return nil, err
  end

  clearMountSummaryRetryCount(record, difficultyID)
  record.difficulties[difficultyID].hasMountLoot = hasMount
  rebuildMountSummary(record)
  if isTargetDebugRecord(record) then
    debugPrintTarget(
      "DRD_DEBUG_TARGET_RESULT",
      formatTargetDebugRecordName(record),
      formatDifficultyLabelForDebug(difficultyID),
      tostring(hasMount == true),
      tostring(record.summary and record.summary.hasAnyMountLoot),
      formatDifficultyListForDebug(record.summary and record.summary.mountDifficultyIDs)
    )
  end

  runtime.completedUnits = runtime.completedUnits + 1
  runtime.stageCompletedUnits = runtime.stageCompletedUnits + 1
  if hasMount == true then
    skipRemainingMountSummaryUnitsForRecord(record, false)
  else
    runtime.cursor.difficultyIndex = runtime.cursor.difficultyIndex + 1
  end
  return false
end

local function advanceOneUnit()
  if runtime.currentStage == "record_pipeline" then
    local stageDone, err, shouldYield = processRecordPipelineUnit()
    if err then
      return false, err, shouldYield
    end
    if stageDone then
      return true
    end
    return false, nil, shouldYield
  end

  return true
end

local function getOrCreateDriverFrame()
  ensureDriverFrame()
  runtime.driverFrame:SetScript("OnUpdate", function()
    if runtime.state ~= "building" then
      return
    end
    if runtime.isEncounterJournalPaused == true then
      return
    end
    if runtime.pendingSkeletonEnumeration == true then
      local ok, err = prepareBuildSkeleton()
      if not ok then
        failBuild(err)
        return
      end
    end

    local startMs = debugprofilestop()
    while runtime.state == "building" do
      local done, err, shouldYield = advanceOneUnit()
      if err then
        failBuild(err)
        break
      end
      if done then
        finishBuild()
        break
      end
      if shouldYield then
        break
      end
      if debugprofilestop() - startMs >= BUILD_BUDGET_MS then
        break
      end
    end
  end)
  return runtime.driverFrame
end

local function buildLockoutLookups()
  local worldToJournal = {}
  local nameToJournals = {}

  for jid, record in pairs(cache.records or {}) do
    local base = record and record.base
    if type(base) == "table" then
      if type(base.worldInstanceID) == "number" and base.worldInstanceID > 0 then
        worldToJournal[base.worldInstanceID] = jid
      end
      local normalized = normalizeName(base.name)
      if normalized then
        nameToJournals[normalized] = nameToJournals[normalized] or {}
        table.insert(nameToJournals[normalized], jid)
      end
    end
  end

  return worldToJournal, nameToJournals
end

local function resolveJournalInstanceID(worldLookup, nameLookup, instanceId, name, difficultyID)
  if type(instanceId) == "number" and instanceId > 0 and worldLookup[instanceId] then
    return worldLookup[instanceId]
  end

  local normalized = normalizeName(name)
  local candidates = normalized and nameLookup[normalized] or nil
  if type(candidates) ~= "table" or #candidates == 0 then
    return nil
  end
  if #candidates == 1 then
    return candidates[1]
  end

  if type(difficultyID) == "number" then
    for _, jid in ipairs(candidates) do
      local record = cache.records and cache.records[jid]
      if record and record.difficulties and record.difficulties[difficultyID] then
        return jid
      end
    end
  end

  return candidates[1]
end

local function ensureEventFrame()
  if runtime.eventFrame then
    return
  end

  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("UPDATE_INSTANCE_INFO")
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
      if isFeatureEnabled() and isCacheInvalid() then
        Directory.StartBuild(false)
      end
      if isFeatureEnabled() and RequestRaidInfo then
        pcall(RequestRaidInfo)
      end
      if isFeatureEnabled() then
        Directory.RefreshLockouts()
      end
    elseif event == "UPDATE_INSTANCE_INFO" then
      if isFeatureEnabled() then
        Directory.RefreshLockouts()
      end
    end
  end)
  runtime.eventFrame = frame
end

--- 当前是否启用目录层调试聊天输出。
---@return boolean
function Directory.IsDebugChatEnabled()
  return isDebugChatEnabled()
end

--- 设置目录层调试聊天输出开关；用于设置页复选框。
---@param enabled boolean|nil true=输出到聊天框；其它值=关闭
function Directory.SetDebugChatEnabled(enabled)
  local db = getSettingsDb()
  db.debug = enabled == true

  local L = Toolbox.L or {}
  if db.debug then
    Toolbox.Chat.PrintAddonMessage(L.DRD_DEBUG_CHAT_ON or "")
    local progress = Directory.GetBuildProgress()
    Toolbox.Chat.PrintAddonMessage(string.format(
      L.DRD_DEBUG_CURRENT_PROGRESS_FMT or "%s",
      tostring(progress.state or ""),
      getStageLabelForDebug(progress.currentStage),
      tonumber(progress.completedUnits) or 0,
      tonumber(progress.totalUnits) or 0,
      tostring(progress.currentLabel or "")
    ))
  else
    Toolbox.Chat.PrintAddonMessage(L.DRD_DEBUG_CHAT_OFF or "")
  end
end

--- 因玩家正在浏览冒险手册副本列表而暂停目录构建推进。
--- 说明：暂停只冻结 driver 的扫描推进，不会清空已完成进度，也不会重置缓存。
function Directory.PauseForEncounterJournal()
  if runtime.isEncounterJournalPaused == true then
    return
  end
  runtime.isEncounterJournalPaused = true
  if runtime.state == "building" then
    runtime.pausedByEncounterJournalThisBuild = true
    local L = Toolbox.L or {}
    debugPrint(L.DRD_EJ_PAUSED or "")
  end
end

--- 结束冒险手册浏览造成的暂停，让目录构建在后台继续推进。
function Directory.ResumeForEncounterJournal()
  runtime.isEncounterJournalPaused = false
end

--- 将后台构建的待处理队列调整为“当前冒险手册资料片优先”。
--- 说明：只重排尚未处理的尾部，不会打断当前正在扫描的副本。
---@return number|nil tierIndex 当前选中的资料片索引；取不到时返回 nil
function Directory.PrioritizeCurrentEncounterJournalTier()
  local tierIndex = getCurrentTierIndex()
  if type(tierIndex) == "number" and tierIndex > 0 then
    setPriorityTierIndex(tierIndex)
    return tierIndex
  end
  return nil
end

--- 当前是否因冒险手册浏览而暂停目录构建推进。
---@return boolean
function Directory.IsPausedForEncounterJournal()
  return runtime.isEncounterJournalPaused == true
end

--- 取走一次性“恢复后已完成”的通知标记；供冒险手册筛选模块决定是否提示聊天框。
---@return boolean
function Directory.ConsumeEncounterJournalReadyNotice()
  local pending = runtime.pendingEncounterJournalReadyNotice == true
  runtime.pendingEncounterJournalReadyNotice = false
  return pending
end

--- 初始化目录层：装载缓存、注册事件，并在登录后按需启动后台预热构建。
function Directory.Initialize()
  if runtime.initialized then
    return
  end

  loadCacheFromDb()
  ensureEventFrame()
  runtime.initialized = true

  if isCacheInvalid() then
    resetRuntimeToIdle()
  else
    runtime.state = "completed"
    runtime.currentStage = nil
    runtime.totalUnits = 1
    runtime.completedUnits = 1
    runtime.stageTotalUnits = 1
    runtime.stageCompletedUnits = 1
    runtime.currentLabel = nil
    if isFeatureEnabled() and IsLoggedIn and IsLoggedIn() then
      if RequestRaidInfo then
        pcall(RequestRaidInfo)
      end
      Directory.RefreshLockouts()
    end
  end
end

--- 启动一次新的目录构建；`isManual=true` 表示来自设置页的手动重建。
--- 若当前正因冒险手册浏览而暂停，则先建立空缓存与运行时状态，待恢复后再继续骨架枚举。
---@param isManual boolean|nil
---@return boolean ok
---@return string|nil err
function Directory.StartBuild(isManual)
  if not isFeatureEnabled() and isManual ~= true then
    return false, "disabled"
  end
  loadCacheFromDb()
  EJStateDriver.Initialize()
  resetRuntimeForBuild(isManual)

  cache = createEmptyCache()
  saveCacheToDb()

  runtime.pendingSkeletonEnumeration = true
  if runtime.isEncounterJournalPaused ~= true then
    local ok, err = prepareBuildSkeleton()
    if not ok then
      failBuild(err)
      return false, tostring(err)
    end
  end

  local driver = getOrCreateDriverFrame()
  driver:Show()
  return true
end

--- 取消当前后台构建；保留当下已写入的局部缓存，供下一次重建覆盖。
function Directory.CancelBuild()
  if runtime.state ~= "building" then
    return
  end
  runtime.state = "cancelled"
  runtime.currentStage = nil
  runtime.currentLabel = nil
  runtime.failureMessage = nil
  runtime.pendingSkeletonEnumeration = false
  runtime.token = (runtime.token or 0) + 1
  clearDriver()
  local L = Toolbox.L or {}
  debugPrint(L.DRD_DEBUG_BUILD_CANCELLED or "")
end

--- 供设置页调用：取消旧任务并从空缓存重新异步构建。
function Directory.RebuildCache()
  local L = Toolbox.L or {}
  debugPrint(L.DRD_DEBUG_REBUILD_REQUESTED or "")
  if runtime.state == "building" then
    Directory.CancelBuild()
  end
  return Directory.StartBuild(true)
end

--- 设置目录功能启用态；关闭时停止后台构建，开启时按需恢复锁定与缓存构建。
---@param enabled boolean|nil true=启用；其它值=关闭
function Directory.SetFeatureEnabled(enabled)
  if enabled == false then
    if runtime.state == "building" then
      Directory.CancelBuild()
    end
    return
  end

  Directory.Initialize()
  if RequestRaidInfo then
    pcall(RequestRaidInfo)
  end
  Directory.RefreshLockouts()
  if runtime.state ~= "building" and isCacheInvalid() then
    Directory.StartBuild(false)
  end
end

--- 清空目录缓存与运行时状态，恢复为默认空缓存；不自动开始重建。
function Directory.ResetCacheToDefaults()
  cache = Toolbox.DB.CopyGlobalDefault("dungeonRaidDirectory")
  saveCacheToDb()
  wipe(runtime.lockoutsByJournalInstanceID)
  runtime.token = (runtime.token or 0) + 1
  clearDriver()
  resetRuntimeToIdle()
end

--- 返回当前后台构建状态。
---@return string
function Directory.GetBuildState()
  return runtime.state or "idle"
end

--- 返回设置页读取的构建进度快照。
---@return table
function Directory.GetBuildProgress()
  local percent = 0
  if runtime.totalUnits > 0 then
    percent = runtime.completedUnits / runtime.totalUnits
  elseif runtime.state == "completed" then
    percent = 1
  end
  if percent < 0 then
    percent = 0
  elseif percent > 1 then
    percent = 1
  end

  return {
    state = runtime.state or "idle",
    currentStage = runtime.currentStage,
    totalUnits = runtime.totalUnits or 0,
    completedUnits = runtime.completedUnits or 0,
    stageTotalUnits = runtime.stageTotalUnits or 0,
    stageCompletedUnits = runtime.stageCompletedUnits or 0,
    percent = percent,
    currentLabel = runtime.currentLabel,
    isManualRebuild = runtime.isManualRebuild == true,
    isPausedForEncounterJournal = runtime.isEncounterJournalPaused == true,
    priorityTierIndex = runtime.priorityTierIndex,
    failureMessage = runtime.failureMessage,
    lastBuildAt = cache and cache.lastBuildAt or 0,
  }
end

--- 按目录顺序列出全部副本记录。
---@return table[]
function Directory.ListAll()
  loadCacheForRead()
  ensureCompletedCacheMountSummariesNormalized()
  local out = {}
  for _, jid in ipairs(getOrderedJournalInstanceIDs()) do
    local record = cache.records and cache.records[jid]
    if record then
      applyMountSummarySupplement(record)
      out[#out + 1] = record
    end
  end
  return out
end

--- 读取单个副本记录。
---@param journalInstanceID number
---@return table|nil
function Directory.GetByJournalInstanceID(journalInstanceID)
  loadCacheForRead()
  ensureCompletedCacheMountSummariesNormalized()
  local record = cache.records and cache.records[journalInstanceID] or nil
  applyMountSummarySupplement(record)
  return record
end

--- 返回某副本的按顺序难度记录，并附带运行时锁定信息。
---@param journalInstanceID number
---@return table[]
function Directory.GetDifficultyRecords(journalInstanceID)
  loadCacheForRead()
  local record = cache.records and cache.records[journalInstanceID]
  if not record then
    return {}
  end

  local out = {}
  local lockouts = runtime.lockoutsByJournalInstanceID[journalInstanceID]
  for _, difficultyID in ipairs(record.difficultyOrder or {}) do
    local difficultyRecord = record.difficulties and record.difficulties[difficultyID] or {}
    out[#out + 1] = {
      difficultyID = difficultyID,
      name = cache.difficultyMeta[difficultyID] and cache.difficultyMeta[difficultyID].name or getDifficultyName(difficultyID),
      hasMountLoot = difficultyRecord.hasMountLoot,
      lockout = lockouts and lockouts[difficultyID] or nil,
    }
  end
  return out
end

--- 返回某副本的掉落摘要。
---@param journalInstanceID number
---@return table|nil
function Directory.GetMountSummary(journalInstanceID)
  loadCacheForRead()
  ensureCompletedCacheMountSummariesNormalized()
  local record = cache.records and cache.records[journalInstanceID]
  applyMountSummarySupplement(record)
  return record and record.summary or nil
end

--- 返回某副本是否存在任一坐骑掉落；未完成扫描时返回 nil。
---@param journalInstanceID number
---@return boolean|nil
function Directory.HasAnyMountLoot(journalInstanceID)
  local summary = Directory.GetMountSummary(journalInstanceID)
  if not summary then
    return nil
  end
  return summary.hasAnyMountLoot
end

--- 返回目录层当前的结构化调试快照；供设置页或 /dump 读取。
---@return table
function Directory.GetDebugSnapshot()
  ensureCacheLoaded()
  ensureCompletedCacheMountSummariesNormalized()

  local progress = Directory.GetBuildProgress()
  local records = collectRecordDebugSnapshots()
  return {
    cacheInfo = {
      schemaVersion = cache and cache.schemaVersion or nil,
      interfaceBuild = cache and cache.interfaceBuild or nil,
      lastBuildAt = cache and cache.lastBuildAt or nil,
      tierNames = copyTierNames(),
      difficultyMeta = copyDifficultyMeta(),
    },
    progress = {
      state = progress.state,
      currentStage = progress.currentStage,
      totalUnits = progress.totalUnits,
      completedUnits = progress.completedUnits,
      stageTotalUnits = progress.stageTotalUnits,
      stageCompletedUnits = progress.stageCompletedUnits,
      percent = progress.percent,
      currentLabel = progress.currentLabel,
      isManualRebuild = progress.isManualRebuild,
      isPausedForEncounterJournal = progress.isPausedForEncounterJournal,
      failureMessage = progress.failureMessage,
      lastBuildAt = progress.lastBuildAt,
    },
    recordCount = countRecordTotal(),
    supportedDifficultyCount = countSupportedDifficultyTotal(),
    mountPositiveRecordCount = countMountPositiveRecordTotal(),
    lockoutMappedCount = countMappedLockoutTotal(),
    displayedRecordCount = #records,
    records = records,
  }
end

--- 生成目录层当前的多行调试文本；用于设置页滚动查看器。
---@return string
function Directory.FormatDebugSnapshot()
  local snapshot = Directory.GetDebugSnapshot()
  local cacheInfo = snapshot.cacheInfo or {}
  local progress = snapshot.progress or {}
  local lines = {
    string.format(
      "state=%s stage=%s total=%s completed=%s percent=%d%% manual=%s pausedForEJ=%s",
      formatDebugScalar(progress.state),
      formatDebugScalar(progress.currentStage),
      formatDebugScalar(progress.totalUnits),
      formatDebugScalar(progress.completedUnits),
      math.floor(((progress.percent or 0) * 100) + 0.5),
      formatDebugScalar(progress.isManualRebuild),
      formatDebugScalar(progress.isPausedForEncounterJournal)
    ),
    string.format(
      "stageProgress=%s/%s current=%s failure=%s",
      formatDebugScalar(progress.stageCompletedUnits),
      formatDebugScalar(progress.stageTotalUnits),
      formatDebugScalar(progress.currentLabel),
      formatDebugScalar(progress.failureMessage)
    ),
    string.format(
      "cache.schemaVersion=%s interfaceBuild=%s lastBuildAt=%s",
      formatDebugScalar(cacheInfo.schemaVersion),
      formatDebugScalar(cacheInfo.interfaceBuild),
      formatDebugScalar(cacheInfo.lastBuildAt)
    ),
    string.format(
      "counts.records=%s displayedRecords=%s supportedDifficulties=%s mountPositiveRecords=%s lockoutMapped=%s",
      formatDebugScalar(snapshot.recordCount),
      formatDebugScalar(snapshot.displayedRecordCount),
      formatDebugScalar(snapshot.supportedDifficultyCount),
      formatDebugScalar(snapshot.mountPositiveRecordCount),
      formatDebugScalar(snapshot.lockoutMappedCount)
    ),
    string.format("tierNames=%s", formatDebugNamedMap(cacheInfo.tierNames)),
    string.format("difficultyMeta=%s", formatDebugNamedMap(cacheInfo.difficultyMeta, "name")),
  }

  if #snapshot.records == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "records=[]"
    return table.concat(lines, "\n")
  end

  for _, record in ipairs(snapshot.records) do
    local base = record.base or {}
    local summary = record.summary or {}

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("[%s] %s", formatDebugScalar(base.journalInstanceID), formatDebugScalar(base.name))
    lines[#lines + 1] = string.format(
      "  kind=%s tierIndex=%s tierName=%s mapID=%s worldInstanceID=%s",
      formatDebugScalar(base.kind),
      formatDebugScalar(base.tierIndex),
      formatDebugScalar(base.tierName),
      formatDebugScalar(base.mapID),
      formatDebugScalar(base.worldInstanceID)
    )
    lines[#lines + 1] = string.format(
      "  summary.hasAnyMountLoot=%s mountDifficultyIDs=%s",
      formatDebugScalar(summary.hasAnyMountLoot),
      formatDebugArray(summary.mountDifficultyIDs)
    )

    if #record.difficulties == 0 then
      lines[#lines + 1] = "  difficulties=[]"
    else
      lines[#lines + 1] = "  difficulties:"
      for _, difficulty in ipairs(record.difficulties) do
        lines[#lines + 1] = string.format(
          "    %s %s hasMountLoot=%s lockout=%s",
          formatDebugScalar(difficulty.difficultyID),
          formatDebugScalar(difficulty.name),
          formatDebugScalar(difficulty.hasMountLoot),
          formatDebugLockout(difficulty.lockout)
        )
      end
    end
  end

  return table.concat(lines, "\n")
end

--- 刷新当前角色锁定到运行时覆盖层；不会改写账号级缓存中的角色态数据。
function Directory.RefreshLockouts()
  loadCacheForRead()
  wipe(runtime.lockoutsByJournalInstanceID)

  if not cache.records or next(cache.records) == nil then
    return
  end

  local worldLookup, nameLookup = buildLockoutLookups()
  local didBackfillWorldInstanceID = false
  local backfillCount = 0
  local mappedCount = 0
  local numSaved = Toolbox.Lockouts.GetNumSavedInstances()

  for index = 1, numSaved do
    local name, _, reset, difficultyId, locked, extended, _, _, _, _, numEncounters, encounterProgress, _, instanceId =
      Toolbox.Lockouts.GetSavedInstanceInfo(index)

    local journalInstanceID = resolveJournalInstanceID(worldLookup, nameLookup, instanceId, name, difficultyId)
    if journalInstanceID and type(difficultyId) == "number" then
      mappedCount = mappedCount + 1
      runtime.lockoutsByJournalInstanceID[journalInstanceID] = runtime.lockoutsByJournalInstanceID[journalInstanceID] or {}
      runtime.lockoutsByJournalInstanceID[journalInstanceID][difficultyId] = {
        instanceId = instanceId,
        difficultyId = difficultyId,
        reset = reset,
        locked = locked,
        extended = extended,
        encounterProgress = encounterProgress,
        numEncounters = numEncounters,
        name = name,
      }

      local record = cache.records[journalInstanceID]
      local base = record and record.base
      if base and base.worldInstanceID == nil and type(instanceId) == "number" and instanceId > 0 then
        base.worldInstanceID = instanceId
        worldLookup[instanceId] = journalInstanceID
        didBackfillWorldInstanceID = true
        backfillCount = backfillCount + 1
      end
    end
  end

  if didBackfillWorldInstanceID then
    saveCacheToDb()
  end

  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.DRD_DEBUG_LOCKOUT_REFRESH_FMT or "%s",
    mappedCount,
    backfillCount
  ))
end

--- 返回某副本按难度组织的锁定信息；无锁定时返回 nil。
---@param journalInstanceID number
---@return table|nil
function Directory.GetLockoutSummary(journalInstanceID)
  return runtime.lockoutsByJournalInstanceID[journalInstanceID]
end
