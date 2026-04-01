--[[
  冒险手册内集成：资料片旁「仅坐骑」勾选、各难度 CD 行、详情标题 CD。
  lootMountsOnly：左侧实例列表仅保留手册内可解析出坐骑的副本（mountDropByJid 缓存）；副本内战利品页仅显示坐骑物品。
  仅在「地下城」「团队副本」浏览上下文显示；资料片旁控件需 resolve 主栏或 LandingPage 内嵌 instanceSelect。
  排除：纯推荐且无实例列表、月度活动、PvP 等。
  依赖 Blizzard_EncounterJournal 加载后的全局函数与 Frame；失败时经 Toolbox.Chat 提示。
]]

Toolbox.SavedInstancesEJ = Toolbox.SavedInstancesEJ or {}

local Data = Toolbox.SavedInstancesData
local MODULE_ID = "saved_instances"

local hooksInited = false
-- 实例列表坐骑判定：分批扫描 journalInstanceID（与 DB.mountDropByJid 一致）
local mountScanQueue = {}
local mountScanQueued = {}

local function getDb()
  Toolbox_NamespaceEnsure()
  return Toolbox.DB.GetModule(MODULE_ID)
end

---@param f Frame|nil
---@return boolean
local function frameIsShown(f)
  if not f or not f.IsShown then
    return false
  end
  local ok, s = pcall(function()
    return f:IsShown()
  end)
  return ok and s == true
end

--- 解析含「资料片」下拉的 instanceSelect：主栏 `EncounterJournal.instanceSelect` 或首页 `LandingPage` 内嵌套（部分版本首页地城/团本用后者）。
---@return Frame|nil
local function resolveEJInstanceSelect()
  local ej = _G.EncounterJournal
  if not ej then
    return nil
  end
  local function hasExpansionPanel(panel)
    return panel and panel.ExpansionDropdown
  end
  local function pickVisible(panel)
    if not hasExpansionPanel(panel) then
      return nil
    end
    if frameIsShown(panel) or frameIsShown(panel.ExpansionDropdown) then
      return panel
    end
    return nil
  end
  local a = pickVisible(ej.instanceSelect)
  if a then
    return a
  end
  local lp = ej.LandingPage or ej.landingPage
  if lp then
    local nested = lp.instanceSelect or lp.InstanceSelect
    local b = pickVisible(nested)
    if b then
      return b
    end
  end
  -- 布局尚未就绪时仍返回主面板，便于创建子控件
  if hasExpansionPanel(ej.instanceSelect) then
    return ej.instanceSelect
  end
  if lp then
    local nested = lp.instanceSelect or lp.InstanceSelect
    if hasExpansionPanel(nested) then
      return nested
    end
  end
  return nil
end

--- 实例列表面板上的 ScrollBox（各版本字段名不一致）。
---@param isPanel Frame|nil
---@return Frame|nil
local function getInstanceListScrollBox(isPanel)
  if not isPanel then
    return nil
  end
  return isPanel.ScrollBox
    or isPanel.scrollBox
    or isPanel.ListScrollBox
    or isPanel.listScrollBox
    or isPanel.InstanceScrollBox
end

--- 从 ScrollBox 取 DataProvider（部分版本挂在 view 子对象上）。
---@param sb Frame|nil
---@return table|nil
local function getScrollBoxDataProvider(sb)
  if not sb then
    return nil
  end
  if sb.GetDataProvider then
    local ok, dp = pcall(function()
      return sb:GetDataProvider()
    end)
    if ok and dp then
      return dp
    end
  end
  if sb.view and sb.view.GetDataProvider then
    local ok, dp = pcall(function()
      return sb.view:GetDataProvider()
    end)
    if ok and dp then
      return dp
    end
  end
  return nil
end

