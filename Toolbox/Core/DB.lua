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
  },
  modules = {
    mover = {
      enabled = true,
      demoVisible = true,
      frames = {},
    },
    micromenu_panels = {
      enabled = true,
      frames = {},
      -- 额外顶层 Frame 名（与 MicroMenuPanels.lua 内置白名单合并）；用设置页或 /toolbox mmadd 添加
      extraFrameNames = {},
    },
    tooltip_anchor = {
      enabled = true,
      mode = "cursor",
      offsetX = 0,
      offsetY = 0,
    },
    chat_notify = {
      enabled = true,
    },
    saved_instances = {
      enabled = true,
      filter = "all",
      -- "all" | 数字 1..EJ_GetNumTiers()，与冒险手册「资料片」分栏（SelectTier）一致
      tierFilter = "all",
      showEncounterJournalButton = false,
      -- 已弃用：旧版「仅坐骑副本」列表筛；保留键以免旧存档报错
      mountFilterEnabled = false,
      -- 冒险手册：左侧实例列表仅坐骑 + 战利品页仅坐骑（SavedInstancesEJ）
      lootMountsOnly = false,
      mountDropByJid = {},
      mountCacheToc = 0,
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
function Toolbox.DB.GetModule(moduleId)
  ToolboxDB.modules = ToolboxDB.modules or {}
  if not ToolboxDB.modules[moduleId] then
    local d = defaults.modules[moduleId]
    if d then
      ToolboxDB.modules[moduleId] = CopyTable(d)
    else
      ToolboxDB.modules[moduleId] = {}
    end
  end
  return ToolboxDB.modules[moduleId]
end
