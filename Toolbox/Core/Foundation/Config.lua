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
    encounter_journal = {
      enabled = true,
      debug = false,
      mountFilterEnabled = true,
      lockoutOverlayEnabled = true,
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
      if encJournalDb.lockoutOverlayEnabled == nil and drd.ejLockoutOverlayEnabled ~= nil then
        encJournalDb.lockoutOverlayEnabled = drd.ejLockoutOverlayEnabled
      end
      if encJournalDb.enabled == nil and drd.enabled ~= nil then
        encJournalDb.enabled = drd.enabled
      end
      ToolboxDB.modules.encounter_journal = encJournalDb
      ToolboxDB.modules.dungeon_raid_directory = nil
    end

    -- 清理 encounter_journal 中遗留的旧字段名
    local encJournalDb = ToolboxDB.modules and ToolboxDB.modules.encounter_journal
    if type(encJournalDb) == "table" and encJournalDb.ejLockoutOverlayEnabled ~= nil then
      if encJournalDb.lockoutOverlayEnabled == nil then
        encJournalDb.lockoutOverlayEnabled = encJournalDb.ejLockoutOverlayEnabled
      end
      encJournalDb.ejLockoutOverlayEnabled = nil
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
