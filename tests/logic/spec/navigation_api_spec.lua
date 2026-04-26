describe("Navigation API", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalUnitClass = nil -- 原始 UnitClass 全局
  local originalUnitFactionGroup = nil -- 原始 UnitFactionGroup 全局
  local originalCSpellBook = nil -- 原始 C_SpellBook 全局
  local originalCMap = nil -- 原始 C_Map 全局

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalUnitClass = rawget(_G, "UnitClass")
    originalUnitFactionGroup = rawget(_G, "UnitFactionGroup")
    originalCSpellBook = rawget(_G, "C_SpellBook")
    originalCMap = rawget(_G, "C_Map")
    rawset(_G, "Toolbox", {
      Navigation = {},
      Data = {},
      L = {},
    })

    local moduleChunk = assert(loadfile("Toolbox/Core/API/Navigation.lua")) -- 导航 API chunk
    moduleChunk()
    dofile("Toolbox/Data/NavigationMapNodes.lua")
    dofile("Toolbox/Data/NavigationManualEdges.lua")
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "UnitClass", originalUnitClass)
    rawset(_G, "UnitFactionGroup", originalUnitFactionGroup)
    rawset(_G, "C_SpellBook", originalCSpellBook)
    rawset(_G, "C_Map", originalCMap)
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

  it("plans_map_target_route_for_orgrimmar_and_durotar_with_confirmed_mage_spell", function()
    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 1,
      x = 0.52,
      y = 0.43,
    }, {
      classFile = "MAGE",
      faction = "Horde",
      knownSpellByID = {
        [3567] = true,
      },
    })

    assert.is_nil(errorObject)
    assert.equals(35, routeResult.totalCost)
    assert.same({ "传送：奥格瑞玛", "从奥格瑞玛前往杜隆塔尔目标" }, routeResult.stepLabels)
  end)

  it("plans_orgrimmar_portal_targets_through_orgrimmar_for_horde_mage", function()
    local portalTargetList = { -- 奥格瑞玛传送门目标样例
      { uiMapID = 198, label = "使用奥格瑞玛传送门前往海加尔山" },
      { uiMapID = 203, label = "使用奥格瑞玛传送门前往瓦丝琪尔" },
      { uiMapID = 207, label = "使用奥格瑞玛传送门前往深岩之洲" },
      { uiMapID = 241, label = "使用奥格瑞玛传送门前往暮光高地" },
      { uiMapID = 249, label = "使用奥格瑞玛传送门前往奥丹姆" },
      { uiMapID = 111, label = "使用奥格瑞玛传送门前往沙塔斯城" },
      { uiMapID = 371, label = "使用奥格瑞玛传送门前往翡翠林" },
      { uiMapID = 624, label = "使用奥格瑞玛传送门前往战争之矛" },
      { uiMapID = 630, label = "使用奥格瑞玛传送门前往阿苏纳" },
      { uiMapID = 862, label = "使用奥格瑞玛传送门前往祖达萨" },
      { uiMapID = 1670, label = "使用奥格瑞玛传送门前往奥利波斯" },
      { uiMapID = 2112, label = "使用奥格瑞玛传送门前往瓦德拉肯" },
      { uiMapID = 2339, label = "使用奥格瑞玛传送门前往多恩诺嘉尔" },
    }

    for _, portalTarget in ipairs(portalTargetList) do
      local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
        uiMapID = portalTarget.uiMapID,
        x = 0.63,
        y = 0.24,
      }, {
        classFile = "MAGE",
        faction = "Horde",
        knownSpellByID = {
          [3567] = true,
        },
      })

      assert.is_nil(errorObject)
      assert.same({ "传送：奥格瑞玛", portalTarget.label }, routeResult.stepLabels)
    end
  end)

  it("uses_known_mage_city_teleports_as_independent_hubs", function()
    local cityTargetList = { -- 法师主城传送目标样例
      { uiMapID = 110, spellID = 32272, label = "传送：银月城", arrival = "到达银月城" },
      { uiMapID = 88, spellID = 3566, label = "传送：雷霆崖", arrival = "到达雷霆崖" },
      { uiMapID = 90, spellID = 3563, label = "传送：幽暗城", arrival = "到达幽暗城" },
      { uiMapID = 111, spellID = 35715, label = "传送：沙塔斯城", arrival = "到达沙塔斯城" },
    }

    for _, cityTarget in ipairs(cityTargetList) do
      local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
        uiMapID = cityTarget.uiMapID,
      }, {
        classFile = "MAGE",
        faction = "Horde",
        knownSpellByID = {
          [cityTarget.spellID] = true,
        },
      })

      assert.is_nil(errorObject)
      assert.same({ cityTarget.label, cityTarget.arrival }, routeResult.stepLabels)
    end
  end)

  it("plans_from_current_city_public_portal_network_without_class_spell", function()
    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 198,
      x = 0.63,
      y = 0.24,
    }, {
      classFile = "WARRIOR",
      faction = "Horde",
      currentUiMapID = 110,
      knownSpellByID = {},
    })

    assert.is_nil(errorObject)
    assert.same({
      "当前位置：银月城",
      "使用银月城传送门前往奥格瑞玛",
      "使用奥格瑞玛传送门前往海加尔山",
    }, routeResult.stepLabels)
  end)

  it("plans_non_mage_class_teleports_when_known", function()
    local deathKnightRoute = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 647,
    }, {
      classFile = "DEATHKNIGHT",
      faction = "Horde",
      knownSpellByID = {
        [50977] = true,
      },
    })
    assert.same({ "死亡之门：阿彻鲁斯", "到达阿彻鲁斯：黑锋要塞" }, deathKnightRoute.stepLabels)

    local druidRoute = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 198,
    }, {
      classFile = "DRUID",
      faction = "Horde",
      knownSpellByID = {
        [193753] = true,
      },
    })
    assert.same({
      "梦境行者：梦境林地",
      "从梦境林地进入翡翠梦境之路",
      "通过翡翠梦境之路前往海加尔山",
    }, druidRoute.stepLabels)

    local monkRoute = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 379,
    }, {
      classFile = "MONK",
      faction = "Horde",
      knownSpellByID = {
        [126892] = true,
      },
    })
    assert.same({ "禅宗朝圣：晴日峰", "到达昆莱山" }, monkRoute.stepLabels)
  end)

  it("plans_map_target_route_from_manual_navigation_data", function()
    Toolbox.Data.NavigationMapNodes = {
      nodes = {
        [777] = { ID = 777, Name_lang = "测试目标" },
      },
    }
    Toolbox.Data.NavigationManualEdges = {
      schemaVersion = 1,
      nodes = {
        hub = { ID = "hub", UiMapID = 888, Name_lang = "测试枢纽" },
        slowHub = { ID = "slowHub", UiMapID = 889, Name_lang = "慢速枢纽" },
      },
      targetRules = {
        [777] = {
          targetNode = "target",
          directCost = 300,
          viaNodes = {
            {
              node = "slowHub",
              cost = 80,
              label = "从慢速枢纽前往测试目标",
            },
            {
              node = "hub",
              cost = 40,
              label = "从测试枢纽前往测试目标",
            },
          },
        },
      },
      edges = {
        {
          from = "current",
          to = "hub",
          cost = 12,
          label = "测试传送",
          requirements = {
            classFile = "MAGE",
            spellID = 123,
          },
        },
        {
          from = "current",
          to = "slowHub",
          cost = 6,
          label = "测试慢速传送",
          requirements = {
            classFile = "MAGE",
            spellID = 123,
          },
        },
      },
    }

    local routeResult, errorObject = Toolbox.Navigation.PlanRouteToMapTarget({
      uiMapID = 777,
    }, {
      classFile = "MAGE",
      knownSpellByID = {
        [123] = true,
      },
    })

    assert.is_nil(errorObject)
    assert.equals(52, routeResult.totalCost)
    assert.same({ "测试传送", "从测试枢纽前往测试目标" }, routeResult.stepLabels)
  end)
end)
