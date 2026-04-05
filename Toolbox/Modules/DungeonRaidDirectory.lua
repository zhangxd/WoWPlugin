--[[
  模块 dungeon_raid_directory：为共享目录领域 API 提供独立设置子页面与模块级启停控制。
  目录缓存与查询逻辑仍在 Core/DungeonRaidDirectory.lua；本文件只负责模块接入、公共设置回调与页面专属区。
]]

local MODULE_ID = "dungeon_raid_directory"

local function getModuleDb()
  return Toolbox.DB.GetModule(MODULE_ID)
end

local function getDirectoryStageLabel(progress)
  local L = Toolbox.L or {}
  if not progress or not progress.currentStage then
    return ""
  end
  if progress.currentStage == "record_pipeline" then
    return L.DRD_STAGE_RECORD_PIPELINE or ""
  end
  if progress.currentStage == "skeleton" then
    return L.DRD_STAGE_SKELETON or ""
  end
  if progress.currentStage == "difficulty" then
    return L.DRD_STAGE_DIFFICULTY or ""
  end
  if progress.currentStage == "mount_summary" then
    return L.DRD_STAGE_MOUNT_SUMMARY or ""
  end
  return tostring(progress.currentStage)
end

local function getDirectoryStatusLabel(progress)
  local L = Toolbox.L or {}
  if not progress then
    return L.DRD_STATUS_IDLE or ""
  end
  if getModuleDb().enabled == false then
    return L.SETTINGS_MODULE_DISABLED_FMT and string.format(L.SETTINGS_MODULE_DISABLED_FMT, L.MODULE_DUNGEON_RAID_DIRECTORY or MODULE_ID) or ""
  end
  if progress.state == "building" then
    return L.DRD_STATUS_BUILDING or ""
  end
  if progress.state == "completed" then
    return L.DRD_STATUS_COMPLETED or ""
  end
  if progress.state == "failed" then
    if progress.failureMessage and progress.failureMessage ~= "" then
      return string.format(L.DRD_BUILD_FAILED_FMT or "%s", tostring(progress.failureMessage))
    end
    return L.DRD_STATUS_FAILED or ""
  end
  if progress.state == "cancelled" then
    return L.DRD_STATUS_CANCELLED or ""
  end
  return L.DRD_STATUS_IDLE or ""
end

