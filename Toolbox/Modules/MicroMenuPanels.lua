--[[
  模块 micromenu_panels：白名单内暴雪「主面板」拖动与存档（modules.micromenu_panels.frames）。
  不处理微型按钮条；内置名见 PANEL_KEYS，另支持存档 extraFrameNames（设置页或 /toolbox mmadd）。
  成就等常懒加载：ADDON_LOADED / ShowUIPanel 补挂 Hook。无法自动枚举「所有」暴雪窗体（需全局名且部分受保护）。
]]

-- 与其它脚本覆盖 _G.Toolbox 时保持一致（见 Core/Namespace.lua）
local function getMicroMenuDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.DB.GetModule("micromenu_panels")
end

-- 正式服常见顶层名；若某版本改名需对照 /fstack 更新。
-- 不包含 StoreFrame：商城等为受保护界面，插件 HookScript/拖动会触发安全错误。
local PANEL_KEYS = {
  "CharacterFrame",
  "SpellBookFrame",
  "ClassTalentFrame",
  "PlayerSpellsFrame",
  "AchievementFrame",
  "QuestMapFrame",
  "CommunitiesFrame",
  "CollectionsJournal",
  "PVEFrame",
  "EncounterJournal",
}

local function strtrim(s)
  if not s then
    return ""
  end
  return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
end

local function isBuiltinPanelKey(key)
  for _, k in ipairs(PANEL_KEYS) do
    if k == key then
      return true
    end
  end
  return false
end

