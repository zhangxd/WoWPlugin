--[[
  模块 minimap_button：小地图上的圆形按钮（暴雪小地图图标用底图 + 边框 + 图标圆形遮罩，与 LibDBIcon 视觉一致），点击打开 Toolbox 设置总览。
  悬停时在按钮左侧展开横向操作列（RegisterFlyoutEntry 注册项；启动后 RegisterBuiltinFlyoutCatalog 会登记各模块设置、冒险手册、关于等，设置页通过勾选决定是否加入菜单）。
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
--- 悬停菜单项（按 flyoutCatalog.order 固定排序）；由 syncFlyoutRegistryFromDb 根据 flyoutSlotIds 勾选结果填充。
local flyoutRegistry = {}
--- 已注册的悬停项模板 id → 定义（供 flyoutSlotIds 引用）。
local flyoutCatalog = {}
--- 按钮中心相对小地图「理论圆/方」半径外推像素，与 LibDBIcon lib.radius 一致。
local MINIMAP_ICON_RADIUS_EXTRA = 5

--- 默认角度（度），与 LibDBIcon 默认一致。
local DEFAULT_MINIMAP_ANGLE = 225
local MINIMAP_COORDS_ANCHOR_TOP = "top"
local MINIMAP_COORDS_ANCHOR_BOTTOM = "bottom"
local COORDS_UPDATE_INTERVAL_SEC = 0.1

local rad, cos, sin, sqrt, max, min, deg, atan2 = math.rad, math.cos, math.sin, math.sqrt, math.max, math.min, math.deg, math.atan2

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

--- 与主按钮同 31×31；悬停菜单固定为横向圆形按钮组。
local FLYOUT_BUTTON_SIZE = 31
local FLYOUT_PAD = 4
local FLYOUT_GAP = 0
local FLYOUT_LAUNCHER_GAP = 0
--- 略加长，配合桥接层；仍依赖桥接消除主按钮与面板之间的死区。
local FLYOUT_HIDE_DELAY_SEC = 0.35

--- 返回按 order / id 固定排序后的悬停菜单模板 id 列表。
---@return table
local function getSortedFlyoutEntryIds()
  local entryIdList = {} -- 已排序的悬停菜单模板 id 列表
  for entryId in pairs(flyoutCatalog) do
    entryIdList[#entryIdList + 1] = entryId
  end
  table.sort(entryIdList, function(leftId, rightId)
    local leftDef = flyoutCatalog[leftId] -- 左侧模板定义
    local rightDef = flyoutCatalog[rightId] -- 右侧模板定义
    local leftOrder = tonumber(leftDef and leftDef.order) or 100 -- 左侧排序值
    local rightOrder = tonumber(rightDef and rightDef.order) or 100 -- 右侧排序值
    if leftOrder ~= rightOrder then
      return leftOrder < rightOrder
    end
    return leftId < rightId
  end)
  return entryIdList
end

--- 检查指定悬停菜单 id 是否已在勾选列表中。
---@param entryIdList table 已勾选 id 列表
---@param targetId string 目标 id
---@return boolean
local function hasFlyoutEntryId(entryIdList, targetId)
  for _, entryId in ipairs(entryIdList) do
    if entryId == targetId then
      return true
    end
  end
  return false
end

--- 从勾选列表中移除指定悬停菜单 id。
---@param entryIdList table 已勾选 id 列表
---@param targetId string 目标 id
local function removeFlyoutEntryId(entryIdList, targetId)
  for index = #entryIdList, 1, -1 do
    if entryIdList[index] == targetId then
      table.remove(entryIdList, index)
    end
  end
end

--- 确保模块存档中的悬停菜单勾选列表可用。
---@param moduleDb table 小地图按钮模块存档
---@return table
local function ensureFlyoutSlotIds(moduleDb)
  if type(moduleDb.flyoutSlotIds) ~= "table" then
    moduleDb.flyoutSlotIds = { "reload_ui", "tb_flyout_quest" }
  end
  return moduleDb.flyoutSlotIds
end

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

--- 离开主按钮/面板后短延迟再隐藏，便于光标移入横向菜单。
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

--- 悬停子按钮：固定使用圆形按钮样式。
---@param parent Frame
---@param def table
---@param L table
---@return Button
local function createFlyoutItemButton(parent, def, L)
  local btn = CreateFrame("Button", nil, parent) -- 悬停菜单圆形按钮
  btn:SetSize(FLYOUT_BUTTON_SIZE, FLYOUT_BUTTON_SIZE)
  local bg = btn:CreateTexture(nil, "BACKGROUND") -- 按钮底图
  bg:SetTexture(TEX_MINIMAP_BG)
  bg:SetSize(24, 24)
  bg:SetPoint("CENTER", btn, "CENTER", 0, 0)
  local border = btn:CreateTexture(nil, "OVERLAY") -- 按钮边框
  border:SetTexture(TEX_MINIMAP_BORDER)
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  if type(def.icon) == "string" and def.icon ~= "" then
    local icon = btn:CreateTexture(nil, "ARTWORK") -- 功能图标
    icon:SetTexture(def.icon)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not applyCircularIconMask(icon) then
      icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
  else
    local labelText = (def.titleKey and (L[def.titleKey] or def.titleKey)) or def.title or "?" -- 无图标时的文本
    local fontString = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- 无图标时的文本节点
    fontString:SetPoint("CENTER", 0, 0)
    fontString:SetWidth(26)
    fontString:SetMaxLines(2)
    fontString:SetText(labelText)
    fontString:SetJustifyH("CENTER")
  end
  btn:SetHighlightTexture(TEX_MINIMAP_HI)
  local highlightTexture = btn:GetHighlightTexture() -- 高亮纹理
  if highlightTexture then
    highlightTexture:SetBlendMode("ADD")
  end
  btn:RegisterForClicks("LeftButtonUp")
  return btn
end

--- 桥接层与展开区锚点：主按钮与展开区之间留窄缝，由透明桥接层接收鼠标。
local function layoutFlyoutAndBridge()
  if not flyoutFrame or not launcher then
    return
  end
  flyoutFrame:ClearAllPoints()
  flyoutFrame:SetPoint("RIGHT", launcher, "LEFT", -FLYOUT_LAUNCHER_GAP, 0)
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

--- 根据 flyoutRegistry 重建悬停面板内按钮（固定为横向圆形菜单）。
local function rebuildFlyoutButtons()
  if not flyoutFrame then
    return
  end
  local oldButtonList = flyoutFrame._buttons or {} -- 旧按钮列表
  for _, buttonFrame in ipairs(oldButtonList) do
    buttonFrame:Hide()
    buttonFrame:SetParent(nil)
  end
  flyoutFrame._buttons = {}
  local buttonCount = #flyoutRegistry -- 当前选中的悬停按钮数量
  if buttonCount == 0 then
    flyoutFrame:SetWidth(FLYOUT_PAD * 2)
    flyoutFrame:SetHeight(FLYOUT_PAD * 2)
    layoutFlyoutAndBridge()
    return
  end
  local localeTable = Toolbox.L or {} -- 本地化文案
  local buttonStep = FLYOUT_BUTTON_SIZE + FLYOUT_GAP -- 横向相邻按钮步长
  local flyoutWidth = FLYOUT_PAD * 2 + buttonCount * FLYOUT_BUTTON_SIZE + math.max(0, buttonCount - 1) * FLYOUT_GAP -- 展开区总宽
  local flyoutHeight = FLYOUT_PAD * 2 + FLYOUT_BUTTON_SIZE -- 展开区总高
  flyoutFrame:SetWidth(flyoutWidth)
  flyoutFrame:SetHeight(flyoutHeight)
  for index = 1, buttonCount do
    local entryDef = flyoutRegistry[index] -- 当前按钮定义
    local buttonFrame = createFlyoutItemButton(flyoutFrame, entryDef, localeTable) -- 当前按钮
    buttonFrame:ClearAllPoints()
    buttonFrame:SetPoint("TOPRIGHT", flyoutFrame, "TOPRIGHT", -(FLYOUT_PAD + (index - 1) * buttonStep), -FLYOUT_PAD)
    buttonFrame:SetScript("OnClick", function()
      if entryDef.onClick then
        pcall(entryDef.onClick, buttonFrame)
      end
      hideFlyoutPanel()
    end)
    buttonFrame:SetScript("OnEnter", function(self)
      cancelFlyoutHideTimer()
      showFlyoutButtonTooltip(self, entryDef, localeTable)
    end)
    buttonFrame:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    flyoutFrame._buttons[#flyoutFrame._buttons + 1] = buttonFrame
  end
  layoutFlyoutAndBridge()
end

--- 根据勾选的 flyoutSlotIds 从 flyoutCatalog 填充 flyoutRegistry 并重建展开区。
local function syncFlyoutRegistryFromDb()
  wipe(flyoutRegistry)
  local moduleDb = Toolbox.Config.GetModule(MODULE_ID) -- 小地图按钮模块存档
  local selectedIdList = ensureFlyoutSlotIds(moduleDb) -- 已勾选 id 列表
  local selectedMap = {} -- 已勾选 id 查找表
  for _, entryId in ipairs(selectedIdList) do
    if type(entryId) == "string" and entryId ~= "" then
      selectedMap[entryId] = true
    end
  end
  for _, entryId in ipairs(getSortedFlyoutEntryIds()) do
    if selectedMap[entryId] and flyoutCatalog[entryId] then
      flyoutRegistry[#flyoutRegistry + 1] = flyoutCatalog[entryId]
    end
  end
  rebuildFlyoutButtons()
end

--- 主按钮外观：固定使用圆形小地图按钮样式。
local function applyLauncherSkin(button)
  if not button or not button._tb_bg or not button._tb_icon or not button._tb_border then
    return
  end
  local bg = button._tb_bg -- 主按钮底图
  local icon = button._tb_icon -- 主按钮图标
  local border = button._tb_border -- 主按钮边框
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
  local highlightTexture = button:GetHighlightTexture() -- 主按钮高亮纹理
  if highlightTexture then
    highlightTexture:SetBlendMode("ADD")
  end
end

--- 创建主按钮底图 / 图标 / 外圈引用并应用当前圆形样式。
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

--- 注册悬停时展开的菜单项模板（其它模块可在加载时调用）；是否出现在菜单中由存档 flyoutSlotIds 决定。
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
  -- 与 LibDBIcon 默认 31x31 一致；固定使用圆形小地图按钮观感
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
      rebuildFlyoutButtons()
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
    local localeTable = Toolbox.L or {} -- 本地化文案
    local moduleDb = Toolbox.Config.GetModule(MODULE_ID) -- 小地图按钮模块存档
    local yOffset = 0 -- 当前纵向游标

    local function persistFlyoutSlots()
      syncFlyoutRegistryFromDb()
      Toolbox.MinimapButton.Refresh()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end

    local showButtonCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 显示小地图按钮开关
    showButtonCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    showButtonCheck.Text:SetText(localeTable.MINIMAP_BUTTON_SETTING_SHOW or "")
    showButtonCheck:SetChecked(moduleDb.showMinimapButton ~= false)
    showButtonCheck:SetScript("OnClick", function(self)
      moduleDb.showMinimapButton = self:GetChecked() and true or false
      Toolbox.MinimapButton.Refresh()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)
    yOffset = yOffset - 36

    local hintLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 小地图按钮说明
    hintLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    hintLabel:SetWidth(580)
    hintLabel:SetJustifyH("LEFT")
    hintLabel:SetText(localeTable.MINIMAP_BUTTON_SETTING_HINT or "")
    yOffset = yOffset - math.max(40, math.ceil((hintLabel:GetStringHeight() or 0) + 12))

    local showCoordsCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 小地图坐标显示开关
    showCoordsCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    showCoordsCheck.Text:SetText(localeTable.MINIMAP_COORDS_SETTING_SHOW or "")
    showCoordsCheck:SetChecked(moduleDb.showCoordsOnMinimap ~= false)
    showCoordsCheck:SetScript("OnClick", function(self)
      moduleDb.showCoordsOnMinimap = self:GetChecked() == true
      refreshCoordinateDisplays()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)
    yOffset = yOffset - 30

    local coordsAnchorLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 坐标锚点标题
    coordsAnchorLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 28, yOffset)
    coordsAnchorLabel:SetText(localeTable.MINIMAP_COORDS_SETTING_ANCHOR or "")
    yOffset = yOffset - 20

    local anchorTopCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 上方锚点开关
    anchorTopCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 28, yOffset)
    anchorTopCheck.Text:SetText(localeTable.MINIMAP_COORDS_SETTING_ANCHOR_TOP or "")
    local anchorBottomCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 下方锚点开关
    anchorBottomCheck:SetPoint("LEFT", anchorTopCheck, "RIGHT", 20, 0)
    anchorBottomCheck.Text:SetText(localeTable.MINIMAP_COORDS_SETTING_ANCHOR_BOTTOM or "")

    local function syncAnchorChecks()
      local anchorKey = getMinimapCoordsAnchor() -- 当前坐标锚点
      local coordsEnabled = moduleDb.showCoordsOnMinimap ~= false -- 坐标显示是否启用
      anchorTopCheck:SetChecked(anchorKey == MINIMAP_COORDS_ANCHOR_TOP)
      anchorBottomCheck:SetChecked(anchorKey == MINIMAP_COORDS_ANCHOR_BOTTOM)
      anchorTopCheck:SetEnabled(coordsEnabled)
      anchorBottomCheck:SetEnabled(coordsEnabled)
    end

    syncAnchorChecks()
    anchorTopCheck:SetScript("OnClick", function()
      moduleDb.minimapCoordsAnchor = MINIMAP_COORDS_ANCHOR_TOP
      syncAnchorChecks()
      refreshCoordinateDisplays()
    end)
    anchorBottomCheck:SetScript("OnClick", function()
      moduleDb.minimapCoordsAnchor = MINIMAP_COORDS_ANCHOR_BOTTOM
      syncAnchorChecks()
      refreshCoordinateDisplays()
    end)
    yOffset = yOffset - 34

    local selectedIdList = ensureFlyoutSlotIds(moduleDb) -- 已勾选的悬停菜单项
    yOffset = yOffset - 12

    local flyoutSectionLabel = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- 悬停菜单分节标题
    flyoutSectionLabel:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    flyoutSectionLabel:SetText(localeTable.MINIMAP_FLYOUT_SLOTS_LABEL or "")
    yOffset = yOffset - 24

    local flyoutSectionHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- 悬停菜单说明
    flyoutSectionHint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    flyoutSectionHint:SetWidth(580)
    flyoutSectionHint:SetJustifyH("LEFT")
    flyoutSectionHint:SetText(localeTable.MINIMAP_FLYOUT_SLOTS_HINT or "")
    yOffset = yOffset - math.max(22, math.ceil((flyoutSectionHint:GetStringHeight() or 0) + 8))

    for _, entryId in ipairs(getSortedFlyoutEntryIds()) do
      local entryDef = flyoutCatalog[entryId] -- 当前悬停菜单定义
      if entryDef then
        local entryCheck = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate") -- 当前功能勾选框
        entryCheck:SetPoint("TOPLEFT", box, "TOPLEFT", 20, yOffset)
        entryCheck.Text:SetText(getFlyoutEntryDisplayName(entryDef, localeTable))
        entryCheck:SetChecked(hasFlyoutEntryId(selectedIdList, entryId))
        entryCheck:SetScript("OnClick", function(self)
          if self:GetChecked() then
            if not hasFlyoutEntryId(selectedIdList, entryId) then
              selectedIdList[#selectedIdList + 1] = entryId
            end
          else
            removeFlyoutEntryId(selectedIdList, entryId)
          end
          persistFlyoutSlots()
        end)
        yOffset = yOffset - 28
      end
    end

    yOffset = yOffset - 12
    local resetPositionButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate") -- 恢复默认位置按钮
    resetPositionButton:SetSize(200, 26)
    resetPositionButton:SetPoint("TOPLEFT", box, "TOPLEFT", 0, yOffset)
    resetPositionButton:SetText(localeTable.MINIMAP_BUTTON_RESET_POSITION or "")
    resetPositionButton:SetScript("OnClick", function()
      Toolbox.MinimapButton.ResetPositionToDefault()
      Toolbox.SettingsHost:BuildPage(Toolbox.SettingsHost:GetModulePageKey(MODULE_ID))
    end)
    yOffset = yOffset - 40

    box.realHeight = math.max(280, math.abs(yOffset) + 24)
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

--- 在 ADDON_LOADED 末尾调用：为每个设置模块、冒险手册、关于页注册悬停项模板（供玩家勾选加入菜单）。
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
    id = "tb_flyout_quest",
    order = 23,
    titleKey = "MINIMAP_FLYOUT_QUEST",
    tooltipKey = "MINIMAP_FLYOUT_QUEST_TOOLTIP",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
    onClick = function()
      if Toolbox.Quest and type(Toolbox.Quest.OpenMainFrame) == "function" then
        Toolbox.Quest.OpenMainFrame()
        return
      end
      if Toolbox.SettingsHost and type(Toolbox.SettingsHost.OpenToModulePage) == "function" then
        Toolbox.SettingsHost:OpenToModulePage("quest")
      end
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
