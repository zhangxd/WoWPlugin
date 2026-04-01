--[[
  全球化：Toolbox.L 由 Locale_Apply() 根据存档 global.locale 与 GetLocale() 生成。
  可选 "auto" | "zhCN" | "enUS"；新增语言时扩展下方表与 GetEffectiveBundleCode。
]]

local enUS = {
  SETTINGS_CATEGORY_TITLE = "Toolbox",
  GAMEMENU_TOOLBOX = "Toolbox",
  ERR_SETTINGS_API = "Retail Settings API required (RegisterCanvasLayoutCategory).",

  LOCALE_SECTION_TITLE = "Language",
  LOCALE_OPTION_AUTO = "Auto (follow game client)",
  LOCALE_OPTION_ZHCN = "Simplified Chinese",
  LOCALE_OPTION_ENUS = "English",
  LOCALE_HINT = "Changing language refreshes this panel and the ESC menu button text.",

  SETTINGS_RELOAD_UI = "Reload UI",
  SETTINGS_RELOAD_HINT = "Reloads the game interface. Use after changing addon files or to apply some settings immediately.",

  SETTINGS_PREVIEW_TITLE = "Live preview",
  SETTINGS_PREVIEW_INTRO = "Try the options above, then use this area to preview tooltip anchoring and read the window-move hint.",
  SETTINGS_PREVIEW_TOOLTIP_SUB = "Tooltip anchor",
  SETTINGS_PREVIEW_TOOLTIP_BTN = "Hover for sample tooltip",
  SETTINGS_PREVIEW_TOOLTIP_LINE1 = "Toolbox · sample tooltip",
  SETTINGS_PREVIEW_TOOLTIP_LINE2 = "Move the mouse — cursor/follow modes update while this tip is open.",
  SETTINGS_PREVIEW_MOVER = "Window move: enable \"Show demo panel\" under Window Move, then drag the sample window by its title bar.",

  LOAD_COMPLETE_MSG = "Load complete. |cff888888/toolbox|r — open settings.",

  MODULE_CHAT_NOTIFY = "Chat",
  CHAT_NOTIFY_ENABLE = "Show a message in chat when the addon finishes loading",
  CHAT_NOTIFY_HINT = "Uses the default chat frame. Reload UI (or relog) after toggling to verify.",

  MODULE_MOVER = "Window Move",
  MODULE_MICROMENU = "Micro Menu Panels",
  MODULE_TOOLTIP = "Tooltip Position",

  MOVER_ENABLE = "Enable dragging for this addon's windows",
  MOVER_DEMO_VISIBLE = "Show demo panel (for testing window move)",
  MOVER_RESET_DEMO = "Reset demo panel position",
  MOVER_HINT = "Only affects windows created by this addon; Blizzard UI is handled by the Micro Menu module.",
  DEMO_TITLE_BAR = "Toolbox · Drag demo (drag title bar)",
  DEMO_BTN_A = "Demo A",
  DEMO_BTN_B = "Demo B",

  MICROMENU_ENABLE = "Enable: drag main panels opened from the micro menu and save position",
  MICROMENU_HINT = "Built-in list is in MicroMenuPanels.lua. Does not move the micro button bar. Protected UIs (e.g. store) cannot be dragged.",
  MICROMENU_EXTRA_LABEL = "Extra frame names (one per line, global name from /fstack):",
  MICROMENU_EXTRA_APPLY = "Apply extra list",
  MICROMENU_EXTRA_SAVED = "Extra frame list saved. Hooks refreshed.",
  MICROMENU_EXTRA_HINT = "Use /fstack on the window border to read the top-level frame name. Lines starting with # are ignored. Then /reload if a panel still ignores drag.",
  MICROMENU_SLASH_MMADD_USAGE = "Usage: |cff888888/toolbox mmadd FrameName|r (e.g. name from /fstack)",
  MICROMENU_ADD_OK_FMT = "Added extra frame: %s",
  MICROMENU_ADD_ERR_INVALID = "Invalid frame name (letters, digits, underscore only).",
  MICROMENU_ADD_ERR_BUILTIN = "That name is already in the built-in list.",
  MICROMENU_ADD_ERR_DUP = "That name is already in the extra list.",

  TOOLTIP_ENABLE = "Enable custom tooltip anchor",
  TOOLTIP_MODE_DEFAULT = "Game default (when enabled + this option, do not override)",
  TOOLTIP_MODE_CURSOR = "Near cursor (follows while tooltip is visible)",
  TOOLTIP_MODE_FOLLOW = "Follow cursor (same behavior; kept for saved settings)",
  TOOLTIP_OFFSET_X = "Horizontal offset:",
  TOOLTIP_OFFSET_Y = "Vertical offset:",
  TOOLTIP_HINT = "Tooltip anchors to the bottom-right of the cursor (with edge clamping). Extra X/Y offset is added on top. May stack with Interface · Mouse options; switch to default if something breaks.",

  MODULE_SAVED_INSTANCES = "Saved instances",
  SAVED_INST_TITLE = "Toolbox · Saved instances",
  SAVED_INST_ENABLE = "Enable saved instance browser",
  SAVED_INST_OPEN_PANEL = "Open panel",
  SAVED_INST_OPEN_EJ = "Open Adventure Guide",
  SAVED_INST_SETTINGS_HINT_EJ = "Lockouts and mount filters are shown inside the Adventure Guide (Encounter Journal). Slash: |cff888888/toolbox instances|r opens the guide.",
  SAVED_INST_EJ_MOUNT_FILTER = "Mounts only (instances)",
  SAVED_INST_EJ_LOOT_MOUNTS = "Mounts only (list & loot)",
  SAVED_INST_EJ_HOOK_FAIL = "Toolbox: Could not hook Adventure Guide. Update the addon after a WoW patch.",
  SAVED_INST_EJ_OPT = "Show Toolbox button on Encounter Journal",
  SAVED_INST_SETTINGS_HINT = "Lockouts and filters appear inside the Adventure Guide. Slash: |cff888888/toolbox instances|r opens the guide.",
  SAVED_INST_FILTER_LABEL = "Filter",
  SAVED_INST_FILTER_ALL = "All",
  SAVED_INST_FILTER_DUNGEON = "Dungeons",
  SAVED_INST_FILTER_RAID = "Raids",
  SAVED_INST_TIER_LABEL = "Expansion",
  SAVED_INST_TIER_ALL = "All",
  SAVED_INST_SECTION_BOSSES = "Bosses",
  SAVED_INST_SECTION_MOUNTS = "Mounts",
  SAVED_INST_SECTION_PETS = "Battle pets",
  SAVED_INST_SECTION_TOYS = "Toys",
  SAVED_INST_SECTION_LOOT = "Loot (sample)",
  SAVED_INST_LABEL_RESET = "Time to reset",
  SAVED_INST_LABEL_PROGRESS = "Encounter progress",
  SAVED_INST_LABEL_TYPE = "Type",
  SAVED_INST_TYPE_RAID = "Raid",
  SAVED_INST_TYPE_DUNGEON = "Dungeon",
  SAVED_INST_SELECT_HINT = "Select an instance on the left.",
  SAVED_INST_LOADING = "Loading…",
  SAVED_INST_NO_JOURNAL = "Could not resolve journal ID for this lockout.",
  SAVED_INST_SCAN_FAIL = "Could not scan loot (Encounter Journal data unavailable).",
  SAVED_INST_NO_MOUNTS = "No mount drops listed for this instance.",
  SAVED_INST_NO_LOOT = "No loot entries (or list empty).",
  SAVED_INST_EMPTY = "No matching lockouts.",
  SAVED_INST_MOUNT_OWNED = "[Learned]",
  SAVED_INST_MOUNT_MISSING = "[Not learned]",
  SAVED_INST_BTN_MAP = "World map",
  SAVED_INST_BTN_JOURNAL = "Encounter Journal",
  SAVED_INST_MSG_MAP_FAIL = "Could not open the world map (invalid map id).",
  SAVED_INST_MSG_NO_MAP = "No map id yet — select an instance and wait for data to load.",
  SAVED_INST_MSG_NO_JOURNAL = "No journal instance id — cannot open the Encounter Journal to this dungeon.",
  SAVED_INST_DISABLED = "Saved instance module is disabled in settings.",
  SAVED_INST_EJ_BUTTON = "Toolbox",
  SAVED_INST_ERR_UI = "Could not open the Adventure Guide (saved instances): %s",
  SAVED_INST_SLASH_MISSING = "Saved Instances module did not load. Check chat for Lua errors and /reload.",
}

