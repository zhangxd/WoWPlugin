--[[
  模块 mover：窗口拖动与位置记忆（modules.mover）。
  - 本插件自建 Frame：Toolbox.Mover.RegisterFrame（`opts.dragRegion` 优先；否则 `blizzardDragHitMode`：仅根或栈底空白层）。
  - 暴雪顶层：拖动条解析（resolveBlizzardDragRegion）；`blizzardDragHitMode` 为标题栏 + 空白时另挂栈底全窗层；自 UIPanel 管线 detach/reattach（ignoreFramePositionManager、
    UIPanelWindows、UISpecialFrames、UIPanelLayout）；位移用手动 SetPoint 非 StartMoving；ShowUIPanel/HideUIPanel/
    ToggleWorldMap 等与 OnShow 重挂；多面板打开后经 C_Timer 合并补正存档位置（见文内说明，主路径仍为 hook）。
  - ContainerFrameCombinedBags（组合背包）：不经 ShowUIPanel，通过 PANEL_KEYS + OnShow hook 补挂；
    顶部创建 20px 透明拖动手柄（__toolbox_mm_baghandle），随 mover 模块开关，无独立设置项。
  - 存档：modules.mover.frames[全局名]（TOPLEFT 相对 UIParent 为主）；暴雪顶层仅 `PANEL_KEYS` 内置名单。
]]

Toolbox.Mover = Toolbox.Mover or {}

local MODULE_ID = "mover"

local function getMoverDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.Config.GetModule(MODULE_ID)
end

local function isDebugEnabled()
  return getMoverDb().debug == true
end

local function debugPrint(message)
  if not isDebugEnabled() or not message or message == "" then
    return
  end
  Toolbox.Chat.PrintAddonMessage(message)
end

--- 是否启用「暴雪面板」拖动（与 `RegisterFrame` 一致，仅受模块总开关 `enabled` 控制）。
local function blizzardDragEnabled()
  local db = getMoverDb()
  return db.enabled ~= false
end

--- 命中模式：`titlebar` 仅标题/解析条；`titlebar_and_empty` 另加栈底全窗层以接住空白像素。
local HIT_TITLEBAR = "titlebar"
local HIT_TITLEBAR_EMPTY = "titlebar_and_empty"

--- 自建窗 `RegisterFrame` 登记项，供命中模式变更时重绑。
local addonDragRegistry = {}

--- 战斗中是否应阻止开始拖动（读 `allowDragInCombat`）。
---@return boolean 为 true 时应阻止
local function shouldBlockDragDueToCombat()
  local db = getMoverDb()
  if db.allowDragInCombat == true then
    return false
  end
  return InCombatLockdown()
end

--- 卸下单个 Region 上的拖动脚本。
---@param region Frame|nil
local function stripDragSurface(region)
  if not region then
    return
  end
  pcall(function()
    if region.RegisterForDrag then
      region:RegisterForDrag()
    end
  end)
  region:SetScript("OnDragStart", nil)
  region:SetScript("OnDragStop", nil)
end

---@param opts table|nil
---@return table
local function copyRegisterFrameOpts(opts)
  if type(opts) ~= "table" then
    return {}
  end
  return { dragRegion = opts.dragRegion }
end

---@param frame Frame
local function removeAddonRegistryEntry(frame)
  for i = #addonDragRegistry, 1, -1 do
    if addonDragRegistry[i].frame == frame then
      table.remove(addonDragRegistry, i)
    end
  end
end

---@param frame Frame
---@param key string
---@param opts table|nil
local function pushAddonRegistry(frame, key, opts)
  removeAddonRegistryEntry(frame)
  addonDragRegistry[#addonDragRegistry + 1] = {
    frame = frame,
    key = key,
    opts = copyRegisterFrameOpts(opts),
  }
end

local function saveFrameAddon(frame, key)
  local db = getMoverDb()
  db.frames = db.frames or {}
  local point, _, rel, x, y = frame:GetPoint()
  db.frames[key] = { point = point, rel = rel or "CENTER", x = x, y = y }
  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.MOVER_DEBUG_SAVE_FMT or "%s",
    tostring(key),
    tostring(point),
    tostring(rel or "CENTER"),
    tostring(x or 0),
    tostring(y or 0)
  ))
end

local function restoreFrameAddon(frame, key)
  local db = getMoverDb()
  local saved = db.frames and db.frames[key]
  if not saved then
    return
  end
  frame:ClearAllPoints()
  frame:SetPoint(saved.point, UIParent, saved.rel or "CENTER", saved.x, saved.y)
  local L = Toolbox.L or {}
  debugPrint(string.format(
    L.MOVER_DEBUG_RESTORE_FMT or "%s",
    tostring(key),
    tostring(saved.point),
    tostring(saved.rel or "CENTER"),
    tostring(saved.x or 0),
    tostring(saved.y or 0)
  ))
end

