--[[
  Logic Test Harness（EncounterJournal，Phase 1）。
  提供：
    - 模块加载与事件驱动入口
    - fake runtime、trace、tooltip 行读取
    - 定时器推进能力
]]

local newFakeRuntime = dofile("tests/logic/harness/fake_runtime.lua")

local Harness = {}
Harness.__index = Harness

local function normalizePath(pathText)
  return (pathText or ""):gsub("\\", "/")
end

local function inferRootFromSource()
  local sourceText = debug.getinfo(1, "S").source -- 当前文件来源
  local rawPath = sourceText:gsub("^@", "") -- 去除 Lua source 前缀
  local normalizedPath = normalizePath(rawPath) -- 统一路径分隔符
  local rootPath = normalizedPath:gsub("tests/logic/harness/harness.lua$", "") -- 仓库根目录
  rootPath = rootPath:gsub("/$", "") -- 去除尾部斜杠
  if rootPath == "" then
    return "." -- 相对路径加载时回落到当前工作目录
  end
  return rootPath
end

local function shallowCopyTable(sourceTable)
  local copied = {} -- 复制结果
  if type(sourceTable) == "table" then
    for key, value in pairs(sourceTable) do
      copied[key] = value
    end
  end
  return copied
end

function Harness.new(options)
  local opts = options or {} -- 构造参数
  local self = setmetatable({}, Harness) -- harness 实例
  self.rootPath = opts.rootPath or inferRootFromSource() -- 仓库根路径
  self.traceList = {} -- 行为追踪
  self.savedGlobals = {} -- 全局还原快照
  self.moduleDef = nil -- 模块定义
  self.runtime = newFakeRuntime({
    traceList = self.traceList,
    addonLoadedSeed = opts.addonLoadedSeed,
  })
  self.moduleDbById = {
    encounter_journal = {
      enabled = opts.moduleEnabled ~= false,
      debug = opts.moduleDebug == true,
      mountFilterEnabled = true,
      lockoutOverlayEnabled = true,
      detailMountOnlyEnabled = false,
      questlineTreeEnabled = true,
      questNavExpansionID = 0,
      questNavModeKey = "map_questline",
      questNavSelectedMapID = 0,
      questNavSelectedTypeKey = "",
      questNavSearchText = "",
      questNavExpandedQuestLineID = 0,
      questlineTreeCollapsed = {},
    },
    quest = {
      enabled = opts.moduleEnabled ~= false,
      debug = opts.moduleDebug == true,
      questlineTreeEnabled = true,
      questNavExpansionID = 0,
      questNavModeKey = "active_log",
      questNavSelectedMapID = 0,
      questNavSelectedTypeKey = "",
      questNavSearchText = "",
      questNavSkinPreset = "archive",
      questInspectorLastQuestID = 0,
      questRecentCompletedList = {},
      questRecentCompletedMax = 10,
      questNavExpandedQuestLineID = 0,
      questlineTreeCollapsed = {},
    },
  }
  self.moduleDb = self.moduleDbById.encounter_journal -- 兼容旧测试引用
  self.questModuleDb = self.moduleDbById.quest -- quest 模块存档快捷引用
  self.locale = opts.locale or "zhCN" -- 当前 locale
  self.lockoutLines = {} -- tooltip 锁定摘要行
  self.lockoutOverflow = 0 -- tooltip 溢出数量
  self:_installGlobals()
  return self
end

function Harness:_setGlobal(keyName, value)
  if self.savedGlobals[keyName] == nil then
    self.savedGlobals[keyName] = rawget(_G, keyName)
  end
  rawset(_G, keyName, value)
end