Toolbox.RegisterModule({
  id = MODULE_ID,
  nameKey = "MODULE_DUNGEON_RAID_DIRECTORY",
  settingsIntroKey = "MODULE_DUNGEON_RAID_DIRECTORY_INTRO",
  settingsOrder = 50,
  OnModuleLoad = function()
    Toolbox.DungeonRaidDirectory.Initialize()
  end,
  OnModuleEnable = function()
    Toolbox.DungeonRaidDirectory.SetFeatureEnabled(getModuleDb().enabled ~= false)
    Toolbox.DungeonRaidDirectory.SetDebugChatEnabled(getModuleDb().debug == true)
  end,
  OnEnabledSettingChanged = function(enabled)
    local L = Toolbox.L or {}
    local key = enabled and "SETTINGS_MODULE_ENABLED_FMT" or "SETTINGS_MODULE_DISABLED_FMT"
    Toolbox.Chat.PrintAddonMessage(string.format(L[key] or "%s", L.MODULE_DUNGEON_RAID_DIRECTORY or MODULE_ID))
    Toolbox.DungeonRaidDirectory.SetFeatureEnabled(enabled == true)
  end,
  OnDebugSettingChanged = function(enabled)
    Toolbox.DungeonRaidDirectory.SetDebugChatEnabled(enabled == true)
  end,
  ResetToDefaultsAndRebuild = function()
    local db = Toolbox.DB.ResetModule(MODULE_ID)
    Toolbox.DungeonRaidDirectory.ResetCacheToDefaults()
    Toolbox.DungeonRaidDirectory.SetDebugChatEnabled(db.debug == true)
    Toolbox.DungeonRaidDirectory.SetFeatureEnabled(db.enabled ~= false)
  end,
  RegisterSettings = function(box)
    local L = Toolbox.L or {}
    local y = 0

    local statusText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    statusText:SetWidth(560)
    statusText:SetJustifyH("LEFT")
    y = y - 24

    local stageText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stageText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    stageText:SetWidth(560)
    stageText:SetJustifyH("LEFT")
    y = y - 20

    local currentText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    currentText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    currentText:SetWidth(560)
    currentText:SetJustifyH("LEFT")
    y = y - 28

    local progressBg = CreateFrame("Frame", nil, box, "BackdropTemplate")
    progressBg:SetSize(574, 18)
    progressBg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    progressBg:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 8,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    progressBg:SetBackdropColor(0.08, 0.08, 0.08, 0.9)

    local progressBar = CreateFrame("StatusBar", nil, progressBg)
    progressBar:SetPoint("TOPLEFT", 2, -2)
    progressBar:SetPoint("BOTTOMRIGHT", -2, 2)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.22, 0.62, 0.92)
    y = y - 28

    local progressText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    progressText:SetWidth(300)
    progressText:SetJustifyH("LEFT")

    local rebuildButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    rebuildButton:SetSize(132, 24)
    rebuildButton:SetPoint("TOPRIGHT", box, "TOPRIGHT", -20, y + 4)
    rebuildButton:SetText(L.DRD_REBUILD_BUTTON or "")
    rebuildButton:SetScript("OnClick", function()
      Toolbox.DungeonRaidDirectory.RebuildCache()
    end)
    y = y - 42

    local snapshotTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    snapshotTitle:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    snapshotTitle:SetText(L.DRD_SNAPSHOT_TITLE or "")

    local snapshotRefreshButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    snapshotRefreshButton:SetSize(120, 22)
    snapshotRefreshButton:SetPoint("TOPRIGHT", box, "TOPRIGHT", -20, y + 4)
    snapshotRefreshButton:SetText(L.DRD_SNAPSHOT_REFRESH or "")
    y = y - 24

    local snapshotHint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    snapshotHint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    snapshotHint:SetWidth(560)
    snapshotHint:SetJustifyH("LEFT")
    snapshotHint:SetText(L.DRD_SNAPSHOT_HINT or "")
    y = y - 32

    local snapshotWrap = CreateFrame("Frame", nil, box, "BackdropTemplate")
    snapshotWrap:SetSize(574, 216)
    snapshotWrap:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    snapshotWrap:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    snapshotWrap:SetBackdropColor(0, 0, 0, 0.4)

    local snapshotScroll = CreateFrame("ScrollFrame", nil, snapshotWrap, "UIPanelScrollFrameTemplate")
    snapshotScroll:SetPoint("TOPLEFT", 6, -6)
    snapshotScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local snapshotChild = CreateFrame("Frame", nil, snapshotScroll)
    snapshotChild:SetSize(532, 200)
    snapshotScroll:SetScrollChild(snapshotChild)

    local snapshotText = snapshotChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    snapshotText:SetPoint("TOPLEFT", snapshotChild, "TOPLEFT", 0, 0)
    snapshotText:SetWidth(532)
    snapshotText:SetJustifyH("LEFT")
    snapshotText:SetJustifyV("TOP")
    snapshotText:SetSpacing(2)
    snapshotText:SetText(L.DRD_SNAPSHOT_EMPTY or "")

    local lastSnapshotText = nil

    local function applySnapshotText(text)
      local nextText = type(text) == "string" and text or ""
      if nextText == lastSnapshotText then
        return
      end
      lastSnapshotText = nextText
      snapshotText:SetText(nextText)
      local contentHeight = math.ceil(snapshotText:GetStringHeight() or 0)
      snapshotChild:SetSize(532, math.max(contentHeight + 8, 200))
      if snapshotScroll.GetVerticalScrollRange and snapshotScroll.GetVerticalScroll then
        local maxScroll = snapshotScroll:GetVerticalScrollRange() or 0
        local currentScroll = snapshotScroll:GetVerticalScroll() or 0
        if currentScroll > maxScroll then
          snapshotScroll:SetVerticalScroll(maxScroll)
        end
      end
    end

    local function buildSnapshotText(progress)
      if Toolbox.DungeonRaidDirectory.FormatDebugSnapshot then
        local ok, text = pcall(Toolbox.DungeonRaidDirectory.FormatDebugSnapshot)
        if ok and type(text) == "string" and text ~= "" then
          return text
        end
        if not ok then
          return "snapshotError=" .. tostring(text)
        end
      end
      if progress and progress.state == "building" then
        return L.DRD_SNAPSHOT_LOADING or ""
      end
      return L.DRD_SNAPSHOT_EMPTY or ""
    end

    local function refresh()
      local progress = Toolbox.DungeonRaidDirectory.GetBuildProgress()
      local percentInt = math.floor(((progress.percent or 0) * 100) + 0.5)
      statusText:SetText(getDirectoryStatusLabel(progress))
      stageText:SetText(getDirectoryStageLabel(progress))
      if progress.currentLabel and progress.currentLabel ~= "" then
        currentText:SetText(string.format(L.DRD_CURRENT_FMT or "%s", tostring(progress.currentLabel)))
      else
        currentText:SetText("")
      end
      progressBar:SetValue(progress.percent or 0)
      progressText:SetText(string.format(
        L.DRD_PROGRESS_FMT or "%d / %d (%d%%)",
        tonumber(progress.completedUnits) or 0,
        tonumber(progress.totalUnits) or 0,
        percentInt
      ))
      rebuildButton:SetEnabled(getModuleDb().enabled ~= false)
      applySnapshotText(buildSnapshotText(progress))
    end

    snapshotRefreshButton:SetScript("OnClick", function()
      refresh()
    end)

    box:SetScript("OnUpdate", function(self, elapsed)
      self._elapsed = (self._elapsed or 0) + elapsed
      if self._elapsed < 0.25 then
        return
      end
      self._elapsed = 0
      if self:IsShown() then
        refresh()
      end
    end)

    refresh()

    y = y - 216 - 16
    box.realHeight = math.abs(y) + 8
  end,
})