--- 对单框应用 `RegisterFrame` 拖动：`opts.dragRegion` 有则仅用该区域；否则按 `blizzardDragHitMode`。
---@param frame Frame
---@param key string
---@param opts table|nil
local function applyAddonFrameDrag(frame, key, opts)
  opts = opts or {}
  local db = getMoverDb()
  if db.enabled == false then
    return
  end
  stripDragSurface(opts.dragRegion)
  stripDragSurface(frame)
  stripDragSurface(frame.__toolbox_mm_draglayer)
  restoreFrameAddon(frame, key)
  frame:SetMovable(true)
  frame:SetUserPlaced(true)
  frame:SetClampedToScreen(true)
  if opts.dragRegion then
    if frame.__toolbox_mm_draglayer then
      pcall(function()
        frame.__toolbox_mm_draglayer:Hide()
      end)
    end
    local drag = opts.dragRegion
    pcall(function()
      drag:EnableMouse(true)
    end)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
      if shouldBlockDragDueToCombat() then
        return
      end
      frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
      saveFrameAddon(frame, key)
    end)
    local L = Toolbox.L or {}
    debugPrint(string.format(L.MOVER_DEBUG_REGISTER_FMT or "%s", tostring(key)))
    return
  end
  local mode = db.blizzardDragHitMode or HIT_TITLEBAR
  if mode == HIT_TITLEBAR_EMPTY then
    local layer = frame.__toolbox_mm_draglayer
    if not layer then
      layer = CreateFrame("Frame", nil, frame)
      frame.__toolbox_mm_draglayer = layer
    end
    layer:SetAllPoints(frame)
    layer:Show()
    pcall(function()
      layer:Lower()
    end)
    pcall(function()
      layer:EnableMouse(true)
    end)
    layer:RegisterForDrag("LeftButton")
    layer:SetScript("OnDragStart", function()
      if shouldBlockDragDueToCombat() then
        return
      end
      frame:StartMoving()
    end)
    layer:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
      saveFrameAddon(frame, key)
    end)
  else
    if frame.__toolbox_mm_draglayer then
      pcall(function()
        frame.__toolbox_mm_draglayer:Hide()
      end)
    end
    local drag = frame
    pcall(function()
      drag:EnableMouse(true)
    end)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
      if shouldBlockDragDueToCombat() then
        return
      end
      frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
      saveFrameAddon(frame, key)
    end)
  end
  local L = Toolbox.L or {}
  debugPrint(string.format(L.MOVER_DEBUG_REGISTER_FMT or "%s", tostring(key)))
end

--- 仅重绑自建登记窗（不跑暴雪 hook）。
local function refreshAddonRegisteredFramesOnly()
  for i = 1, #addonDragRegistry do
    local e = addonDragRegistry[i]
    if e.frame and e.key then
      pcall(function()
        applyAddonFrameDrag(e.frame, e.key, e.opts)
      end)
    end
  end
end

--- 为本插件自建框体启用拖动与位置记忆；战斗中是否可拖由 `allowDragInCombat` 与 `shouldBlockDragDueToCombat` 决定。
---@param frame Frame 目标框体
---@param key string 存档键
---@param opts table|nil 可选；`dragRegion` 为仅作为拖动命中区的子 Region（指定时忽略命中模式）
function Toolbox.Mover.RegisterFrame(frame, key, opts)
  opts = opts or {}
  local db = getMoverDb()
  if db.enabled == false then
    return
  end
  pushAddonRegistry(frame, key, opts)
  applyAddonFrameDrag(frame, key, opts)
end

--[[
  暴雪窗口拖动 · 原理（对齐 MoveAnything 等对 UIPanel 的处理）

  1) 移动谁：在「要记忆位置的根 Frame」上改锚点（全局名 = 存档键，如 WorldMapFrame）。子 Frame 单独拖无法带动整块。

  2) 从哪拖：RegisterForDrag 挂在命中区（见 resolveBlizzardDragRegion；大地图优先 TitleCanvasSpacerFrame）。

  3) 与面板管线：UIPanelWindows / UIPARENT_MANAGED_FRAME_POSITIONS 会驱动 FramePositionManager 每帧重锚，
     仅用 StartMoving 常被立刻抵消。故在 apply 时 detach（ignoreFramePositionManager、暂移出 UIPanelWindows、
     UISpecialFrames、UIPanelLayout-enabled），disable 时 reattach；位移用光标 delta + SetPoint(TOPLEFT)，
     与 MoveAnything 存盘思路一致。

  4) 入口：ShowUIPanel、HideUIPanel、ToggleWorldMap、OpenWorldMap / OpenQuestLog / ToggleQuestLog、WorldMapOnShow 等；
     Show/Hide 后对已可见窗口做「位置与存档比对」补正；C_Timer.After(0) 仅下一帧合并执行（AGENTS：非等布局主路径），
     0.06s 为同次打开流程内可能分帧重锚的二次补正。

  5) 生命周期：HookScript(OnShow) 重挂；受保护界面见 BLIZZARD_DRAG_DENY。
]]

-- 常见顶层名（补丁变更时请对照 /fstack）；ShowUIPanel 仍会挂接未列于此的合法全局框。
-- WorldMapFrame：大地图 + 任务侧栏（QuestMapFrame 为子 Frame）；QuestFrame：NPC 任务对话窗。
local PANEL_KEYS = {
  "CharacterFrame",
  "SpellBookFrame",
  "ClassTalentFrame",
  "PlayerSpellsFrame",
  "AchievementFrame",
  "WorldMapFrame",
  "QuestFrame",
  "CommunitiesFrame",
  "CollectionsJournal",
  "PVEFrame",
  "EncounterJournal",
  -- 组合背包：不经 ShowUIPanel，通过 OnShow hook 补挂；拖动条为顶部透明手柄（见 resolveBlizzardDragRegion）。
  "ContainerFrameCombinedBags",
}

-- 不参与拖动（受保护或易报错）。
-- GameMenuFrame：经 ShowUIPanel 打开；若 detach UIPanel 管线会破坏 ESC 菜单与战斗中安全路径，表现为菜单/选项无法操作。
-- SettingsPanel：零售系统「选项」独立顶层（若存在）；同上勿剥离管线。
local BLIZZARD_DRAG_DENY = {
  StoreFrame = true,
  OrderHallTalentFrame = true,
  GameMenuFrame = true,
  SettingsPanel = true,
}

