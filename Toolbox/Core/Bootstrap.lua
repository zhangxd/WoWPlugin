--[[
  插件入口：事件与斜杠。
  ADDON_LOADED：SV 已就绪，可注册 Settings、构建设置 UI（不依赖角色）。
  PLAYER_LOGIN：角色数据可用，再启用需进世界的模块（示例窗、微型菜单 Hook 等）。
  加载完成聊天提示：在本事件处理末尾调用 ChatNotify.PrintLoadComplete()（实现见 Modules/ChatNotify.lua，输出经 Toolbox.Chat）。
]]

local ADDON_NAME = "Toolbox"

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" and addonName == ADDON_NAME then
    Toolbox_NamespaceEnsure()
    Toolbox.DB.Init()
    Toolbox.Locale_Apply()
    Toolbox.ModuleRegistry:RunOnModuleLoad()
    Toolbox.SettingsHost:Build()
    if Toolbox.MinimapButton and Toolbox.MinimapButton.RegisterBuiltinFlyoutCatalog then
      Toolbox.MinimapButton.RegisterBuiltinFlyoutCatalog()
    end
    Toolbox.GameMenu_Init()

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
        return
      end
      if cmd == "mmadd" or cmd == "addframe" then
        local L = Toolbox.L or {}
        Toolbox.Chat.PrintAddonMessage(L.MICROMENU_MMADD_REMOVED or "")
        return
      end
      Toolbox.SettingsHost:Open()
    end

    -- 主流程末尾再通知：此时 DB、语言包、设置 UI、斜杠均已就绪；无需 C_Timer 延迟
    Toolbox.ChatNotify.PrintLoadComplete()
  elseif event == "PLAYER_LOGIN" then
    Toolbox_NamespaceEnsure()
    Toolbox.DB.Init()
    Toolbox.ModuleRegistry:RunOnModuleEnable()
    -- GameMenu 在 ADDON_LOADED 时可能尚未加载，登录后再挂 ESC 按钮
    Toolbox.GameMenu_Init()
  end
end)