--- 将 DataProvider 写回 ScrollBox（与 getScrollBoxDataProvider 对称）。
---@param sb Frame|nil
---@param newDp table|nil
---@return boolean
local function setScrollBoxDataProvider(sb, newDp)
  if not sb or not newDp then
    return false
  end
  if sb.SetDataProvider then
    local ok = pcall(function()
      sb:SetDataProvider(newDp)
    end)
    if ok then
      return true
    end
  end
  if sb.view and sb.view.SetDataProvider then
    return pcall(function()
      sb.view:SetDataProvider(newDp)
    end)
  end
  return false
end

--- 收集可能承载左侧副本列表的 instanceSelect（首页可能与主栏不是同一块 Region）。
---@return Frame[]
local function collectInstanceSelectPanels()
  local ej = _G.EncounterJournal
  local out = {}
  local seen = {}
  local function add(p)
    if not p or seen[p] then
      return
    end
    seen[p] = true
    out[#out + 1] = p
  end
  if ej then
    add(resolveEJInstanceSelect())
    add(ej.instanceSelect)
    local lp = ej.LandingPage or ej.landingPage
    if lp then
      add(lp.instanceSelect)
      add(lp.InstanceSelect)
    end
  end
  return out
end

--- 从手册列表 DataProvider 元素解析 Journal 实例 ID（兼容 elementData 包装与各键名）。
--- 先读外层再读 e.info：部分版本 ID 在外层、`info` 仅有展示字段，若只读 info 会得到 withId==0 从而永不替换列表。
local function entryJournalInstanceId(entry)
  if not entry then
    return nil
  end
  local e = entry.elementData or entry
  if type(e) ~= "table" then
    return nil
  end
  local function pickIdFrom(t)
    if type(t) ~= "table" then
      return nil
    end
    local id = t.instanceID
      or t.journalInstanceID
      or t.journalInstanceId
      or t.encounterJournalInstanceID
      or t.encounterJournalID
      or t.id
      or t.instanceId
    if type(id) == "number" and id > 0 then
      return id
    end
    if type(id) == "string" then
      return tonumber(id)
    end
    return nil
  end
  local id = pickIdFrom(e)
  if id then
    return id
  end
  if type(e.info) == "table" then
    return pickIdFrom(e.info)
  end
  return nil
end

--- 列表元素上的副本显示名（叠加 CD 用）。
local function entryInstanceName(entry)
  if not entry then
    return nil
  end
  local e = entry.elementData or entry
  if type(e) ~= "table" then
    return nil
  end
  local function pickNameFrom(t)
    if type(t) ~= "table" then
      return nil
    end
    return t.name or t.instanceName or t.title or t.text
  end
  local name = pickNameFrom(e)
  if not name and type(e.info) == "table" then
    name = pickNameFrom(e.info)
  end
  return name
end

--- 遍历 ScrollBox DataProvider（ForEach / EnumerateData；兼容单参或与索引双参）。
local function dataProviderForEach(dp, fn)
  if not dp or type(fn) ~= "function" then
    return false
  end
  local function wrap(...)
    local n = select("#", ...)
    local a, b = ...
    if n == 0 then
      return
    elseif n == 1 then
      fn(a)
    elseif type(a) == "table" then
      fn(a)
    elseif type(b) == "table" then
      fn(b)
    else
      fn(a)
    end
  end
  if dp.ForEach then
    local ok = pcall(function()
      dp:ForEach(wrap)
    end)
    return ok
  end
  if dp.EnumerateData then
    local ok = pcall(function()
      dp:EnumerateData(wrap)
    end)
    return ok
  end
  return false
end

--- 当前是否处于冒险手册「地下城」或「团队副本」浏览上下文（列表或副本详情）。
--- 注意：首页嵌套 instanceSelect 常因父级裁剪导致 IsShown 为 false，有 ScrollBox 即视为列表上下文。
---@return boolean
local function isEJDungeonOrRaidTab()
  local ej = _G.EncounterJournal
  if not ej then
    return false
  end
  local ok, r = pcall(function()
    if frameIsShown(ej.MonthlyActivitiesFrame) or frameIsShown(ej.monthlyActivitiesFrame) then
      return false
    end
    if frameIsShown(ej.PvPFrame) or frameIsShown(ej.pvpFrame) then
      return false
    end
    for _, p in ipairs(collectInstanceSelectPanels()) do
      if frameIsShown(p) or frameIsShown(p.ExpansionDropdown) then
        return true
      end
      if getInstanceListScrollBox(p) then
        return true
      end
    end
    if ej.encounter and frameIsShown(ej.encounter) and ej.encounter.info then
      return true
    end
    return false
  end)
  return ok and r == true
end

--- 隐藏左侧实例列表上由本插件创建的 CD 文本。
local function hideToolboxEJListOverlays()
  for _, isPanel in ipairs(collectInstanceSelectPanels()) do
    local sb = getInstanceListScrollBox(isPanel)
    if sb then
      local dp = getScrollBoxDataProvider(sb)
      if dp then
        dataProviderForEach(dp, function(entry)
          if not entry then
            return
          end
          local jid = entryJournalInstanceId(entry)
          if not jid then
            return
          end
          local b = sb.FindFrameByPredicate and sb:FindFrameByPredicate(function(_, elementData)
            return entryJournalInstanceId(elementData) == jid
          end)
          if b and b.toolboxEJLockoutFS then
            b.toolboxEJLockoutFS:SetShown(false)
          end
        end)
      end
    end
  end
end

--- 隐藏副本详情标题旁的 CD 文本。
local function hideToolboxEJTitleCD()
  local ej = _G.EncounterJournal
  if not ej or not ej.encounter or not ej.encounter.info then
    return
  end
  local info = ej.encounter.info
  if info.toolboxEJTitleCD then
    info.toolboxEJTitleCD:SetShown(false)
  end
end

---@param show boolean
local function setLootMountWidgetsVisible(show)
  local cb = _G.ToolboxEJLootMountFilterCheck
  local lab = _G.ToolboxEJLootMountFilterLabel
  if cb then
    cb:SetShown(show)
  end
  if lab then
    lab:SetShown(show)
  end
end

local function fmtReset(sec)
  if not sec or sec <= 0 then
    return "—"
  end
  if SecondsToTime then
    return SecondsToTime(sec, true) or tostring(sec)
  end
  return tostring(sec)
end

local function refreshInstanceListOverlays()
  local db = getDb()
  if db.enabled == false then
    return
  end
  if not isEJDungeonOrRaidTab() then
    hideToolboxEJListOverlays()
    return
  end
  local locks = Data.GetLockoutsGroupedByInstanceName()
  for _, isPanel in ipairs(collectInstanceSelectPanels()) do
    local sb = getInstanceListScrollBox(isPanel)
    if sb then
      local dp = getScrollBoxDataProvider(sb)
      if dp then
        dataProviderForEach(dp, function(entry)
          if not entry then
            return
          end
          local jid = entryJournalInstanceId(entry)
          local iname = entryInstanceName(entry)
          if not jid or not iname then
            return
          end
          local b = sb.FindFrameByPredicate and sb:FindFrameByPredicate(function(_, elementData)
            return entryJournalInstanceId(elementData) == jid
          end)
          if b then
            if not b.toolboxEJLockoutFS then
              b.toolboxEJLockoutFS = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
              b.toolboxEJLockoutFS:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
              b.toolboxEJLockoutFS:SetWidth(220)
              b.toolboxEJLockoutFS:SetJustifyH("LEFT")
            end
            local lines = {}
            local rows = locks[iname]
            if rows then
              for _, r in ipairs(rows) do
                if r.locked ~= false then
                  lines[#lines + 1] = string.format(
                    "%s: %s  %d/%d",
                    r.difficultyName or "—",
                    fmtReset(r.reset),
                    r.encounterProgress or 0,
                    r.numEncounters or 0
                  )
                end
              end
            end
            local txt = table.concat(lines, "\n")
            b.toolboxEJLockoutFS:SetText(txt)
            b.toolboxEJLockoutFS:SetShown(#lines > 0)
          end
        end)
      end
    end
  end
end

--- TOC 变化时清空坐骑实例缓存，避免大版本后误判。
local function ensureMountCacheToc(db)
  local _, _, _, toc = GetBuildInfo()
  if type(toc) == "number" and db.mountCacheToc ~= toc then
    wipe(db.mountDropByJid or {})
    db.mountCacheToc = toc
  end
end

local function processMountScanQueue()
  local jid = table.remove(mountScanQueue, 1)
  if not jid then
    return
  end
  mountScanQueued[jid] = nil
  local db = getDb()
  db.mountDropByJid = db.mountDropByJid or {}
  local has = Data.ScanInstanceHasMount(jid)
  db.mountDropByJid[jid] = has
  if #mountScanQueue > 0 then
    C_Timer.After(0.08, processMountScanQueue)
  elseif EncounterJournal_ListInstances then
    EncounterJournal_ListInstances()
  end
end

--- 对当前列表中尚无缓存的实例 ID 排队扫描是否含坐骑掉落。
local function enqueueUnknownMountScans(sb)
  local db = getDb()
  if not db.lootMountsOnly then
    return
  end
  local dp = getScrollBoxDataProvider(sb)
  if not dp then
    return
  end
  local cache = db.mountDropByJid or {}
  local added = false
  local function consider(entry)
    if not entry then
      return
    end
    local jid = entryJournalInstanceId(entry)
    if jid and cache[jid] == nil and not mountScanQueued[jid] then
      mountScanQueued[jid] = true
      mountScanQueue[#mountScanQueue + 1] = jid
      added = true
    end
  end
  dataProviderForEach(dp, consider)
  if added then
    C_Timer.After(0.05, processMountScanQueue)
  end
end

--- 在单块 instanceSelect 上应用坐骑列表筛选；成功返回 true。
local function tryMountFilterOnInstancePanel(isPanel, db)
  local sb = getInstanceListScrollBox(isPanel)
  if not sb or not CreateDataProvider then
    return false
  end
  local dp = getScrollBoxDataProvider(sb)
  if not dp then
    return false
  end
  ensureMountCacheToc(db)
  local newDp = CreateDataProvider()
  local cache = db.mountDropByJid or {}
  local entryCount = 0
  local withId = 0
  local function consume(entry)
    if not entry then
      return
    end
    entryCount = entryCount + 1
    local jid = entryJournalInstanceId(entry)
    if jid then
      withId = withId + 1
    end
    if jid and cache[jid] == false then
      return
    end
    newDp:Insert(entry)
  end
  if not dataProviderForEach(dp, consume) then
    return false
  end
  if entryCount == 0 or withId == 0 then
    return false
  end
  if not setScrollBoxDataProvider(sb, newDp) then
    return false
  end
  enqueueUnknownMountScans(sb)
  return true
end

--- 首页/列表：勾选「仅坐骑」时收缩 ScrollBox；多块面板依次尝试直至成功。
local function applyInstanceListMountFilter()
  local db = getDb()
  if not db.lootMountsOnly then
    return
  end
  if not isEJDungeonOrRaidTab() then
    return
  end
  for _, isPanel in ipairs(collectInstanceSelectPanels()) do
    if tryMountFilterOnInstancePanel(isPanel, db) then
      return
    end
  end
end

local ejWidgetsFrame

--- Prefer loot class/spec dropdown left (detail); else expansion dropdown left (home).
--- 返回列表后 encounter 可能仍残留引用，必须要求 encounter 真正显示才挂到 LootContainer，否则会父级留在已隐藏容器上导致按钮丢失。
local function reanchorLootMountFilter()
  local ej = _G.EncounterJournal
  if not ej or not _G.ToolboxEJLootMountFilterCheck then
    return
  end
  if not isEJDungeonOrRaidTab() then
    setLootMountWidgetsVisible(false)
    return
  end
  setLootMountWidgetsVisible(true)
  local lcb = _G.ToolboxEJLootMountFilterCheck
  local llab = _G.ToolboxEJLootMountFilterLabel
  local is = resolveEJInstanceSelect()
  local lc = ej.encounter and ej.encounter.info and ej.encounter.info.LootContainer
  local classFilter = lc and lc.filter
  local encShown = ej.encounter and ej.encounter.IsShown and ej.encounter:IsShown()
  local useLootRow = encShown and lc and lc.IsShown and lc:IsShown() and classFilter and classFilter.IsShown and classFilter:IsShown()

  if useLootRow then
    lcb:SetParent(lc)
    lcb:ClearAllPoints()
    lcb:SetPoint("RIGHT", classFilter, "LEFT", -8, 0)
    if llab then
      llab:SetParent(lc)
      llab:ClearAllPoints()
      llab:SetPoint("RIGHT", lcb, "LEFT", -4, 0)
    end
  elseif is and is.ExpansionDropdown then
    lcb:SetParent(is)
    lcb:ClearAllPoints()
    lcb:SetPoint("RIGHT", is.ExpansionDropdown, "LEFT", -8, 0)
    if llab then
      llab:SetParent(is)
      llab:ClearAllPoints()
      llab:SetPoint("RIGHT", lcb, "LEFT", -4, 0)
    end
  elseif is then
    -- 资料片下拉尚未就绪时仍挂到 instanceSelect，避免控件留在已隐藏 Frame 下
    lcb:SetParent(is)
    lcb:ClearAllPoints()
    lcb:SetPoint("TOPRIGHT", is, "TOPRIGHT", -4, -4)
    if llab then
      llab:SetParent(is)
      llab:ClearAllPoints()
      llab:SetPoint("RIGHT", lcb, "LEFT", -4, 0)
    end
  end
end

--- 按当前页签统一显示/隐藏本模块在手册内的所有叠加内容。
local function syncToolboxEJVisibility()
  local db = getDb()
  if db.enabled == false then
    return
  end
  -- 首页地城/团本的资料片面板可能晚于 ADDON_LOADED 才创建，需补建筛选按钮。
  if not _G.ToolboxEJLootMountFilterCheck then
    pcall(createEncounterJournalWidgets)
  end
  if not isEJDungeonOrRaidTab() then
    hideToolboxEJListOverlays()
    hideToolboxEJTitleCD()
    setLootMountWidgetsVisible(false)
    return
  end
  -- 先收缩列表（若开启仅坐骑），再画 CD 叠加，避免 ForEach 仍遍历未过滤前的数据
  pcall(applyInstanceListMountFilter)
  pcall(refreshInstanceListOverlays)
  pcall(reanchorLootMountFilter)
end

--- 当前手册选中的首领序号（用于 GetLootInfoByIndex 第二参数，部分掉落需与首领对齐）。
local function getEncounterIndexForLoot()
  local CJ = C_EncounterJournal
  if CJ and CJ.GetEncounterIndex then
    local ok, n = pcall(function()
      return CJ.GetEncounterIndex()
    end)
    if ok and type(n) == "number" and n > 0 then
      return n
    end
  end
  if EJ_GetEncounterIndex then
    local ok, n = pcall(EJ_GetEncounterIndex)
    if ok and type(n) == "number" and n > 0 then
      return n
    end
  end
  return nil
end

--- 从 ScrollBox 元素解析物品 ID（优先 entry 自带字段，否则经 EJ 门面查表）。
local function resolveLootScrollEntryItemID(entry)
  if not entry or entry.header then
    return nil
  end
  if type(entry.itemID) == "number" and entry.itemID > 0 then
    return entry.itemID
  end
  local idx = entry.index or entry.lootIndex
  if not idx then
    return nil
  end
  local encIdx = entry.encounterIndex or entry.bossIndex or getEncounterIndexForLoot()
  local info = Toolbox.EJ.GetLootInfoByIndex(idx, encIdx)
  if info and info.itemID then
    return info.itemID
  end
  info = Toolbox.EJ.GetLootInfoByIndex(idx)
  if info and info.itemID then
    return info.itemID
  end
  return nil
end

--- 将战利品 ScrollBox 替换为仅含坐骑行（依赖 EncounterJournal_LootUpdate 已填充数据；延迟一帧以避开暴雪异步刷新）。
local function applyLootMountsOnlyFilter()
  local db = getDb()
  if db.enabled == false or not db.lootMountsOnly then
    pcall(reanchorLootMountFilter)
    return
  end
  if not isEJDungeonOrRaidTab() then
    pcall(reanchorLootMountFilter)
    return
  end
  local ej = _G.EncounterJournal
  if not ej or not ej.encounter or not ej.encounter.info or not ej.encounter.info.LootContainer then
    pcall(reanchorLootMountFilter)
    return
  end
  local scrollBox = ej.encounter.info.LootContainer.ScrollBox
  if not scrollBox or not CreateDataProvider then
    pcall(reanchorLootMountFilter)
    return
  end
  local dp = getScrollBoxDataProvider(scrollBox)
  if not dp then
    pcall(reanchorLootMountFilter)
    return
  end
  local MJ = Toolbox.MountJournal
  local newDp = CreateDataProvider()
  local pendingHeader = nil
  local okWalk = dataProviderForEach(dp, function(entry)
    if entry.header then
      pendingHeader = entry
      return
    end
    local itemID = resolveLootScrollEntryItemID(entry)
    if itemID and MJ.GetMountFromItem(itemID) then
      if pendingHeader then
        newDp:Insert(pendingHeader)
        pendingHeader = nil
      end
      newDp:Insert(entry)
    end
  end)
  if not okWalk then
    pcall(reanchorLootMountFilter)
    return
  end
  setScrollBoxDataProvider(scrollBox, newDp)
  pcall(reanchorLootMountFilter)
end

local function onListInstances()
  local db = getDb()
  if db.enabled == false then
    return
  end
  -- 从详情返回列表时布局晚一帧才稳定，双次延迟避免筛选按钮仍挂在已隐藏的 LootContainer 上
  C_Timer.After(0.03, function()
    pcall(syncToolboxEJVisibility)
  end)
  C_Timer.After(0.12, function()
    pcall(syncToolboxEJVisibility)
    pcall(reanchorLootMountFilter)
  end)
end

local function onDisplayInstance()
  local db = getDb()
  if db.enabled == false then
    return
  end
  local ej = _G.EncounterJournal
  if not ej or not ej.encounter or not ej.encounter.info then
    pcall(reanchorLootMountFilter)
    return
  end
  local info = ej.encounter.info
  if not isEJDungeonOrRaidTab() then
    hideToolboxEJTitleCD()
    setLootMountWidgetsVisible(false)
    pcall(reanchorLootMountFilter)
    return
  end
  if not info.instanceTitle then
    pcall(reanchorLootMountFilter)
    return
  end
  local name = select(1, (EJ_GetInstanceInfo and EJ_GetInstanceInfo()) or nil)
  local diffId = EJ_GetDifficulty and EJ_GetDifficulty() or nil
  local locks = Data.GetLockoutsGroupedByInstanceName()
  local rows = name and locks[name]
  local txt = ""
  if rows and diffId ~= nil then
    for _, r in ipairs(rows) do
      if r.difficultyId == diffId and r.locked ~= false then
        txt = string.format("%s  %d/%d", fmtReset(r.reset), r.encounterProgress or 0, r.numEncounters or 0)
        break
      end
    end
  end
  if not info.toolboxEJTitleCD then
    info.toolboxEJTitleCD = info:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info.toolboxEJTitleCD:SetPoint("LEFT", info.instanceTitle, "RIGHT", 8, 0)
  end
  info.toolboxEJTitleCD:SetText(txt)
  info.toolboxEJTitleCD:SetShown(txt ~= "")
  pcall(reanchorLootMountFilter)
  -- 切换副本后强制刷新战利品数据，避免仍使用上次 SetDataProvider 后的过滤结果导致筛选异常
  if db.lootMountsOnly then
    C_Timer.After(0.05, function()
      if EncounterJournal_LootUpdate then
        EncounterJournal_LootUpdate()
      end
    end)
  end
end

local function onLootUpdate()
  local db = getDb()
  if db.enabled == false or not db.lootMountsOnly then
    pcall(reanchorLootMountFilter)
    return
  end
  if not isEJDungeonOrRaidTab() then
    setLootMountWidgetsVisible(false)
    return
  end
  -- Hook 在暴雪填充之后触发，但部分版本会在同一帧稍后再次写入 ScrollBox，故延后一帧再过滤。
  C_Timer.After(0, function()
    pcall(applyLootMountsOnlyFilter)
  end)
end

--- 资料片旁「仅坐骑」勾选：刷新战利品筛选 + 首页实例列表筛选。
local function onLootMountFilterCheckboxClick(self)
  local db = getDb()
  db.lootMountsOnly = self:GetChecked() and true or false
  if EncounterJournal_LootUpdate then
    pcall(EncounterJournal_LootUpdate)
  end
  if db.lootMountsOnly then
    -- 先刷新列表数据再筛：否则首页 ScrollBox 的 DataProvider 可能尚未就绪
    if EncounterJournal_ListInstances then
      pcall(EncounterJournal_ListInstances)
    end
    local function applyListAndOverlays()
      pcall(applyInstanceListMountFilter)
      pcall(refreshInstanceListOverlays)
    end
    C_Timer.After(0.03, applyListAndOverlays)
    C_Timer.After(0.12, applyListAndOverlays)
    C_Timer.After(0.28, applyListAndOverlays)
  else
    wipe(mountScanQueue)
    wipe(mountScanQueued)
    if EncounterJournal_ListInstances then
      EncounterJournal_ListInstances()
    end
  end
end

--- 隐藏旧版本「仅坐骑副本」勾选，避免与当前设计重复。
local function hideLegacyMountInstanceFilterWidget()
  local cb = _G.ToolboxEJMountFilterCheck
  if cb and cb.Hide then
    cb:Hide()
    if cb.Disable then
      cb:Disable()
    end
  end
  local lab = _G.ToolboxEJMountFilterLabel
  if lab and lab.Hide then
    lab:Hide()
  end
end

local function createEncounterJournalWidgets()
  local ej = _G.EncounterJournal
  local is = resolveEJInstanceSelect()
  if not ej or not is or not is.ExpansionDropdown then
    return false
  end
  local db = getDb()
  hideLegacyMountInstanceFilterWidget()

  local lc = ej.encounter and ej.encounter.info and ej.encounter.info.LootContainer
  local lootParent = lc or is
  if lootParent and not _G.ToolboxEJLootMountFilterCheck then
    local lcb = CreateFrame("CheckButton", "ToolboxEJLootMountFilterCheck", lootParent, "UICheckButtonTemplate")
    lcb:SetSize(22, 22)
    lcb:SetChecked(db.lootMountsOnly == true)
    lcb:SetScript("OnClick", onLootMountFilterCheckboxClick)
    local llab = lootParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    llab:SetJustifyH("RIGHT")
    llab:SetText((Toolbox.L and Toolbox.L.SAVED_INST_EJ_LOOT_MOUNTS) or "")
    _G.ToolboxEJLootMountFilterLabel = llab
    pcall(reanchorLootMountFilter)
  elseif _G.ToolboxEJLootMountFilterCheck then
    _G.ToolboxEJLootMountFilterCheck:SetChecked(db.lootMountsOnly == true)
    _G.ToolboxEJLootMountFilterCheck:SetScript("OnClick", onLootMountFilterCheckboxClick)
    pcall(reanchorLootMountFilter)
  end
  return true
end

--- 在推荐/地城/团本/PvP 等面板切换时刷新插件控件是否应显示。
local function attachEJVisibilityHooks()
  local ej = _G.EncounterJournal
  if not ej or ej.toolboxEJVisibilityHooked then
    return
  end
  local function scheduleSync()
    C_Timer.After(0.02, function()
      pcall(syncToolboxEJVisibility)
    end)
  end
  if ej.LandingPage and ej.LandingPage.HookScript then
    ej.LandingPage:HookScript("OnShow", scheduleSync)
  end
  if ej.landingPage and ej.landingPage.HookScript then
    ej.landingPage:HookScript("OnShow", scheduleSync)
  end
  if ej.instanceSelect and ej.instanceSelect.HookScript then
    ej.instanceSelect:HookScript("OnShow", scheduleSync)
  end
  if ej.MonthlyActivitiesFrame and ej.MonthlyActivitiesFrame.HookScript then
    ej.MonthlyActivitiesFrame:HookScript("OnShow", scheduleSync)
  end
  if ej.PvPFrame and ej.PvPFrame.HookScript then
    ej.PvPFrame:HookScript("OnShow", scheduleSync)
  end
  ej.toolboxEJVisibilityHooked = true
end

local function tryInitHooks()
  if hooksInited then
    return
  end
  local ej = _G.EncounterJournal
  if not ej then
    return
  end
  if not hooksecurefunc then
    local L = Toolbox.L or {}
    Toolbox.Chat.PrintAddonMessage(L.SAVED_INST_EJ_HOOK_FAIL or "Toolbox: Encounter Journal hook failed.")
    hooksInited = true
    return
  end
  local ok1 = pcall(function()
    hooksecurefunc("EncounterJournal_ListInstances", onListInstances)
  end)
  pcall(function()
    hooksecurefunc("EncounterJournal_DisplayInstance", onDisplayInstance)
  end)
  pcall(function()
    hooksecurefunc("EncounterJournal_LootUpdate", onLootUpdate)
  end)
  if not ok1 then
    local L = Toolbox.L or {}
    Toolbox.Chat.PrintAddonMessage(L.SAVED_INST_EJ_HOOK_FAIL or "Toolbox: EncounterJournal_ListInstances hook failed.")
  end
  pcall(function()
    hooksecurefunc("EncounterJournal_SetTab", function()
      C_Timer.After(0.02, function()
        pcall(syncToolboxEJVisibility)
      end)
    end)
  end)
  -- 从副本详情返回实例列表时暴雪会调用，用于补一次锚点与可见性
  pcall(function()
    hooksecurefunc("EncounterJournal_ShowInstances", function()
      C_Timer.After(0.04, function()
        pcall(syncToolboxEJVisibility)
        pcall(reanchorLootMountFilter)
      end)
    end)
  end)
  pcall(createEncounterJournalWidgets)
  pcall(attachEJVisibilityHooks)
  C_Timer.After(0.1, function()
    pcall(syncToolboxEJVisibility)
  end)
  hooksInited = true
end

--- 注册冒险手册事件与 Hook；模块启用时由 SavedInstances 调用。
---@return nil
function Toolbox.SavedInstancesEJ.Register()
  if ejWidgetsFrame then
    return
  end
  ejWidgetsFrame = CreateFrame("Frame", "ToolboxSavedInstancesEJHost")
  ejWidgetsFrame:RegisterEvent("ADDON_LOADED")
  ejWidgetsFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
  ejWidgetsFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then
      C_Timer.After(0.05, tryInitHooks)
    elseif event == "UPDATE_INSTANCE_INFO" then
      if EncounterJournal and EncounterJournal:IsShown() and EncounterJournal.instanceSelect and EncounterJournal.instanceSelect:IsShown() then
        if EncounterJournal_ListInstances then
          EncounterJournal_ListInstances()
        end
      end
    end
  end)
  if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    C_Timer.After(0.05, tryInitHooks)
  end
  Data.EnsureEncounterJournalAddOn()
end

--- 切换界面语言后刷新战利品筛选控件的文案。
---@return nil
function Toolbox.SavedInstancesEJ.RefreshWidgetsLocale()
  if _G.ToolboxEJLootMountFilterLabel and Toolbox.L then
    _G.ToolboxEJLootMountFilterLabel:SetText(Toolbox.L.SAVED_INST_EJ_LOOT_MOUNTS or "")
  end
end
