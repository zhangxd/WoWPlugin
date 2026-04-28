local Harness = dofile("tests/logic/harness/harness.lua")

local function buildDataProvider()
  local provider = { -- 冒险手册列表数据源替身
    records = {
      { instanceID = 101 },
      { instanceID = 202 },
    },
    removeCount = 0,
  }

  function provider:ForEach(visitorFunc)
    for _, elementData in ipairs(self.records) do
      visitorFunc(elementData)
    end
  end

  function provider:Remove(targetElementData)
    for index = #self.records, 1, -1 do
      if self.records[index] == targetElementData then
        table.remove(self.records, index)
        self.removeCount = self.removeCount + 1
        break
      end
    end
  end

  return provider
end

local function buildLootDataProvider()
  local provider = { -- 详情页战利品数据源替身
    records = {
      { itemID = 111 },
      { itemID = 222 },
    },
    removeCount = 0,
  }

  function provider:ForEach(visitorFunc)
    for _, elementData in ipairs(self.records) do
      visitorFunc(elementData)
    end
  end

  function provider:Remove(targetElementData)
    for index = #self.records, 1, -1 do
      if self.records[index] == targetElementData then
        table.remove(self.records, index)
        self.removeCount = self.removeCount + 1
        break
      end
    end
  end

  return provider
end

