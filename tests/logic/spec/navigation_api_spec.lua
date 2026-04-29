describe("Navigation API", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalUnitClass = nil -- 原始 UnitClass 全局
  local originalUnitFactionGroup = nil -- 原始 UnitFactionGroup 全局
  local originalCSpellBook = nil -- 原始 C_SpellBook 全局
  local originalCMap = nil -- 原始 C_Map 全局
  local originalCTaxiMap = nil -- 原始 C_TaxiMap 全局
  local originalGetBindLocation = nil -- 原始 GetBindLocation 全局

  local function setNavigationData(routeNodes, routeEdges, mapNodes, abilityTemplates)
    Toolbox.Data.NavigationRouteEdges = {
      nodes = routeNodes or {},
      edges = routeEdges or {},
    }
    Toolbox.Data.NavigationMapNodes = {
      nodes = mapNodes or {},
    }
    Toolbox.Data.NavigationAbilityTemplates = {
      templates = abilityTemplates or {},
    }
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalUnitClass = rawget(_G, "UnitClass")
    originalUnitFactionGroup = rawget(_G, "UnitFactionGroup")
    originalCSpellBook = rawget(_G, "C_SpellBook")
    originalCMap = rawget(_G, "C_Map")
    originalCTaxiMap = rawget(_G, "C_TaxiMap")
    originalGetBindLocation = rawget(_G, "GetBindLocation")
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
    rawset(_G, "C_TaxiMap", originalCTaxiMap)
    rawset(_G, "GetBindLocation", originalGetBindLocation)
  end)

  it("prefers_the_fewest_completed_route_steps_even_when_the_old_cost_is_higher", function()
    local routeGraph = { -- 测试路径图
      nodes = {
        start = { id = "start", name = "起点" },
        relay = { id = "relay", name = "中转点" },
        target = { id = "target", name = "目标" },
      },
      edges = {
        {
          from = "start",
          to = "target",
          cost = 99,
          stepCost = 1,
          mode = "class_teleport",
          label = "直接传送",
          traversedUiMapIDs = { 777 },
          traversedUiMapNames = { "目标地图" },
        },
        {
          from = "start",
          to = "relay",
          cost = 1,
          stepCost = 1,
          mode = "walk_local",
          label = "先走到中转点",
          traversedUiMapIDs = { 888 },
          traversedUiMapNames = { "起点地图" },
        },
        {
          from = "relay",
          to = "target",
          cost = 1,
          stepCost = 1,
          mode = "taxi",
          label = "再坐飞行点",
          traversedUiMapIDs = { 888, 777 },
          traversedUiMapNames = { "起点地图", "目标地图" },
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.FindShortestPath(routeGraph, "start", "target")

    assert.is_nil(errorObject)
    assert.equals(1, routeResult.totalSteps)
    assert.equals(1, #routeResult.segments)
    assert.equals("class_teleport", routeResult.segments[1].mode)
    assert.equals("直接传送", routeResult.segments[1].label)
  end)

  it("breaks_step_count_ties_by_preferring_fewer_walk_segments", function()
    local routeGraph = { -- 平局路径图
      nodes = {
        start = { id = "start", name = "起点" },
        walkRelay = { id = "walkRelay", name = "步行中转" },
        taxiRelay = { id = "taxiRelay", name = "飞行中转" },
        target = { id = "target", name = "目标" },
      },
      edges = {
        {
          from = "start",
          to = "walkRelay",
          cost = 1,
          stepCost = 1,
          mode = "walk_local",
          label = "先步行",
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          from = "walkRelay",
          to = "target",
          cost = 1,
          stepCost = 1,
          mode = "taxi",
          label = "再飞行",
          traversedUiMapIDs = { 85, 114 },
          traversedUiMapNames = { "奥格瑞玛", "北风苔原" },
        },
        {
          from = "start",
          to = "taxiRelay",
          cost = 20,
          stepCost = 1,
          mode = "taxi",
          label = "直接飞往中转站",
          traversedUiMapIDs = { 85, 12 },
          traversedUiMapNames = { "奥格瑞玛", "卡利姆多" },
        },
        {
          from = "taxiRelay",
          to = "target",
          cost = 20,
          stepCost = 1,
          mode = "taxi",
          label = "继续飞往目标",
          traversedUiMapIDs = { 12, 114 },
          traversedUiMapNames = { "卡利姆多", "北风苔原" },
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.FindShortestPath(routeGraph, "start", "target")

    assert.is_nil(errorObject)
    assert.equals(2, routeResult.totalSteps)
    assert.equals(2, #routeResult.segments)
    assert.equals("taxi", routeResult.segments[1].mode)
    assert.equals("taxi", routeResult.segments[2].mode)
  end)

  it("compresses_consecutive_walk_segments_in_the_output", function()
    local routeGraph = { -- 连续步行路径图
      nodes = {
        start = { id = "start", name = "起点" },
        walkA = { id = "walkA", name = "步行点 A" },
        walkB = { id = "walkB", name = "步行点 B" },
        target = { id = "target", name = "目标" },
      },
      edges = {
        {
          from = "start",
          to = "walkA",
          cost = 1,
          stepCost = 1,
          mode = "walk_local",
          label = "步行到 A",
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          from = "walkA",
          to = "walkB",
          cost = 1,
          stepCost = 1,
          mode = "walk_local",
          label = "步行到 B",
          traversedUiMapIDs = { 85 },
          traversedUiMapNames = { "奥格瑞玛" },
        },
        {
          from = "walkB",
          to = "target",
          cost = 1,
          stepCost = 1,
          mode = "class_portal",
          label = "开启传送门抵达目标",
          traversedUiMapIDs = { 85, 110 },
          traversedUiMapNames = { "奥格瑞玛", "银月城" },
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.FindShortestPath(routeGraph, "start", "target")

    assert.is_nil(errorObject)
    assert.equals(2, routeResult.totalSteps)
    assert.equals(2, #routeResult.segments)
    assert.equals("walk_local", routeResult.segments[1].mode)
    assert.equals("class_portal", routeResult.segments[2].mode)
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
        { from = "start", to = "orgrimmar", stepCost = 1, mode = "class_teleport", requirements = { classFile = "MAGE", spellID = 3567 } },
        { from = "start", to = "stormwind", stepCost = 1, mode = "class_portal", requirements = { faction = "Alliance" } },
        { from = "start", to = "unknownPortal", stepCost = 1, mode = "class_portal", requirements = { spellID = 999999 } },
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

  it("builds_current_character_availability_from_runtime_spellbook_taxi_map_and_bind_location", function()
    local checkedSpellIDList = {} -- 被查询的技能 ID
    setNavigationData({
      taxi_start = { NodeID = "taxi_start", Kind = "taxi", UiMapID = 1, Name_lang = "起点飞行点", WalkClusterKey = "uimap_1", TaxiNodeID = 100 },
      taxi_hidden = { NodeID = "taxi_hidden", Kind = "taxi", UiMapID = 1, Name_lang = "未开飞行点", WalkClusterKey = "uimap_1", TaxiNodeID = 101 },
      taxi_target = { NodeID = "taxi_target", Kind = "taxi", UiMapID = 2, Name_lang = "目标飞行点", WalkClusterKey = "uimap_2", TaxiNodeID = 200 },
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", UiMapID = 1, Name_lang = "起点地图", WalkClusterKey = "uimap_1" },
      uimap_2 = { NodeID = "uimap_2", Kind = "map_anchor", UiMapID = 2, Name_lang = "绑定地图", WalkClusterKey = "uimap_2" },
    }, {}, {
      [1] = { Name_lang = "起点地图", MapType = 3, ParentUiMapID = 0 },
      [2] = { Name_lang = "绑定地图", MapType = 3, ParentUiMapID = 0 },
    }, {})
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
    rawset(_G, "C_TaxiMap", {
      GetTaxiNodesForMap = function(uiMapID)
        if uiMapID == 1 then
          return {
            { nodeID = 100, isUndiscovered = false },
            { nodeID = 101, isUndiscovered = true },
          }
        end
        if uiMapID == 2 then
          return {
            { nodeID = 200, isUndiscovered = false },
          }
        end
        return {}
      end,
    })
    rawset(_G, "GetBindLocation", function()
      return "绑定地图"
    end)

    local availabilityContext = Toolbox.Navigation.BuildCurrentCharacterAvailability({ 3567, 999999 })

    assert.equals("MAGE", availabilityContext.classFile)
    assert.equals("Horde", availabilityContext.faction)
    assert.equals(110, availabilityContext.currentUiMapID)
    assert.is_true(availabilityContext.knownSpellByID[3567])
    assert.is_nil(availabilityContext.knownSpellByID[999999])
    assert.is_true(availabilityContext.knownTaxiNodeByID[100])
    assert.is_nil(availabilityContext.knownTaxiNodeByID[101])
    assert.is_true(availabilityContext.knownTaxiNodeByID[200])
    assert.equals("uimap_2", availabilityContext.hearthBindNodeID)
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

  it("collects_required_spell_ids_from_route_data_and_navigation_ability_templates", function()
    Toolbox.Data.NavigationAbilityTemplates = {
      templates = {
        hearth = { SpellID = 8690 },
        teleport = { SpellID = 3567 },
        duplicate = { SpellID = 3567 },
      },
    }
    local spellIDList = Toolbox.Navigation.GetRequiredSpellIDList({
      edges = {
        { requirements = { spellID = 3567 } },
        { requirements = { spellID = 3567 } },
        { requirements = { spellID = 50977 } },
        { requirements = { classFile = "MAGE" } },
      },
    })

    assert.same({ 3567, 50977, 8690 }, spellIDList)
  end)

  it("expands_hearthstone_template_only_when_spell_and_bind_node_are_available", function()
    setNavigationData({
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", Source = "uimap", UiMapID = 1, Name_lang = "起点地图", WalkClusterKey = "uimap_1" },
      uimap_2 = { NodeID = "uimap_2", Kind = "map_anchor", Source = "uimap", UiMapID = 2, Name_lang = "炉石绑定地", WalkClusterKey = "uimap_2" },
    }, {}, {
      [1] = { Name_lang = "起点地图", MapType = 3, ParentUiMapID = 0 },
      [2] = { Name_lang = "炉石绑定地", MapType = 3, ParentUiMapID = 0 },
    }, {
      hearth = {
        TemplateID = "hearth",
        Mode = "hearthstone",
        SpellID = 8690,
        TargetRuleKind = "hearth_bind",
        Label = "炉石",
        SelfUseOnly = true,
      },
    })

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      currentX = 0.20,
      currentY = 0.20,
      knownSpellByID = {
        [8690] = true,
      },
      knownTaxiNodeByID = {},
      hearthBindNodeID = "uimap_2",
    })

    assert.is_table(routeResult)
    assert.equals(2, routeResult.totalSteps)
    assert.equals("hearthstone", routeResult.segments[1].mode)

    local noSpellRoute, noSpellError = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {},
      knownTaxiNodeByID = {},
      hearthBindNodeID = "uimap_2",
    })

    assert.is_nil(noSpellRoute)
    assert.equals("NAVIGATION_ERR_NO_ROUTE", noSpellError.code)

    local noBindRoute, noBindError = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {
        [8690] = true,
      },
      knownTaxiNodeByID = {},
    })

    assert.is_nil(noBindRoute)
    assert.equals("NAVIGATION_ERR_NO_ROUTE", noBindError.code)
  end)

  it("expands_class_templates_only_when_class_faction_and_spell_match", function()
    setNavigationData({
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", Source = "uimap", UiMapID = 1, Name_lang = "起点地图", WalkClusterKey = "uimap_1" },
      uimap_85 = { NodeID = "uimap_85", Kind = "map_anchor", Source = "uimap", UiMapID = 85, Name_lang = "奥格瑞玛", WalkClusterKey = "uimap_85" },
    }, {}, {
      [1] = { Name_lang = "起点地图", MapType = 3, ParentUiMapID = 0 },
      [85] = { Name_lang = "奥格瑞玛", MapType = 3, ParentUiMapID = 0 },
    }, {
      mageTeleport = {
        TemplateID = "mage_teleport_orgrimmar",
        Mode = "class_teleport",
        SpellID = 3567,
        ClassFile = "MAGE",
        FactionGroup = "Horde",
        TargetRuleKind = "fixed_node",
        ToNodeID = "uimap_85",
        Label = "传送：奥格瑞玛",
        SelfUseOnly = true,
      },
    })

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 85,
      x = 0.41,
      y = 0.59,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {
        [3567] = true,
      },
      knownTaxiNodeByID = {},
    })

    assert.is_table(routeResult)
    assert.equals("class_teleport", routeResult.segments[1].mode)

    local wrongClassRoute, wrongClassError = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 85,
      x = 0.41,
      y = 0.59,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {
        [3567] = true,
      },
      knownTaxiNodeByID = {},
    })

    assert.is_nil(wrongClassRoute)
    assert.equals("NAVIGATION_ERR_NO_ROUTE", wrongClassError.code)
  end)

  it("allows_taxi_routes_only_when_both_endpoint_nodes_are_known", function()
    setNavigationData({
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", Source = "uimap", UiMapID = 1, Name_lang = "起点地图", WalkClusterKey = "uimap_1" },
      uimap_2 = { NodeID = "uimap_2", Kind = "map_anchor", Source = "uimap", UiMapID = 2, Name_lang = "目标地图", WalkClusterKey = "uimap_2" },
      taxi_100 = { NodeID = "taxi_100", Kind = "taxi", Source = "taxi", UiMapID = 1, Name_lang = "起点飞行点", WalkClusterKey = "uimap_1", TaxiNodeID = 100 },
      taxi_200 = { NodeID = "taxi_200", Kind = "taxi", Source = "taxi", UiMapID = 2, Name_lang = "目标飞行点", WalkClusterKey = "uimap_2", TaxiNodeID = 200 },
    }, {
      {
        ID = 9001,
        FromNodeID = "taxi_100",
        ToNodeID = "taxi_200",
        FromTaxiNodeID = 100,
        ToTaxiNodeID = 200,
        FromUiMapID = 1,
        ToUiMapID = 2,
        StepCost = 1,
        Mode = "taxi",
        Label = "起点飞到目标",
        TraversedUiMapIDs = { 1, 2 },
        TraversedUiMapNames = { "起点地图", "目标地图" },
      },
    }, {
      [1] = { Name_lang = "起点地图", MapType = 3, ParentUiMapID = 0 },
      [2] = { Name_lang = "目标地图", MapType = 3, ParentUiMapID = 0 },
    }, {})

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.55,
      y = 0.44,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      currentX = 0.20,
      currentY = 0.20,
      knownSpellByID = {},
      knownTaxiNodeByID = {
        [100] = true,
        [200] = true,
      },
    })

    assert.is_table(routeResult)
    assert.equals(3, routeResult.totalSteps)
    assert.equals("taxi", routeResult.segments[2].mode)

    local noTaxiRoute, noTaxiError = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.55,
      y = 0.44,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {},
      knownTaxiNodeByID = {
        [100] = true,
      },
    })

    assert.is_nil(noTaxiRoute)
    assert.equals("NAVIGATION_ERR_NO_ROUTE", noTaxiError.code)
  end)

  it("routes_transport_edges_when_both_endpoint_nodes_are_known", function()
    setNavigationData({
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", Source = "uimap", UiMapID = 1, Name_lang = "起点地图", WalkClusterKey = "uimap_1" },
      uimap_2 = { NodeID = "uimap_2", Kind = "map_anchor", Source = "uimap", UiMapID = 2, Name_lang = "目标地图", WalkClusterKey = "uimap_2" },
      taxi_35 = { NodeID = "taxi_35", Kind = "taxi", Source = "taxi", UiMapID = 1, Name_lang = "交通工具，起点", WalkClusterKey = "uimap_1", TaxiNodeID = 35 },
      taxi_90 = { NodeID = "taxi_90", Kind = "taxi", Source = "taxi", UiMapID = 2, Name_lang = "交通工具，目标", WalkClusterKey = "uimap_2", TaxiNodeID = 90 },
    }, {
      {
        ID = 9002,
        FromNodeID = "taxi_35",
        ToNodeID = "taxi_90",
        FromTaxiNodeID = 35,
        ToTaxiNodeID = 90,
        FromUiMapID = 1,
        ToUiMapID = 2,
        StepCost = 1,
        Mode = "transport",
        Label = "乘坐交通工具前往目标",
        TraversedUiMapIDs = { 1, 2 },
        TraversedUiMapNames = { "起点地图", "目标地图" },
      },
    }, {
      [1] = { Name_lang = "起点地图", MapType = 3, ParentUiMapID = 0 },
      [2] = { Name_lang = "目标地图", MapType = 3, ParentUiMapID = 0 },
    }, {})

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.55,
      y = 0.44,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      currentX = 0.20,
      currentY = 0.20,
      knownSpellByID = {},
      knownTaxiNodeByID = {
        [35] = true,
        [90] = true,
      },
    })

    assert.is_table(routeResult)
    assert.equals(3, routeResult.totalSteps)
    assert.equals("transport", routeResult.segments[2].mode)
    assert.equals("交通工具，目标", routeResult.segments[2].label)

    local noNodeRoute, noNodeError = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 2,
      x = 0.55,
      y = 0.44,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      currentUiMapID = 1,
      knownSpellByID = {},
      knownTaxiNodeByID = {
        [35] = true,
      },
    })

    assert.is_nil(noNodeRoute)
    assert.equals("NAVIGATION_ERR_NO_ROUTE", noNodeError.code)
  end)

  it("bridges_same_walk_cluster_nodes_with_a_single_compressed_walk_segment", function()
    setNavigationData({
      uimap_18 = { NodeID = "uimap_18", Kind = "map_anchor", Source = "uimap", UiMapID = 18, Name_lang = "提瑞斯法林地", WalkClusterKey = "uimap_18" },
      uimap_90 = { NodeID = "uimap_90", Kind = "map_anchor", Source = "uimap", UiMapID = 90, Name_lang = "幽暗城", WalkClusterKey = "uimap_18" },
    }, {}, {
      [18] = { Name_lang = "提瑞斯法林地", MapType = 3, ParentUiMapID = 0 },
      [90] = { Name_lang = "幽暗城", MapType = 3, ParentUiMapID = 18 },
    }, {})

    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 18,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "PRIEST",
      faction = "Horde",
      currentUiMapID = 90,
      currentX = 0.20,
      currentY = 0.20,
      knownSpellByID = {},
      knownTaxiNodeByID = {},
    })

    assert.is_nil(errorObject)
    assert.is_table(routeResult)
    assert.equals(1, routeResult.totalSteps)
    assert.equals(1, #routeResult.segments)
    assert.equals("walk_local", routeResult.segments[1].mode)
  end)

  it("allows_public_portal_edges_for_all_characters_regardless_of_taxi_nodes", function()
    setNavigationData({
      uimap_1 = { NodeID = "uimap_1", Kind = "map_anchor", Source = "uimap", UiMapID = 1, Name_lang = "暴风城", WalkClusterKey = "uimap_1" },
      uimap_12 = { NodeID = "uimap_12", Kind = "map_anchor", Source = "uimap", UiMapID = 12, Name_lang = "卡利姆多", WalkClusterKey = "uimap_12" },
      portal_100 = { NodeID = "portal_100", Kind = "portal", Source = "portal", UiMapID = 1, Name_lang = "使用巫师圣殿的传送门前往海加尔山", WalkClusterKey = "uimap_1" },
      portal_200 = { NodeID = "portal_200", Kind = "portal", Source = "portal", UiMapID = 12, Name_lang = "海加尔山", WalkClusterKey = "uimap_12" },
    }, {
      {
        ID = 0,
        FromNodeID = "portal_100",
        ToNodeID = "portal_200",
        FromUiMapID = 1,
        ToUiMapID = 12,
        StepCost = 1,
        Mode = "public_portal",
        Label = "使用巫师圣殿的传送门前往海加尔山→海加尔山",
        TraversedUiMapIDs = { 1, 12 },
        TraversedUiMapNames = { "暴风城", "卡利姆多" },
      },
    }, {
      [1] = { Name_lang = "暴风城", MapType = 3, ParentUiMapID = 0 },
      [12] = { Name_lang = "卡利姆多", MapType = 3, ParentUiMapID = 0 },
    }, {})

    local routeResult = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 12,
      x = 0.50,
      y = 0.50,
    }, {
      classFile = "WARRIOR",
      faction = "Alliance",
      currentUiMapID = 1,
      currentX = 0.20,
      currentY = 0.20,
      knownSpellByID = {},
      knownTaxiNodeByID = {},
    })

    assert.is_table(routeResult)
    assert.is_nil(routeResult.errorObject)
    assert.equals("public_portal", routeResult.segments[2].mode)
    assert.equals("海加尔山", routeResult.segments[2].toName)
  end)

  it("filters_public_portal_edges_by_faction_requirement", function()
    local routeGraph = {
      nodes = {
        start = { id = "start", name = "起点" },
        alliancePortal = { id = "alliancePortal", name = "联盟传送门出口" },
        hordePortal = { id = "hordePortal", name = "部落传送门出口" },
      },
      edges = {
        {
          from = "start",
          to = "alliancePortal",
          stepCost = 1,
          mode = "public_portal",
          label = "联盟专属传送门",
          FactionRequirement = "Alliance",
          traversedUiMapIDs = { 1, 2 },
          traversedUiMapNames = { "暴风城", "铁炉堡" },
        },
        {
          from = "start",
          to = "hordePortal",
          stepCost = 1,
          mode = "public_portal",
          label = "部落专属传送门",
          FactionRequirement = "Horde",
          traversedUiMapIDs = { 1, 3 },
          traversedUiMapNames = { "暴风城", "奥格瑞玛" },
        },
      },
    }

    local allianceGraph = Toolbox.Navigation.FilterRouteGraph(routeGraph, {
      faction = "Alliance",
    })

    assert.equals(1, #allianceGraph.edges)
    assert.equals("alliancePortal", allianceGraph.edges[1].to)

    local hordeGraph = Toolbox.Navigation.FilterRouteGraph(routeGraph, {
      faction = "Horde",
    })

    assert.equals(1, #hordeGraph.edges)
    assert.equals("hordePortal", hordeGraph.edges[1].to)
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
end)