--- 是否跳过 Blizzard 拖动挂接（内置受保护名单：商城、职业大厅天赋、ESC 菜单、系统选项顶层等）。
---@param name string 顶层 Frame 全局名
---@return boolean
local function isBlizzardPanelDragDenied(name)
  if type(name) ~= "string" or name == "" then
    return true
  end
  return BLIZZARD_DRAG_DENY[name] == true
end

--- 仅内置 `PANEL_KEYS`；ShowUIPanel 仍会挂接其它合法顶层名，但懒加载补挂名单不扩展。
local function getAllPanelKeys()
  return PANEL_KEYS
end

local function saveAsTopLeft(frame, key, db)
  local left, top = frame:GetLeft(), frame:GetTop()
  local ul, ut = UIParent:GetLeft(), UIParent:GetTop()
  if not left or not top or not ul or not ut then
    return false
  end
  db.frames = db.frames or {}
  db.frames[key] = {
    point = "TOPLEFT",
    rel = "TOPLEFT",
    x = left - ul,
    y = top - ut,
  }
  return true
end

local function migrateSavedToTopLeft(frame, key, s)
  if not s or s.point == "TOPLEFT" and (s.rel == "TOPLEFT" or s.rel == nil) then
    return s
  end
  frame:ClearAllPoints()
  frame:SetPoint(s.point, UIParent, s.rel or "CENTER", s.x, s.y)
  local db = getMoverDb()
  if saveAsTopLeft(frame, key, db) then
    return db.frames[key]
  end
  return s
end

local function saveBlizzardPanel(frame, key)
  local db = getMoverDb()
  db.frames = db.frames or {}
  if saveAsTopLeft(frame, key, db) then
    local saved = db.frames and db.frames[key]
    local L = Toolbox.L or {}
    debugPrint(string.format(
      L.MICROMENU_DEBUG_SAVE_FMT or "%s",
      tostring(key),
      tostring(saved and saved.x or 0),
      tostring(saved and saved.y or 0)
    ))
    return
  end
  local p, _, rel, x, y = frame:GetPoint()
  db.frames[key] = { point = p, rel = rel or "CENTER", x = x, y = y }
end

local function restoreBlizzardPanel(frame, key)
  local db = getMoverDb()
  local s = db.frames and db.frames[key]
  if not s then
    return
  end
  s = migrateSavedToTopLeft(frame, key, s)
  frame:ClearAllPoints()
  if s.point == "TOPLEFT" then
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", s.x, s.y)
  else
    frame:SetPoint(s.point, UIParent, s.rel or "CENTER", s.x, s.y)
  end
end

local POS_MATCH_EPS = 2
local function positionMatchesSaved(frame, key)
  local db = getMoverDb()
  local s = db.frames and db.frames[key]
  if not s then
    return true
  end
  if s.point ~= "TOPLEFT" then
    return false
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  local ul, ut = UIParent:GetLeft(), UIParent:GetTop()
  if not left or not top or not ul or not ut then
    return false
  end
  if math.abs((left - ul) - s.x) >= POS_MATCH_EPS then
    return false
  end
  if math.abs((top - ut) - s.y) >= POS_MATCH_EPS then
    return false
  end
  return true
end

local function restoreBlizzardPanelIfMisplaced(frame, key)
  local db = getMoverDb()
  if not db or db.enabled == false or not frame or not frame:IsShown() or not frame.__toolbox_mm_inited then
    return
  end
  if positionMatchesSaved(frame, key) then
    return
  end
  restoreBlizzardPanel(frame, key)
end

--- 解析拖动条：顺序与 § 暴雪窗口拖动原理一致（大地图 TitleCanvasSpacerFrame → 根 TitleContainer → Border.TitleContainer → BorderFrame）。
---@param frame Frame
---@return Frame
local function resolveBlizzardDragRegion(frame)
  if not frame then
    return frame
  end
  local fname = frame.GetName and frame:GetName() or nil
  -- 大地图须优先于 BorderFrame.TitleContainer：后者仅肖像旁窄条，NavBar 占满 Spacer 大部，玩家易点不中。
  if fname == "WorldMapFrame" and frame.TitleCanvasSpacerFrame then
    return frame.TitleCanvasSpacerFrame
  end
  -- 成就：TitleContainer 多在肖像侧较窄，中间标题区点不中；Header 为整块顶栏（含标题区域命中）。
  if fname == "AchievementFrame" and frame.Header then
    return frame.Header
  end
  -- 组合背包：无标题栏，在顶部创建一条透明拖动手柄（仅创建一次，复用同一对象）。
  if fname == "ContainerFrameCombinedBags" then
    if not frame.__toolbox_mm_baghandle then
      local handle = CreateFrame("Frame", nil, frame)
      handle:SetHeight(20)
      handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
      handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
      handle:EnableMouse(true)
      frame.__toolbox_mm_baghandle = handle
    end
    return frame.__toolbox_mm_baghandle
  end
  if frame.TitleContainer then
    return frame.TitleContainer
  end
  local bf = frame.BorderFrame
  if bf and bf.TitleContainer then
    return bf.TitleContainer
  end
  if bf then
    return bf
  end
  return frame
end