-- 解析设置框文本 -> 存档用的名字数组（# 行为注释）
local function parseExtraFrameNames(text)
  local out = {}
  local seen = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    line = strtrim(line)
    if line ~= "" and not line:match("^#") then
      if line:match("^[%a_][%w_]*$") then
        if not seen[line] then
          seen[line] = true
          out[#out + 1] = line
        end
      end
    end
  end
  return out
end

-- 内置白名单 + modules.micromenu_panels.extraFrameNames（去重）
local function getAllPanelKeys()
  local db = getMicroMenuDb()
  local out = {}
  local seen = {}
  for _, key in ipairs(PANEL_KEYS) do
    out[#out + 1] = key
    seen[key] = true
  end
  local extras = db.extraFrameNames
  if type(extras) == "table" then
    for _, key in ipairs(extras) do
      if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        out[#out + 1] = key
      end
    end
  end
  return out
end

-- 白名单内各面板在切换子页签或内容高度变化时，CENTER 等锚点会导致视觉「漂移」。统一固定为相对 UIParent 的左上角存档与恢复。
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
  local db = getMicroMenuDb()
  if saveAsTopLeft(frame, key, db) then
    return db.frames[key]
  end
  return s
end

local function savePanel(frame, key)
  local db = getMicroMenuDb()
  db.frames = db.frames or {}
  if saveAsTopLeft(frame, key, db) then
    return
  end
  local p, _, rel, x, y = frame:GetPoint()
  db.frames[key] = { point = p, rel = rel or "CENTER", x = x, y = y }
end

local function restorePanel(frame, key)
  local db = getMicroMenuDb()
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

-- 与存档一致则不再 ClearAllPoints，减少页签切换时多余布局导致的闪烁
local POS_MATCH_EPS = 2
local function positionMatchesSaved(frame, key)
  local db = getMicroMenuDb()
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

local function restorePanelIfMisplaced(frame, key)
  local db = getMicroMenuDb()
  if not db or not db.enabled or not frame or not frame:IsShown() or not frame.__toolbox_mm_inited then
    return
  end
  if positionMatchesSaved(frame, key) then
    return
  end
  restorePanel(frame, key)
end

-- 战斗中 InCombatLockdown 则禁止 StartMoving，减少安全框体报错
local function applyPanel(frame, key)
  local db = getMicroMenuDb()
  if not db.enabled then
    return
  end
  restorePanel(frame, key)
  frame:SetMovable(true)
  frame:SetUserPlaced(true)
  frame:SetClampedToScreen(true)
  -- 整框体常被子控件挡住点击；有 TitleContainer 时拖标题栏（与暴雪面板习惯一致）
  local drag = frame.TitleContainer or frame
  if drag.EnableMouse then
    drag:EnableMouse(true)
  end
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    if InCombatLockdown() then
      return
    end
    frame:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePanel(frame, key)
  end)
end

local hooked = {}
-- HookScript 失败或受暴雪保护的 Frame，不再反复尝试（避免刷屏）
local skipped = {}

-- 切换页签时暴雪会重设锚点；后续数帧内还可能再改。用短时 OnUpdate 每帧仅在偏离存档时 SetPoint，
-- 避免 C_Timer 与多次无条件 ClearAllPoints 带来的可见闪烁。
local tabRestoreDriver
local tabRestoreUntil = {}
local TAB_RESTORE_BURST_SEC = 0.18

local function tabRestoreDriverTick()
  local db = getMicroMenuDb()
  if not db or not db.enabled then
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
        restorePanelIfMisplaced(f, key)
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
    tabRestoreDriver = CreateFrame("Frame", "ToolboxMicroMenuTabRestoreDriver", UIParent)
  end
  tabRestoreDriver:SetScript("OnUpdate", tabRestoreDriverTick)
end

local tabSwitchHookAttempted = false
local function installTabSwitchHook()
  if tabSwitchHookAttempted or not hooksecurefunc then
    return
  end
  tabSwitchHookAttempted = true
  pcall(function()
    hooksecurefunc("PanelTemplates_SetTab", function(frame, id)
      if not frame or not frame.GetName then
        return
      end
      local name = frame:GetName()
      if not name then
        return
      end
      for _, key in ipairs(getAllPanelKeys()) do
        if key == name then
          restorePanelIfMisplaced(frame, key)
          beginTabRestoreBurst(key)
          return
        end
      end
    end)
  end)
end

local function hookPanel(key)
  if hooked[key] or skipped[key] then
    return
  end
  local f = _G[key]
  if not f or not f.HookScript then
    return
  end
  local hookOk = pcall(function()
    f:HookScript("OnShow", function(self)
      local function run()
        if not self.__toolbox_mm_inited then
          self.__toolbox_mm_inited = true
          applyPanel(self, key)
        else
          restorePanel(self, key)
        end
      end
      pcall(run)
    end)
  end)
  if not hookOk then
    skipped[key] = true
    return
  end
  hooked[key] = true
end

-- 已在屏幕上的面板不会再次触发 OnShow，需在启用模块或勾选开关后主动 apply
local function applyVisiblePanels()
  for _, key in ipairs(getAllPanelKeys()) do
    local f = _G[key]
    if f and f:IsShown() then
      pcall(function()
        if not f.__toolbox_mm_inited then
          f.__toolbox_mm_inited = true
        end
        applyPanel(f, key)
      end)
    end
  end
end

-- 成就等面板随 Blizzard_* 子插件懒加载，PLAYER_LOGIN 时 _G 可能仍为 nil；仅 1s/5s 重试会永远挂不上 Hook。
local function tryHookPendingPanels()
  for _, key in ipairs(getAllPanelKeys()) do
    hookPanel(key)
  end
end

local addonLoadedHookInstalled = false
local showUIPanelHookInstalled = false

local function installAddonLoadedHook()
  if addonLoadedHookInstalled then
    return
  end
  addonLoadedHookInstalled = true
  local ev = CreateFrame("Frame", "ToolboxMicroMenuLazyHook", UIParent)
  ev:RegisterEvent("ADDON_LOADED")
  ev:SetScript("OnEvent", function()
    local db = getMicroMenuDb()
    if not db or not db.enabled then
      return
    end
    tryHookPendingPanels()
    applyVisiblePanels()
  end)
end

local function installShowUIPanelHook()
  if showUIPanelHookInstalled or not hooksecurefunc then
    return
  end
  local ok = pcall(function()
    hooksecurefunc("ShowUIPanel", function(frame)
      if not frame or not frame.GetName then
        return
      end
      local name = frame:GetName()
      if not name then
        return
      end
      local db = getMicroMenuDb()
      if not db or not db.enabled then
        return
      end
      for _, key in ipairs(getAllPanelKeys()) do
        if key == name then
          hookPanel(key)
          local f = _G[key]
          if f and f:IsShown() then
            pcall(function()
              if not f.__toolbox_mm_inited then
                f.__toolbox_mm_inited = true
              end
              applyPanel(f, key)
            end)
          end
          return
        end
      end
    end)
  end)
  if ok then
    showUIPanelHookInstalled = true
  end
end

local function installLazyFrameHooks()
  installAddonLoadedHook()
  installShowUIPanelHook()
end

local function runHooks()
  local db = getMicroMenuDb()
  if not db.enabled then
    return
  end
  installTabSwitchHook()
  installLazyFrameHooks()
  tryHookPendingPanels()
  applyVisiblePanels()
  C_Timer.After(1, function()
    local d = getMicroMenuDb()
    if not d or not d.enabled then
      return
    end
    tryHookPendingPanels()
    applyVisiblePanels()
  end)
  C_Timer.After(5, function()
    local d = getMicroMenuDb()
    if not d or not d.enabled then
      return
    end
    tryHookPendingPanels()
    applyVisiblePanels()
  end)
end

-- 供设置页、斜杠与其它模块刷新挂钩；无法靠插件自动发现「全部」暴雪界面
Toolbox.MicroMenuPanels = Toolbox.MicroMenuPanels or {}

function Toolbox.MicroMenuPanels.RefreshHooks()
  runHooks()
end

function Toolbox.MicroMenuPanels.AddExtraFrame(name)
  if type(name) ~= "string" then
    return false, "invalid"
  end
  name = strtrim(name)
  if not name:match("^[%a_][%w_]*$") then
    return false, "invalid"
  end
  if isBuiltinPanelKey(name) then
    return false, "builtin"
  end
  local db = getMicroMenuDb()
  db.extraFrameNames = db.extraFrameNames or {}
  for _, k in ipairs(db.extraFrameNames) do
    if k == name then
      return false, "dup"
    end
  end
  db.extraFrameNames[#db.extraFrameNames + 1] = name
  if db.enabled then
    runHooks()
  end
  return true
end

function Toolbox.MicroMenuPanels.SetExtraFrameNamesFromText(text)
  local db = getMicroMenuDb()
  db.extraFrameNames = parseExtraFrameNames(text)
  if db.enabled then
    runHooks()
  end
end

Toolbox.RegisterModule({
  id = "micromenu_panels",
  nameKey = "MODULE_MICROMENU",
  OnModuleLoad = function() end,
  OnModuleEnable = function()
    runHooks()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = getMicroMenuDb()
    local y = 0

    local en = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    en:SetPoint("TOPLEFT", 0, y)
    en.Text:SetText(L.MICROMENU_ENABLE)
    en:SetChecked(db.enabled)
    en:SetScript("OnClick", function(self)
      db.enabled = self:GetChecked()
      if db.enabled then
        runHooks()
      end
    end)
    y = y - 36

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MICROMENU_HINT)
    y = y - 48

    local extraL = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    extraL:SetPoint("TOPLEFT", 0, y)
    extraL:SetWidth(580)
    extraL:SetJustifyH("LEFT")
    extraL:SetText(L.MICROMENU_EXTRA_LABEL)
    y = y - 22

    local wrap = CreateFrame("Frame", nil, box, "BackdropTemplate")
    wrap:SetSize(560, 104)
    wrap:SetPoint("TOPLEFT", 0, y)
    wrap:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    wrap:SetBackdropColor(0, 0, 0, 0.35)
    local eb = CreateFrame("EditBox", nil, wrap)
    eb:SetMultiLine(true)
    eb:SetSize(544, 92)
    eb:SetPoint("TOPLEFT", 8, -8)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetMaxLetters(8000)
    eb:SetAutoFocus(false)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetText(table.concat(db.extraFrameNames or {}, "\n"))
    y = y - 112

    local apply = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    apply:SetSize(160, 26)
    apply:SetPoint("TOPLEFT", 0, y)
    apply:SetText(L.MICROMENU_EXTRA_APPLY)
    apply:SetScript("OnClick", function()
      db.extraFrameNames = parseExtraFrameNames(eb:GetText())
      if db.enabled then
        runHooks()
      end
      local chat = Toolbox.Chat and Toolbox.Chat.PrintAddonMessage
      if chat then
        chat(L.MICROMENU_EXTRA_SAVED)
      end
    end)
    y = y - 36

    local extraHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    extraHint:SetPoint("TOPLEFT", 0, y)
    extraHint:SetWidth(580)
    extraHint:SetJustifyH("LEFT")
    extraHint:SetText(L.MICROMENU_EXTRA_HINT)
    y = y - 44

    box.realHeight = math.abs(y) + 8
  end,
})
