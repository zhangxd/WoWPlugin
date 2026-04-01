--[[
  提示框领域门面（Toolbox.Tooltip）：GameTooltip_SetDefaultAnchor 的 hook 与光标锚点逻辑。
  配置读取 modules.tooltip_anchor；业务模块 tooltip_anchor 仅负责 RegisterModule 与设置 UI。
  禁止在 OnUpdate 中 SetOwner，否则会清空提示文字。
]]

Toolbox.Tooltip = Toolbox.Tooltip or {}

local MODULE_ID = "tooltip_anchor"

local updateFrame
local hooked

-- 相对光标的基础偏移（BOTTOMLEFT：右下为 x+、y-）
local BASE_OFFSET_X = 12
local BASE_OFFSET_Y = -12

local FOLLOW_TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

local function getDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.DB.GetModule(MODULE_ID)
end

local function positionByCursor(tooltip, db)
  if not tooltip or not tooltip:IsShown() then
    return
  end
  pcall(function()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    local ox = (db.offsetX or 0)
    local oy = (db.offsetY or 0)
    local ax = x / s + ox + BASE_OFFSET_X
    local ay = y / s + oy + BASE_OFFSET_Y
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ax, ay)
    if tooltip.SetClampedToScreen then
      tooltip:SetClampedToScreen(true)
    end
  end)
end

local function onTooltipUpdate()
  local db = getDb()
  if not db or not db.enabled then
    return
  end
  if db.mode ~= "cursor" and db.mode ~= "follow" then
    return
  end
  for _, name in ipairs(FOLLOW_TOOLTIP_NAMES) do
    local t = _G[name]
    if t and t:IsShown() then
      positionByCursor(t, db)
    end
  end
end

-- 按当前存档挂接或关闭跟随驱动帧
function Toolbox.Tooltip.RefreshDriver()
  local db = getDb()
  if not db.enabled then
    if updateFrame then
      updateFrame:SetScript("OnUpdate", nil)
    end
    return
  end
  if db.mode == "cursor" or db.mode == "follow" then
    if not updateFrame then
      updateFrame = CreateFrame("Frame", "ToolboxTooltipFollowDriver", UIParent)
    end
    updateFrame:SetScript("OnUpdate", onTooltipUpdate)
  elseif updateFrame then
    updateFrame:SetScript("OnUpdate", nil)
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
    if not db or not db.enabled or db.mode == "default" then
      return
    end
    if db.mode == "cursor" or db.mode == "follow" then
      positionByCursor(tooltip, db)
    end
  end)
end