local zhCN = {
  SETTINGS_CATEGORY_TITLE = "工具箱",
  GAMEMENU_TOOLBOX = "工具箱",
  ERR_SETTINGS_API = "需要正式服 Settings API（RegisterCanvasLayoutCategory）。",

  LOCALE_SECTION_TITLE = "界面语言",
  LOCALE_OPTION_AUTO = "自动（跟随游戏客户端）",
  LOCALE_OPTION_ZHCN = "简体中文",
  LOCALE_OPTION_ENUS = "English",
  LOCALE_HINT = "切换后将刷新本页与 ESC 菜单中「工具箱」按钮文字。",

  SETTINGS_RELOAD_UI = "重载界面",
  SETTINGS_RELOAD_HINT = "重新加载游戏界面。修改插件文件后、或需要让部分设置立刻生效时使用。",

  SETTINGS_PREVIEW_TITLE = "效果预览",
  SETTINGS_PREVIEW_INTRO = "调整上方各模块选项后，可在此预览提示框锚点并查看窗口拖动说明。",
  SETTINGS_PREVIEW_TOOLTIP_SUB = "提示框锚点",
  SETTINGS_PREVIEW_TOOLTIP_BTN = "鼠标悬停显示示例提示框",
  SETTINGS_PREVIEW_TOOLTIP_LINE1 = "工具箱 · 示例提示",
  SETTINGS_PREVIEW_TOOLTIP_LINE2 = "保持悬停并移动鼠标，可感受「贴近鼠标」等模式下的跟随效果。",
  SETTINGS_PREVIEW_MOVER = "窗口拖动：在「窗口拖动」中勾选「显示示例面板」，可拖动屏幕上的示例窗口（拖标题栏）。",

  LOAD_COMPLETE_MSG = "加载完成。|cff888888/toolbox|r — 打开设置",

  MODULE_CHAT_NOTIFY = "聊天提示",
  CHAT_NOTIFY_ENABLE = "插件加载完成后在聊天窗口输出一行提示",
  CHAT_NOTIFY_HINT = "使用默认聊天框输出；关闭后需重载界面或下次登录生效。",

  MODULE_MOVER = "窗口拖动",
  MODULE_MICROMENU = "微型菜单面板",
  MODULE_TOOLTIP = "提示框位置",

  MOVER_ENABLE = "启用本插件窗口拖动",
  MOVER_DEMO_VISIBLE = "显示示例面板（用于测试窗口拖动）",
  MOVER_RESET_DEMO = "重置示例面板位置",
  MOVER_HINT = "仅影响本插件创建的窗口；暴雪界面由「微型菜单面板」模块处理。",
  DEMO_TITLE_BAR = "工具箱 · 拖动示例（拖标题栏）",
  DEMO_BTN_A = "示例按钮 A",
  DEMO_BTN_B = "示例按钮 B",

  MICROMENU_ENABLE = "启用：可拖动微型菜单打开的主界面并记忆位置",
  MICROMENU_HINT = "内置名单见 MicroMenuPanels.lua；不包含微型按钮条。商城等受保护界面无法拖动。",
  MICROMENU_EXTRA_LABEL = "额外窗体（每行一个全局名，来自 /fstack 顶层）：",
  MICROMENU_EXTRA_APPLY = "应用额外列表",
  MICROMENU_EXTRA_SAVED = "已保存额外窗体列表并刷新挂钩。",
  MICROMENU_EXTRA_HINT = "在窗口边缘开 /fstack 查看顶层 Frame 名；以 # 开头的行视为注释。若仍不能拖可 /reload 后再试。",
  MICROMENU_SLASH_MMADD_USAGE = "用法：|cff888888/toolbox mmadd 框架名|r（与 /fstack 中一致）",
  MICROMENU_ADD_OK_FMT = "已加入额外窗体：%s",
  MICROMENU_ADD_ERR_INVALID = "框架名无效（仅字母、数字、下划线）。",
  MICROMENU_ADD_ERR_BUILTIN = "该名已在内置白名单中。",
  MICROMENU_ADD_ERR_DUP = "该名已在额外列表中。",

  TOOLTIP_ENABLE = "启用自定义提示框锚点",
  TOOLTIP_MODE_DEFAULT = "游戏默认锚点（启用总开关且选此项时不覆盖）",
  TOOLTIP_MODE_CURSOR = "贴近鼠标（显示期间持续跟随）",
  TOOLTIP_MODE_FOLLOW = "跟随鼠标（与上一项效果相同，兼容旧存档）",
  TOOLTIP_OFFSET_X = "水平偏移：",
  TOOLTIP_OFFSET_Y = "垂直偏移：",
  TOOLTIP_HINT = "提示框锚在光标右下方（贴屏幕边缘时会自动内推）。下方偏移为在默认位置上的额外微调；与「界面·鼠标」等可能叠加，异常时请切回游戏默认。",

  MODULE_SAVED_INSTANCES = "副本进度",
  SAVED_INST_TITLE = "工具箱 · 副本进度",
  SAVED_INST_ENABLE = "启用副本进度与掉落浏览",
  SAVED_INST_OPEN_PANEL = "打开面板",
  SAVED_INST_OPEN_EJ = "打开冒险指南",
  SAVED_INST_SETTINGS_HINT_EJ = "锁定与坐骑筛选已并入冒险指南（地下城手册）。命令 |cff888888/toolbox instances|r 会打开指南。",
  SAVED_INST_EJ_MOUNT_FILTER = "仅坐骑副本",
  SAVED_INST_EJ_LOOT_MOUNTS = "仅坐骑（列表与战利品）",
  SAVED_INST_EJ_HOOK_FAIL = "Toolbox：无法挂接冒险指南，小版本更新后请更新插件。",
  SAVED_INST_EJ_OPT = "在冒险手册上显示工具箱按钮",
  SAVED_INST_SETTINGS_HINT = "锁定与筛选已并入冒险指南。命令：|cff888888/toolbox instances|r 或 |cff888888/toolbox cd|r 可打开指南。",
  SAVED_INST_FILTER_LABEL = "筛选",
  SAVED_INST_FILTER_ALL = "全部",
  SAVED_INST_FILTER_DUNGEON = "地下城",
  SAVED_INST_FILTER_RAID = "团队副本",
  SAVED_INST_TIER_LABEL = "资料片",
  SAVED_INST_TIER_ALL = "全部",
  SAVED_INST_SECTION_BOSSES = "首领",
  SAVED_INST_SECTION_MOUNTS = "坐骑掉落",
  SAVED_INST_SECTION_PETS = "宠物",
  SAVED_INST_SECTION_TOYS = "玩具",
  SAVED_INST_SECTION_LOOT = "掉落（节选）",
  SAVED_INST_LABEL_RESET = "重置剩余",
  SAVED_INST_LABEL_PROGRESS = "首领进度",
  SAVED_INST_LABEL_TYPE = "类型",
  SAVED_INST_TYPE_RAID = "团队副本",
  SAVED_INST_TYPE_DUNGEON = "地下城",
  SAVED_INST_SELECT_HINT = "请从左侧选择一条锁定记录。",
  SAVED_INST_LOADING = "加载中…",
  SAVED_INST_NO_JOURNAL = "无法解析该锁定对应的手册实例 ID。",
  SAVED_INST_SCAN_FAIL = "无法扫描掉落（冒险手册数据不可用或未加载）。",
  SAVED_INST_NO_MOUNTS = "手册中未列出坐骑掉落。",
  SAVED_INST_NO_LOOT = "无掉落条目或列表为空。",
  SAVED_INST_EMPTY = "没有符合筛选的锁定记录。",
  SAVED_INST_MOUNT_OWNED = "[已学会]",
  SAVED_INST_MOUNT_MISSING = "[未学会]",
  SAVED_INST_BTN_MAP = "世界地图",
  SAVED_INST_BTN_JOURNAL = "冒险手册",
  SAVED_INST_MSG_MAP_FAIL = "无法打开世界地图（地图 ID 无效）。",
  SAVED_INST_MSG_NO_MAP = "尚无地图 ID — 请先选择实例并等待数据加载。",
  SAVED_INST_MSG_NO_JOURNAL = "无手册实例 ID，无法定位到该副本。",
  SAVED_INST_DISABLED = "副本进度模块已在设置中关闭。",
  SAVED_INST_EJ_BUTTON = "工具箱",
  SAVED_INST_ERR_UI = "无法打开冒险指南（副本进度）：%s",
  SAVED_INST_SLASH_MISSING = "副本进度模块未加载，请查看聊天中的 Lua 报错并重载（/reload）。",
  SAVED_INST_SLASH_OPEN_EJ = "已打开冒险指南，坐骑与副本筛选在指南界面内。",
}

