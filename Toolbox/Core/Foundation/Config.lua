--[[
  配置管理：ToolboxDB 默认值、初始化与迁移。
  各模块只应通过 GetModule(moduleId) 读写 modules[moduleId]，避免键冲突。
]]

local defaults = {
  version = 2,
  global = {
    debug = false,
    -- auto：跟随游戏客户端；zhCN / enUS：强制界面语言
    locale = "auto",
    -- 设置宿主：最近一次停留的叶子页；首次打开回退到 general
    settingsLastLeafPage = "general",
  },
  modules = {
    mover = {
      enabled = true,
      debug = false,
      frames = {},
      -- 暴雪 / 自建（无 dragRegion）共用：titlebar=仅标题解析区；titlebar_and_empty=标题区 + 栈底全窗透明层（空白处）
      blizzardDragHitMode = "titlebar",
      -- 为 true 时战斗中仍尝试拖动（仍可能受安全模板等限制）
      allowDragInCombat = false,
    },
    micromenu_panels = {
      enabled = true,
      debug = false,
      frames = {},
    },
    tooltip_anchor = {
      enabled = true,
      debug = false,
      mode = "cursor",
      offsetX = 0,
      offsetY = 0,
    },
    minimap_button = {
      enabled = true,
      debug = false,
      -- 模块启用时是否在小地图旁显示打开设置的按钮（可与「启用本模块」独立）
      showMinimapButton = true,
      -- 是否在小地图上/下显示玩家当前坐标
      showCoordsOnMinimap = true,
      -- 小地图坐标锚点：top（上）| bottom（下）
      minimapCoordsAnchor = "bottom",
      -- 沿小地图边缘的角度（度），与 LibDBIcon 一致；nil 表示默认 225°（左上象限靠外）
      minimapPos = nil,
      -- 悬停展开菜单：首项相对面板左上内边距、相邻两项之间的额外竖直间距（像素）；布局见 MinimapButton.lua
      flyoutPad = 4,
      flyoutGap = 0,
      -- 展开区右缘与微缩按钮左缘之间的横向间距（像素），对应 SetPoint RIGHT/LEFT 的 x 偏移绝对值
      flyoutLauncherGap = 0,
      -- 微缩主按钮外观：round 圆形（默认）| square 方形
      buttonShape = "round",
      -- 悬停展开方向：vertical 纵向叠放（默认）| horizontal 横向一排（靠小地图一侧为首项）
      flyoutExpand = "vertical",
      -- 悬停展开项 id 列表（顺序即显示顺序）；id 须已由 RegisterFlyoutEntry 注册
      flyoutSlotIds = { "reload_ui", "tb_flyout_quest" },
    },
    chat_notify = {
      enabled = true,
      debug = false,
      -- 前缀颜色（不含 |cff），默认金黄色 ffd700
      prefixColor = "ffd700",
      -- 正文颜色（不含 |cff）；PrintAddonMessage 将正文包在 |cff 内，默认白色 ffffff
      contentColor = "ffffff",
    },
    encounter_journal = {
      enabled = true,
      debug = false,
      mountFilterEnabled = true,
      -- 副本列表入口图钉是否常驻显示；false 时仅焦点行或悬停行显示
      listPinAlwaysVisible = false,
    },
    navigation = {
      enabled = true,
      debug = false,
      -- 最近一次世界地图目标，仅用于调试和后续恢复，不参与账号级跨角色推断。
      lastTargetUiMapID = 0,
      lastTargetX = 0,
      lastTargetY = 0,
    },
    quest = {
      enabled = true,
      debug = false,
      -- 任务视图总开关
      questlineTreeEnabled = true,
      -- 左侧树：当前资料片（0 表示运行时自动选择首项）
      questNavExpansionID = 0,
      -- 左侧树：当前战役（0 表示未选中）
      questNavSelectedCampaignID = 0,
      -- 左侧树：当前成就（0 表示未选中）
      questNavSelectedAchievementID = 0,
      -- 当前模式（active_log | map_questline | campaign | achievement）
      questNavModeKey = "active_log",
      -- 左侧树：当前地图（0 表示未选中）
      questNavSelectedMapID = 0,
      -- 兼容旧结构保留（当前版本不再使用 quest_type）
      questNavSelectedTypeKey = "",
      -- 视图内搜索关键词
      questNavSearchText = "",
      -- 任务视图皮肤模式（default | archive | contrast）
      questNavSkinPreset = "archive",
      -- 任务详情查询页：最近一次输入 QuestID（0 表示未查询）
      questInspectorLastQuestID = 0,
      -- 最近完成任务记录（按时间倒序）
      questRecentCompletedList = {},
      -- 最近完成任务保留上限（1-30）
      questRecentCompletedMax = 10,
      -- 主区：当前展开任务线（0 表示全部折叠）
      questNavExpandedQuestLineID = 0,
      -- 左侧树折叠状态（key=true 表示折叠）
      questlineTreeCollapsed = {},
    },
  },
}

