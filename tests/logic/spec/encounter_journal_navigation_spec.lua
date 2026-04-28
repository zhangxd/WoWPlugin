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

  it("finds_dungeon_entrance_by_journal_instance_id_from_exported_data", function()
    Toolbox.Data.NavigationInstanceEntrances = {
      entrancesByJournalInstanceID = {
        [2001] = {
          JournalInstanceID = 2001,
          EntranceID = 7001,
          Name_lang = "测试副本入口",
          TargetUiMapID = 85,
          TargetX = 0.42,
          TargetY = 0.64,
        },
      },
    }

    local entrance = Toolbox.EJ.FindDungeonEntranceForJournalInstance(2001, {
      candidateMapIDs = { 84, 85 },
    })

    assert.equals(85, entrance.uiMapID)
    assert.equals(7001, entrance.entranceID)
    assert.equals("测试副本入口", entrance.name)
    assert.equals("exported", entrance.source)
    assert.equals(0.42, entrance.position.x)
    assert.equals(0.64, entrance.position.y)
  end)

  it("opens_map_and_sets_super_tracked_user_waypoint_for_entrance", function()
    local waypointCalls = {} -- waypoint 设置调用
    local superTrackCalls = {} -- super track 调用
    local openedMapIDs = {} -- 打开的地图 ID
    local createdPoint = nil -- 创建出的 UiMapPoint
    Toolbox.Data.NavigationInstanceEntrances = {
      entrancesByJournalInstanceID = {
        [2001] = {
          JournalInstanceID = 2001,
          EntranceID = 7001,
          Name_lang = "测试副本入口",
          TargetUiMapID = 85,
          TargetX = 0.42,
          TargetY = 0.64,
        },
      },
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
    assert.equals(0.42, waypointCalls[1].position.x)
    assert.equals(0.64, waypointCalls[1].position.y)
    assert.same({ true }, superTrackCalls)
  end)

  it("returns_failure_without_throwing_when_waypoint_is_not_allowed", function()
    Toolbox.Data.NavigationInstanceEntrances = {
      entrancesByJournalInstanceID = {
        [2001] = {
          JournalInstanceID = 2001,
          EntranceID = 7001,
          Name_lang = "测试副本入口",
          TargetUiMapID = 85,
          TargetX = 0.42,
          TargetY = 0.64,
        },
      },
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

  it("uses_exported_db_entrance_for_duplicate_instance_map_entries", function()
    local convertedPosition = { x = 0.44, y = 0.37 } -- 转换后的地图坐标
    local createdPoint = nil -- 创建出的 waypoint
    local waypointCalls = {} -- waypoint 设置调用
    local openedMapIDs = {} -- 打开的地图 ID

    Toolbox.Data.NavigationInstanceEntrances = {
      entrancesByJournalInstanceID = {
        [1277] = {
          JournalInstanceID = 1277,
          EntranceID = 209,
          Name_lang = "厄运之槌 - 戈多克议会",
          WorldMapID = 1,
          TargetUiMapID = 69,
          TargetX = 0.44,
          TargetY = 0.37,
        },
      },
    }

    _G.C_Map = {
      CanSetUserWaypointOnMap = function(uiMapID)
        return uiMapID == 69
      end,
      SetUserWaypoint = function(mapPoint)
        waypointCalls[#waypointCalls + 1] = mapPoint
      end,
    }
    _G.CreateVector2D = function(xValue, yValue)
      return { x = xValue, y = yValue }
    end
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

    local success, result = Toolbox.EJ.NavigateToDungeonEntrance(1277, {
      candidateMapIDs = { 69 },
    })

    assert.is_true(success)
    assert.equals("exported", result.source)
    assert.equals("厄运之槌 - 戈多克议会", result.name)
    assert.same({ 69 }, openedMapIDs)
    assert.equals(createdPoint, waypointCalls[1])
    assert.equals(convertedPosition.x, waypointCalls[1].position.x)
    assert.equals(convertedPosition.y, waypointCalls[1].position.y)
  end)

  it("uses_static_db_entrance_when_runtime_entrance_is_missing_exact_journal_id", function()
    local conversionCalls = {} -- 世界坐标转换调用
    local waypointCalls = {} -- waypoint 设置调用
    local openedMapIDs = {} -- 打开的地图 ID
    local convertedPosition = { x = 0.59518843889236, y = 0.403237074613 } -- 转换后的地图坐标

    Toolbox.Data.InstanceEntrances = {
      entrances = {
        [1277] = {
          {
            Source = "journalinstanceentrance",
            EntranceID = 209,
            JournalInstanceID = 1277,
            InstanceName = "厄运之槌 - 戈多克议会",
            AreaName = "巨槌竞技场",
            WorldMapID = 1,
            HintUiMapID = 69,
            WorldX = -3519.95,
            WorldY = 1089.93,
            WorldZ = 161.065,
          },
        },
      },
    }

    _G.C_EncounterJournal = {
      GetDungeonEntrancesForMap = function(uiMapID)
        if uiMapID == 69 then
          return {
            {
              journalInstanceID = 230,
              areaPoiID = 6501,
              name = "厄运之槌",
              position = { x = 0.59518843889236, y = 0.403237074613 },
            },
          }
        end
        return {}
      end,
    }
    _G.C_Map = {
      GetMapPosFromWorldPos = function(worldMapID, worldPosition, overrideUiMapID)
        conversionCalls[#conversionCalls + 1] = {
          worldMapID = worldMapID,
          worldPosition = worldPosition,
          overrideUiMapID = overrideUiMapID,
        }
        return 69, convertedPosition
      end,
      CanSetUserWaypointOnMap = function(uiMapID)
        return uiMapID == 69
      end,
      SetUserWaypoint = function(mapPoint)
        waypointCalls[#waypointCalls + 1] = mapPoint
      end,
    }
    _G.CreateVector2D = function(xValue, yValue)
      return { x = xValue, y = yValue }
    end
    _G.UiMapPoint = {
      CreateFromVector2D = function(uiMapID, position)
        return {
          uiMapID = uiMapID,
          position = position,
        }
      end,
    }
    _G.OpenWorldMap = function(uiMapID)
      openedMapIDs[#openedMapIDs + 1] = uiMapID
    end

    local success, result = Toolbox.EJ.NavigateToDungeonEntrance(1277, {
      candidateMapIDs = { 69 },
    })

    assert.is_true(success)
    assert.equals("static", result.source)
    assert.equals("厄运之槌 - 戈多克议会", result.name)
    assert.equals(209, result.entranceID)
    assert.same({ 69 }, openedMapIDs)
    assert.equals(1, #conversionCalls)
    assert.equals(1, conversionCalls[1].worldMapID)
    assert.equals(-3519.95, conversionCalls[1].worldPosition.x)
    assert.equals(1089.93, conversionCalls[1].worldPosition.y)
    assert.equals(69, conversionCalls[1].overrideUiMapID)
    assert.equals(convertedPosition, waypointCalls[1].position)
  end)

  it("uses_static_db_entrance_directly_without_runtime_priority", function()
    local runtimeCallCount = 0 -- 运行时入口 API 调用次数
    local conversionCalls = {} -- 世界坐标转换调用
    local staticPosition = { x = 0.31, y = 0.62 } -- 静态数据转换后的坐标

    Toolbox.Data.InstanceEntrances = {
      entrances = {
        [230] = {
          {
            Source = "areapoi",
            EntranceID = 6501,
            AreaPoiID = 6501,
            JournalInstanceID = 230,
            InstanceName = "厄运之槌 - 中心花园",
            AreaName = "厄运之槌",
            WorldMapID = 1,
            HintUiMapID = 69,
            WorldX = -4235.0,
            WorldY = 1305.11,
            WorldZ = 177.129,
          },
        },
      },
    }

    _G.C_EncounterJournal = {
      GetDungeonEntrancesForMap = function()
        runtimeCallCount = runtimeCallCount + 1
        return {
          {
            journalInstanceID = 230,
            areaPoiID = 6501,
            name = "运行时入口不应优先",
            position = { x = 0.99, y = 0.99 },
          },
        }
      end,
    }
    _G.C_Map = {
      GetMapPosFromWorldPos = function(worldMapID, worldPosition, overrideUiMapID)
        conversionCalls[#conversionCalls + 1] = {
          worldMapID = worldMapID,
          worldPosition = worldPosition,
          overrideUiMapID = overrideUiMapID,
        }
        return 69, staticPosition
      end,
    }
    _G.CreateVector2D = function(xValue, yValue)
      return { x = xValue, y = yValue }
    end

    local entrance = Toolbox.EJ.FindDungeonEntranceForJournalInstance(230, {
      candidateMapIDs = { 69 },
    })

    assert.equals(0, runtimeCallCount)
    assert.equals("static", entrance.source)
    assert.equals("厄运之槌 - 中心花园", entrance.name)
    assert.equals(6501, entrance.areaPoiID)
    assert.equals(staticPosition, entrance.position)
    assert.equals(1, #conversionCalls)
    assert.equals(-4235.0, conversionCalls[1].worldPosition.x)
    assert.equals(1305.11, conversionCalls[1].worldPosition.y)
  end)

  it("list_row_pin_invokes_navigation_for_row_instance", function()
    harness:teardown()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    harness.moduleDb.listPinAlwaysVisible = true

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
    assert.equals("Waypoint-MapPin-Tracked", buttonObject._ToolboxEntrancePinIcon._atlas)

    buttonObject:RunScript("OnClick")

    assert.same({ 2001 }, navigateCalls)
    local traceList = harness:getTrace()
    local lastTrace = traceList[#traceList]
    assert.equals("chat_print", lastTrace.kind)
    assert.matches("测试副本入口", lastTrace.text)
  end)

  it("single_click_focuses_row_without_entering_and_hover_reveals_non_focused_pin", function()
    harness:teardown()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    harness.moduleDb.listPinAlwaysVisible = false
    local encounterJournalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal", UIParent) -- 冒险指南根框体
    local instanceSelectFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 副本列表面板
    local scrollBoxFrame = harness.runtime.CreateFrame("Frame", nil, instanceSelectFrame) -- 列表滚动框
    local enterCallCount = 0 -- 进入副本调用次数

    local firstRow = harness.runtime.CreateFrame("Button", nil, scrollBoxFrame) -- 第一行
    firstRow.GetElementData = function()
      return { instanceID = 2001, name = "测试副本一" }
    end
    firstRow:SetScript("OnClick", function()
      enterCallCount = enterCallCount + 1
    end)

    local secondRow = harness.runtime.CreateFrame("Button", nil, scrollBoxFrame) -- 第二行
    secondRow.GetElementData = function()
      return { instanceID = 2002, name = "测试副本二" }
    end
    secondRow:SetScript("OnClick", function()
      enterCallCount = enterCallCount + 1
    end)

    scrollBoxFrame.ForEachFrame = function(_, callback)
      callback(firstRow)
      callback(secondRow)
    end
    instanceSelectFrame.ScrollBox = scrollBoxFrame
    encounterJournalFrame.instanceSelect = instanceSelectFrame
    encounterJournalFrame:Show()
    instanceSelectFrame:Show()
    scrollBoxFrame:Show()
    firstRow:Show()
    secondRow:Show()

    harness:loadEncounterJournalModule()
    harness.moduleDef.OnModuleEnable()

    local firstButton = firstRow._ToolboxEntrancePinButton -- 第一行图钉
    local secondButton = secondRow._ToolboxEntrancePinButton -- 第二行图钉
    assert.is_false(firstButton:IsShown())
    assert.is_false(secondButton:IsShown())
    assert.equals("Waypoint-MapPin-Tracked", firstButton._ToolboxEntrancePinIcon._atlas)
    assert.equals("Waypoint-MapPin-Highlight", firstButton._ToolboxEntrancePinHighlight._atlas)

    firstRow:RunScript("OnClick", "LeftButton")

    assert.equals(0, enterCallCount)
    assert.is_true(firstButton:IsShown())
    assert.is_false(secondButton:IsShown())

    secondRow:RunScript("OnEnter")
    assert.is_true(secondButton:IsShown())

    secondRow:RunScript("OnLeave")
    assert.is_false(secondButton:IsShown())
    assert.is_true(firstButton:IsShown())
  end)

  it("keeps_hover_pin_visible_when_cursor_moves_from_row_to_pin", function()
    harness:teardown()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    harness.moduleDb.listPinAlwaysVisible = false

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

    harness:loadEncounterJournalModule()
    harness.moduleDef.OnModuleEnable()

    local buttonObject = rowFrame._ToolboxEntrancePinButton -- 列表行图钉按钮
    assert.is_false(buttonObject:IsShown())

    rowFrame:RunScript("OnEnter")
    assert.is_true(buttonObject:IsShown())

    buttonObject.IsMouseOver = function()
      return true
    end
    rowFrame:RunScript("OnLeave")

    assert.is_true(buttonObject:IsShown())

    buttonObject.IsMouseOver = function()
      return false
    end
    rowFrame.IsMouseOver = function()
      return false
    end
    buttonObject:RunScript("OnLeave")

    assert.is_false(buttonObject:IsShown())
  end)

  it("double_click_uses_original_enter_behavior_for_focused_row", function()
    harness:teardown()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    harness.moduleDb.listPinAlwaysVisible = false
    local encounterJournalFrame = harness.runtime.CreateFrame("Frame", "EncounterJournal", UIParent) -- 冒险指南根框体
    local instanceSelectFrame = harness.runtime.CreateFrame("Frame", nil, encounterJournalFrame) -- 副本列表面板
    local scrollBoxFrame = harness.runtime.CreateFrame("Frame", nil, instanceSelectFrame) -- 列表滚动框
    local enterCallCount = 0 -- 进入副本调用次数

    local rowFrame = harness.runtime.CreateFrame("Button", nil, scrollBoxFrame) -- 副本列表行
    rowFrame.GetElementData = function()
      return { instanceID = 2001, name = "测试副本" }
    end
    rowFrame:SetScript("OnClick", function()
      enterCallCount = enterCallCount + 1
    end)

    scrollBoxFrame.ForEachFrame = function(_, callback)
      callback(rowFrame)
    end
    instanceSelectFrame.ScrollBox = scrollBoxFrame
    encounterJournalFrame.instanceSelect = instanceSelectFrame
    encounterJournalFrame:Show()
    instanceSelectFrame:Show()
    scrollBoxFrame:Show()
    rowFrame:Show()

    harness:loadEncounterJournalModule()
    harness.moduleDef.OnModuleEnable()

    rowFrame:RunScript("OnClick", "LeftButton")
    assert.equals(0, enterCallCount)

    rowFrame:RunScript("OnDoubleClick", "LeftButton")
    assert.equals(1, enterCallCount)
  end)
end)
