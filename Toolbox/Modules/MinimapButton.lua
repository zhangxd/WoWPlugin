--[[
  模块 minimap_button：小地图上的圆形按钮（暴雪小地图图标用底图 + 边框 + 图标圆形遮罩，与 LibDBIcon 视觉一致），点击打开 Toolbox 设置总览。
  悬停时在按钮左侧展开纵向操作列（RegisterFlyoutEntry 注册项；启动后 RegisterBuiltinFlyoutCatalog 会登记各模块设置、冒险手册、关于等，设置页可拖入或「全部加入」）。
  位置算法与拖动命中与 LibDBIcon-1.0 同类：角度（度）+ 沿小地图形状约束。
  生命周期：MinimapCluster OnShow；可见性由模块启用与「显示小地图按钮」决定。
]]

--- 正式服小地图圆形图标资源（与 LibDBIcon ResetButton* 一致；边框须 TOPLEFT 对齐按钮，不能用 CENTER，否则环会错位）。
local TEX_MINIMAP_BG = "Interface\\Minimap\\UI-Minimap-Background"
local TEX_MINIMAP_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local TEX_MINIMAP_HI = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local TEX_ICON_MASK_PRIMARY = "Interface\\Minimap\\UI-Minimap-IconMask"
local TEX_ICON_MASK_FALLBACK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

Toolbox.MinimapButton = Toolbox.MinimapButton or {}

local MODULE_ID = "minimap_button"
local launcher
local minimapCoordsText  -- 小地图坐标文本
local worldMapCoordsText  -- 大地图左下角坐标文本
local coordsDriverFrame  -- 坐标刷新驱动 Frame
--- 悬停展开面板（UIParent 子级，锚在 launcher 左侧）；子级含圆形按钮与「桥接」透明层（缝补与主按钮之间的空隙，避免误触发隐藏）。
local flyoutFrame
--- 透明命中层：填补主按钮左缘与展开区右缘之间的缝，使光标移入子按钮时不会先被判定为离开。
local flyoutBridge
local flyoutHideHandle
--- 悬停菜单项（显示顺序）；由 syncFlyoutRegistryFromDb 根据 flyoutSlotIds 从 flyoutCatalog 填充。
local flyoutRegistry = {}
--- 已注册的悬停项模板 id → 定义（供 flyoutSlotIds 引用）。
local flyoutCatalog = {}
--- 方形按钮用：遮罩用全白纹理等效于不裁切圆（避免圆形 SetMask 残留）。
local TEX_MASK_SQUARE_PASS = "Interface\\Buttons\\WHITE8X8"

--- 按钮中心相对小地图「理论圆/方」半径外推像素，与 LibDBIcon lib.radius 一致。
local MINIMAP_ICON_RADIUS_EXTRA = 5

--- 默认角度（度），与 LibDBIcon 默认一致。
local DEFAULT_MINIMAP_ANGLE = 225
local MINIMAP_COORDS_ANCHOR_TOP = "top"
local MINIMAP_COORDS_ANCHOR_BOTTOM = "bottom"
local COORDS_UPDATE_INTERVAL_SEC = 0.1

local rad, cos, sin, sqrt, max, min, deg, atan2 = math.rad, math.cos, math.sin, math.sqrt, math.max, math.min, math.deg, math.atan2

--- 去掉首尾空白，避免设置框 GetText 带空格时 tonumber 失败而回退默认间距。
local function strtrim(s)
  if not s then
    return ""
  end
  return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

