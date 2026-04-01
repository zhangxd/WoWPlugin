--[[
  模块 mover：本插件创建的 Frame 可拖动与位置记忆（modules.mover.frames[key]）。
  示例窗 ToolboxDemoMoverFrame 用于演示；拖标题栏而非整窗。
]]

Toolbox.Mover = Toolbox.Mover or {}
Toolbox.Mover.DemoFrame = nil
Toolbox.Mover.DemoTitleFS = nil
Toolbox.Mover.DemoBtn1 = nil
Toolbox.Mover.DemoBtn2 = nil
-- 标题条区域，供多次 createDemoFrame 时重复 RegisterFrame
Toolbox.Mover.DemoDragRegion = nil

-- 与其它脚本覆盖 _G.Toolbox 时保持一致（见 Core/Namespace.lua）
local function getMoverDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.DB.GetModule("mover")
end

-- 存相对 UIParent 的一点，供重载后 restoreFrame
local function saveFrame(frame, key)
  local db = getMoverDb()
  db.frames = db.frames or {}
  local p, _, rel, x, y = frame:GetPoint()
  db.frames[key] = { point = p, rel = rel or "CENTER", x = x, y = y }
end

local function restoreFrame(frame, key)
  local db = getMoverDb()
  local s = db.frames and db.frames[key]
  if not s then
    return
  end
  frame:ClearAllPoints()
  frame:SetPoint(s.point, UIParent, s.rel or "CENTER", s.x, s.y)
end

-- opts.dragRegion：仅该区域触发拖动（如标题条）；不传则整框体可拖
function Toolbox.Mover.RegisterFrame(frame, key, opts)
  opts = opts or {}
  local db = getMoverDb()
  if not db.enabled then
    return
  end
  restoreFrame(frame, key)
  frame:SetMovable(true)
  frame:SetUserPlaced(true)
  frame:SetClampedToScreen(true)
  local drag = opts.dragRegion or frame
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    if InCombatLockdown() then
      return
    end
    frame:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    saveFrame(frame, key)
  end)
end

local function createDemoFrame()
  local db = getMoverDb()
  -- 示例窗仅在「启用拖动」且「显示示例」同时开启时展示；任一为关则隐藏，避免关不掉或逻辑矛盾
  if not db.enabled or not db.demoVisible then
    if Toolbox.Mover.DemoFrame then
      Toolbox.Mover.DemoFrame:Hide()
    end
    return
  end
  local f = Toolbox.Mover.DemoFrame
  if not f then
    f = CreateFrame("Frame", "ToolboxDemoMoverFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 200)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    local title = CreateFrame("Frame", nil, f)
    title:SetHeight(28)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    title:EnableMouse(true)

    local L = Toolbox.L
    local tStr = title:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tStr:SetPoint("LEFT", 8, 0)
    tStr:SetText(L.DEMO_TITLE_BAR)

    local btn1 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn1:SetSize(120, 24)
    btn1:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 8, -16)
    btn1:SetText(L.DEMO_BTN_A)

    local btn2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn2:SetSize(120, 24)
    btn2:SetPoint("LEFT", btn1, "RIGHT", 12, 0)
    btn2:SetText(L.DEMO_BTN_B)

    Toolbox.Mover.DemoFrame = f
    Toolbox.Mover.DemoTitleFS = tStr
    Toolbox.Mover.DemoBtn1 = btn1
    Toolbox.Mover.DemoBtn2 = btn2
    Toolbox.Mover.DemoDragRegion = title
  end
  restoreFrame(f, "demo")
  f:Show()
  -- 每次显示或「启用拖动」开关变更后都要注册；仅首次创建时注册会导致之后打开拖动不生效
  if Toolbox.Mover.DemoDragRegion then
    Toolbox.Mover.RegisterFrame(f, "demo", { dragRegion = Toolbox.Mover.DemoDragRegion })
  end
end

-- 切换界面语言后由 Locale_Apply 调用，刷新示例窗文案
function Toolbox.Mover.RefreshDemoLocale()
  local L = Toolbox.L
  if Toolbox.Mover.DemoTitleFS then
    Toolbox.Mover.DemoTitleFS:SetText(L.DEMO_TITLE_BAR)
  end
  if Toolbox.Mover.DemoBtn1 then
    Toolbox.Mover.DemoBtn1:SetText(L.DEMO_BTN_A)
  end
  if Toolbox.Mover.DemoBtn2 then
    Toolbox.Mover.DemoBtn2:SetText(L.DEMO_BTN_B)
  end
end

Toolbox.RegisterModule({
  id = "mover",
  nameKey = "MODULE_MOVER",
  OnModuleLoad = function() end,
  OnModuleEnable = function()
    createDemoFrame()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = getMoverDb()
    local y = 0

    local vis
    local en = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    en:SetPoint("TOPLEFT", 0, y)
    en.Text:SetText(L.MOVER_ENABLE)
    en:SetChecked(db.enabled ~= false)
    en:SetScript("OnClick", function(self)
      db.enabled = self:GetChecked() and true or false
      createDemoFrame()
      if vis then
        vis:SetEnabled(db.enabled)
      end
    end)
    y = y - 32

    vis = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    vis:SetPoint("TOPLEFT", 0, y)
    vis.Text:SetText(L.MOVER_DEMO_VISIBLE)
    vis:SetChecked(db.demoVisible ~= false)
    vis:SetEnabled(db.enabled ~= false)
    vis:SetScript("OnClick", function(self)
      db.demoVisible = self:GetChecked() and true or false
      createDemoFrame()
    end)
    y = y - 32

    local reset = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    reset:SetSize(160, 24)
    reset:SetPoint("TOPLEFT", 0, y)
    reset:SetText(L.MOVER_RESET_DEMO)
    reset:SetScript("OnClick", function()
      db.frames = db.frames or {}
      db.frames.demo = nil
      if Toolbox.Mover.DemoFrame then
        Toolbox.Mover.DemoFrame:ClearAllPoints()
        Toolbox.Mover.DemoFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end
    end)
    y = y - 36

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.MOVER_HINT)
    y = y - 40

    box.realHeight = math.abs(y) + 8
  end,
})
