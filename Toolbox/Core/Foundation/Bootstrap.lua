--[[
  插件入口：事件与斜杠。
  ADDON_LOADED：SV 已就绪，可注册 Settings、构建设置 UI（不依赖角色）。
  PLAYER_LOGIN：角色数据可用，再启用需进世界的模块（示例窗、微型菜单 Hook 等）。
  加载完成聊天提示：在本事件处理末尾调用 ChatNotify.PrintLoadComplete()（实现见 Modules/ChatNotify.lua，输出经 Toolbox.Chat）。
]]

local ADDON_NAME = "Toolbox"

-- 辅助函数：处理 /toolbox instances 命令
local function handleInstancesCommand()
  local ok, err = pcall(function()
    local ejName = "Blizzard_EncounterJournal"
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ejName) then
      -- 已加载
    elseif C_AddOns and C_AddOns.LoadAddOn then
      pcall(C_AddOns.LoadAddOn, ejName)
    elseif LoadAddOn then
      LoadAddOn(ejName)
    end
    if ToggleEncounterJournal then
      ToggleEncounterJournal()
    end
  end)
  if not ok then
    local L = Toolbox.L or {}
    Toolbox.Chat.PrintAddonMessage(string.format(L.SAVED_INST_ERR_UI or "%s", tostring(err)))
  end
end

-- 辅助函数：处理 /toolbox mmadd 命令
local function handleMmaddCommand()
  local L = Toolbox.L or {}
  Toolbox.Chat.PrintAddonMessage(L.MICROMENU_MMADD_REMOVED or "")
end

-- 辅助函数：注册斜杠命令
local function registerSlashCommand()
  SLASH_TOOLBOX1 = "/toolbox"
  SlashCmdList["TOOLBOX"] = function(msg)
    Toolbox_NamespaceEnsure()
    local m = (msg or ""):match("^%s*(.-)%s*$") or ""
    if m == "" then
      Toolbox.SettingsHost:Open()
      return
    end
    local cmd, rest = m:match("^(%S+)%s*(.*)$")
    cmd = cmd and string.lower(cmd) or ""
    if cmd == "instances" or cmd == "cd" or cmd == "saved" then
      handleInstancesCommand()
      return
    end
    if cmd == "mmadd" or cmd == "addframe" then
      handleMmaddCommand()
      return
    end
    Toolbox.SettingsHost:Open()
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" and addonName == ADDON_NAME then
    Toolbox_NamespaceEnsure()

    -- 初始化数据库
    local ok, err = pcall(Toolbox.Config.Init)
    if not ok then
      print("[Toolbox] Error in Config.Init:", err)
    end

    -- 应用语言包
    ok, err = pcall(Toolbox.Locale_Apply)
    if not ok then
      print("[Toolbox] Error in Locale_Apply:", err)
    end

    -- 运行模块加载钩子
    ok, err = pcall(Toolbox.ModuleRegistry.RunOnModuleLoad, Toolbox.ModuleRegistry)
    if not ok then
      print("[Toolbox] Error in RunOnModuleLoad:", err)
    end

    -- 构建设置界面
    ok, err = pcall(Toolbox.SettingsHost.Build, Toolbox.SettingsHost)
    if not ok then
      print("[Toolbox] Error in SettingsHost:Build:", err)
    end

    -- 注册小地图按钮目录
    if Toolbox.MinimapButton and Toolbox.MinimapButton.RegisterBuiltinFlyoutCatalog then
      ok, err = pcall(Toolbox.MinimapButton.RegisterBuiltinFlyoutCatalog)
      if not ok then
        print("[Toolbox] Error in MinimapButton.RegisterBuiltinFlyoutCatalog:", err)
      end
    end

    -- 初始化游戏菜单按钮
    ok, err = pcall(Toolbox.GameMenu_Init)
    if not ok then
      print("[Toolbox] Error in GameMenu_Init:", err)
    end

    -- 注册斜杠命令
    registerSlashCommand()

    -- 主流程末尾再通知：此时 DB、语言包、设置 UI、斜杠均已就绪；无需 C_Timer 延迟
    ok, err = pcall(Toolbox.ChatNotify.PrintLoadComplete)
    if not ok then
      print("[Toolbox] Error in ChatNotify.PrintLoadComplete:", err)
    end
  elseif event == "PLAYER_LOGIN" then
    Toolbox_NamespaceEnsure()

    -- 运行模块启用钩子
    local ok, err = pcall(Toolbox.ModuleRegistry.RunOnModuleEnable, Toolbox.ModuleRegistry)
    if not ok then
      print("[Toolbox] Error in RunOnModuleEnable:", err)
    end

    -- GameMenu 在 ADDON_LOADED 时可能尚未加载，登录后再挂 ESC 按钮
    ok, err = pcall(Toolbox.GameMenu_Init)
    if not ok then
      print("[Toolbox] Error in GameMenu_Init (PLAYER_LOGIN):", err)
    end
  end
end)