--- 参考 MoveAnything Modules/Position：受 FramePositionManager / UIPanel 管线管理的窗口若不排除，
--- 暴雪每帧会重锚，StartMoving 几乎立刻被抵消，表现为「拖不动」。此处临时剥离并在禁用时恢复。
local function detachBlizzardPanelLayout(frame, key)
  if not frame or not key or frame.__toolbox_mm_detached then
    return
  end
  if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS[key] then
    frame.ignoreFramePositionManager = true
    frame.__toolbox_mm_ifpm = true
  end
  if UIPanelWindows and UIPanelWindows[key] then
    frame.__toolbox_savedUIPanelWindows = UIPanelWindows[key]
    UIPanelWindows[key] = nil
    pcall(function()
      frame:SetAttribute("UIPanelLayout-enabled", false)
    end)
    if UISpecialFrames then
      local found = false
      for i, v in ipairs(UISpecialFrames) do
        if v == key then
          found = true
          break
        end
      end
      if not found then
        table.insert(UISpecialFrames, key)
      end
      frame.__toolbox_mm_uispecial = true
    end
  end
  frame.__toolbox_mm_detached = true
end

local function reattachBlizzardPanelLayout(frame, key)
  if not frame or not key or not frame.__toolbox_mm_detached then
    return
  end
  if frame.__toolbox_mm_ifpm then
    frame.ignoreFramePositionManager = nil
    frame.__toolbox_mm_ifpm = nil
  end
  if frame.__toolbox_savedUIPanelWindows and UIPanelWindows then
    UIPanelWindows[key] = frame.__toolbox_savedUIPanelWindows
    frame.__toolbox_savedUIPanelWindows = nil
    pcall(function()
      frame:SetAttribute("UIPanelLayout-enabled", true)
    end)
  end
  if frame.__toolbox_mm_uispecial and UISpecialFrames then
    for i, v in ipairs(UISpecialFrames) do
      if v == key then
        table.remove(UISpecialFrames, i)
        break
      end
    end
    frame.__toolbox_mm_uispecial = nil
  end
  frame.__toolbox_mm_detached = nil
end

--- 不用 StartMoving：以光标位移驱动 TOPLEFT 相对 UIParent；scale 取拖动起点时 UIParent 有效缩放，拖动中不变更。
---@param frame Frame 要移动的暴雪根 Frame
local function blizzardPanelManualDragStart(frame)
  local ul = UIParent:GetLeft() or 0
  local ut = UIParent:GetTop() or 0
  local scale = UIParent:GetEffectiveScale() or 1
  if scale == 0 then
    scale = 1
  end
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local fl, ft = frame:GetLeft(), frame:GetTop()
  if not fl or not ft then
    return
  end
  frame.__toolbox_mm_drag = {
    sx = cx,
    sy = cy,
    ox = fl - ul,
    oy = ft - ut,
  }
  frame:SetScript("OnUpdate", function(self)
    local d = self.__toolbox_mm_drag
    if not d then
      return
    end
    local nx, ny = GetCursorPosition()
    nx, ny = nx / scale, ny / scale
    local dx = nx - d.sx
    local dy = ny - d.sy
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", d.ox + dx, d.oy + dy)
  end)
end

---@param frame Frame
---@param key string 全局名，与 saveBlizzardPanel 存档键一致
local function blizzardPanelManualDragStop(frame, key)
  frame:SetScript("OnUpdate", nil)
  frame.__toolbox_mm_drag = nil
  saveBlizzardPanel(frame, key)
end

--- 对单个已挂接面板应用：读档、detach、挂拖动条与手动位移；重复调用会覆盖同名拖动脚本。
---@param frame Frame
---@param key string
local function applyBlizzardPanel(frame, key)
  if not blizzardDragEnabled() then
    return
  end
  if isBlizzardPanelDragDenied(key) then
    return
  end
  local titleDrag = resolveBlizzardDragRegion(frame)
  stripDragSurface(titleDrag)
  stripDragSurface(frame.__toolbox_mm_draglayer)
  restoreBlizzardPanel(frame, key)
  detachBlizzardPanelLayout(frame, key)
  frame:SetMovable(true)
  frame:SetUserPlaced(true)
  frame:SetClampedToScreen(true)
  local db = getMoverDb()
  local mode = db.blizzardDragHitMode or HIT_TITLEBAR
  ---@param drag Frame
  local function bindBlizzardDragSurface(drag)
    pcall(function()
      drag:EnableMouse(true)
    end)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
      if shouldBlockDragDueToCombat() then
        return
      end
      blizzardPanelManualDragStart(frame)
    end)
    drag:SetScript("OnDragStop", function()
      blizzardPanelManualDragStop(frame, key)
    end)
  end
  if mode == HIT_TITLEBAR_EMPTY then
    local layer = frame.__toolbox_mm_draglayer
    if not layer then
      layer = CreateFrame("Frame", nil, frame)
      frame.__toolbox_mm_draglayer = layer
    end
    layer:SetAllPoints(frame)
    layer:Show()
    pcall(function()
      layer:Lower()
    end)
    bindBlizzardDragSurface(titleDrag)
    bindBlizzardDragSurface(layer)
  else
    if frame.__toolbox_mm_draglayer then
      pcall(function()
        frame.__toolbox_mm_draglayer:Hide()
      end)
    end
    bindBlizzardDragSurface(titleDrag)
  end
  --- 提高标题/解析条层级，避免顶栏装饰/子控件盖住标题区导致 RegisterForDrag 点不中（成就等）。
  pcall(function()
    local dl = titleDrag:GetFrameLevel() or 0
    local fl = frame:GetFrameLevel() or 0
    if dl < fl + 20 then
      titleDrag:SetFrameLevel(fl + 25)
    end
  end)
  local L = Toolbox.L or {}
  debugPrint(string.format(L.MICROMENU_DEBUG_APPLY_FMT or "%s", tostring(key)))
