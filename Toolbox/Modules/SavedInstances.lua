--[[
  副本进度模块：功能已迁入冒险手册（SavedInstancesEJ）；本文件负责设置注册与斜杠打开手册。
]]

Toolbox.SavedInstances = Toolbox.SavedInstances or {}

local MODULE_ID = "saved_instances"

local function getDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.DB.GetModule(MODULE_ID)
end

--- 打开冒险指南（副本进度与筛选在手册内展示）；模块关闭时仅聊天提示。
---@return nil
function Toolbox.SavedInstances.Show()
  local db = getDb()
  if db.enabled == false then
    Toolbox.Chat.PrintAddonMessage(Toolbox.L.SAVED_INST_DISABLED or "")
    return
  end
  Toolbox.SavedInstancesData.EnsureEncounterJournalAddOn()
  if ToggleEncounterJournal then
    ToggleEncounterJournal()
  end
end

--- 若冒险指南已显示则关闭（`HideUIPanel`）；异常吞掉以免设置页报错。
---@return nil
function Toolbox.SavedInstances.Hide()
  pcall(function()
    if EncounterJournal and EncounterJournal:IsShown() then
      HideUIPanel(EncounterJournal)
    end
  end)
end

--- 切换冒险指南显示/隐藏（与 `Show`/`Hide` 一致）。
---@return nil
function Toolbox.SavedInstances.Toggle()
  if EncounterJournal and EncounterJournal:IsShown() then
    Toolbox.SavedInstances.Hide()
  else
    Toolbox.SavedInstances.Show()
  end
end

--- 兼容旧接口：副本进度已迁入手册，无独立主窗体，恒为 nil。
---@return nil
function Toolbox.SavedInstances.GetMainFrame()
  return nil
end

--- 刷新冒险手册内挂接控件的文字（切换游戏语言后调用）。
---@return nil
function Toolbox.SavedInstances.RefreshLocale()
  if Toolbox.SavedInstancesEJ and Toolbox.SavedInstancesEJ.RefreshWidgetsLocale then
    Toolbox.SavedInstancesEJ.RefreshWidgetsLocale()
  end
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_SAVED_INSTANCES",
  dependencies = {},
  OnModuleLoad = function()
  end,
  OnModuleEnable = function()
    Toolbox.SavedInstancesEJ.Register()
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L
    local db = getDb()
    local y = 0

    local en = CreateFrame("CheckButton", nil, box, "InterfaceOptionsCheckButtonTemplate")
    en:SetPoint("TOPLEFT", 0, y)
    en.Text:SetText(L.SAVED_INST_ENABLE)
    en:SetChecked(db.enabled ~= false)
    en:SetScript("OnClick", function(self)
      db.enabled = self:GetChecked() and true or false
    end)
    y = y - 32

    local open = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", 0, y)
    open:SetText(L.SAVED_INST_OPEN_EJ or L.SAVED_INST_OPEN_PANEL or "Open Adventure Guide")
    open:SetScript("OnClick", function()
      local ok, err = pcall(function()
        Toolbox.SavedInstances.Show()
      end)
      if not ok then
        Toolbox.Chat.PrintAddonMessage(string.format(L.SAVED_INST_ERR_UI, tostring(err)))
      end
    end)
    y = y - 36

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    hint:SetWidth(580)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.SAVED_INST_SETTINGS_HINT_EJ or L.SAVED_INST_SETTINGS_HINT)
    y = y - 48

    box.realHeight = math.abs(y) + 8
  end,
})
