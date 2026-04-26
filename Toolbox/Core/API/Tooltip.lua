--[[
  提示框（领域对外 API）（Toolbox.Tooltip）：统一管理默认 tooltip 锚点接管。
  配置读取 modules.tooltip_anchor；业务模块 tooltip_anchor 仅负责 RegisterModule 与设置 UI。
  当前实现恢复 WoWTools 式 GameTooltip_SetDefaultAnchor 全局 post-hook。
]]

Toolbox.Tooltip = Toolbox.Tooltip or {}

local MODULE_ID = "tooltip_anchor"

local anchorOverrideSkipState = setmetatable({}, { __mode = "k" }) -- tooltip 私有跳过标记表
local defaultAnchorHookInstalled = false -- 默认锚点 hook 是否已安装

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

local function shouldOverrideDefaultAnchor(tooltip)
  local db = getDb() -- tooltip 模块存档
  local mode = db.mode -- 当前锚点模式
  if db.enabled == false then
    return false
  end
  if mode ~= "cursor" and mode ~= "follow" then
    return false
  end
  if Toolbox.Tooltip.ShouldSkipAnchorOverride(tooltip) then
    return false
  end
  return true
end

local function applyCursorAnchorOverride(tooltip, ownerFrame)
  if type(tooltip) ~= "table" or type(tooltip.SetOwner) ~= "function" then
    return
  end

  local db = getDb() -- tooltip 模块存档
  local offsetX = tonumber(db.offsetX) or 0 -- X 偏移
  local offsetY = tonumber(db.offsetY) or 0 -- Y 偏移

  if type(tooltip.ClearAllPoints) == "function" then
    tooltip:ClearAllPoints()
  end
  tooltip:SetOwner(ownerFrame, "ANCHOR_CURSOR_LEFT", offsetX, offsetY)
end

function Toolbox.Tooltip.RefreshDriver()
  local db = getDb() -- tooltip 模块存档
  if db.enabled == false or db.mode == "default" then
    debugPrint((Toolbox.L or {}).TOOLTIP_DEBUG_DRIVER_OFF or "")
    return
  end

  debugPrint(string.format(
    ((Toolbox.L or {}).TOOLTIP_DEBUG_DRIVER_ON_FMT or "mode=%s offsetX=%s offsetY=%s"),
    tostring(db.mode or "default"),
    tostring(db.offsetX or 0),
    tostring(db.offsetY or 0)
  ))
end

--- 设置是否跳过默认锚点接管。
---@param tooltip table|nil
---@param shouldSkip boolean
function Toolbox.Tooltip.SetSkipAnchorOverride(tooltip, shouldSkip)
  if type(tooltip) ~= "table" then
    return
  end
  if shouldSkip then
    anchorOverrideSkipState[tooltip] = true
  else
    anchorOverrideSkipState[tooltip] = nil
  end
end

--- 判断 tooltip 是否应跳过默认锚点接管。
---@param tooltip table|nil
---@return boolean
function Toolbox.Tooltip.ShouldSkipAnchorOverride(tooltip)
  return type(tooltip) == "table" and anchorOverrideSkipState[tooltip] == true or false
end

function Toolbox.Tooltip.InstallDefaultAnchorHook()
  if defaultAnchorHookInstalled then
    return
  end

  hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, ownerFrame)
    if not shouldOverrideDefaultAnchor(tooltip) then
      return
    end
    applyCursorAnchorOverride(tooltip, ownerFrame)
  end)

  defaultAnchorHookInstalled = true
end