end

--- 标记已挂接并应用暴雪拖动（与 ShowUIPanel / 可见刷新等路径共用，避免 __toolbox_mm_inited 与 apply 分叉）。
---@param frame Frame
---@param key string 全局名
local function ensureBlizzardPanelApplied(frame, key)
  if isBlizzardPanelDragDenied(key) then
    return
  end
  if not frame.__toolbox_mm_inited then
    frame.__toolbox_mm_inited = true
  end
  applyBlizzardPanel(frame, key)
end

--- 关闭拖动：清 OnUpdate、reattach 布局管线、卸 RegisterForDrag。
--- 不在此调用 SetMovable(false)：第三方插件可能对根 Frame 仍执行
--- StartMoving；若强行不可移动会导致其 OnDrag 路径报错。
---@param frame Frame|nil
local function disableBlizzardPanel(frame)
  if not frame then
    return
  end
  local key = frame.GetName and frame:GetName() or nil
  frame:SetScript("OnUpdate", nil)
  frame.__toolbox_mm_drag = nil
  if key then
    reattachBlizzardPanelLayout(frame, key)
  end
  local titleDrag = resolveBlizzardDragRegion(frame)
  stripDragSurface(titleDrag)
  stripDragSurface(frame.__toolbox_mm_draglayer)
  if frame.__toolbox_mm_draglayer then
    pcall(function()
      frame.__toolbox_mm_draglayer:Hide()
    end)
  end
end

local hooked = {}
local skipped = {}

local tabRestoreDriver
local tabRestoreUntil = {}
local TAB_RESTORE_BURST_SEC = 0.18