describe("EncounterJournal mount filter", function()
  local harness = nil -- 测试 harness
  local dataProvider = nil -- 列表数据源

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    harness:loadEncounterJournalModule()
    dataProvider = buildDataProvider()

    Toolbox.EJ.IsRaidOrDungeonInstanceListTab = function()
      return true
    end
    Toolbox.EJ.HasMountDrops = function(journalInstanceID)
      return journalInstanceID == 101
    end

    local encounterJournalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal") -- 冒险手册根框体
    local instanceSelectFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 副本列表面板
    local expansionDropdown = harness.runtime.CreateFrame("Frame", nil, instanceSelectFrame) -- 资料片下拉框占位
    instanceSelectFrame.ExpansionDropdown = expansionDropdown
    instanceSelectFrame.ScrollBox = {
      GetDataProvider = function()
        return dataProvider
      end,
    }
    encounterJournalFrame.instanceSelect = instanceSelectFrame
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("refresh_apply_filter_removes_non_mount_instances", function()
    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    assert.equals(1, dataProvider.removeCount)
    assert.equals(1, #dataProvider.records)
    assert.equals(101, dataProvider.records[1].instanceID)
  end)

  it("detail_panel_does_not_show_redundant_mount_only_button", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local lootContainer = harness.runtime.CreateFrame("Frame", nil, infoFrame) -- 战利品容器
    lootContainer:Show()
    infoFrame.LootContainer = lootContainer
    infoFrame:Show()
    encounterFrame.info = infoFrame
    encounterFrame:Show()
    encounterJournalFrame.encounter = encounterFrame

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    assert.is_nil(_G.ToolboxEJDetailMountOnlyCheck)
  end)

  it("detail_panel_no_longer_filters_loot_to_mount_only", function()
    local lootDataProvider = buildLootDataProvider() -- 详情页战利品数据源
    harness.moduleDb.detailMountOnlyEnabled = true

    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local lootContainer = harness.runtime.CreateFrame("Frame", nil, infoFrame) -- 战利品容器
    lootContainer:Show()
    lootContainer.ScrollBox = {
      GetDataProvider = function()
        return lootDataProvider
      end,
    }
    infoFrame.LootContainer = lootContainer
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame
    encounterJournalFrame.instanceID = 101

    infoFrame:Show()
    encounterFrame:Show()

    local originalGetCurrentInstance = _G.EJ_GetCurrentInstance -- 旧 EJ 当前副本查询
    _G.EJ_GetCurrentInstance = function()
      return 101
    end
    Toolbox.EJ.GetMountItemSetForInstance = function()
      return {
        [111] = true,
      }
    end

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    assert.equals(0, lootDataProvider.removeCount)
    assert.equals(2, #lootDataProvider.records)

    _G.EJ_GetCurrentInstance = originalGetCurrentInstance
  end)

  it("lockout_label_shows_only_on_instance_title_when_lockout_exists", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local instanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 副本标题控件
    local encounterTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 首领标题控件
    infoFrame.instanceTitle = instanceTitle
    infoFrame.encounterTitle = encounterTitle
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame

    infoFrame:Show()
    encounterFrame:Show()
    encounterTitle:Show()
    instanceTitle:Hide()

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()
    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    assert.is_not_nil(lockoutLabel)
    assert.is_false(lockoutLabel:IsShown())

    instanceTitle:Show()
    local originalGetCurrentInstance = _G.EJ_GetCurrentInstance -- 旧的 EJ 当前副本查询
    _G.EJ_GetCurrentInstance = function()
      return 101
    end
    Toolbox.EJ.GetSelectedDifficultyID = function()
      return 16
    end
    Toolbox.EJ.GetLockoutForInstanceAndDifficulty = function()
      return { difficultyID = 16, difficultyName = "史诗", resetTime = 3600 }
    end
    Toolbox.EJ.GetAllLockoutsForInstance = function()
      return {}
    end
    scheduler:execute()
    assert.is_true(lockoutLabel:IsShown())

    _G.EJ_GetCurrentInstance = originalGetCurrentInstance
  end)

  it("lockout_label_hides_when_no_lockout", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local instanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 副本标题控件
    infoFrame.instanceTitle = instanceTitle
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame

    infoFrame:Show()
    encounterFrame:Show()
    instanceTitle:Show()

    local originalGetCurrentInstance = _G.EJ_GetCurrentInstance -- 旧的 EJ 当前副本查询
    _G.EJ_GetCurrentInstance = function()
      return 101
    end
    Toolbox.EJ.GetSelectedDifficultyID = function()
      return 16
    end
    Toolbox.EJ.GetLockoutForInstanceAndDifficulty = function()
      return nil
    end
    Toolbox.EJ.GetAllLockoutsForInstance = function()
      return {}
    end

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    assert.is_false(lockoutLabel and lockoutLabel:IsShown() or false)
    assert.equals("", lockoutLabel and lockoutLabel:GetText() or "")

    _G.EJ_GetCurrentInstance = originalGetCurrentInstance
  end)

  it("lockout_label_reanchors_to_instance_title_when_title_appears_late", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local difficultyControl = harness.runtime.CreateFrame("Frame", nil, infoFrame) -- 难度控件占位
    infoFrame.Difficulty = difficultyControl
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame

    infoFrame:Show()
    encounterFrame:Show()

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    assert.is_not_nil(lockoutLabel)
    local fallbackPoint = lockoutLabel._points[#lockoutLabel._points] -- 初次锚点
    assert.equals(difficultyControl, fallbackPoint and fallbackPoint.relativeFrame)

    local instanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 迟到的副本标题控件
    instanceTitle:Show()
    infoFrame.instanceTitle = instanceTitle

    scheduler:execute()

    local latestPoint = lockoutLabel._points[#lockoutLabel._points] -- 最新锚点
    assert.equals(instanceTitle, latestPoint and latestPoint.relativeFrame)
  end)

  it("lockout_label_anchors_after_visible_instance_title_text", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local infoInstanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 右侧详情区副本标题
    infoInstanceTitle:SetWidth(290) -- 暴雪原生宽度
    infoInstanceTitle:SetText("测试副本") -- 标题文本
    infoFrame.instanceTitle = infoInstanceTitle
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame

    infoFrame:Show()
    encounterFrame:Show()
    infoInstanceTitle:Show()

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    local latestPoint = lockoutLabel and lockoutLabel._points[#lockoutLabel._points] -- 最新锚点
    assert.equals(infoInstanceTitle, latestPoint and latestPoint.relativeFrame)
    assert.equals("LEFT", latestPoint and latestPoint.relativePoint)
    assert.equals((#"测试副本" * 8) + 8, latestPoint and latestPoint.x)
  end)

  it("lockout_label_falls_back_when_selected_difficulty_has_no_lockout", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local infoInstanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 右侧详情区副本标题
    infoInstanceTitle:SetText("测试副本")
    infoFrame.instanceTitle = infoInstanceTitle
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame

    infoFrame:Show()
    encounterFrame:Show()
    infoInstanceTitle:Show()

    local originalGetCurrentInstance = _G.EJ_GetCurrentInstance -- 旧的 EJ 当前副本查询
    _G.EJ_GetCurrentInstance = function()
      return 101
    end

    Toolbox.EJ.GetSelectedDifficultyID = function()
      return 999
    end
    Toolbox.EJ.GetLockoutForInstanceAndDifficulty = function()
      return nil
    end
    Toolbox.EJ.GetAllLockoutsForInstance = function()
      return {
        { difficultyID = 16, difficultyName = "史诗", resetTime = 5400 },
      }
    end

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    assert.equals("重置：1h 30m", lockoutLabel and lockoutLabel:GetText())

    _G.EJ_GetCurrentInstance = originalGetCurrentInstance
  end)

  it("lockout_label_uses_encounterjournal_instanceid_when_ej_current_instance_is_invalid", function()
    local encounterJournalFrame = _G.EncounterJournal -- 冒险手册根框体
    local encounterFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 首领详情面板
    local infoFrame = harness.runtime.CreateFrame("Frame", nil, encounterFrame) -- 首领详情信息面板
    local infoInstanceTitle = harness.runtime.CreateFrame("FontString", nil, infoFrame) -- 右侧详情区副本标题
    infoInstanceTitle:SetText("测试副本")
    infoFrame.instanceTitle = infoInstanceTitle
    encounterFrame.info = infoFrame
    encounterJournalFrame.encounter = encounterFrame
    encounterJournalFrame.instanceID = 2001

    infoFrame:Show()
    encounterFrame:Show()
    infoInstanceTitle:Show()

    local originalGetCurrentInstance = _G.EJ_GetCurrentInstance -- 旧 EJ 当前副本查询
    _G.EJ_GetCurrentInstance = function()
      return 0 -- 模拟 API 返回无效实例 ID
    end

    Toolbox.EJ.GetSelectedDifficultyID = function()
      return 16
    end
    Toolbox.EJ.GetLockoutForInstanceAndDifficulty = function(journalInstanceID, difficultyID)
      if journalInstanceID == 2001 and difficultyID == 16 then
        return { difficultyID = 16, difficultyName = "史诗", resetTime = 7200 }
      end
      return nil
    end
    Toolbox.EJ.GetAllLockoutsForInstance = function()
      return {}
    end

    local scheduler = Toolbox.TestHooks.EncounterJournal:getRefreshScheduler() -- 刷新调度器
    scheduler:execute()

    local lockoutLabel = Toolbox.EncounterJournalInternal.DetailEnhancer.lockoutLabel -- 重置标签
    assert.equals("重置：2h 0m", lockoutLabel and lockoutLabel:GetText())

    _G.EJ_GetCurrentInstance = originalGetCurrentInstance
  end)
end)
