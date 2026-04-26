local Harness = dofile("tests/logic/harness/harness.lua")

describe("EncounterJournal entrance navigation", function()
  local harness = nil -- 测试 harness

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    local apiChunk = assert(loadfile("Toolbox/Core/API/EncounterJournal.lua"))
    apiChunk()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("finds_dungeon_entrance_by_journal_instance_id_from_candidate_maps", function()
    local positionObject = {
      GetXY = function()
        return 0.42, 0.64
      end,
    } -- 入口坐标
    local queriedMapIDs = {} -- 查询过的地图 ID

    _G.C_EncounterJournal = {
      GetDungeonEntrancesForMap = function(uiMapID)
        queriedMapIDs[#queriedMapIDs + 1] = uiMapID
        if uiMapID == 85 then
          return {
            {
              journalInstanceID = 2001,
              areaPoiID = 7001,
              name = "测试副本入口",
              position = positionObject,
            },
          }
        end
        return {}
      end,
    }

    local entrance = Toolbox.EJ.FindDungeonEntranceForJournalInstance(2001, {
      candidateMapIDs = { 84, 85 },
    })

    assert.equals(84, queriedMapIDs[1])
    assert.equals(85, queriedMapIDs[2])
    assert.equals(85, entrance.uiMapID)
    assert.equals(7001, entrance.areaPoiID)
    assert.equals("测试副本入口", entrance.name)
    assert.equals(positionObject, entrance.position)
  end)

  it("opens_map_and_sets_super_tracked_user_waypoint_for_entrance", function()
    local waypointCalls = {} -- waypoint 设置调用
    local superTrackCalls = {} -- super track 调用
    local openedMapIDs = {} -- 打开的地图 ID
    local createdPoint = nil -- 创建出的 UiMapPoint
    local positionObject = {} -- 入口坐标对象

    _G.C_EncounterJournal = {
      GetDungeonEntrancesForMap = function(uiMapID)
        if uiMapID == 85 then
          return {
            {
              journalInstanceID = 2001,
              areaPoiID = 7001,
              name = "测试副本入口",
              position = positionObject,
            },
          }
        end
        return {}
      end,
    }
    _G.C_Map = {
      CanSetUserWaypointOnMap = function(uiMapID)
        return uiMapID == 85
      end,
      SetUserWaypoint = function(mapPoint)
        waypointCalls[#waypointCalls + 1] = mapPoint
      end,
    }
    _G.C_SuperTrack = {
      SetSuperTrackedUserWaypoint = function(enabled)
        superTrackCalls[#superTrackCalls + 1] = enabled
      end,
    }
    _G.UiMapPoint = {
      CreateFromVector2D = function(uiMapID, position)
        createdPoint = {
          uiMapID = uiMapID,
          position = position,
        }
        return createdPoint
      end,
    }
    _G.OpenWorldMap = function(uiMapID)
      openedMapIDs[#openedMapIDs + 1] = uiMapID
    end

    local success, result = Toolbox.EJ.NavigateToDungeonEntrance(2001, {
      candidateMapIDs = { 85 },
    })

    assert.is_true(success)
    assert.equals("测试副本入口", result.name)
    assert.same({ 85 }, openedMapIDs)
    assert.equals(createdPoint, waypointCalls[1])
    assert.equals(85, waypointCalls[1].uiMapID)
    assert.equals(positionObject, waypointCalls[1].position)
    assert.same({ true }, superTrackCalls)
  end)

  it("returns_failure_without_throwing_when_waypoint_is_not_allowed", function()
    _G.C_EncounterJournal = {
      GetDungeonEntrancesForMap = function(uiMapID)
        if uiMapID == 85 then
          return {
            {
              journalInstanceID = 2001,
              areaPoiID = 7001,
              name = "测试副本入口",
              position = {},
            },
          }
        end
        return {}
      end,
    }
    _G.C_Map = {
      CanSetUserWaypointOnMap = function()
        return false
      end,
      SetUserWaypoint = function()
        error("SetUserWaypoint should not be called")
      end,
    }
    _G.UiMapPoint = {
      CreateFromVector2D = function()
        error("CreateFromVector2D should not be called")
      end,
    }

    local success, reason = Toolbox.EJ.NavigateToDungeonEntrance(2001, {
      candidateMapIDs = { 85 },
    })

    assert.is_false(success)
    assert.equals("waypoint_forbidden", reason)
  end)

  it("list_row_pin_invokes_navigation_for_row_instance", function()
    harness:teardown()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    local encounterJournalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal", UIParent) -- 冒险指南根框体
    local instanceSelectFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 副本列表面板
    local scrollBoxFrame = harness.runtime.CreateFrame("Frame", nil, instanceSelectFrame) -- 列表滚动框
    local rowFrame = harness.runtime.CreateFrame("Button", nil, scrollBoxFrame) -- 副本列表行
    rowFrame.GetElementData = function()
      return { instanceID = 2001, name = "测试副本" }
    end
    scrollBoxFrame.ForEachFrame = function(_, callback)
      callback(rowFrame)
    end
    instanceSelectFrame.ScrollBox = scrollBoxFrame
    encounterJournalFrame.instanceSelect = instanceSelectFrame
    encounterJournalFrame:Show()
    instanceSelectFrame:Show()
    scrollBoxFrame:Show()
    rowFrame:Show()

    local navigateCalls = {} -- 导航调用记录
    Toolbox.EJ.NavigateToDungeonEntrance = function(journalInstanceID)
      navigateCalls[#navigateCalls + 1] = journalInstanceID
      return true, { name = "测试副本入口" }
    end

    harness:loadEncounterJournalModule()
    harness.moduleDef.OnModuleEnable()

    local buttonObject = rowFrame._ToolboxEntrancePinButton -- 列表行图钉按钮
    assert.is_truthy(buttonObject)
    assert.is_true(buttonObject:IsShown())
    assert.is_nil(buttonObject.templateName)
    assert.equals("", buttonObject:GetText())
    assert.is_truthy(buttonObject._ToolboxEntrancePinIcon)
    assert.equals("Waypoint-MapPin-ChatIcon", buttonObject._ToolboxEntrancePinIcon._atlas)

    buttonObject:RunScript("OnClick")

    assert.same({ 2001 }, navigateCalls)
    local traceList = harness:getTrace()
    local lastTrace = traceList[#traceList]
    assert.equals("chat_print", lastTrace.kind)
    assert.matches("测试副本入口", lastTrace.text)
  end)
end)