-- 游戏客户端语言 -> 本插件使用的文案包（zhCN 或 enUS）
local function gameLocaleToBundleCode()
  local code = GetLocale()
  if code == "zhCN" or code == "zhTW" then
    return "zhCN"
  end
  return "enUS"
end

-- 当前应使用的文案包代码（仅 zhCN / enUS 两套表）
function Toolbox.Locale_GetEffectiveBundleCode()
  local g = ToolboxDB and ToolboxDB.global
  local pref = (g and g.locale) or "auto"
  if pref == "auto" then
    return gameLocaleToBundleCode()
  end
  if pref == "zhCN" or pref == "enUS" then
    return pref
  end
  return "enUS"
end

-- 重建 Toolbox.L（替换表引用，调用方请始终读 Toolbox.L 勿缓存旧表）
function Toolbox.Locale_Apply()
  Toolbox_NamespaceEnsure()
  local bundle = Toolbox.Locale_GetEffectiveBundleCode()
  local out = {}
  for k, v in pairs(enUS) do
    out[k] = v
  end
  if bundle == "zhCN" then
    for k, v in pairs(zhCN) do
      out[k] = v
    end
  end
  Toolbox.L = out

  if Toolbox.Mover and Toolbox.Mover.RefreshDemoLocale then
    Toolbox.Mover.RefreshDemoLocale()
  end
  if Toolbox._gameMenuBtn then
    Toolbox._gameMenuBtn:SetText(Toolbox.L.GAMEMENU_TOOLBOX)
  end
  if Toolbox.SavedInstances and Toolbox.SavedInstances.RefreshLocale then
    Toolbox.SavedInstances.RefreshLocale()
  end
end

-- 占位；在 Bootstrap 中于 DB.Init() 之后调用 Locale_Apply() 填充
Toolbox.L = {}
