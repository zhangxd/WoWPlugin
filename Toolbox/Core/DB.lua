--[[
  SavedVariables：ToolboxDB 默认值与迁移。
  各模块只应通过 GetModule(moduleId) 读写 modules[moduleId]，避免键冲突。
]]

local defaults = {
  version = 1,
  global = {
    debug = false,
    -- auto：跟随游戏客户端；zhCN / enUS：强制界面语言
    locale = "auto",
    -- 旧版单页设置的折叠状态；保留旧档兼容，当前子页面设置树不再使用
    settingsGroupsExpanded = {},
    -- 冒险手册驱动的地下城 / 团队副本共享目录缓存；角色锁定不落在这里
    dungeonRaidDirectory = {
      schemaVersion = 1,
      interfaceBuild = 0,
      lastBuildAt = 0,
      tierNames = {},
      difficultyMeta = {},
      records = {},
    },
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
      -- 遗留键；已不再合并至 mover
      extraFrameNames = {},
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
      flyoutSlotIds = { "reload_ui" },
    },
    chat_notify = {
      enabled = true,
      debug = false,
      -- 前缀颜色（不含 |cff），默认金黄色 ffd700
      prefixColor = "ffd700",
      -- 正文颜色（不含 |cff）；PrintAddonMessage 将正文包在 |cff 内，默认白色 ffffff
      contentColor = "ffffff",
    },
    dungeon_raid_directory = {
      enabled = true,
      debug = false,
    },
    -- 冒险指南「仅坐骑」筛选：仅保存勾选与调试开关；掉落数据统一来自 DungeonRaidDirectory
    ej_mount_filter = {
      enabled = false,
      -- 为 true 时在聊天框输出筛选/遍历/扫描调试信息（见 Locales EJ_MOUNT_FILTER_DEBUG_*）
      debug = false,
    },
  },
}

-- 将 src 中缺失键合并进 dst；嵌套表递归合并，不覆盖用户已有标量
local function mergeTable(dst, src)
  if type(dst) ~= "table" then return CopyTable(src) end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      mergeTable(dst[k], v)
    elseif dst[k] == nil then
      if type(v) == "table" then
        dst[k] = CopyTable(v)
      else
        dst[k] = v
      end
    end
  end
  return dst
end

-- ADDON_LOADED 时调用；SavedVariables 已由客户端载入到 ToolboxDB
-- 全局杂项配置（非 modules.*）；须在本插件 DB.Init 之后使用，以保证已 merge 默认值
function Toolbox.DB.GetGlobal()
  if not ToolboxDB then
    ToolboxDB = {}
  end
  ToolboxDB.global = ToolboxDB.global or {}
  return ToolboxDB.global
end

function Toolbox.DB.Init()
  if not ToolboxDB then
    ToolboxDB = CopyTable(defaults)
    return
  end
  ToolboxDB.global = ToolboxDB.global or {}
  ToolboxDB.modules = ToolboxDB.modules or {}
  mergeTable(ToolboxDB, defaults)

  -- 旧版 global.notifyLoadComplete=false 迁移到 modules.chat_notify.enabled
  if ToolboxDB.global and ToolboxDB.global.notifyLoadComplete == false then
    ToolboxDB.modules.chat_notify = ToolboxDB.modules.chat_notify or {}
    ToolboxDB.modules.chat_notify.enabled = false
  end

  -- 目录调试旧键：global.dungeonRaidDirectoryDebugChat -> modules.dungeon_raid_directory.debug
  if ToolboxDB.global and ToolboxDB.global.dungeonRaidDirectoryDebugChat ~= nil then
    ToolboxDB.modules.dungeon_raid_directory = ToolboxDB.modules.dungeon_raid_directory or {}
    if ToolboxDB.modules.dungeon_raid_directory.debug == nil then
      ToolboxDB.modules.dungeon_raid_directory.debug = ToolboxDB.global.dungeonRaidDirectoryDebugChat == true
    end
    ToolboxDB.global.dungeonRaidDirectoryDebugChat = nil
  end

  -- micromenu_panels 存档并入 mover（一次性）
  do
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
  end

  -- mover：丢弃已废弃键 demoVisible、frames.demo、dragBlizzardPanels（暴雪拖动改由 enabled 总控）
  do
    local mv = ToolboxDB.modules and ToolboxDB.modules.mover
    if type(mv) == "table" then
      mv.demoVisible = nil
      mv.dragBlizzardPanels = nil
      if type(mv.frames) == "table" then
        mv.frames.demo = nil
      end
    end
  end

  -- mover：移除已废弃的冲突/检测相关存档键（每次载入清理，缩小 SavedVariables）
  do
    local mv = ToolboxDB.modules and ToolboxDB.modules.mover
    if type(mv) == "table" then
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
  end

  -- ej_mount_filter 调试旧键：debugChat -> debug
  if ToolboxDB.modules and ToolboxDB.modules.ej_mount_filter then
    local ejDb = ToolboxDB.modules.ej_mount_filter
    if ejDb.debug == nil and ejDb.debugChat ~= nil then
      ejDb.debug = ejDb.debugChat == true
    end
    ejDb.debugChat = nil
  end

  local ver = ToolboxDB.version or 0
  if ver < 1 then
    ToolboxDB.version = 1
  end
  -- 已移除 hitinsets 模块；旧存档中的键可丢弃
  if ToolboxDB.modules and ToolboxDB.modules.hitinsets then
    ToolboxDB.modules.hitinsets = nil
  end
end

-- 返回 modules[moduleId] 表；若不存在则从 defaults 拷贝一份，保证字段齐全
-- 注意：SavedVariables 在全部脚本执行完后才写入全局 ToolboxDB；模块文件顶层若调用 GetModule，须先保证表存在（与 GetGlobal 一致）。
function Toolbox.DB.GetModule(moduleId)
  if not ToolboxDB then
    ToolboxDB = {}
  end
  ToolboxDB.modules = ToolboxDB.modules or {}
  if not ToolboxDB.modules[moduleId] then
    ToolboxDB.modules[moduleId] = Toolbox.DB.CopyModuleDefaults(moduleId)
  end
  return ToolboxDB.modules[moduleId]
end

--- 返回某个模块的默认值副本；无默认值时返回空表。
---@param moduleId string 模块 id
---@return table
function Toolbox.DB.CopyModuleDefaults(moduleId)
  local d = defaults.modules[moduleId]
  if type(d) == "table" then
    return CopyTable(d)
  end
  return {}
end

--- 将某个模块的存档重置为默认值，并返回新的模块表。
---@param moduleId string 模块 id
---@return table
function Toolbox.DB.ResetModule(moduleId)
  ToolboxDB = ToolboxDB or {}
  ToolboxDB.modules = ToolboxDB.modules or {}
  ToolboxDB.modules[moduleId] = Toolbox.DB.CopyModuleDefaults(moduleId)
  return ToolboxDB.modules[moduleId]
end

--- 返回某个全局默认键的副本；表值会深拷贝，标量直接返回。
---@param key string global 下的键名
---@return any
function Toolbox.DB.CopyGlobalDefault(key)
  local value = defaults.global[key]
  if type(value) == "table" then
    return CopyTable(value)
  end
  return value
end
