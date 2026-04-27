describe("Navigation API", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalUnitClass = nil -- 原始 UnitClass 全局
  local originalUnitFactionGroup = nil -- 原始 UnitFactionGroup 全局
  local originalCSpellBook = nil -- 原始 C_SpellBook 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local originalCreateVector2D = nil -- 原始 CreateVector2D 全局

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalUnitClass = rawget(_G, "UnitClass")
    originalUnitFactionGroup = rawget(_G, "UnitFactionGroup")
    originalCSpellBook = rawget(_G, "C_SpellBook")
    originalCMap = rawget(_G, "C_Map")
    originalCreateVector2D = rawget(_G, "CreateVector2D")
    rawset(_G, "Toolbox", {
      Navigation = {},
      Data = {},
      L = {},
    })

    local moduleChunk = assert(loadfile("Toolbox/Core/API/Navigation.lua")) -- 导航 API chunk
    moduleChunk()
    dofile("Toolbox/Data/NavigationMapNodes.lua")
    dofile("Toolbox/Data/NavigationRouteEdges.lua")
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "UnitClass", originalUnitClass)
    rawset(_G, "UnitFactionGroup", originalUnitFactionGroup)
    rawset(_G, "C_SpellBook", originalCSpellBook)
    rawset(_G, "C_Map", originalCMap)
    rawset(_G, "CreateVector2D", originalCreateVector2D)
  end)

  it("finds_the_lowest_cost_route_between_nodes", function()
    local routeGraph = { -- 测试路径图
      nodes = {
        start = { id = "start", name = "起点" },
        portal = { id = "portal", name = "传送点" },
        target = { id = "target", name = "目标" },
      },
      edges = {
        { from = "start", to = "target", cost = 120, label = "直接前往" },
        { from = "start", to = "portal", cost = 10, label = "使用传送" },
        { from = "portal", to = "target", cost = 30, label = "前往目标" },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.FindShortestPath(routeGraph, "start", "target")

    assert.is_nil(errorObject)
    assert.equals(40, routeResult.totalCost)
    assert.same({ "start", "portal", "target" }, routeResult.nodePath)
    assert.same({ "使用传送", "前往目标" }, routeResult.stepLabels)
  end)

  it("filters_edges_that_are_not_confirmed_available_for_the_current_character", function()
    local routeGraph = { -- 包含可用与不可用边的路径图
      nodes = {
        start = { id = "start", name = "起点" },
        orgrimmar = { id = "orgrimmar", name = "奥格瑞玛" },
        stormwind = { id = "stormwind", name = "暴风城" },
        unknownPortal = { id = "unknownPortal", name = "未知传送门" },
      },
      edges = {
        { from = "start", to = "orgrimmar", cost = 10, requirements = { classFile = "MAGE", spellID = 3567 } },
        { from = "start", to = "stormwind", cost = 10, requirements = { faction = "Alliance" } },
        { from = "start", to = "unknownPortal", cost = 10, requirements = { spellID = 999999 } },
      },
    }
    local availabilityContext = { -- 当前角色可用性快照
      classFile = "MAGE",
      faction = "Horde",
      knownSpellByID = {
        [3567] = true,
      },
    }

    local filteredGraph = Toolbox.Navigation.FilterRouteGraph(routeGraph, availabilityContext)

    assert.equals(1, #filteredGraph.edges)
    assert.equals("orgrimmar", filteredGraph.edges[1].to)
  end)

  it("plans_orgrimmar_route_with_mage_teleport_only_when_spell_is_confirmed", function()
    local routeGraph = { -- 奥格瑞玛验收样例路径图
      nodes = {
        current = { id = "current", name = "当前位置" },
        orgrimmar = { id = "orgrimmar", name = "奥格瑞玛" },
        durotar = { id = "durotar", name = "杜隆塔尔目标" },
      },
      edges = {
        { from = "current", to = "durotar", cost = 180, label = "直接跨地图移动" },
        { from = "current", to = "orgrimmar", cost = 10, label = "传送：奥格瑞玛", requirements = { classFile = "MAGE", spellID = 3567 } },
        { from = "orgrimmar", to = "durotar", cost = 25, label = "从奥格瑞玛前往杜隆塔尔" },
      },
    }

    local mageRoute = Toolbox.Navigation.PlanRoute(routeGraph, "current", "durotar", {
      classFile = "MAGE",
      faction = "Horde",
      knownSpellByID = {
        [3567] = true,
      },
    })

    assert.equals(35, mageRoute.totalCost)
    assert.same({ "传送：奥格瑞玛", "从奥格瑞玛前往杜隆塔尔" }, mageRoute.stepLabels)

    local unknownSpellRoute = Toolbox.Navigation.PlanRoute(routeGraph, "current", "durotar", {
      classFile = "MAGE",
      faction = "Horde",
      knownSpellByID = {},
    })

    assert.equals(180, unknownSpellRoute.totalCost)
    assert.same({ "直接跨地图移动" }, unknownSpellRoute.stepLabels)
  end)

  it("builds_current_character_availability_from_runtime_spellbook", function()
    local checkedSpellIDList = {} -- 被查询的技能 ID
    rawset(_G, "UnitClass", function()
      return "法师", "MAGE", 8
    end)
    rawset(_G, "UnitFactionGroup", function()
      return "Horde", "Horde"
    end)
    rawset(_G, "C_SpellBook", {
      IsSpellInSpellBook = function(spellID)
        checkedSpellIDList[#checkedSpellIDList + 1] = spellID
        return spellID == 3567
      end,
      IsSpellKnown = function()
        error("should prefer C_SpellBook.IsSpellInSpellBook")
      end,
    })
    rawset(_G, "C_Map", {
      GetBestMapForUnit = function(unitToken)
        assert.equals("player", unitToken)
        return 110
      end,
    })

    local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability({ 3567, 999999 })

    assert.equals("MAGE", availabilityContext.classFile)
    assert.equals("Horde", availabilityContext.faction)
    assert.equals(110, availabilityContext.currentUiMapID)
    assert.is_true(availabilityContext.knownSpellByID[3567])
    assert.is_nil(availabilityContext.knownSpellByID[999999])
    assert.same({ 3567, 999999 }, checkedSpellIDList)
  end)

  it("falls_back_to_legacy_spellbook_known_api_when_needed", function()
    rawset(_G, "UnitClass", function()
      return "法师", "MAGE", 8
    end)
    rawset(_G, "UnitFactionGroup", function()
      return "Horde", "Horde"
    end)
    rawset(_G, "C_SpellBook", {
      IsSpellKnown = function(spellID)
        return spellID == 3567
      end,
    })

    local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability({ 3567 })

    assert.is_true(availabilityContext.knownSpellByID[3567])
  end)

  it("collects_required_spell_ids_from_route_data", function()
    local spellIDList = Toolbox.Navigation.GetRequiredSpellIDList({
      edges = {
        { requirements = { spellID = 3567 } },
        { requirements = { spellID = 3567 } },
        { requirements = { spellID = 50977 } },
        { requirements = { classFile = "MAGE" } },
      },
    })

    assert.same({ 3567, 50977 }, spellIDList)
  end)

  it("plans_map_target_route_from_exported_navigation_data", function()
    Toolbox.Data.NavigationMapNodes = {
      nodes = {
        [777] = { ID = 777, Name_lang = "测试目标" },
        [888] = { ID = 888, Name_lang = "测试起点" },
      },
    }
    Toolbox.Data.NavigationRouteEdges = {
      schemaVersion = 2,
      nodes = {
        uimap_777 = { ID = 777, Source = "uimap", UiMapID = 777, Name_lang = "测试目标" },
        uimap_888 = { ID = 888, Source = "uimap", UiMapID = 888, Name_lang = "测试起点" },
      },
      edges = {
        {
          from = "uimap_888",
          to = "uimap_777",
          cost = 12,
          label = "前往测试目标",
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 777,
    }, {
      classFile = "MAGE",
      currentUiMapID = 888,
      knownSpellByID = {
        [123] = true,
      },
    })

    assert.is_nil(errorObject)
    assert.equals(192, routeResult.totalCost)
    assert.same({ "当前位置：测试起点", "前往测试目标", "目标位置：测试目标" }, routeResult.stepLabels)
  end)

  it("adds_terminal_cost_from_exported_via_arrival_position_to_target_coordinates", function()
    Toolbox.Data.NavigationMapNodes = {
      nodes = {
        [777] = { ID = 777, Name_lang = "测试目标" },
      },
    }
    Toolbox.Data.NavigationRouteEdges = {
      schemaVersion = 2,
      nodes = {
        uimap_777 = { Source = "uimap", UiMapID = 777, Name_lang = "测试目标" },
      },
      targetRules = {},
      edges = {},
    }

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 777,
      x = 0.12,
      y = 0.10,
    }, {
      classFile = "MAGE",
      currentUiMapID = 777,
      knownSpellByID = {},
    })

    assert.same({ "当前位置：测试目标", "目标位置：测试目标 12.0, 10.0" }, routeResult.stepLabels)
  end)

  it("consumes_simulated_public_transport_edges_for_borean_tundra_route", function()
    Toolbox.Data.NavigationMapNodes = {
      nodes = {
        [85] = { ID = 85, Name_lang = "奥格瑞玛" },
        [114] = { ID = 114, Name_lang = "北风苔原" },
      },
    }
    Toolbox.Data.NavigationRouteEdges = {
      schemaVersion = 2,
      nodes = {
        uimap_85 = { Source = "uimap", UiMapID = 85, Name_lang = "奥格瑞玛" },
        uimap_114 = { Source = "uimap", UiMapID = 114, Name_lang = "北风苔原" },
        waypoint_1 = { Source = "waypoint", UiMapID = 85, Name_lang = "奥格瑞玛飞艇" },
        waypoint_2 = { Source = "waypoint", UiMapID = 114, Name_lang = "战歌要塞" },
      },
      edges = {
        {
          from = "uimap_85",
          to = "waypoint_1",
          cost = 1,
          label = "前往奥格瑞玛飞艇",
        },
        {
          from = "waypoint_1",
          to = "waypoint_2",
          cost = 25,
          label = "乘坐飞艇前往战歌要塞",
        },
        {
          from = "waypoint_2",
          to = "uimap_114",
          cost = 1,
          label = "前往北风苔原",
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 114,
      x = 0.45,
      y = 0.55,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 85,
      knownSpellByID = {},
    })

    assert.is_nil(errorObject)
    assert.same({
      "当前位置：奥格瑞玛",
      "前往奥格瑞玛飞艇",
      "乘坐飞艇前往战歌要塞",
      "前往北风苔原",
      "目标位置：北风苔原 45.0, 55.0",
    }, routeResult.stepLabels)
    assert.is_true(routeResult.totalCost < 300)
  end)

  it("rejects_world_and_continent_maps_as_navigation_targets", function()
    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 947,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 85,
      knownSpellByID = {},
    })

    assert.is_nil(routeResult)
    assert.equals("NAVIGATION_ERR_UNSUPPORTED_MAP_LEVEL", errorObject.code)
  end)

  it("plans_orgrimmar_to_silvermoon_from_exported_route_edges", function()
    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 110,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 85,
      knownSpellByID = {},
    })

    assert.is_nil(errorObject)
    assert.equals("当前位置：奥格瑞玛", routeResult.stepLabels[1])
    assert.is_true(type(routeResult.stepLabels[2]) == "string")
    assert.is_true(string.find(routeResult.stepLabels[2], "银月城", 1, true) ~= nil)
    assert.is_true(string.find(routeResult.stepLabels[2], "传送门", 1, true) ~= nil)
    assert.is_true(string.find(routeResult.stepLabels[#routeResult.stepLabels], "目标位置：银月城", 1, true) ~= nil)
  end)

  it("resolves_target_point_to_a_more_specific_child_map_before_planning", function()
    rawset(_G, "C_Map", {
      GetMapInfoAtPosition = function(uiMapID, posX, posY)
        assert.equals(94, uiMapID)
        assert.equals(0.50, posX)
        assert.equals(0.50, posY)
        return {
          mapID = 110,
          name = "银月城",
        }
      end,
    })

    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 94,
      x = 0.50,
      y = 0.50,
      name = "银月城",
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 85,
      knownSpellByID = {},
    })

    assert.is_nil(errorObject)
    assert.equals("当前位置：奥格瑞玛", routeResult.stepLabels[1])
    assert.is_true(string.find(routeResult.stepLabels[2], "银月城", 1, true) ~= nil)
    assert.is_true(string.find(routeResult.stepLabels[2], "传送门", 1, true) ~= nil)
    assert.is_true(string.find(routeResult.stepLabels[#routeResult.stepLabels], "目标位置：银月城", 1, true) ~= nil)
  end)

  it("resolves_current_variant_city_map_to_a_navigable_route_node", function()
    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 110,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 1534,
      knownSpellByID = {},
    })

    assert.is_nil(errorObject)
    assert.equals("当前位置：奥格瑞玛", routeResult.stepLabels[1])
    assert.is_true(string.find(routeResult.stepLabels[2], "银月城", 1, true) ~= nil)
  end)

  it("adds_portal_position_to_waypoint_link_step_labels", function()
    rawset(_G, "CreateVector2D", function(x, y)
      return { x = x, y = y }
    end)
    rawset(_G, "C_Map", {
      GetMapPosFromWorldPos = function(worldMapID, worldPosition, hintUiMapID)
        assert.equals(1, worldMapID)
        assert.equals(85, hintUiMapID)
        assert.same({ x = 10, y = 20 }, worldPosition)
        return 85, { x = 0.41, y = 0.52 }
      end,
    })

    Toolbox.Data.NavigationMapNodes = {
      nodes = {
        [85] = { ID = 85, Name_lang = "奥格瑞玛" },
        [110] = { ID = 110, Name_lang = "银月城" },
      },
    }
    Toolbox.Data.NavigationRouteEdges = {
      schemaVersion = 3,
      nodes = {
        uimap_85 = { Source = "uimap", UiMapID = 85, Name_lang = "奥格瑞玛" },
        uimap_110 = { Source = "uimap", UiMapID = 110, Name_lang = "银月城" },
      },
      edges = {
        {
          from = "uimap_85",
          to = "uimap_110",
          fromUiMapID = 85,
          toUiMapID = 110,
          cost = 30,
          label = "使用奥格瑞玛的传送门前往银月城",
          mode = "WAYPOINT_LINK",
          portalWorldMapID = 1,
          portalWorldX = 10,
          portalWorldY = 20,
        },
      },
    }

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 110,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 85,
      knownSpellByID = {},
    })

    assert.is_true(string.find(routeResult.stepLabels[2], "奥格瑞玛 41.0, 52.0；使用奥格瑞玛的传送门前往银月城", 1, true) ~= nil)
  end)
end)
