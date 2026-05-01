--[[
  模块 navigation：世界地图目标导航与跨地图路径规划。
  当前文件只负责模块注册、设置页与开关回调；路径算法在 Core/API/Navigation.lua。
]]

local MODULE_ID = "navigation"

--- 安装世界地图入口。
local function installWorldMapEntry()
  local worldMap = Toolbox.NavigationModule and Toolbox.NavigationModule.WorldMap or nil -- 世界地图入口模块
  if worldMap and type(worldMap.Install) == "function" then
    worldMap.Install()
  end
end

--- 隐藏 navigation 创建的玩家可见 UI。
local function hideNavigationUi()
  local navigationModule = Toolbox.NavigationModule or {} -- navigation 模块内部命名空间
  local worldMap = navigationModule.WorldMap -- 世界地图入口模块
  local routeBar = navigationModule.RouteBar -- 顶部路径条模块
  if worldMap and type(worldMap.Hide) == "function" then
    worldMap.Hide()
  end
  if routeBar and type(routeBar.ClearRoute) == "function" then
    routeBar.ClearRoute()
  end
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_NAVIGATION",
  settingsIntroKey = "MODULE_NAVIGATION_INTRO",
  settingsOrder = 70,
  OnModuleEnable = function()
    installWorldMapEntry()
  end,
  OnEnabledSettingChanged = function(enabled)
    local localeTable = Toolbox.L or {} -- 本地化字符串表
    local title = localeTable.MODULE_NAVIGATION or MODULE_ID -- 模块显示名
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT" -- 状态文案键
    if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage then
      Toolbox.Chat.PrintAddonMessage(string.format(localeTable[key] or "%s", title))
    end
    if enabled then
      installWorldMapEntry()
    else
      hideNavigationUi()
    end
  end,
  OnDebugSettingChanged = function(enabled)
    local localeTable = Toolbox.L or {} -- 本地化字符串表
    local title = localeTable.MODULE_NAVIGATION or MODULE_ID -- 模块显示名
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT" -- 调试文案键
    if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage then
      Toolbox.Chat.PrintAddonMessage(string.format(localeTable[key] or "%s", title))
    end
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
  end,
  RegisterSettings = function(box)
    local localeTable = Toolbox.L or {} -- 本地化字符串表
    box:AddNoteRow({
      text = localeTable.NAVIGATION_SETTINGS_HINT or "",
    })
  end,
})