-- 将 src 中缺失键合并进 dst；嵌套表递归合并，不覆盖用户已有标量
-- 添加类型校验：若用户存档中某键类型与默认值不匹配，使用默认值
local function mergeTable(dst, src)
  if type(dst) ~= "table" then return CopyTable(src) end
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) == "table" then
        mergeTable(dst[k], v)
      elseif dst[k] == nil then
        dst[k] = CopyTable(v)
      else
        -- 类型不匹配：用户存档中该键不是表，但默认值是表，使用默认值
        dst[k] = CopyTable(v)
      end
    else
      if dst[k] == nil then
        dst[k] = v
      elseif type(dst[k]) ~= type(v) then
        -- 类型不匹配：用户存档中该键类型与默认值不同，使用默认值
        dst[k] = v
      end
    end
  end
  return dst
end

-- ADDON_LOADED 时调用；SavedVariables 已由客户端载入到 ToolboxDB
-- 全局杂项配置（非 modules.*）；须在本插件 Config.Init 之后使用，以保证已 merge 默认值
function Toolbox.Config.GetGlobal()
  if not ToolboxDB then
    ToolboxDB = {}
  end
  ToolboxDB.global = ToolboxDB.global or {}
  return ToolboxDB.global
end

function Toolbox.Config.Init()
  if not ToolboxDB then
    ToolboxDB = CopyTable(defaults)
    return
  end
  ToolboxDB.global = ToolboxDB.global or {}
  ToolboxDB.modules = ToolboxDB.modules or {}
  local preMergeModuleStore = type(ToolboxDB.modules) == "table" and CopyTable(ToolboxDB.modules) or {} -- 合并默认值前的模块存档快照
  mergeTable(ToolboxDB, defaults)

  local ver = ToolboxDB.version or 0

  -- v0 -> v1 迁移
  if ver < 1 then
    -- 旧版 global.notifyLoadComplete=false 迁移到 modules.chat_notify.enabled
    if ToolboxDB.global and ToolboxDB.global.notifyLoadComplete == false then
      ToolboxDB.modules.chat_notify = ToolboxDB.modules.chat_notify or {}
      ToolboxDB.modules.chat_notify.enabled = false
    end
    ToolboxDB.version = 1
  end

  -- v1 -> v2 迁移
  if ver < 2 then
    -- micromenu_panels 存档并入 mover（一次性）
    local mv = ToolboxDB.modules and ToolboxDB.modules.mover
    local mm = ToolboxDB.modules and ToolboxDB.modules.micromenu_panels
    if type(mv) == "table" and type(mm) == "table" and not mv._micromenuMerged then
      mv.frames = mv.frames or {}
      if type(mm.frames) == "table" then
        for k, v in pairs(mm.frames) do
          if type(k) == "string" and k ~= "demo" and mv.frames[k] == nil and type(v) == "table" then
            mv.frames[k] = CopyTable(v)
          end
        end
      end
      mv._micromenuMerged = true
    end

    -- mover：丢弃已废弃键
    if type(mv) == "table" then
      mv.demoVisible = nil
      mv.dragBlizzardPanels = nil
      if type(mv.frames) == "table" then
        mv.frames.demo = nil
      end
      -- 移除已废弃的冲突/检测相关存档键
      mv.blizzardDragConflictRulesExtra = nil
      mv.blizzardNonNativeHints = nil
      mv.blizzardDragFixMarker = nil
      mv.blizzardDragPreferNative = nil
      mv.blizzardNonNativeListFilter = nil
      mv.blizzardDragAutoDenyFrames = nil
      mv.blizzardDragAutoDenyReason = nil
      mv.blizzardDragConflictAllowOverride = nil
      mv._nonNativeHintsMigrated = nil
      mv.blizzardExtraFrameNames = nil
    end

    -- dungeon_raid_directory -> encounter_journal 迁移
    local drd = ToolboxDB.modules and ToolboxDB.modules.dungeon_raid_directory
    if type(drd) == "table" then
      local encJournalDb = ToolboxDB.modules.encounter_journal or {}
      if encJournalDb.mountFilterEnabled == nil and drd.mountFilterEnabled ~= nil then
        encJournalDb.mountFilterEnabled = drd.mountFilterEnabled
      end
      if encJournalDb.enabled == nil and drd.enabled ~= nil then
        encJournalDb.enabled = drd.enabled
      end
      ToolboxDB.modules.encounter_journal = encJournalDb
      ToolboxDB.modules.dungeon_raid_directory = nil
    end

    -- 清理旧 global.dungeonRaidDirectory 缓存
    if ToolboxDB.global and ToolboxDB.global.dungeonRaidDirectory then
      ToolboxDB.global.dungeonRaidDirectory = nil
    end

    -- 清理已移除模块的存档
    if ToolboxDB.modules then
      ToolboxDB.modules.hitinsets = nil
      ToolboxDB.modules.ej_mount_filter = nil
    end

    ToolboxDB.version = 2
  end

  -- quest 模块：从 encounter_journal 旧任务键迁移并做字段归一化（幂等，不依赖全局 version）。
  local moduleStore = ToolboxDB.modules or {} -- 模块存档表
  local legacyModuleStore = type(preMergeModuleStore) == "table" and preMergeModuleStore or {} -- 默认值合并前的模块存档
  local legacyEncounterJournalDb = type(legacyModuleStore.encounter_journal) == "table" and legacyModuleStore.encounter_journal or nil -- 冒险指南旧存档
  local legacyQuestDb = type(legacyModuleStore.quest) == "table" and legacyModuleStore.quest or nil -- quest 模块旧存档
  local encounterJournalDb = type(moduleStore.encounter_journal) == "table" and moduleStore.encounter_journal or nil -- 当前冒险指南存档
  local questDb = type(moduleStore.quest) == "table" and moduleStore.quest or {} -- quest 模块存档

  local function readQuestField(fieldName, fallbackValue)
    if type(legacyQuestDb) == "table" and legacyQuestDb[fieldName] ~= nil then
      return legacyQuestDb[fieldName]
    end
    if type(legacyEncounterJournalDb) == "table" and legacyEncounterJournalDb[fieldName] ~= nil then
      return legacyEncounterJournalDb[fieldName]
    end
    return fallbackValue
  end

  local legacyExpandedMap = readQuestField("questlineTreeExpanded", nil) -- 旧版展开状态
  if type(legacyExpandedMap) == "table" and type(questDb.questlineTreeCollapsed) ~= "table" then
    questDb.questlineTreeCollapsed = {}
    for collapseKey, expandedFlag in pairs(legacyExpandedMap) do
      if expandedFlag == false then
        questDb.questlineTreeCollapsed[collapseKey] = true
      end
    end
  end

  local legacyViewMode = readQuestField("questViewMode", nil) -- 旧版视图模式
  local legacyModeKey = readQuestField("questNavModeKey", nil) -- 旧版模式键
  if legacyModeKey == "active_log" then
    questDb.questNavModeKey = "active_log"
  elseif legacyModeKey == "campaign" then
    questDb.questNavModeKey = "campaign"
  elseif legacyModeKey == "achievement" then
    questDb.questNavModeKey = "achievement"
  elseif legacyModeKey == "map_questline" then
    questDb.questNavModeKey = "map_questline"
  elseif legacyViewMode == nil then
    questDb.questNavModeKey = "active_log"
  else
    questDb.questNavModeKey = "map_questline"
  end

  local legacyMapID = readQuestField("questViewSelectedMapID", nil) -- 旧版地图选中 ID
  local selectedMapID = readQuestField("questNavSelectedMapID", nil) -- 当前地图选中 ID
  if type(legacyMapID) == "number" and legacyMapID > 0 then
    questDb.questNavSelectedMapID = legacyMapID
  elseif type(selectedMapID) == "number" then
    questDb.questNavSelectedMapID = math.max(0, math.floor(selectedMapID))
  else
    questDb.questNavSelectedMapID = 0
  end

  local selectedCampaignID = readQuestField("questNavSelectedCampaignID", 0) -- 当前战役选中 ID
  if type(selectedCampaignID) == "number" then
    questDb.questNavSelectedCampaignID = math.max(0, math.floor(selectedCampaignID))
  else
    questDb.questNavSelectedCampaignID = 0
  end

  local selectedAchievementID = readQuestField("questNavSelectedAchievementID", 0) -- 当前成就选中 ID
  if type(selectedAchievementID) == "number" then
    questDb.questNavSelectedAchievementID = math.max(0, math.floor(selectedAchievementID))
  else
    questDb.questNavSelectedAchievementID = 0
  end

  local legacyTypeID = readQuestField("questViewSelectedTypeID", nil) -- 旧版类型 ID
  local selectedTypeKey = readQuestField("questNavSelectedTypeKey", "") -- 当前类型键
  if type(legacyTypeID) == "number" and legacyTypeID > 0 then
    questDb.questNavSelectedTypeKey = "type:" .. tostring(legacyTypeID)
  elseif type(selectedTypeKey) == "string" then
    questDb.questNavSelectedTypeKey = selectedTypeKey
  else
    questDb.questNavSelectedTypeKey = ""
  end

  local selectedExpansionID = readQuestField("questNavExpansionID", 0) -- 当前资料片 ID
  if type(selectedExpansionID) == "number" then
    questDb.questNavExpansionID = math.max(0, math.floor(selectedExpansionID))
  else
    questDb.questNavExpansionID = 0
  end

  local searchText = readQuestField("questNavSearchText", "") -- 搜索关键词
  questDb.questNavSearchText = type(searchText) == "string" and searchText or ""

  local skinPreset = readQuestField("questNavSkinPreset", "archive") -- 皮肤模式
  if skinPreset ~= "default" and skinPreset ~= "archive" and skinPreset ~= "contrast" then
    skinPreset = "archive"
  end
  questDb.questNavSkinPreset = skinPreset

  local inspectorQuestID = readQuestField("questInspectorLastQuestID", 0) -- 最近查询 QuestID
  if type(inspectorQuestID) == "number" then
    questDb.questInspectorLastQuestID = math.max(0, math.floor(inspectorQuestID))
  else
    questDb.questInspectorLastQuestID = 0
  end

  local recentCompletedMax = readQuestField("questRecentCompletedMax", 10) -- 最近完成保留上限
  if type(recentCompletedMax) ~= "number" then
    recentCompletedMax = 10
  end
  recentCompletedMax = math.floor(recentCompletedMax)
  if recentCompletedMax < 1 then
    recentCompletedMax = 1
  elseif recentCompletedMax > 30 then
    recentCompletedMax = 30
  end
  questDb.questRecentCompletedMax = recentCompletedMax

  local recentCompletedList = readQuestField("questRecentCompletedList", {}) -- 最近完成列表
  if type(recentCompletedList) ~= "table" then
    recentCompletedList = {}
  end
  local normalizedRecentList = {} -- 归一化后的最近完成列表
  for _, entry in ipairs(recentCompletedList) do
    if type(entry) == "table" and type(entry.questID) == "number" and entry.questID > 0 then
      normalizedRecentList[#normalizedRecentList + 1] = {
        questID = entry.questID,
        questName = type(entry.questName) == "string" and entry.questName or "",
        completedAt = type(entry.completedAt) == "number" and entry.completedAt or 0,
      }
    end
  end
  questDb.questRecentCompletedList = normalizedRecentList

  local legacySelectionTable = readQuestField("questlineTreeSelection", nil) -- 旧版选中状态表
  local legacyQuestLineID = readQuestField("questViewSelectedQuestLineID", nil) -- 旧版任务线选中 ID
  local selectedQuestLineID = readQuestField("questNavExpandedQuestLineID", nil) -- 当前展开任务线 ID
  if type(legacyQuestLineID) ~= "number" and type(legacySelectionTable) == "table" then
    legacyQuestLineID = legacySelectionTable.selectedQuestLineID
  end
  if type(legacyQuestLineID) == "number" and legacyQuestLineID > 0 then
    questDb.questNavExpandedQuestLineID = legacyQuestLineID
  elseif type(selectedQuestLineID) == "number" then
    questDb.questNavExpandedQuestLineID = math.max(0, math.floor(selectedQuestLineID))
  else
    questDb.questNavExpandedQuestLineID = 0
  end
  if questDb.questNavModeKey == "active_log" then
    questDb.questNavSelectedCampaignID = 0
    questDb.questNavSelectedAchievementID = 0
    questDb.questNavExpandedQuestLineID = 0
  elseif questDb.questNavModeKey == "campaign" then
    questDb.questNavSelectedAchievementID = 0
  elseif questDb.questNavModeKey == "achievement" then
    questDb.questNavSelectedCampaignID = 0
  end

  if type(readQuestField("questlineTreeEnabled", nil)) == "boolean" then
    questDb.questlineTreeEnabled = readQuestField("questlineTreeEnabled", true) == true
  elseif type(questDb.questlineTreeEnabled) ~= "boolean" then
    questDb.questlineTreeEnabled = true
  end

  local legacyCollapsedMap = readQuestField("questlineTreeCollapsed", nil) -- 旧版折叠状态
  if type(legacyCollapsedMap) == "table" then
    local normalizedCollapseMap = {} -- 归一化后的折叠状态
    for collapseKey, collapseFlag in pairs(legacyCollapsedMap) do
      if collapseFlag == true then
        normalizedCollapseMap[collapseKey] = true
      end
    end
    questDb.questlineTreeCollapsed = normalizedCollapseMap
  elseif type(questDb.questlineTreeCollapsed) ~= "table" then
    questDb.questlineTreeCollapsed = {}
  end

  questDb.questlineTreeExpanded = nil
  questDb.questlineTreeSelection = nil
  questDb.questNavCategoryKey = nil
  questDb.questNavSelectedQuestLineID = nil
  questDb.questViewMode = nil
  questDb.questViewSelectedMapID = nil
  questDb.questViewSelectedTypeID = nil
  questDb.questViewSelectedQuestLineID = nil
  questDb.questViewSelectedQuestID = nil

  moduleStore.quest = questDb

  if type(encounterJournalDb) == "table" then
    encounterJournalDb.questlineTreeEnabled = nil
    encounterJournalDb.questNavExpansionID = nil
    encounterJournalDb.questNavModeKey = nil
    encounterJournalDb.questNavSelectedCampaignID = nil
    encounterJournalDb.questNavSelectedAchievementID = nil
    encounterJournalDb.questNavSelectedMapID = nil
    encounterJournalDb.questNavSelectedTypeKey = nil
    encounterJournalDb.questNavSearchText = nil
    encounterJournalDb.questNavSkinPreset = nil
    encounterJournalDb.questInspectorLastQuestID = nil
    encounterJournalDb.questRecentCompletedList = nil
    encounterJournalDb.questRecentCompletedMax = nil
    encounterJournalDb.questNavExpandedQuestLineID = nil
    encounterJournalDb.questlineTreeCollapsed = nil
    encounterJournalDb.questlineTreeExpanded = nil
    encounterJournalDb.questlineTreeSelection = nil
    encounterJournalDb.questNavCategoryKey = nil
    encounterJournalDb.questNavSelectedQuestLineID = nil
    encounterJournalDb.questViewMode = nil
    encounterJournalDb.questViewSelectedMapID = nil
    encounterJournalDb.questViewSelectedTypeID = nil
    encounterJournalDb.questViewSelectedQuestLineID = nil
    encounterJournalDb.questViewSelectedQuestID = nil
    encounterJournalDb.rootTabOrderIds = nil
    encounterJournalDb.rootTabHiddenIds = nil
  end

  local minimapButtonDb = type(moduleStore.minimap_button) == "table" and moduleStore.minimap_button or nil -- 小地图按钮存档
  if type(minimapButtonDb) == "table" and type(minimapButtonDb.flyoutSlotIds) == "table" then
    local hasQuestEntry = false -- 是否已存在 quest 入口
    for _, slotId in ipairs(minimapButtonDb.flyoutSlotIds) do
      if slotId == "tb_flyout_quest" then
        hasQuestEntry = true
        break
      end
    end
    if not hasQuestEntry then
      minimapButtonDb.flyoutSlotIds[#minimapButtonDb.flyoutSlotIds + 1] = "tb_flyout_quest"
    end
  end

  local tooltipAnchorDb = type(moduleStore.tooltip_anchor) == "table" and moduleStore.tooltip_anchor or nil -- tooltip 锚点存档
  if type(tooltipAnchorDb) == "table" then
    tooltipAnchorDb.managedUberTooltipsActive = nil
    tooltipAnchorDb.managedUberTooltipsOriginal = nil
  end
end

-- 返回 modules[moduleId] 表；若不存在则从 defaults 拷贝一份，保证字段齐全
-- 注意：SavedVariables 在全部脚本执行完后才写入全局 ToolboxDB；模块文件顶层若调用 GetModule，须先保证表存在（与 GetGlobal 一致）。
function Toolbox.Config.GetModule(moduleId)
  if not ToolboxDB then
    ToolboxDB = {}
  end
  ToolboxDB.modules = ToolboxDB.modules or {}
  if not ToolboxDB.modules[moduleId] then
    local d = defaults.modules[moduleId]
    if type(d) == "table" then
      ToolboxDB.modules[moduleId] = CopyTable(d)
    else
      ToolboxDB.modules[moduleId] = {}
    end
  end
  return ToolboxDB.modules[moduleId]
end

--- 将某个模块的存档重置为默认值，并返回新的模块表。
---@param moduleId string 模块 id
---@return table
function Toolbox.Config.ResetModule(moduleId)
  ToolboxDB = ToolboxDB or {}
  ToolboxDB.modules = ToolboxDB.modules or {}
  local d = defaults.modules[moduleId]
  if type(d) == "table" then
    ToolboxDB.modules[moduleId] = CopyTable(d)
  else
    ToolboxDB.modules[moduleId] = {}
  end
  return ToolboxDB.modules[moduleId]
end