--- GetMinimapShape 四象限是否按椭圆弧处理（与 LibDBIcon minimapShapes 一致）。
local minimapShapes = {
  ROUND = { true, true, true, true },
  SQUARE = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

--- 按角度将按钮置于 Minimap 边缘内侧（LibDBIcon-1.0 updatePosition）。
---@param button Frame
---@param positionDeg number|nil 角度（度），nil 用默认
local function updateLauncherPositionFromAngle(button, positionDeg)
  local minimap = _G.Minimap
  if not minimap or not button then
    return
  end
  local mw, mh = minimap:GetWidth(), minimap:GetHeight()
  if not mw or not mh or mw < 8 or mh < 8 then
    return
  end
  local angle = rad(positionDeg or DEFAULT_MINIMAP_ANGLE)
  local x, y, q = cos(angle), sin(angle), 1
  if x < 0 then
    q = q + 1
  end
  if y > 0 then
    q = q + 2
  end
  local shapeName = "ROUND"
  if _G.GetMinimapShape then
    local ok, s = pcall(_G.GetMinimapShape)
    if ok and s and minimapShapes[s] then
      shapeName = s
    end
  end
  local quadTable = minimapShapes[shapeName] or minimapShapes.ROUND
  local w = (minimap:GetWidth() / 2) + MINIMAP_ICON_RADIUS_EXTRA
  local h = (minimap:GetHeight() / 2) + MINIMAP_ICON_RADIUS_EXTRA
  if quadTable[q] then
    x, y = x * w, y * h
  else
    local diagRadiusW = sqrt(2 * w * w) - 10
    local diagRadiusH = sqrt(2 * h * h) - 10
    x = max(-w, min(x * diagRadiusW, w))
    y = max(-h, min(y * diagRadiusH, h))
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

--- 是否应显示小地图按钮。
---@return boolean
local function shouldShowLauncher()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  if db.enabled == false then
    return false
  end
  if db.showMinimapButton == false then
    return false
  end
  return true
end

--- 拖动中根据光标更新角度并存档（LibDBIcon OnUpdate：光标用 Minimap:GetEffectiveScale()）。
local function onDragPositionUpdate(self)
  local minimap = _G.Minimap
  if not minimap then
    return
  end
  local mx, my = minimap:GetCenter()
  if not mx or not my then
    return
  end
  local px, py = GetCursorPosition()
  local scale = minimap:GetEffectiveScale()
  px = px / scale
  py = py / scale
  local pos = deg(atan2(py - my, px - mx)) % 360
  local db = Toolbox.Config.GetModule(MODULE_ID)
  db.minimapPos = pos
  updateLauncherPositionFromAngle(self, pos)
end

--- 打开 Toolbox 设置总览。
local function openSettings()
  Toolbox_NamespaceEnsure()
  if Toolbox.SettingsHost and Toolbox.SettingsHost.Open then
    pcall(function()
      Toolbox.SettingsHost:Open()
    end)
  end
end

--- 旧版 offset 存档迁移为 minimapPos（度）。
local function migrateLegacyMinimapDb()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  if db.minimapPos ~= nil then
    db.useCustomPosition = nil
    db.offsetX = nil
    db.offsetY = nil
    return
  end
  if db.useCustomPosition and (tonumber(db.offsetX) or tonumber(db.offsetY)) then
    local ox = tonumber(db.offsetX) or 0
    local oy = tonumber(db.offsetY) or 0
    if ox ~= 0 or oy ~= 0 then
      db.minimapPos = deg(atan2(oy, ox)) % 360
    end
  end
  db.useCustomPosition = nil
  db.offsetX = nil
  db.offsetY = nil
end

--- 按存档放置按钮。
local function applyLauncherPosition()
  if not launcher then
    return
  end
  local db = Toolbox.Config.GetModule(MODULE_ID)
  local angle = db.minimapPos
  if angle == nil then
    angle = DEFAULT_MINIMAP_ANGLE
  end
  updateLauncherPositionFromAngle(launcher, angle)
end

--- 返回小地图坐标锚点（top / bottom）；非法值回退 bottom 并写档。
---@return string
local function getMinimapCoordsAnchor()
  local db = Toolbox.Config.GetModule(MODULE_ID)  -- 小地图按钮模块存档
  local anchor = db.minimapCoordsAnchor  -- 小地图坐标锚点字符串
  if anchor ~= MINIMAP_COORDS_ANCHOR_TOP and anchor ~= MINIMAP_COORDS_ANCHOR_BOTTOM then
    anchor = MINIMAP_COORDS_ANCHOR_BOTTOM
    db.minimapCoordsAnchor = anchor
  end
  return anchor
end

--- 获取玩家当前最佳地图 id。
---@return number|nil
local function getPlayerBestMapID()
  if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or type(mapID) ~= "number" or mapID <= 0 then
    return nil
  end
  return mapID
end

--- 读取指定地图下玩家归一化坐标（0~1）。
---@param mapID number|nil
---@return number|nil, number|nil
local function getPlayerNormalizedCoords(mapID)
  if type(mapID) ~= "number" or mapID <= 0 then
    return nil, nil
  end
  if not C_Map or type(C_Map.GetPlayerMapPosition) ~= "function" then
    return nil, nil
  end
  local ok, mapPos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not ok or not mapPos then
    return nil, nil
  end
  local posX = mapPos.x  -- 玩家坐标 X（0~1）
  local posY = mapPos.y  -- 玩家坐标 Y（0~1）
  if type(posX) ~= "number" or type(posY) ~= "number" then
    return nil, nil
  end
  return posX, posY
end

--- 读取当前大地图显示地图 id。
---@return number|nil
local function getWorldMapShownMapID()
  local worldMapFrame = _G.WorldMapFrame  -- 大地图根 Frame
  if not worldMapFrame or type(worldMapFrame.GetMapID) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(worldMapFrame.GetMapID, worldMapFrame)
  if not ok or type(mapID) ~= "number" or mapID <= 0 then
    return nil
  end
  return mapID
end

--- 读取大地图当前鼠标归一化坐标（0~1）；鼠标不在地图区域时返回 nil。
---@return number|nil, number|nil
local function getWorldMapMouseNormalizedCoords()
  local worldMapFrame = _G.WorldMapFrame  -- 大地图根 Frame
  if not worldMapFrame or not worldMapFrame:IsShown() then
    return nil, nil
  end
  local scrollFrame = worldMapFrame.ScrollContainer  -- 地图滚动容器
  if not scrollFrame or type(scrollFrame.GetNormalizedCursorPosition) ~= "function" then
    return nil, nil
  end
  if type(scrollFrame.IsMouseOver) == "function" and not scrollFrame:IsMouseOver() then
    return nil, nil
  end
  local ok, posX, posY = pcall(scrollFrame.GetNormalizedCursorPosition, scrollFrame)
  if not ok or type(posX) ~= "number" or type(posY) ~= "number" then
    return nil, nil
  end
  if posX < 0 or posX > 1 or posY < 0 or posY > 1 then
    return nil, nil
  end
  return posX, posY
end

--- 将归一化坐标格式化为百分比文本（保留 1 位小数）。
---@param posX number|nil
---@param posY number|nil
---@return string
local function formatPercentCoords(posX, posY)
  local loc = Toolbox.L or {}
  local unknown = loc.WORLD_MAP_COORDS_UNKNOWN or "--, --"
  if type(posX) ~= "number" or type(posY) ~= "number" then
    return unknown
  end
  return string.format("%.1f, %.1f", posX * 100, posY * 100)
end

--- 确保小地图坐标文本已创建并按设置锚点摆放。
---@return FontString|nil
local function ensureMinimapCoordsText()
  local minimapFrame = _G.Minimap  -- 小地图根 Frame
  if not minimapFrame then
    return nil
  end
  if not minimapCoordsText then
    minimapCoordsText = minimapFrame:CreateFontString("ToolboxMinimapCoordsText", "OVERLAY", "GameFontNormalSmall")
    minimapCoordsText:SetWidth(170)
    minimapCoordsText:SetJustifyH("CENTER")
    minimapCoordsText:SetTextColor(1, 0.82, 0.18, 1)
  end
  minimapCoordsText:ClearAllPoints()
  local anchor = getMinimapCoordsAnchor()
  if anchor == MINIMAP_COORDS_ANCHOR_TOP then
    minimapCoordsText:SetPoint("BOTTOM", minimapFrame, "TOP", 0, 2)
  else
    minimapCoordsText:SetPoint("TOP", minimapFrame, "BOTTOM", 0, -2)
  end
  return minimapCoordsText
end

--- 确保大地图左下角坐标文本已创建并锚定。
---@return FontString|nil
local function ensureWorldMapCoordsText()
  local worldMapFrame = _G.WorldMapFrame  -- 大地图根 Frame
  if not worldMapFrame then
    return nil
  end
  local anchorParent = worldMapFrame.BorderFrame or worldMapFrame  -- 左下角锚点父级
  if not anchorParent then
    return nil
  end
  if worldMapCoordsText and worldMapCoordsText:GetParent() ~= anchorParent then
    worldMapCoordsText:SetParent(anchorParent)
    worldMapCoordsText:ClearAllPoints()
  end
  if not worldMapCoordsText then
    worldMapCoordsText = anchorParent:CreateFontString("ToolboxWorldMapCoordsText", "OVERLAY", "GameFontHighlightSmall")
    worldMapCoordsText:SetWidth(420)
    worldMapCoordsText:SetJustifyH("LEFT")
    worldMapCoordsText:SetTextColor(1, 0.82, 0.18, 1)
  end
  worldMapCoordsText:ClearAllPoints()
  worldMapCoordsText:SetPoint("BOTTOMLEFT", anchorParent, "BOTTOMLEFT", 16, 10)
  return worldMapCoordsText
end

--- 刷新小地图坐标文本（玩家坐标）。
local function updateMinimapCoordsText()
  local db = Toolbox.Config.GetModule(MODULE_ID)  -- 小地图按钮模块存档
  local coordsText = ensureMinimapCoordsText()  -- 小地图坐标文本对象
  if not coordsText then
    return
  end
  if db.enabled == false or db.showCoordsOnMinimap == false then
    coordsText:Hide()
    return
  end
  local mapID = getPlayerBestMapID()
  local playerX, playerY = getPlayerNormalizedCoords(mapID)
  local loc = Toolbox.L or {}
  coordsText:SetText(string.format(loc.MINIMAP_COORDS_PLAYER_FMT or "Player: %s", formatPercentCoords(playerX, playerY)))
  coordsText:Show()
end

--- 刷新大地图左下角坐标文本（玩家坐标 + 鼠标坐标）。
local function updateWorldMapCoordsText()
  local db = Toolbox.Config.GetModule(MODULE_ID)  -- 小地图按钮模块存档
  if db.enabled == false then
    if worldMapCoordsText then
      worldMapCoordsText:Hide()
    end
    return
  end
  local worldMapFrame = _G.WorldMapFrame  -- 大地图根 Frame
  if not worldMapFrame or not worldMapFrame:IsShown() then
    if worldMapCoordsText then
      worldMapCoordsText:Hide()
    end
    return
  end
  local coordsText = ensureWorldMapCoordsText()  -- 大地图坐标文本对象
  if not coordsText then
    return
  end
  local mapID = getWorldMapShownMapID() or getPlayerBestMapID()
  local playerX, playerY = getPlayerNormalizedCoords(mapID)
  local mouseX, mouseY = getWorldMapMouseNormalizedCoords()
  local loc = Toolbox.L or {}
  local playerText = string.format(loc.WORLD_MAP_COORDS_PLAYER_FMT or "Player: %s", formatPercentCoords(playerX, playerY))
  local mouseText = string.format(loc.WORLD_MAP_COORDS_MOUSE_FMT or "Mouse: %s", formatPercentCoords(mouseX, mouseY))
  coordsText:SetText(playerText .. "    " .. mouseText)
  coordsText:Show()
end

--- 停止坐标刷新驱动并隐藏相关文本。
local function stopCoordinateDisplays()
  if coordsDriverFrame then
    coordsDriverFrame:SetScript("OnUpdate", nil)
    coordsDriverFrame._toolboxCoordElapsed = 0
  end
  if minimapCoordsText then
    minimapCoordsText:Hide()
  end
  if worldMapCoordsText then
    worldMapCoordsText:Hide()
  end
end

--- 刷新坐标显示生命周期：模块启用时启动节流刷新，禁用时关闭。
local function refreshCoordinateDisplays()
  local db = Toolbox.Config.GetModule(MODULE_ID)  -- 小地图按钮模块存档
  if db.enabled == false then
    stopCoordinateDisplays()
    return
  end
  if not coordsDriverFrame then
    coordsDriverFrame = CreateFrame("Frame", "ToolboxMapCoordDriver", UIParent)
  end
  coordsDriverFrame._toolboxCoordElapsed = COORDS_UPDATE_INTERVAL_SEC
  coordsDriverFrame:SetScript("OnUpdate", function(self, elapsed)
    local elapsedTotal = (self._toolboxCoordElapsed or 0) + elapsed
    if elapsedTotal < COORDS_UPDATE_INTERVAL_SEC then
      self._toolboxCoordElapsed = elapsedTotal
      return
    end
    self._toolboxCoordElapsed = 0
    updateMinimapCoordsText()
    updateWorldMapCoordsText()
  end)
  updateMinimapCoordsText()
  updateWorldMapCoordsText()
end

--- 与主按钮同 31×31。横向贴靠距离 flyoutLauncherGap；竖直间距 flyoutPad / flyoutGap（设置页可改，重建时读取）。
local FLYOUT_ROUND_SIZE = 31
--- 存档缺省或非法时的回退（与 DB.lua defaults 一致）
local DEFAULT_FLYOUT_PAD = 4
local DEFAULT_FLYOUT_GAP = 0
--- 展开区贴微缩按钮一侧的横向缝（原硬编码 -4；现由 flyoutLauncherGap 存档驱动）
local DEFAULT_FLYOUT_LAUNCHER_GAP = 0

--- 从存档读非负整数；键为 nil 时用 default；0 为合法值（勿用 `not n` 判断）。
---@param raw any
---@param default number
---@param maxV number
---@return number
local function readStoredUInt(raw, default, maxV)
  if raw == nil then
    return default
  end
  local n = tonumber(strtrim(tostring(raw)))
  if n == nil or n < 0 or n > maxV then
    return default
  end
  return math.floor(n + 0.5)
end

---@return number pad
---@return number gap
local function getFlyoutPadding()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  local pad = readStoredUInt(db.flyoutPad, DEFAULT_FLYOUT_PAD, 64)
  local gap = readStoredUInt(db.flyoutGap, DEFAULT_FLYOUT_GAP, 64)
  return pad, gap
end

---@return number 展开区右缘与微缩按钮左缘之间的横向像素间距（锚点 SetPoint 使用 -hGap）
local function getFlyoutLauncherGap()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  return readStoredUInt(db.flyoutLauncherGap, DEFAULT_FLYOUT_LAUNCHER_GAP, 32)
end

---@return string "round"|"square"
local function getButtonShape()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  if db.buttonShape == "square" then
    return "square"
  end
  return "round"
end

---@return string "vertical"|"horizontal"
local function getFlyoutExpand()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  if db.flyoutExpand == "horizontal" then
    return "horizontal"
  end
  return "vertical"
end
--- 略加长，配合桥接层；仍依赖桥接消除主按钮与面板之间的死区。
local FLYOUT_HIDE_DELAY_SEC = 0.35

--- 取消悬停面板的延迟隐藏计时器。
local function cancelFlyoutHideTimer()
  if flyoutHideHandle then
    flyoutHideHandle:Cancel()
    flyoutHideHandle = nil
  end
end

--- 立即隐藏悬停面板（拖动主按钮或刷新可见性时调用）。
local function hideFlyoutPanel()
  cancelFlyoutHideTimer()
  if flyoutFrame then
    flyoutFrame:Hide()
  end
end

--- 离开主按钮/面板后短延迟再隐藏，便于光标移入纵向菜单。
local function scheduleFlyoutHide()
  cancelFlyoutHideTimer()
  flyoutHideHandle = C_Timer.NewTimer(FLYOUT_HIDE_DELAY_SEC, function()
    flyoutHideHandle = nil
    if flyoutFrame then
      flyoutFrame:Hide()
    end
  end)
end

--- 与主按钮图标层相同的 SetMask 圆形裁切（失败则仅靠 TexCoord）。
---@param tex Texture
---@return boolean
local function applyCircularIconMask(tex)
  for _, maskPath in ipairs({ TEX_ICON_MASK_PRIMARY, TEX_ICON_MASK_FALLBACK }) do
    local ok = pcall(function()
      tex:SetMask(maskPath)
    end)
    if ok then
      return true
    end
  end
  return false
end

--- 去掉图标层 mask（方形 / 圆形款式切换时复用同一 Texture；带 mask 时 Retail 禁止 SetTexCoord，会报错并中断 Refresh）。
---@param tex Texture|nil
local function clearIconMask(tex)
  if not tex then
    return
  end
  pcall(function()
    tex:SetMask(nil)
  end)
end

--- 悬停子按钮：款式与主按钮一致（圆形 / 方形）。
---@param parent Frame
---@param def table
---@param L table
---@param shape string round|square
---@return Button
local function createFlyoutItemButton(parent, def, L, shape)
  local btn
  if shape == "square" then
    btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(FLYOUT_ROUND_SIZE, FLYOUT_ROUND_SIZE)
    btn:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
    btn:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
    if type(def.icon) == "string" and def.icon ~= "" then
      local icon = btn:CreateTexture(nil, "ARTWORK")
      icon:SetTexture(def.icon)
      icon:SetSize(20, 20)
      icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      pcall(function()
        icon:SetMask(TEX_MASK_SQUARE_PASS)
      end)
    else
      local txt = (def.titleKey and (L[def.titleKey] or def.titleKey)) or def.title or "?"
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("CENTER", 0, 0)
      fs:SetWidth(26)
      fs:SetMaxLines(2)
      fs:SetText(txt)
      fs:SetJustifyH("CENTER")
    end
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  else
    btn = CreateFrame("Button", nil, parent)
    btn:SetSize(FLYOUT_ROUND_SIZE, FLYOUT_ROUND_SIZE)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(TEX_MINIMAP_BG)
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture(TEX_MINIMAP_BORDER)
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    if type(def.icon) == "string" and def.icon ~= "" then
      local icon = btn:CreateTexture(nil, "ARTWORK")
      icon:SetTexture(def.icon)
      icon:SetSize(18, 18)
      icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      if not applyCircularIconMask(icon) then
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
      end
    else
      local txt = (def.titleKey and (L[def.titleKey] or def.titleKey)) or def.title or "?"
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("CENTER", 0, 0)
      fs:SetWidth(26)
      fs:SetMaxLines(2)
      fs:SetText(txt)
      fs:SetJustifyH("CENTER")
    end
    btn:SetHighlightTexture(TEX_MINIMAP_HI)
    local hi = btn:GetHighlightTexture()
    if hi then
      hi:SetBlendMode("ADD")
    end
  end
  btn:RegisterForClicks("LeftButtonUp")
  return btn
end

--- 桥接层与展开区锚点：主按钮与展开区之间留窄缝，由透明桥接层接收鼠标，避免光标经过缝时触发主按钮 OnLeave 后无法进入展开区。
local function layoutFlyoutAndBridge()
  if not flyoutFrame or not launcher then
    return
  end
  local hGap = getFlyoutLauncherGap()
  flyoutFrame:ClearAllPoints()
  flyoutFrame:SetPoint("RIGHT", launcher, "LEFT", -hGap, 0)
  flyoutFrame._toolbox_appliedLauncherGap = hGap
  if flyoutBridge then
    flyoutBridge:ClearAllPoints()
    flyoutBridge:SetPoint("LEFT", flyoutFrame, "RIGHT", 0, 0)
    flyoutBridge:SetPoint("RIGHT", launcher, "LEFT", 0, 0)
    flyoutBridge:SetPoint("TOP", flyoutFrame, "TOP", 0, 0)
    flyoutBridge:SetPoint("BOTTOM", flyoutFrame, "BOTTOM", 0, 0)
  end
end

--- 拓展菜单项在提示框第一行显示的名称（与 titleKey / title 一致，与图标旁可见文案对齐）。
---@param def table RegisterFlyoutEntry 的 entry
---@param L table Toolbox.L
---@return string
local function getFlyoutEntryDisplayName(def, L)
  L = L or {}
  if def.titleKey and type(L[def.titleKey]) == "string" and L[def.titleKey] ~= "" then
    return L[def.titleKey]
  end
  if type(def.title) == "string" and def.title ~= "" then
    return def.title
  end
  if type(def.id) == "string" and def.id ~= "" then
    return def.id
  end
  return "?"
end

--- 鼠标指向拓展按钮：第一行为具体功能名称；若有 tooltipKey / tooltip 则第二行为补充说明。
---@param owner Region
---@param def table
---@param L table
local function showFlyoutButtonTooltip(owner, def, L)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if GameTooltip.ClearLines then
    GameTooltip:ClearLines()
  end
  local name = getFlyoutEntryDisplayName(def, L)
  GameTooltip:SetText(name, 1, 1, 1)
  if def.tooltipKey then
    local desc = L[def.tooltipKey]
    if type(desc) == "string" and desc ~= "" then
      GameTooltip:AddLine(desc, 0.82, 0.88, 1, true)
    end
  elseif type(def.tooltip) == "string" and def.tooltip ~= "" then
    GameTooltip:AddLine(def.tooltip, 0.82, 0.88, 1, true)
  end
  if type(def.augmentTooltip) == "function" then
    pcall(def.augmentTooltip)
  end
  GameTooltip:Show()
end

--- 根据 flyoutRegistry 重建悬停面板内按钮（仅当 flyoutFrame 已创建）。
--- 第 i 项：TOPLEFT 相对 flyoutFrame 的 Y 偏移为 -(pad + (i-1)*(FLYOUT_ROUND_SIZE+gap))；pad/gap 来自 getFlyoutPadding()。
local function rebuildFlyoutButtons()
  if not flyoutFrame then
    return
  end
  local pad, gap = getFlyoutPadding()
  local oldBtns = flyoutFrame._buttons or {}
  for _, b in ipairs(oldBtns) do
    b:Hide()
    b:SetParent(nil)
  end
  flyoutFrame._buttons = {}
  local n = #flyoutRegistry
  local expand = getFlyoutExpand()
  if n == 0 then
    flyoutFrame:SetWidth(FLYOUT_ROUND_SIZE + pad * 2)
    flyoutFrame:SetHeight(pad * 2)
    flyoutFrame._toolbox_appliedPad = pad
    flyoutFrame._toolbox_appliedGap = gap
    flyoutFrame._toolbox_appliedN = 0
    flyoutFrame._toolbox_appliedButtonShape = getButtonShape()
    flyoutFrame._toolbox_appliedExpand = expand
    layoutFlyoutAndBridge()
    return
  end
  local L = Toolbox.L or {}
  local shape = getButtonShape()
  local step = FLYOUT_ROUND_SIZE + gap
  if expand == "horizontal" then
    -- 横向：首项靠微缩按钮（面板右侧），向左排列。
    local innerW
    if n == 1 then
      innerW = pad + FLYOUT_ROUND_SIZE + gap + pad
    else
      innerW = pad + n * FLYOUT_ROUND_SIZE + (n - 1) * gap + pad
    end
    local innerH = pad * 2 + FLYOUT_ROUND_SIZE
    flyoutFrame:SetWidth(innerW)
    flyoutFrame:SetHeight(innerH)
    for i = 1, n do
      local def = flyoutRegistry[i]
      local btn = createFlyoutItemButton(flyoutFrame, def, L, shape)
      btn:ClearAllPoints()
      btn:SetPoint("TOPRIGHT", flyoutFrame, "TOPRIGHT", -(pad + (i - 1) * step), -pad)
      btn:SetScript("OnClick", function()
        if def.onClick then
          pcall(def.onClick, btn)
        end
        hideFlyoutPanel()
      end)
      btn:SetScript("OnEnter", function(self)
        cancelFlyoutHideTimer()
        showFlyoutButtonTooltip(self, def, L)
      end)
      btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      flyoutFrame._buttons[#flyoutFrame._buttons + 1] = btn
    end
  else
    -- n==1 时 (n-1)*gap 为 0；将 gap 作为单项下方额外留白。
    local innerH
    if n == 1 then
      innerH = pad + FLYOUT_ROUND_SIZE + gap + pad
    else
      innerH = pad + n * FLYOUT_ROUND_SIZE + (n - 1) * gap + pad
    end
    local flyoutW = pad * 2 + FLYOUT_ROUND_SIZE
    flyoutFrame:SetWidth(flyoutW)
    flyoutFrame:SetHeight(innerH)
    for i = 1, n do
      local def = flyoutRegistry[i]
      local btn = createFlyoutItemButton(flyoutFrame, def, L, shape)
      local yTop = pad + (i - 1) * step
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", pad, -yTop)
      btn:SetScript("OnClick", function()
        if def.onClick then
          pcall(def.onClick, btn)
        end
        hideFlyoutPanel()
      end)
      btn:SetScript("OnEnter", function(self)
        cancelFlyoutHideTimer()
        showFlyoutButtonTooltip(self, def, L)
      end)
      btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      flyoutFrame._buttons[#flyoutFrame._buttons + 1] = btn
    end
  end
  flyoutFrame._toolbox_appliedPad = pad
  flyoutFrame._toolbox_appliedGap = gap
  flyoutFrame._toolbox_appliedN = n
  flyoutFrame._toolbox_appliedButtonShape = shape
  flyoutFrame._toolbox_appliedExpand = expand
  layoutFlyoutAndBridge()
end

--- 根据存档 flyoutSlotIds 从 flyoutCatalog 填充 flyoutRegistry 并重建展开区。
local function syncFlyoutRegistryFromDb()
  wipe(flyoutRegistry)
  local db = Toolbox.Config.GetModule(MODULE_ID)
  local ids = db.flyoutSlotIds
  if type(ids) ~= "table" or #ids == 0 then
    ids = { "reload_ui" }
  end
  local seen = {}
  for _, id in ipairs(ids) do
    if type(id) == "string" and id ~= "" and not seen[id] and flyoutCatalog[id] then
      flyoutRegistry[#flyoutRegistry + 1] = flyoutCatalog[id]
      seen[id] = true
    end
  end
  if #flyoutRegistry == 0 and flyoutCatalog["reload_ui"] then
    flyoutRegistry[1] = flyoutCatalog["reload_ui"]
  end
  rebuildFlyoutButtons()
end

--- 主按钮外观（与预览按钮共用）：须先 createLauncherChrome。
local function applyLauncherSkin(button)
  if not button or not button._tb_bg or not button._tb_icon or not button._tb_border then
    return
  end
  local shape = getButtonShape()
  local bg, icon, border = button._tb_bg, button._tb_icon, button._tb_border
  clearIconMask(icon)
  if shape == "square" then
    border:Hide()
    bg:ClearAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.14, 0.14, 0.16, 0.96)
    bg:SetAllPoints(button)
    icon:ClearAllPoints()
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(function()
      icon:SetMask(TEX_MASK_SQUARE_PASS)
    end)
    if button.SetBackdrop then
      button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      button:SetBackdropColor(0.14, 0.14, 0.16, 0.96)
      button:SetBackdropBorderColor(0.45, 0.45, 0.52, 1)
    end
    button:SetHighlightTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  else
    if button.ClearBackdrop then
      button:ClearBackdrop()
    end
    border:Show()
    bg:ClearAllPoints()
    bg:SetTexture(TEX_MINIMAP_BG)
    bg:SetVertexColor(1, 1, 1, 1)
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:ClearAllPoints()
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not applyCircularIconMask(icon) then
      icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
    button:SetHighlightTexture(TEX_MINIMAP_HI)
    local hi = button:GetHighlightTexture()
    if hi then
      hi:SetBlendMode("ADD")
    end
  end
end

--- 创建主按钮底图 / 图标 / 外圈引用并应用当前款式。
---@param button Button
local function createLauncherChrome(button)
  local bg = button:CreateTexture(nil, "BACKGROUND")
  local icon = button:CreateTexture(nil, "ARTWORK")
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture(TEX_MINIMAP_BORDER)
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  button._tb_bg = bg
  button._tb_icon = icon
  button._tb_border = border
  applyLauncherSkin(button)
end

--- 创建悬停展开面板（仅一次，依赖已存在的 launcher）。
local function ensureFlyoutFrame()
  if flyoutFrame or not launcher then
    return
  end
  flyoutFrame = CreateFrame("Frame", "ToolboxMinimapFlyout", UIParent)
  flyoutFrame:SetFrameStrata("TOOLTIP")
  flyoutFrame:SetFrameLevel((launcher:GetFrameLevel() or 0) + 50)
  flyoutFrame:EnableMouse(true)
  flyoutFrame:SetClampedToScreen(true)
  if flyoutFrame.SetClipsChildren then
    flyoutFrame:SetClipsChildren(false)
  end
  flyoutFrame:Hide()
  flyoutFrame:SetScript("OnEnter", function()
    cancelFlyoutHideTimer()
  end)
  flyoutFrame:SetScript("OnLeave", function()
    scheduleFlyoutHide()
  end)

  flyoutBridge = CreateFrame("Frame", "ToolboxMinimapFlyoutBridge", flyoutFrame)
  flyoutBridge:SetFrameLevel(flyoutFrame:GetFrameLevel() + 10)
  flyoutBridge:EnableMouse(true)
  flyoutBridge:SetScript("OnEnter", function()
    cancelFlyoutHideTimer()
  end)
  flyoutBridge:SetScript("OnLeave", function()
    scheduleFlyoutHide()
  end)

  rebuildFlyoutButtons()
end

--- 注册悬停时展开的纵向菜单项模板（其它模块可在加载时调用）；是否出现在菜单中由存档 flyoutSlotIds 决定。
---@param entry table id: string 唯一；order: number 可选（仅作同批注册时的排序提示）；icon / titleKey / tooltipKey / onClick 等同前
function Toolbox.MinimapButton.RegisterFlyoutEntry(entry)
  if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" then
    return
  end
  flyoutCatalog[entry.id] = entry
  syncFlyoutRegistryFromDb()
end

local function onLauncherDragStart(self)
  GameTooltip:Hide()
  hideFlyoutPanel()
  self:SetScript("OnUpdate", onDragPositionUpdate)
end

local function onLauncherDragStop(self)
  self:SetScript("OnUpdate", nil)
end

--- 创建按钮（仅一次）。
---@return boolean
local function ensureLauncher()
  if launcher then
    return true
  end
  local minimap = _G.Minimap
  if not minimap then
    return false
  end
  launcher = CreateFrame("Button", "ToolboxMinimapLauncherButton", minimap, "BackdropTemplate")
  -- 与 LibDBIcon 默认 31x31 一致；圆形款用外圈纹理，方形款用 BackdropTemplate
  launcher:SetSize(31, 31)
  launcher:SetFrameStrata("MEDIUM")
  if launcher.SetFixedFrameStrata then
    pcall(function()
      launcher:SetFixedFrameStrata(true)
    end)
  end
  launcher:SetFrameLevel(minimap:GetFrameLevel() + 10)
  if launcher.SetFixedFrameLevel then
    pcall(function()
      launcher:SetFixedFrameLevel(true)
    end)
  end
  launcher:EnableMouse(true)
  launcher:RegisterForClicks("anyUp")
  launcher:RegisterForDrag("LeftButton")

  -- 必须先锚定到 Minimap，再挂子纹理；否则按钮会落在父框架默认位置（常表现为小地图左上角）
  migrateLegacyMinimapDb()
  applyLauncherPosition()

  createLauncherChrome(launcher)

  launcher:SetScript("OnDragStart", onLauncherDragStart)
  launcher:SetScript("OnDragStop", onLauncherDragStop)
  launcher:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
      openSettings()
    end
  end)

  ensureFlyoutFrame()

  -- 小地图首帧宽可能为 0，OnShow 后再算一次边缘位置（下一帧合并，非秒级等布局）
  if not minimap.__toolbox_minimapBtnLayoutHook then
    minimap.__toolbox_minimapBtnLayoutHook = true
    minimap:HookScript("OnShow", function()
      if launcher and launcher:IsShown() then
        applyLauncherPosition()
      end
    end)
  end

  launcher:SetScript("OnEnter", function(self)
    cancelFlyoutHideTimer()
    ensureFlyoutFrame()
    if flyoutFrame and #flyoutRegistry > 0 then
      -- 与存档对齐：若上次 Refresh 未执行或同帧被覆盖，此处用当前间距与横向缝强制重建/重锚。
      local pad, gap = getFlyoutPadding()
      local lg = getFlyoutLauncherGap()
      local n = #flyoutRegistry
      local needRebuild = flyoutFrame._toolbox_appliedPad ~= pad
        or flyoutFrame._toolbox_appliedGap ~= gap
        or flyoutFrame._toolbox_appliedN ~= n
        or flyoutFrame._toolbox_appliedLauncherGap ~= lg
        or flyoutFrame._toolbox_appliedButtonShape ~= getButtonShape()
        or flyoutFrame._toolbox_appliedExpand ~= getFlyoutExpand()
      if needRebuild then
        rebuildFlyoutButtons()
      else
        layoutFlyoutAndBridge()
      end
      flyoutFrame:Show()
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local L = Toolbox.L or {}
    GameTooltip:SetText(L.MINIMAP_BUTTON_TOOLTIP_TITLE or "Toolbox", 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_BUTTON_TOOLTIP_HINT or "", 1, 1, 1, true)
    if L.MINIMAP_BUTTON_TOOLTIP_FLYOUT and L.MINIMAP_BUTTON_TOOLTIP_FLYOUT ~= "" then
      GameTooltip:AddLine(L.MINIMAP_BUTTON_TOOLTIP_FLYOUT, 0.75, 0.9, 1, true)
    end
    GameTooltip:AddLine(L.MINIMAP_BUTTON_TOOLTIP_DRAG or "", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  launcher:SetScript("OnLeave", function()
    GameTooltip:Hide()
    scheduleFlyoutHide()
  end)

  return true
end

--- 将按钮恢复为默认角度并写档。
function Toolbox.MinimapButton.ResetPositionToDefault()
  local db = Toolbox.Config.GetModule(MODULE_ID)
  db.minimapPos = nil
  applyLauncherPosition()
end

--- 刷新显示与位置。
function Toolbox.MinimapButton.Refresh()
  local launcherReady = ensureLauncher()  -- 小地图按钮是否已创建
  if launcherReady then
    migrateLegacyMinimapDb()
    applyLauncherPosition()
    if shouldShowLauncher() then
      launcher:Show()
    else
      hideFlyoutPanel()
      launcher:Hide()
    end
    -- 与 ensureLauncher 内创建链一致；保证提交间距后必有 flyoutFrame 可重建（避免仅 rebuild 时早退）
    ensureFlyoutFrame()
    rebuildFlyoutButtons()
    if launcher and launcher._tb_bg then
      applyLauncherSkin(launcher)
    end
  end
  refreshCoordinateDisplays()
end

local clusterHooked

local function initClusterHook()
  if clusterHooked then
    return
  end
  local cluster = _G.MinimapCluster
  if not cluster then
    return
  end
  clusterHooked = true
  cluster:HookScript("OnShow", function()
    Toolbox.MinimapButton.Refresh()
  end)
end

function Toolbox.MinimapButton.Init()
  migrateLegacyMinimapDb()
  initClusterHook()
  Toolbox.MinimapButton.Refresh()
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_MINIMAP_BUTTON",
  settingsIntroKey = "MODULE_MINIMAP_BUTTON_INTRO",
  settingsOrder = 15,
  OnModuleLoad = function()
    Toolbox.MinimapButton.Init()
  end,
  OnModuleEnable = function()
    Toolbox.MinimapButton.Init()
  end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_MINIMAP_BUTTON or MODULE_ID))
    if not enabled then
      -- 模块禁用时取消待执行的延迟隐藏计时器，避免禁用后仍触发
      cancelFlyoutHideTimer()
    end
    Toolbox.MinimapButton.Refresh()
  end,
  OnDebugSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_MINIMAP_BUTTON or MODULE_ID))
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
    Toolbox.MinimapButton.Refresh()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {}
    local db = Toolbox.Config.GetModule(MODULE_ID)
    local y = 0
    --- 预览刷新：在展开方式/款式等控件之前声明，供回调引用。
    local updateMinimapPreview
    --- 预览展开区顶部内边距透明命中条布局（在赋值后由 updateMinimapPreview 调用）。
    local layoutPreviewPadStrip

    local showBtn = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    showBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    showBtn.Text:SetText(L.MINIMAP_BUTTON_SETTING_SHOW or "")
    showBtn:SetChecked(db.showMinimapButton ~= false)
    showBtn:SetScript("OnClick", function(self)
      db.showMinimapButton = self:GetChecked() and true or false
      Toolbox.MinimapButton.Refresh()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)
    y = y - 36

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MINIMAP_BUTTON_SETTING_HINT or "")
    y = y - math.max(40, math.ceil((hint:GetStringHeight() or 0) + 12))

    local showCoordsCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    showCoordsCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    showCoordsCheck.Text:SetText(L.MINIMAP_COORDS_SETTING_SHOW or "")
    showCoordsCheck:SetChecked(db.showCoordsOnMinimap ~= false)
    showCoordsCheck:SetScript("OnClick", function(self)
      db.showCoordsOnMinimap = self:GetChecked() == true
      refreshCoordinateDisplays()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)
    y = y - 30

    local coordsAnchorLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordsAnchorLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 28, y)
    coordsAnchorLabel:SetText(L.MINIMAP_COORDS_SETTING_ANCHOR or "")
    y = y - 20

    local anchorTopCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    anchorTopCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 28, y)
    anchorTopCheck.Text:SetText(L.MINIMAP_COORDS_SETTING_ANCHOR_TOP or "")
    local anchorBottomCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    anchorBottomCheck:SetPoint("LEFT", anchorTopCheck, "RIGHT", 20, 0)
    anchorBottomCheck.Text:SetText(L.MINIMAP_COORDS_SETTING_ANCHOR_BOTTOM or "")

    local function syncAnchorChecks()
      local anchor = getMinimapCoordsAnchor()
      anchorTopCheck:SetChecked(anchor == MINIMAP_COORDS_ANCHOR_TOP)
      anchorBottomCheck:SetChecked(anchor == MINIMAP_COORDS_ANCHOR_BOTTOM)
      local enabled = db.showCoordsOnMinimap ~= false
      anchorTopCheck:SetEnabled(enabled)
      anchorBottomCheck:SetEnabled(enabled)
    end
    syncAnchorChecks()
    anchorTopCheck:SetScript("OnClick", function()
      db.minimapCoordsAnchor = MINIMAP_COORDS_ANCHOR_TOP
      syncAnchorChecks()
      refreshCoordinateDisplays()
    end)
    anchorBottomCheck:SetScript("OnClick", function()
      db.minimapCoordsAnchor = MINIMAP_COORDS_ANCHOR_BOTTOM
      syncAnchorChecks()
      refreshCoordinateDisplays()
    end)
    y = y - 34

    if type(db.flyoutSlotIds) ~= "table" or #db.flyoutSlotIds == 0 then
      db.flyoutSlotIds = { "reload_ui" }
    end
    if db.buttonShape ~= "square" and db.buttonShape ~= "round" then
      db.buttonShape = "round"
    end
    if db.flyoutExpand ~= "horizontal" and db.flyoutExpand ~= "vertical" then
      db.flyoutExpand = "vertical"
    end

    y = y - 12
    local previewSec = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewSec:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    previewSec:SetText(L.MINIMAP_PREVIEW_SECTION or "Preview")
    y = y - 22

    local previewDragHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewDragHint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    previewDragHint:SetWidth(580)
    previewDragHint:SetJustifyH("LEFT")
    previewDragHint:SetText(L.MINIMAP_PREVIEW_DRAG_HINT or "")
    y = y - math.max(22, math.ceil((previewDragHint:GetStringHeight() or 18) + 8))

    local expandLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    expandLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    expandLabel:SetText(L.MINIMAP_FLYOUT_EXPAND_LABEL or "")
    local expandV = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    expandV:SetPoint("TOPLEFT", expandLabel, "BOTTOMLEFT", 0, -6)
    expandV.Text:SetText(L.MINIMAP_FLYOUT_EXPAND_VERTICAL or "")
    expandV:SetChecked(db.flyoutExpand ~= "horizontal")
    local expandH = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    expandH:SetPoint("LEFT", expandV, "RIGHT", 24, 0)
    expandH.Text:SetText(L.MINIMAP_FLYOUT_EXPAND_HORIZONTAL or "")
    expandH:SetChecked(db.flyoutExpand == "horizontal")
    local function applyExpandChoice(isHorizontal)
      db.flyoutExpand = isHorizontal and "horizontal" or "vertical"
      expandV:SetChecked(not isHorizontal)
      expandH:SetChecked(isHorizontal)
      Toolbox.MinimapButton.Refresh()
      updateMinimapPreview()
    end
    expandV:SetScript("OnClick", function()
      applyExpandChoice(false)
    end)
    expandH:SetScript("OnClick", function()
      applyExpandChoice(true)
    end)
    y = y - 52

    local PREVIEW_WRAP_W = 580
    --- 需容纳纵向多枚展开按钮时的预览高度（间距改为预览内拖动后略增高）。
    local PREVIEW_WRAP_H = 220
    local previewWrap = CreateFrame("Frame", nil, box, "BackdropTemplate")
    previewWrap:SetSize(PREVIEW_WRAP_W, PREVIEW_WRAP_H)
    previewWrap:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    do
      -- 仅背景、无描边，避免 ChatFrameBorder 类竖横线
      local bd = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true,
        tileSize = 16,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      }
      previewWrap:SetBackdrop(bd)
      previewWrap:SetBackdropColor(0.06, 0.06, 0.08, 0.88)
    end
    y = y - PREVIEW_WRAP_H - 14

    local previewLauncher = CreateFrame("Button", nil, previewWrap, "BackdropTemplate")
    previewLauncher:SetSize(31, 31)
    createLauncherChrome(previewLauncher)
    previewLauncher:EnableMouse(true)
    previewLauncher:RegisterForDrag("LeftButton")
    previewLauncher:SetScript("OnClick", function() end)

    local previewFlyout = CreateFrame("Frame", nil, previewWrap)
    previewFlyout:SetFrameStrata("DIALOG")
    local previewFlyoutBtns = {}

    --- 预览内间距拖动：与存档相同的上下限（像素）。
    local SPACING_DRAG_LAUNCHER_GAP_MAX = 32
    local SPACING_DRAG_PAD_MAX = 64
    local SPACING_DRAG_GAP_MAX = 64

    --- 展开区顶部透明命中层（无可见底色），用于拖动内边距；位于子按钮之上以便在留白区接收拖动。
    local previewPadHit = CreateFrame("Button", nil, previewFlyout, "BackdropTemplate")
    previewPadHit:SetFrameStrata("DIALOG")
    previewPadHit:SetFrameLevel((previewFlyout:GetFrameLevel() or 0) + 18)
    previewPadHit:EnableMouse(true)
    previewPadHit:RegisterForDrag("LeftButton")
    if previewPadHit.SetBackdrop then
      previewPadHit:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      })
      previewPadHit:SetBackdropColor(0, 0, 0, 0)
    end
    previewPadHit:Hide()

    --- 主按钮叠在展开区之上，避免与左侧拓展区重叠时抢不到点击。
    previewLauncher:SetFrameLevel((previewFlyout:GetFrameLevel() or 0) + 10)

    local function pushSpacingToGame()
      Toolbox.MinimapButton.Refresh()
      updateMinimapPreview()
      C_Timer.After(0, function()
        pcall(function()
          ensureFlyoutFrame()
          rebuildFlyoutButtons()
        end)
      end)
    end

    --- 仅同步游戏内展开区，不重建设置页预览（避免拖动中销毁当前拓展按钮导致拖不动）。
    local function pushSpacingToGameWorldOnly()
      Toolbox.MinimapButton.Refresh()
      C_Timer.After(0, function()
        pcall(function()
          ensureFlyoutFrame()
          rebuildFlyoutButtons()
        end)
      end)
    end

    --- 预览拓展子按钮：悬停为功能提示；拖动调整项间距（存档 flyoutGap，多段同变）。
    local function wirePreviewFlyoutItemGapDrag(btn, def, L)
      btn:EnableMouse(true)
      btn:RegisterForDrag("LeftButton")
      btn:SetScript("OnEnter", function(self)
        showFlyoutButtonTooltip(self, def, L)
        local hint = L.MINIMAP_PREVIEW_DRAG_TOOLTIP_ENTRY_GAP
        if type(hint) == "string" and hint ~= "" then
          GameTooltip:AddLine(hint, 0.55, 0.78, 0.95, true)
        end
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self._tb_lastX, self._tb_lastY = GetCursorPosition()
        self._tb_dragActive = true
        self._tb_gapAccum = 0
        self:SetScript("OnUpdate", function(s)
          if not s._tb_dragActive then
            return
          end
          local x, y = GetCursorPosition()
          local scale = s:GetEffectiveScale() or 1
          if scale == 0 then
            scale = 1
          end
          local expandMode = getFlyoutExpand()
          local dx = (x - s._tb_lastX) / scale
          local dy = (y - s._tb_lastY) / scale
          s._tb_lastX, s._tb_lastY = x, y
          --- 累积子像素位移，避免每帧 floor 为 0 时间距几乎不变。
          local raw = expandMode == "horizontal" and -dx or -dy
          s._tb_gapAccum = (s._tb_gapAccum or 0) + raw
          local delta = 0
          if s._tb_gapAccum >= 1 then
            delta = math.floor(s._tb_gapAccum)
            s._tb_gapAccum = s._tb_gapAccum - delta
          elseif s._tb_gapAccum <= -1 then
            delta = math.ceil(s._tb_gapAccum)
            s._tb_gapAccum = s._tb_gapAccum - delta
          end
          if delta == 0 then
            return
          end
          local nv = db.flyoutGap + delta
          nv = max(0, min(SPACING_DRAG_GAP_MAX, nv))
          if nv ~= db.flyoutGap then
            db.flyoutGap = nv
            pushSpacingToGameWorldOnly()
          end
        end)
      end)
      btn:SetScript("OnDragStop", function(self)
        self._tb_dragActive = false
        self:SetScript("OnUpdate", nil)
        self._tb_gapAccum = nil
        --- 松手后再重建预览，与存档对齐并恢复拖动命中。
        updateMinimapPreview()
      end)
    end

    --- 仅布局顶部透明命中条（有展开内容时显示）。
    layoutPreviewPadStrip = function()
      if not previewFlyout:IsShown() then
        previewPadHit:Hide()
        return
      end
      local pad = select(1, getFlyoutPadding())
      previewPadHit:ClearAllPoints()
      previewPadHit:SetPoint("TOPLEFT", previewFlyout, "TOPLEFT", 0, 0)
      previewPadHit:SetPoint("TOPRIGHT", previewFlyout, "TOPRIGHT", 0, 0)
      previewPadHit:SetHeight(math.max(12, pad + 6))
      previewPadHit:Show()
      --- 子按钮为后创建的兄弟节点，Raise 保证顶部留白区仍优先接收拖动。
      previewPadHit:Raise()
    end

    updateMinimapPreview = function()
      applyLauncherSkin(previewLauncher)
      previewLauncher:ClearAllPoints()
      previewLauncher:SetPoint("CENTER", previewWrap, "CENTER", 0, 0)
      for _, b in ipairs(previewFlyoutBtns) do
        b:Hide()
        b:SetParent(nil)
      end
      wipe(previewFlyoutBtns)
      local pad, gap = getFlyoutPadding()
      local hGap = getFlyoutLauncherGap()
      local shape = getButtonShape()
      local ids = db.flyoutSlotIds
      if type(ids) ~= "table" then
        ids = {}
      end
      local n = 0
      for _, id in ipairs(ids) do
        if flyoutCatalog[id] then
          n = n + 1
        end
      end
      if n == 0 then
        previewFlyout:SetSize(8, 8)
        previewFlyout:Hide()
        previewPadHit:Hide()
        return
      end
      previewFlyout:Show()
      local step = FLYOUT_ROUND_SIZE + gap
      local expandMode = getFlyoutExpand()
      previewFlyout:ClearAllPoints()
      previewFlyout:SetPoint("RIGHT", previewLauncher, "LEFT", -hGap, 0)
      if expandMode == "horizontal" then
        local innerW
        if n == 1 then
          innerW = pad + FLYOUT_ROUND_SIZE + gap + pad
        else
          innerW = pad + n * FLYOUT_ROUND_SIZE + (n - 1) * gap + pad
        end
        local innerH = pad * 2 + FLYOUT_ROUND_SIZE
        previewFlyout:SetSize(innerW, innerH)
        local idx = 0
        for _, id in ipairs(ids) do
          local def = flyoutCatalog[id]
          if def then
            idx = idx + 1
            local btn = createFlyoutItemButton(previewFlyout, def, L, shape)
            btn:SetPoint("TOPRIGHT", previewFlyout, "TOPRIGHT", -(pad + (idx - 1) * step), -pad)
            wirePreviewFlyoutItemGapDrag(btn, def, L)
            previewFlyoutBtns[#previewFlyoutBtns + 1] = btn
          end
        end
      else
        local innerH
        if n == 1 then
          innerH = pad + FLYOUT_ROUND_SIZE + gap + pad
        else
          innerH = pad + n * FLYOUT_ROUND_SIZE + (n - 1) * gap + pad
        end
        local flyoutW = pad * 2 + FLYOUT_ROUND_SIZE
        previewFlyout:SetSize(flyoutW, innerH)
        local idx = 0
        for _, id in ipairs(ids) do
          local def = flyoutCatalog[id]
          if def then
            idx = idx + 1
            local btn = createFlyoutItemButton(previewFlyout, def, L, shape)
            btn:SetPoint("TOPLEFT", previewFlyout, "TOPLEFT", pad, -(pad + (idx - 1) * step))
            wirePreviewFlyoutItemGapDrag(btn, def, L)
            previewFlyoutBtns[#previewFlyoutBtns + 1] = btn
          end
        end
      end
      layoutPreviewPadStrip()
    end

    --- 微缩主按钮：左右拖动调整与展开区的缝宽（预览不再改小地图角度）。
    previewLauncher:SetScript("OnDragStart", function(self)
      GameTooltip:Hide()
      self._tb_lastX, self._tb_lastY = GetCursorPosition()
      self._tb_dragActive = true
      self:SetScript("OnUpdate", function(s)
        if not s._tb_dragActive then
          return
        end
        local x, y = GetCursorPosition()
        local scale = s:GetEffectiveScale() or 1
        if scale == 0 then
          scale = 1
        end
        local dx = (x - s._tb_lastX) / scale
        s._tb_lastX, s._tb_lastY = x, y
        local delta = -math.floor(dx + 0.5)
        if delta == 0 then
          return
        end
        local nv = db.flyoutLauncherGap + delta
        nv = max(0, min(SPACING_DRAG_LAUNCHER_GAP_MAX, nv))
        if nv ~= db.flyoutLauncherGap then
          db.flyoutLauncherGap = nv
          pushSpacingToGame()
        end
      end)
    end)
    previewLauncher:SetScript("OnDragStop", function(self)
      self._tb_dragActive = false
      self:SetScript("OnUpdate", nil)
    end)

    --- 顶部透明区：上下拖动调整内边距。
    previewPadHit:SetScript("OnDragStart", function(self)
      GameTooltip:Hide()
      self._tb_lastX, self._tb_lastY = GetCursorPosition()
      self._tb_dragActive = true
      self:SetScript("OnUpdate", function(s)
        if not s._tb_dragActive then
          return
        end
        local x, y = GetCursorPosition()
        local scale = s:GetEffectiveScale() or 1
        if scale == 0 then
          scale = 1
        end
        local dy = (y - s._tb_lastY) / scale
        s._tb_lastX, s._tb_lastY = x, y
        local delta = -math.floor(dy + 0.5)
        if delta == 0 then
          return
        end
        local nv = db.flyoutPad + delta
        nv = max(0, min(SPACING_DRAG_PAD_MAX, nv))
        if nv ~= db.flyoutPad then
          db.flyoutPad = nv
          pushSpacingToGame()
        end
      end)
    end)
    previewPadHit:SetScript("OnDragStop", function(self)
      self._tb_dragActive = false
      self:SetScript("OnUpdate", nil)
    end)

    local function previewDragTooltipEnter(self, key)
      self:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[key] or "")
        GameTooltip:Show()
      end)
      self:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
    previewDragTooltipEnter(previewLauncher, "MINIMAP_PREVIEW_DRAG_TOOLTIP_LAUNCHER_GAP")
    previewDragTooltipEnter(previewPadHit, "MINIMAP_PREVIEW_DRAG_TOOLTIP_PAD")

    local shapeLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shapeLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    shapeLabel:SetText(L.MINIMAP_SHAPE_LABEL or "")
    local shapeRound = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    shapeRound:SetPoint("TOPLEFT", shapeLabel, "BOTTOMLEFT", 0, -6)
    shapeRound.Text:SetText(L.MINIMAP_SHAPE_ROUND or "")
    shapeRound:SetChecked(db.buttonShape ~= "square")
    local shapeSquare = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    shapeSquare:SetPoint("LEFT", shapeRound, "RIGHT", 24, 0)
    shapeSquare.Text:SetText(L.MINIMAP_SHAPE_SQUARE or "")
    shapeSquare:SetChecked(db.buttonShape == "square")
    local function applyShapeChoice(isSquare)
      db.buttonShape = isSquare and "square" or "round"
      shapeRound:SetChecked(not isSquare)
      shapeSquare:SetChecked(isSquare)
      Toolbox.MinimapButton.Refresh()
      updateMinimapPreview()
    end
    shapeRound:SetScript("OnClick", function()
      applyShapeChoice(false)
    end)
    shapeSquare:SetScript("OnClick", function()
      applyShapeChoice(true)
    end)

    local flyoutSec = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    flyoutSec:SetPoint("TOPLEFT", shapeRound, "BOTTOMLEFT", 0, -16)
    flyoutSec:SetText(L.MINIMAP_FLYOUT_SLOTS_LABEL or "")

    local flyoutAddAllBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    flyoutAddAllBtn:SetSize(132, 22)
    flyoutAddAllBtn:SetPoint("LEFT", flyoutSec, "RIGHT", 12, 0)
    flyoutAddAllBtn:SetText(L.MINIMAP_FLYOUT_ADD_ALL or "")

    local flyoutPoolHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flyoutPoolHint:SetPoint("TOPLEFT", flyoutSec, "BOTTOMLEFT", 0, -8)
    flyoutPoolHint:SetWidth(560)
    flyoutPoolHint:SetJustifyH("LEFT")
    flyoutPoolHint:SetText(L.MINIMAP_FLYOUT_POOL_HINT or "")

    local flyoutPool = CreateFrame("Frame", nil, box)
    flyoutPool:SetPoint("TOPLEFT", flyoutPoolHint, "BOTTOMLEFT", 0, -4)
    flyoutPool:SetSize(520, 2)

    local flyoutDropBar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    flyoutDropBar:SetSize(520, 34)
    flyoutDropBar:SetPoint("TOPLEFT", flyoutPool, "BOTTOMLEFT", 0, -8)
    do
      local bd = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      }
      flyoutDropBar:SetBackdrop(bd)
      flyoutDropBar:SetBackdropColor(0.06, 0.14, 0.08, 0.75)
      flyoutDropBar:SetBackdropBorderColor(0.25, 0.55, 0.35, 0.9)
    end
    flyoutDropBar:EnableMouse(true)
    local flyoutDropText = flyoutDropBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flyoutDropText:SetPoint("CENTER", 0, 0)
    flyoutDropText:SetWidth(500)
    flyoutDropText:SetJustifyH("CENTER")
    flyoutDropText:SetText(L.MINIMAP_FLYOUT_DROP_HERE or "")

    local slotListAnchor = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotListAnchor:SetPoint("TOPLEFT", flyoutDropBar, "BOTTOMLEFT", 0, -10)
    slotListAnchor:SetWidth(1)
    slotListAnchor:SetHeight(1)

    local slotRows = {}
    local addMenu = CreateFrame("Frame", nil, box, "BackdropTemplate")
    addMenu:SetSize(220, 1)
    addMenu:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 16,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    addMenu:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    addMenu:Hide()

    local function catalogSorted()
      local t = {}
      for id in pairs(flyoutCatalog) do
        t[#t + 1] = id
      end
      table.sort(t, function(leftId, rightId)
        local leftDef = flyoutCatalog[leftId]
        local rightDef = flyoutCatalog[rightId]
        local leftOrder = tonumber(leftDef and leftDef.order) or 100
        local rightOrder = tonumber(rightDef and rightDef.order) or 100
        if leftOrder ~= rightOrder then
          return leftOrder < rightOrder
        end
        return leftId < rightId
      end)
      return t
    end

    local function idInList(id, list)
      for _, x in ipairs(list) do
        if x == id then
          return true
        end
      end
      return false
    end

    local function persistFlyoutSlots()
      syncFlyoutRegistryFromDb()
      Toolbox.MinimapButton.Refresh()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end

    --- 尚未加入悬停菜单的项：可拖到 flyoutDropBar 或点「+」加入。
    local function rebuildFlyoutPool()
      local children = { flyoutPool:GetChildren() }
      for _, c in ipairs(children) do
        c:Hide()
        c:SetParent(nil)
      end
      local ids = db.flyoutSlotIds
      if type(ids) ~= "table" then
        ids = {}
      end
      local py = 0
      local n = 0
      for _, cid in ipairs(catalogSorted()) do
        if not idInList(cid, ids) then
          n = n + 1
          local row = CreateFrame("Button", nil, flyoutPool, "BackdropTemplate")
          row:SetSize(500, 24)
          row:SetPoint("TOPLEFT", flyoutPool, "TOPLEFT", 0, py)
          py = py - 26
          if row.SetBackdrop then
            row:SetBackdrop({
              bgFile = "Interface\\Buttons\\WHITE8X8",
              edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
              tile = true,
              tileSize = 8,
              edgeSize = 8,
              insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row:SetBackdropColor(0.1, 0.1, 0.12, 0.55)
            row:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.5)
          end
          local def = flyoutCatalog[cid]
          local lab = (def and def.titleKey and (L[def.titleKey] or def.titleKey)) or cid
          local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          fs:SetPoint("LEFT", 8, 0)
          fs:SetWidth(400)
          fs:SetJustifyH("LEFT")
          fs:SetText(lab)
          row:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
          row:SetScript("OnMouseDown", function(self, btn)
            if btn ~= "LeftButton" then
              return
            end
            self._dragCid = cid
            self:SetScript("OnUpdate", function(s)
              if IsMouseButtonDown("LeftButton") then
                return
              end
              s:SetScript("OnUpdate", nil)
              local cidr = s._dragCid
              s._dragCid = nil
              if cidr and flyoutDropBar:IsMouseOver() then
                local idsl = db.flyoutSlotIds
                if type(idsl) == "table" and not idInList(cidr, idsl) then
                  idsl[#idsl + 1] = cidr
                  persistFlyoutSlots()
                end
              end
            end)
          end)
          local quick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
          quick:SetSize(28, 20)
          quick:SetPoint("RIGHT", -4, 0)
          quick:SetText("+")
          quick:SetScript("OnClick", function()
            local idsl = db.flyoutSlotIds
            if type(idsl) ~= "table" then
              return
            end
            if not idInList(cid, idsl) then
              idsl[#idsl + 1] = cid
              persistFlyoutSlots()
            end
          end)
        end
      end
      flyoutPool:SetHeight(math.max(2, (n > 0 and (n * 26 + 4)) or 2))
    end

    flyoutAddAllBtn:SetScript("OnClick", function()
      local ids = db.flyoutSlotIds
      if type(ids) ~= "table" then
        db.flyoutSlotIds = {}
        ids = db.flyoutSlotIds
      end
      wipe(ids)
      for _, cid in ipairs(catalogSorted()) do
        ids[#ids + 1] = cid
      end
      if #ids == 0 then
        ids[1] = "reload_ui"
      end
      persistFlyoutSlots()
    end)

    local slotAddBtnRef
    local function rebuildSlotRows()
      for _, row in ipairs(slotRows) do
        row:Hide()
        row:SetParent(nil)
      end
      wipe(slotRows)
      addMenu:Hide()
      addMenu:SetHeight(1)
      local ids = db.flyoutSlotIds
      if type(ids) ~= "table" then
        ids = {}
      end
      local ry = 0
      for i, id in ipairs(ids) do
        local def = flyoutCatalog[id]
        local row = CreateFrame("Frame", nil, box)
        row:SetSize(520, 26)
        row:SetPoint("TOPLEFT", slotListAnchor, "BOTTOMLEFT", 0, ry)
        ry = ry - 28
        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("LEFT", 0, 0)
        title:SetWidth(220)
        title:SetJustifyH("LEFT")
        if def and def.titleKey then
          title:SetText(L[def.titleKey] or id)
        else
          title:SetText(id)
        end
        local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        up:SetSize(52, 22)
        up:SetPoint("LEFT", title, "RIGHT", 8, 0)
        up:SetText(L.MINIMAP_FLYOUT_SLOT_UP or "Up")
        up:SetScript("OnClick", function()
          if i > 1 then
            ids[i], ids[i - 1] = ids[i - 1], ids[i]
            persistFlyoutSlots()
          end
        end)
        local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        down:SetSize(52, 22)
        down:SetPoint("LEFT", up, "RIGHT", 4, 0)
        down:SetText(L.MINIMAP_FLYOUT_SLOT_DOWN or "Dn")
        down:SetScript("OnClick", function()
          if i < #ids then
            ids[i], ids[i + 1] = ids[i + 1], ids[i]
            persistFlyoutSlots()
          end
        end)
        local rm = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rm:SetSize(52, 22)
        rm:SetPoint("LEFT", down, "RIGHT", 4, 0)
        rm:SetText(L.MINIMAP_FLYOUT_SLOT_REMOVE or "X")
        rm:SetScript("OnClick", function()
          table.remove(ids, i)
          if #ids == 0 then
            ids[1] = "reload_ui"
          end
          persistFlyoutSlots()
        end)
        slotRows[#slotRows + 1] = row
      end

      local addBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
      addBtn:SetSize(140, 24)
      addBtn:SetPoint("TOPLEFT", slotListAnchor, "BOTTOMLEFT", 0, ry - 4)
      addBtn:SetText(L.MINIMAP_FLYOUT_SLOT_ADD or "Add…")
      addBtn:SetScript("OnClick", function()
        if addMenu:IsShown() then
          addMenu:Hide()
          return
        end
        local children = { addMenu:GetChildren() }
        for _, c in ipairs(children) do
          c:Hide()
          c:SetParent(nil)
        end
        local ay = -6
        local any = false
        for _, cid in ipairs(catalogSorted()) do
          if not idInList(cid, ids) then
            any = true
            local b = CreateFrame("Button", nil, addMenu, "UIPanelButtonTemplate")
            b:SetSize(200, 22)
            b:SetPoint("TOPLEFT", addMenu, "TOPLEFT", 10, ay)
            local lab = flyoutCatalog[cid] and flyoutCatalog[cid].titleKey and (L[flyoutCatalog[cid].titleKey] or cid) or cid
            b:SetText(lab)
            b:SetScript("OnClick", function()
              ids[#ids + 1] = cid
              addMenu:Hide()
              persistFlyoutSlots()
            end)
            ay = ay - 26
          end
        end
        if not any then
          addMenu:SetHeight(40)
          local nx = addMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          nx:SetPoint("TOPLEFT", 10, -8)
          nx:SetText(L.MINIMAP_FLYOUT_SLOT_ADD_EMPTY or "")
        else
          addMenu:SetHeight(-ay + 16)
        end
        addMenu:ClearAllPoints()
        addMenu:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -4)
        addMenu:Show()
      end)
      slotRows[#slotRows + 1] = addBtn
      slotAddBtnRef = addBtn
      rebuildFlyoutPool()
    end

    rebuildSlotRows()
    updateMinimapPreview()

    if db.flyoutLauncherGap == nil then
      db.flyoutLauncherGap = getFlyoutLauncherGap()
    end
    do
      local pEff, gEff = getFlyoutPadding()
      if db.flyoutPad == nil then
        db.flyoutPad = pEff
      end
      if db.flyoutGap == nil then
        db.flyoutGap = gEff
      end
    end

    local resetPos = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    resetPos:SetSize(200, 26)
    resetPos:SetPoint("TOPLEFT", slotAddBtnRef, "BOTTOMLEFT", 0, -16)
    resetPos:SetText(L.MINIMAP_BUTTON_RESET_POSITION or "")
    resetPos:SetScript("OnClick", function()
      Toolbox.MinimapButton.ResetPositionToDefault()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)

    do
      local bt, rbb = box:GetTop(), resetPos:GetBottom()
      if type(bt) == "number" and type(rbb) == "number" then
        box.realHeight = math.max(280, (bt - rbb) + 24)
      else
        box.realHeight = 520
      end
    end
  end,
})

-- 内置悬停项：重载界面（其它模块可在加载后调用 RegisterFlyoutEntry 追加，order 建议 20+）
Toolbox.MinimapButton.RegisterFlyoutEntry({
  id = "reload_ui",
  order = 10,
  titleKey = "MINIMAP_FLYOUT_RELOAD",
  tooltipKey = "MINIMAP_FLYOUT_RELOAD_TOOLTIP",
  icon = "Interface\\Icons\\Spell_Nature_TimeStop",
  onClick = function()
    if _G.ReloadUI then
      _G.ReloadUI()
    end
  end,
})

Toolbox.MinimapButton.RegisterFlyoutEntry({
  id = "open_settings",
  order = 15,
  titleKey = "MINIMAP_FLYOUT_OPEN_SETTINGS",
  tooltipKey = "MINIMAP_FLYOUT_OPEN_SETTINGS_TOOLTIP",
  icon = "Interface\\Icons\\INV_Misc_Gear_03",
  onClick = function()
    if Toolbox.SettingsHost and Toolbox.SettingsHost.Open then
      Toolbox.SettingsHost:Open()
    end
  end,
})

--- 在 ADDON_LOADED 末尾调用：为每个设置模块、冒险手册、关于页注册悬停项模板（供玩家勾选/拖入菜单）。
function Toolbox.MinimapButton.RegisterBuiltinFlyoutCatalog()
  if Toolbox.MinimapButton._builtinFlyoutCatalogDone then
    return
  end
  Toolbox.MinimapButton._builtinFlyoutCatalogDone = true
  if Toolbox.ModuleRegistry and Toolbox.ModuleRegistry.GetSorted then
    for _, m in ipairs(Toolbox.ModuleRegistry:GetSorted()) do
      if m.RegisterSettings and m.id then
        local mid = m.id
        Toolbox.MinimapButton.RegisterFlyoutEntry({
          id = "tb_mod_" .. mid,
          order = 50,
          titleKey = m.nameKey,
          tooltipKey = "MINIMAP_FLYOUT_OPEN_MODULE_TOOLTIP",
          icon = "Interface\\Icons\\Trade_Engineering",
          onClick = function()
            if Toolbox.SettingsHost and Toolbox.SettingsHost.OpenToModulePage then
              Toolbox.SettingsHost:OpenToModulePage(mid)
            end
          end,
        })
      end
    end
  end
  Toolbox.MinimapButton.RegisterFlyoutEntry({
    id = "tb_flyout_ej",
    order = 22,
    titleKey = "MINIMAP_FLYOUT_ADVENTURE_JOURNAL",
    tooltipKey = "MINIMAP_FLYOUT_ADVENTURE_JOURNAL_TOOLTIP",
    icon = "Interface\\Icons\\Achievement_Zone_EasternKingdoms",
    augmentTooltip = function()
      local loc = Toolbox.L or {}
      local sectionTitle = loc.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE or "Current lockouts"
      local emptyText = loc.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_EMPTY or "No saved instance lockouts."
      local moreFmt = loc.MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_MORE_FMT or "+%d more..."

      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(sectionTitle, 1, 0.82, 0.2)

      if not Toolbox.EJ or type(Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines) ~= "function" then
        GameTooltip:AddLine(emptyText, 0.75, 0.75, 0.75, true)
        return
      end

      local lines, overflow = Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(8)
      if type(lines) ~= "table" or #lines == 0 then
        GameTooltip:AddLine(emptyText, 0.75, 0.75, 0.75, true)
        return
      end

      for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 0.82, 0.88, 1, true)
      end
      if type(overflow) == "number" and overflow > 0 then
        GameTooltip:AddLine(string.format(moreFmt, overflow), 0.6, 0.6, 0.6, true)
      end
    end,
    onClick = function()
      pcall(function()
        local ejName = "Blizzard_EncounterJournal"
        if C_AddOns and C_AddOns.LoadAddOn then
          pcall(C_AddOns.LoadAddOn, ejName)
        elseif LoadAddOn then
          LoadAddOn(ejName)
        end
        if ToggleEncounterJournal then
          ToggleEncounterJournal()
        end
      end)
    end,
  })
  Toolbox.MinimapButton.RegisterFlyoutEntry({
    id = "tb_flyout_about",
    order = 24,
    titleKey = "MINIMAP_FLYOUT_ABOUT",
    tooltipKey = "MINIMAP_FLYOUT_ABOUT_TOOLTIP",
    icon = "Interface\\Icons\\INV_Misc_QuestionMark",
    onClick = function()
      if Toolbox.SettingsHost and Toolbox.SettingsHost.OpenToAbout then
        Toolbox.SettingsHost:OpenToAbout()
      end
    end,
  })
end
