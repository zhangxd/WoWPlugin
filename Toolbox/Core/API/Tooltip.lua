--[[
  提示框（领域对外 API）（Toolbox.Tooltip）：GameTooltip_SetDefaultAnchor 的 hook 与光标锚点逻辑。
  配置读取 modules.tooltip_anchor；业务模块 tooltip_anchor 仅负责 RegisterModule 与设置 UI。
  使用 ANCHOR_CURSOR_RIGHT 让 Blizzard 原生处理光标跟随与边界检测，避免手动定位导致的闪烁问题。
]]

Toolbox.Tooltip = Toolbox.Tooltip or {}

local MODULE_ID = "tooltip_anchor"

local hooked

local function getDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.Config.GetModule(MODULE_ID)
end

local function isDebugEnabled()
  return getDb().debug == true
end

local function debugPrint(message)
  if not isDebugEnabled() or not message or message == "" then
    return
  end
  if Toolbox.Chat and Toolbox.Chat.PrintAddonMessage then
    Toolbox.Chat.PrintAddonMessage(message)
  end
end

-- 空函数，保持接口兼容
function Toolbox.Tooltip.RefreshDriver()
  local db = getDb()
  local L = Toolbox.L or {}
  if db.enabled == false then
    debugPrint(L.TOOLTIP_DEBUG_DRIVER_OFF or "")
  else
    local mode = db.mode or "default"
    debugPrint(string.format(L.TOOLTIP_DEBUG_DRIVER_ON_FMT or "模式: %s", tostring(mode), "0", "0"))
  end
end

-- 仅调用一次：hooksecurefunc 注册 GameTooltip_SetDefaultAnchor
function Toolbox.Tooltip.InstallDefaultAnchorHook()
  if hooked then
    return
  end
  hooked = true
  hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    local db = getDb()
    if not db or db.enabled == false or db.mode ~= "cursor" then
      return
    end
    if not tooltip or not parent then
      return
    end
    -- 跳过标记为不接管的 tooltip（如 EJMountFilter 复选框，避免 ANCHOR_RIGHT 被覆盖）
    if tooltip._ToolboxSkipAnchorOverride then
      debugPrint("[SetDefaultAnchor] skip (marked)")
      return
    end
    -- 跳过受保护的提示框
    if tooltip.IsPreventingSecretValues and tooltip:IsPreventingSecretValues() then
      debugPrint("[SetDefaultAnchor] skip (secret values)")
      return
    end

    -- 使用 ANCHOR_CURSOR_RIGHT 让提示框显示在光标右下角
    tooltip:ClearAllPoints()
    tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT")
    debugPrint("[SetDefaultAnchor] ANCHOR_CURSOR_RIGHT")
  end)
end