function Harness:_installGlobals()
  local localeTable = {
    MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE = self.locale == "enUS" and "Current lockouts" or "当前锁定",
    MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_EMPTY = self.locale == "enUS" and "No saved instance lockouts." or "当前没有副本进度锁定。",
    MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_MORE_FMT = self.locale == "enUS" and "+%d more..." or "还有 %d 条未显示",
  }

  local toolboxTable = { -- Toolbox 替身
    Runtime = self.runtime,
    L = localeTable,
    Data = {
      InstanceMapIDs = {},
      MountDrops = {},
      InstanceQuestlines = {},
    },
    Chat = {
      PrintAddonMessage = function(_, text)
        self.traceList[#self.traceList + 1] = {
          kind = "chat_print",
          text = text,
        }
      end,
    },
    Config = {
      Init = function() end,
      GetModule = function(moduleId, maybeModuleId)
        local resolvedModuleId = maybeModuleId or moduleId -- 兼容点调用与冒号调用
        if type(self.moduleDbById[resolvedModuleId]) ~= "table" then
          self.moduleDbById[resolvedModuleId] = {}
        end
        return self.moduleDbById[resolvedModuleId]
      end,
      GetGlobal = function()
        return { debug = false }
      end,
    },
    EJ = {
      IsRaidOrDungeonInstanceListTab = function()
        return true
      end,
      HasMountDrops = function()
        return true
      end,
      GetAllLockoutsForInstance = function()
        return {}
      end,
      GetKilledBosses = function()
        return {}
      end,
      BuildSavedInstanceLockoutTooltipLines = function()
        return shallowCopyTable(self.lockoutLines), self.lockoutOverflow
      end,
    },
    Questlines = {
      GetQuestTabModel = function()
        return {}
      end,
    },
    TestHooks = {},
    _registeredModules = {},
  }

  function toolboxTable.RegisterModule(moduleDef)
    toolboxTable._registeredModules[moduleDef.id] = moduleDef
  end

  self.toolboxTable = toolboxTable

  self:_setGlobal("Toolbox", toolboxTable)
  self:_setGlobal("ToolboxAddon", toolboxTable)
  self:_setGlobal("Toolbox_NamespaceEnsure", function() end)
  self:_setGlobal("GameTooltip", self.runtime.tooltip)
  self:_setGlobal("EJMicroButton", self.runtime.CreateFrame("Button", "EJMicroButton"))
  self:_setGlobal("RequestRaidInfo", function()
    self.traceList[#self.traceList + 1] = { kind = "request_raid_info" }
  end)
  self:_setGlobal("GetTime", function()
    return self.runtime.timer.now
  end)
  self:_setGlobal("GetLocale", function()
    return self.locale
  end)
  self:_setGlobal("LoadAddOn", function(addonName)
    return self.runtime.LoadAddOn(addonName)
  end)
  self:_setGlobal("wipe", function(targetTable)
    if type(targetTable) == "table" then
      for key in pairs(targetTable) do
        targetTable[key] = nil
      end
    end
    return targetTable
  end)
  self:_setGlobal("hooksecurefunc", function() end)
  self:_setGlobal("UIParent", self.runtime.CreateFrame("Frame", "UIParent"))
  self:_setGlobal("GetCursorPosition", function() return 0, 0 end)
  self:_setGlobal("InCombatLockdown", function() return false end)
  self:_setGlobal("IsMouseButtonDown", function() return false end)
end

function Harness:setLockoutTooltipData(lineList, overflowCount)
  self.lockoutLines = shallowCopyTable(lineList)
  self.lockoutOverflow = tonumber(overflowCount) or 0
end

function Harness:loadEncounterJournalModule()
  local modulePathList = {
    self.rootPath .. "/Toolbox/Modules/EncounterJournal/Shared.lua",
    self.rootPath .. "/Toolbox/Modules/EncounterJournal/DetailEnhancer.lua",
    self.rootPath .. "/Toolbox/Modules/EncounterJournal/LockoutOverlay.lua",
    self.rootPath .. "/Toolbox/Modules/EncounterJournal.lua",
  } -- encounter journal 相关加载顺序
  for _, modulePath in ipairs(modulePathList) do
    local moduleChunk, loadError = loadfile(modulePath) -- 加载模块 chunk
    if not moduleChunk then
      error(loadError)
    end
    moduleChunk()
  end
  self.moduleDef = self.toolboxTable._registeredModules.encounter_journal
  assert(self.moduleDef, "encounter_journal module should be registered")
  if type(self.moduleDef.OnModuleLoad) == "function" then
    self.moduleDef.OnModuleLoad()
  end
  return self.moduleDef
end

function Harness:loadQuestModule()
  local modulePathList = {
    self.rootPath .. "/Toolbox/Modules/Quest/Shared.lua",
    self.rootPath .. "/Toolbox/Modules/Quest/QuestNavigation.lua",
    self.rootPath .. "/Toolbox/Modules/Quest.lua",
  } -- quest 模块加载顺序
  for _, modulePath in ipairs(modulePathList) do
    local moduleChunk, loadError = loadfile(modulePath) -- 加载模块 chunk
    if not moduleChunk then
      error(loadError)
    end
    moduleChunk()
  end
  self.moduleDef = self.toolboxTable._registeredModules.quest
  assert(self.moduleDef, "quest module should be registered")
  if type(self.moduleDef.OnModuleLoad) == "function" then
    self.moduleDef.OnModuleLoad()
  end
  return self.moduleDef
end

function Harness:getEventFrame()
  return self.runtime.frameByName.ToolboxEncounterJournalHost
end

function Harness:isEventRegistered(eventName)
  local eventFrame = self:getEventFrame() -- 事件 frame
  if not eventFrame then
    return false
  end
  return eventFrame.registeredEvents[eventName] == true
end

function Harness:emit(eventName, ...)
  local eventFrame = self:getEventFrame() -- 事件 frame
  if not eventFrame then
    return false
  end
  return eventFrame:EmitEvent(eventName, ...)
end

function Harness:triggerMicroButtonOnEnter()
  local microButton = rawget(_G, "EJMicroButton") -- 微型菜单按钮
  if microButton and microButton.RunScript then
    microButton:RunScript("OnEnter")
  end
end

function Harness:advance(seconds)
  return self.runtime.timer:advance(seconds)
end

function Harness:runAllTimers()
  self.runtime.timer:runAll()
end

function Harness:getTrace()
  return self.traceList
end

function Harness:getTooltipLines()
  return shallowCopyTable(self.runtime.tooltip.lines)
end

function Harness:getRequestRaidInfoCallCount()
  local count = 0 -- 调用次数
  for _, entry in ipairs(self.traceList) do
    if entry.kind == "request_raid_info" then
      count = count + 1
    end
  end
  return count
end

function Harness:getTimerCancelCount()
  local count = 0 -- 取消次数
  for _, entry in ipairs(self.traceList) do
    if entry.kind == "timer_skip_canceled" then
      count = count + 1
    end
  end
  return count
end

function Harness:resetState()
  self.traceList = {}
  self.runtime.traceList = self.traceList
  self.runtime.tooltip.traceList = self.traceList
  self.runtime.tooltip:ClearLines()
  self.runtime.timer.traceList = self.traceList
end

function Harness:teardown()
  local testHooks = self.toolboxTable and self.toolboxTable.TestHooks and self.toolboxTable.TestHooks.EncounterJournal
  if testHooks and type(testHooks.resetInternalState) == "function" then
    pcall(testHooks.resetInternalState)
  end
  local questHooks = self.toolboxTable and self.toolboxTable.TestHooks and self.toolboxTable.TestHooks.Quest
  if questHooks and type(questHooks.resetInternalState) == "function" then
    pcall(questHooks.resetInternalState)
  end
  for keyName, originalValue in pairs(self.savedGlobals) do
    rawset(_G, keyName, originalValue)
  end
end

return Harness