local function tabRestoreDriverTick()
  local db = getMoverDb()
  if not db or db.enabled == false then
    wipe(tabRestoreUntil)
    if tabRestoreDriver then
      tabRestoreDriver:SetScript("OnUpdate", nil)
    end
    return
  end
  local now = GetTime()
  local keys = {}
  for k in pairs(tabRestoreUntil) do
    keys[#keys + 1] = k
  end
  for _, key in ipairs(keys) do
    local tEnd = tabRestoreUntil[key]
    if tEnd and now >= tEnd then
      tabRestoreUntil[key] = nil
    elseif tEnd then
      local f = _G[key]
      if f and f:IsShown() and f.__toolbox_mm_inited then
        restoreBlizzardPanelIfMisplaced(f, key)
      end
    end
  end
  if not next(tabRestoreUntil) and tabRestoreDriver then
    tabRestoreDriver:SetScript("OnUpdate", nil)
  end
end

local function beginTabRestoreBurst(key)
  tabRestoreUntil[key] = GetTime() + TAB_RESTORE_BURST_SEC
  if not tabRestoreDriver then
    tabRestoreDriver = CreateFrame("Frame", "ToolboxMoverTabRestoreDriver", UIParent)
  end
  tabRestoreDriver:SetScript("OnUpdate", tabRestoreDriverTick)
end

--- 页签控件常在子 Frame 上，向上找到已挂接的顶层 Global（如 AchievementFrame）。
local function resolveHookedRootPanel(startFrame)
  local f = startFrame
  local depth = 0
  while f and depth < 24 do
    depth = depth + 1
    local n = f.GetName and f:GetName()
    if type(n) == "string" and n ~= "" and hooked[n] then
      return f, n
    end
    f = f.GetParent and f:GetParent()
  end
  return nil, nil
end

--- 前向声明：`installTabSwitchHook` 需在切页后与 ShowUIPanel 一样做延迟位置补正（第三方插件可能分帧改布局）。
local schedulePostShowPanelRestore

local tabSwitchHookAttempted = false
local function installTabSwitchHook()
  if tabSwitchHookAttempted or not hooksecurefunc then
    return
  end
  tabSwitchHookAttempted = true
  pcall(function()
    hooksecurefunc("PanelTemplates_SetTab", function(frame, id)
      if not frame then
        return
      end
      local root, name = resolveHookedRootPanel(frame)
      if not root or not name then
        return
      end
      restoreBlizzardPanelIfMisplaced(root, name)
      beginTabRestoreBurst(name)
      --- 部分第三方插件会在切页后继续改子面板锚点，与 ShowUIPanel 相同做下一帧/短延迟全量补正。
      if schedulePostShowPanelRestore then
        schedulePostShowPanelRestore()
      end
    end)
  end)
end

--- 检测 WorldMapFrame 当前是否处于嵌入模式（任务日志侧栏）。
--- 嵌入时父级为任务日志容器而非 UIParent，Blizzard 完全控制其位置；
--- 此时 Mover 不应 restore，否则会把地图拉离任务日志造成闪烁。
---@return boolean 为 true 表示嵌入模式，Mover 应跳过 restore
local function isWorldMapEmbedded()
  local f = _G.WorldMapFrame
  if not f then
    return false
  end
  -- 全屏模式：父级为 UIParent；嵌入模式：父级为任务日志容器（非 UIParent）
  local parent = f:GetParent()
  if not parent then
    return false
  end
  return parent ~= UIParent
end

local function attachBlizzardOnShow(name, frame)
  if hooked[name] or skipped[name] then
    return
  end
  if isBlizzardPanelDragDenied(name) then
    return
  end
  if not frame or not frame.HookScript then
    return
  end
  local hookOk = pcall(function()
    frame:HookScript("OnShow", function(self)
      local function run()
        if blizzardDragEnabled() then
          -- WorldMapFrame 嵌入任务侧栏时 Blizzard 控制位置，跳过 apply/restore 避免闪烁
          if name == "WorldMapFrame" and isWorldMapEmbedded() then
            return
          end
          ensureBlizzardPanelApplied(self, name)
        else
          if not self.__toolbox_mm_inited then
            self.__toolbox_mm_inited = true
          end
          disableBlizzardPanel(self)
        end
      end
      pcall(run)
    end)
  end)
  if not hookOk then
    skipped[name] = true
    return
  end
  hooked[name] = true
end

local function hookPanelByKey(key)
  if hooked[key] or skipped[key] then
    return
  end
  if isBlizzardPanelDragDenied(key) then
    return
  end
  local f = _G[key]
  if not f or not f.HookScript then
    return
  end
  attachBlizzardOnShow(key, f)
end

--- 先内置+额外名单，再已挂接名；同名只执行一次（与 restore 一致）。
local function forEachUniqueTrackedPanelKey(fn)
  local seen = {}
  local function run(key)
    if type(key) ~= "string" or key == "" or seen[key] then
      return
    end
    seen[key] = true
    fn(key)
  end
  for _, key in ipairs(getAllPanelKeys()) do
    run(key)
  end
  for name in pairs(hooked) do
    run(name)
  end
end

local function applyVisibleBlizzardPanels()
  forEachUniqueTrackedPanelKey(function(key)
    local f = _G[key]
    if f and f:IsShown() then
      pcall(function()
        ensureBlizzardPanelApplied(f, key)
      end)
    end
  end)
end

local function disableVisibleBlizzardPanels()
  forEachUniqueTrackedPanelKey(function(key)
    local frame = _G[key]
    if frame then
      pcall(function()
        disableBlizzardPanel(frame)
      end)
    end
  end)
end

local function tryHookPendingPanels()
  for _, key in ipairs(getAllPanelKeys()) do
    hookPanelByKey(key)
  end
end

--- 对已挂接且仍显示的暴雪窗口，若当前位置与存档偏差则 restore（多面板切换后 UIParent 可能重锚）。
--- WorldMapFrame 嵌入模式（任务侧栏）时跳过，避免把地图拉离任务日志造成闪烁。
local function restoreAllVisibleTrackedPanelsIfMisplaced()
  if not blizzardDragEnabled() then
    return
  end
  forEachUniqueTrackedPanelKey(function(key)
    local f = _G[key]
    if not f or not f.IsShown or not f:IsShown() or not f.__toolbox_mm_inited then
      return
    end
    -- WorldMapFrame 嵌入任务侧栏时 Blizzard 控制位置，跳过 restore
    if key == "WorldMapFrame" and isWorldMapEmbedded() then
      return
    end
    pcall(function()
      restoreBlizzardPanelIfMisplaced(f, key)
    end)
  end)
end

--- ShowUIPanel / PanelTemplates_SetTab 后下一帧与短延迟各补一次位置（主路径为 hook；见 AGENTS 定时器例外说明）。
schedulePostShowPanelRestore = function()
  --- After(0)：下一帧合并补正，主路径已为 hooksecurefunc(ShowUIPanel)。
  C_Timer.After(0, function()
    if blizzardDragEnabled() then
      restoreAllVisibleTrackedPanelsIfMisplaced()
    end
  end)
  --- 同次打开流程内部分客户端仍分帧重锚，短延迟二次比对。
  C_Timer.After(0.06, function()
    if blizzardDragEnabled() then
      restoreAllVisibleTrackedPanelsIfMisplaced()
    end
  end)
end

local addonLoadedHookInstalled = false
local addonLoadedHookFrame = nil  -- 持久监听 Frame，禁用时 UnregisterEvent
local universalShowUIPanelHookInstalled = false
local hideUIPanelHookInstalled = false
local hookToggleWorldMapDone = false
--- OpenWorldMap / OpenQuestLog / ToggleQuestLog 各自是否已成功 hooksecurefunc。
local WORLD_MAP_GLOBAL_HOOK_NAMES = { "OpenWorldMap", "OpenQuestLog", "ToggleQuestLog" }
local worldMapGlobalFuncHooked = {
  OpenWorldMap = false,
  OpenQuestLog = false,
  ToggleQuestLog = false,
}
local worldMapOnShowRegistered = false
local enteringWorldHookInstalled = false
local enteringWorldHookFrame = nil  -- 持久监听 Frame，禁用时 UnregisterEvent

--- WorldMapFrame：下一帧再 apply，补 OpenWorldMap/任务日志等路径及 Blizzard OnShow 后覆盖脚本的竞态。
--- 嵌入模式（任务侧栏）下仅挂接 hook，不 restore 位置，避免把地图拉离任务日志造成闪烁。
local worldMapOnShowOwner = {}
local function applyWorldMapFrameDragDeferred()
  if not blizzardDragEnabled() then
    return
  end
  --- After(0)：下一帧合并 apply/restore，与 OpenWorldMap 等 hook、WorldMap OnShow 配合；非单独「等布局」主路径（AGENTS 例外）。
  C_Timer.After(0, function()
    if not blizzardDragEnabled() then
      return
    end
    local f = _G.WorldMapFrame
    if not f or not f:IsShown() then
      return
    end
    pcall(function()
      if not hooked.WorldMapFrame then
        attachBlizzardOnShow("WorldMapFrame", f)
      end
      -- 嵌入模式（任务侧栏）：Blizzard 控制位置，跳过 restore 避免闪烁
      if isWorldMapEmbedded() then
        return
      end
      ensureBlizzardPanelApplied(f, "WorldMapFrame")
      if blizzardDragEnabled() then
        restoreAllVisibleTrackedPanelsIfMisplaced()
      end
    end)
  end)
end

--- 除 ToggleWorldMap 外，OpenWorldMap / OpenQuestLog / ToggleQuestLog 亦会显示地图或任务侧栏；WorldMapOnShow 在 OnShow 末尾再补挂一层。
--- 各函数在 Blizzard_Map 等加载后方存在，须在 ADDON_LOADED 中反复尝试直至成功。
local function installWorldMapAuxHooks()
  if not hooksecurefunc then
    return
  end
  for _, globalName in ipairs(WORLD_MAP_GLOBAL_HOOK_NAMES) do
    if not worldMapGlobalFuncHooked[globalName] and type(_G[globalName]) == "function" then
      local ok = pcall(function()
        hooksecurefunc(globalName, function()
          applyWorldMapFrameDragDeferred()
        end)
      end)
      if ok then
        worldMapGlobalFuncHooked[globalName] = true
      end
    end
  end
  local ER = _G.EventRegistry
  if not worldMapOnShowRegistered and ER and ER.RegisterCallback then
    local ok = pcall(function()
      ER:RegisterCallback("WorldMapOnShow", function()
        applyWorldMapFrameDragDeferred()
      end, worldMapOnShowOwner)
    end)
    if ok then
      worldMapOnShowRegistered = true
    end
  end
end

--- 经 ShowUIPanel 打开的顶层界面：尽可能全部挂接（排除受保护名单），行为接近 BlizzMove 类插件。
local function installUniversalShowUIPanelHook()
  if universalShowUIPanelHookInstalled or not hooksecurefunc then
    return
  end
  local ok = pcall(function()
    hooksecurefunc("ShowUIPanel", function(frame)
      if not blizzardDragEnabled() then
        return
      end
      if not frame or not frame.GetName or not frame.HookScript then
        return
      end
      local name = frame:GetName()
      if not name or name == "" then
        return
      end
      if isBlizzardPanelDragDenied(name) then
        return
      end
      if not hooked[name] then
        attachBlizzardOnShow(name, frame)
      end
      pcall(function()
        ensureBlizzardPanelApplied(frame, name)
      end)
      schedulePostShowPanelRestore()
    end)
  end)
  if ok then
    universalShowUIPanelHookInstalled = true
  end
end

--- HideUIPanel 后其余仍可见的面板也可能被重排，补断言存档位置。
local function installHideUIPanelHook()
  if hideUIPanelHookInstalled or not hooksecurefunc then
    return
  end
  local ok = pcall(function()
    hooksecurefunc("HideUIPanel", function()
      if not blizzardDragEnabled() then
        return
      end
      --- Hide 后其余可见面板可能被重排；After(0) 下一帧合并补正（主路径为 hook）。
      C_Timer.After(0, function()
        if blizzardDragEnabled() then
          restoreAllVisibleTrackedPanelsIfMisplaced()
        end
      end)
    end)
  end)
  if ok then
    hideUIPanelHookInstalled = true
  end
end

--- ToggleWorldMap：与 OpenWorldMap 等共用 applyWorldMapFrameDragDeferred（晚于 Blizzard_Map 加载时再挂）。
local function installToggleWorldMapHook()
  if hookToggleWorldMapDone or not hooksecurefunc then
    return
  end
  if type(_G.ToggleWorldMap) ~= "function" then
    return
  end
  local ok = pcall(function()
    hooksecurefunc("ToggleWorldMap", function()
      applyWorldMapFrameDragDeferred()
    end)
  end)
  if ok then
    hookToggleWorldMapDone = true
  end
end

--- ADDON_LOADED / PLAYER_ENTERING_WORLD 共用：补挂待处理面板、刷新可见、再尝试地图相关 hook。
local function runLazyHookRefresh()
  local db = getMoverDb()
  if not db or db.enabled == false then
    return
  end
  tryHookPendingPanels()
  applyVisibleBlizzardPanels()
  installWorldMapAuxHooks()
  installToggleWorldMapHook()
end

local function installAddonLoadedHook()
  if addonLoadedHookInstalled then
    return
  end
  addonLoadedHookInstalled = true
  addonLoadedHookFrame = CreateFrame("Frame", "ToolboxMoverLazyHook", UIParent)
  addonLoadedHookFrame:RegisterEvent("ADDON_LOADED")
  addonLoadedHookFrame:SetScript("OnEvent", runLazyHookRefresh)
end

local function installEnteringWorldHook()
  if enteringWorldHookInstalled then
    return
  end
  enteringWorldHookInstalled = true
  enteringWorldHookFrame = CreateFrame("Frame", "ToolboxMoverPEWHook", UIParent)
  enteringWorldHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  enteringWorldHookFrame:SetScript("OnEvent", runLazyHookRefresh)
end

local function installLazyBlizzardHooks()
  installAddonLoadedHook()
  installUniversalShowUIPanelHook()
  installHideUIPanelHook()
  installWorldMapAuxHooks()
  installToggleWorldMapHook()
  installEnteringWorldHook()
end

local function blizzardRunHooks()
  local db = getMoverDb()
  if db.enabled == false then
    return
  end
  installTabSwitchHook()
  installLazyBlizzardHooks()
  tryHookPendingPanels()
  applyVisibleBlizzardPanels()
end

--- 供设置页：命中模式等变更后，重绑已登记自建窗并刷新当前可见暴雪窗。
function Toolbox.Mover.RefreshDragConfiguration()
  refreshAddonRegisteredFramesOnly()
  if blizzardDragEnabled() then
    applyVisibleBlizzardPanels()
  end
end

--- 供设置页与旧 API 刷新：重新尝试懒加载 Hook 与当前可见面板的拖动应用。
function Toolbox.Mover.BlizzardPanelsRefresh()
  blizzardRunHooks()
  refreshAddonRegisteredFramesOnly()
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_MOVER",
  settingsIntroKey = "MODULE_MOVER_INTRO",
  settingsOrder = 20,
  OnModuleLoad = function() end,
  OnModuleEnable = function()
    blizzardRunHooks()
    refreshAddonRegisteredFramesOnly()
  end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_MOVER or MODULE_ID))
    if enabled then
      -- 重新挂接事件监听（禁用时已注销）
      if addonLoadedHookFrame then
        addonLoadedHookFrame:RegisterEvent("ADDON_LOADED")
      end
      if enteringWorldHookFrame then
        enteringWorldHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
      end
      blizzardRunHooks()
    else
      -- 持久监听 Frame 禁用时注销，避免模块关闭后仍触发回调
      if addonLoadedHookFrame then
        addonLoadedHookFrame:UnregisterEvent("ADDON_LOADED")
      end
      if enteringWorldHookFrame then
        enteringWorldHookFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
      end
      disableVisibleBlizzardPanels()
    end
  end,
  OnDebugSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_DEBUG_ON_FMT" or "SETTINGS_MODULE_DEBUG_OFF_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_MOVER or MODULE_ID))
  end,
  ResetToDefaultsAndRebuild = function()
    Toolbox.Config.ResetModule(MODULE_ID)
    blizzardRunHooks()
    refreshAddonRegisteredFramesOnly()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {}
    local db = getMoverDb()
    local y = 0
    local en = db.enabled ~= false

    local hitSec = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hitSec:SetPoint("TOPLEFT", 0, y)
    hitSec:SetWidth(560)
    hitSec:SetJustifyH("LEFT")
    hitSec:SetText(L.MOVER_SETTINGS_HIT_TITLE)
    y = y - 22

    local hitSub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hitSub:SetPoint("TOPLEFT", 0, y)
    hitSub:SetWidth(560)
    hitSub:SetJustifyH("LEFT")
    hitSub:SetText(L.MOVER_SETTINGS_HIT_SUB)
    y = y - math.max(32, math.ceil((hitSub:GetStringHeight() or 0) + 10))

    local rbTitle = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    rbTitle:SetSize(22, 22)
    rbTitle:SetPoint("TOPLEFT", 0, y)
    local rbTitleL = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rbTitleL:SetPoint("LEFT", rbTitle, "RIGHT", 6, 0)
    rbTitleL:SetWidth(520)
    rbTitleL:SetJustifyH("LEFT")
    rbTitleL:SetText(L.MOVER_SETTINGS_HIT_TITLEBAR)

    local rbEmpty = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    rbEmpty:SetSize(22, 22)
    rbEmpty:SetPoint("TOPLEFT", 0, y - 26)
    local rbEmptyL = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rbEmptyL:SetPoint("LEFT", rbEmpty, "RIGHT", 6, 0)
    rbEmptyL:SetWidth(520)
    rbEmptyL:SetJustifyH("LEFT")
    rbEmptyL:SetText(L.MOVER_SETTINGS_HIT_TITLEBAR_EMPTY)

    local function syncHitRadios()
      local m = db.blizzardDragHitMode or HIT_TITLEBAR
      rbTitle:SetChecked(m == HIT_TITLEBAR)
      rbEmpty:SetChecked(m == HIT_TITLEBAR_EMPTY)
    end
    syncHitRadios()
    rbTitle:SetEnabled(en)
    rbEmpty:SetEnabled(en)
    rbTitle:SetScript("OnClick", function()
      db.blizzardDragHitMode = HIT_TITLEBAR
      syncHitRadios()
      Toolbox.Mover.RefreshDragConfiguration()
    end)
    rbEmpty:SetScript("OnClick", function()
      db.blizzardDragHitMode = HIT_TITLEBAR_EMPTY
      syncHitRadios()
      Toolbox.Mover.RefreshDragConfiguration()
    end)
    y = y - 56

    local combatSec = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatSec:SetPoint("TOPLEFT", 0, y)
    combatSec:SetWidth(560)
    combatSec:SetJustifyH("LEFT")
    combatSec:SetText(L.MOVER_SETTINGS_COMBAT_TITLE)
    y = y - 22

    local combatSub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    combatSub:SetPoint("TOPLEFT", 0, y)
    combatSub:SetWidth(560)
    combatSub:SetJustifyH("LEFT")
    combatSub:SetText(L.MOVER_SETTINGS_COMBAT_SUB)
    y = y - math.max(28, math.ceil((combatSub:GetStringHeight() or 0) + 6))

    local cbCombat = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    cbCombat:SetSize(22, 22)
    cbCombat:SetPoint("TOPLEFT", 0, y)
    local cbCombatL = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbCombatL:SetPoint("LEFT", cbCombat, "RIGHT", 6, 0)
    cbCombatL:SetWidth(520)
    cbCombatL:SetJustifyH("LEFT")
    cbCombatL:SetText(L.MOVER_SETTINGS_COMBAT_CHECK)
    cbCombat:SetChecked(db.allowDragInCombat == true)
    cbCombat:SetEnabled(en)
    cbCombat:SetScript("OnClick", function(self)
      db.allowDragInCombat = self:GetChecked() == true
    end)
    y = y - 28

    box.realHeight = math.abs(y) + 8
  end,
})
