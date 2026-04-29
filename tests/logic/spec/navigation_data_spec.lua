describe("Navigation data", function()
  local originalToolbox = nil -- 原始 Toolbox 全局

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    rawset(_G, "Toolbox", {
      Data = {},
    })
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
  end)

  it("exports_navigation_v1_nodes_and_edges_with_minimum_step_fields", function()
    dofile("Toolbox/Data/NavigationMapNodes.lua")
    dofile("Toolbox/Data/NavigationRouteEdges.lua")
    dofile("Toolbox/Data/NavigationAbilityTemplates.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local generatedNodes = Toolbox.Data.NavigationMapNodes.nodes -- 导出的地图节点
    local abilityTemplateData = Toolbox.Data.NavigationAbilityTemplates -- 导出的能力模板
    local nodeExistsById = {} -- 路径图节点存在性
    local checkedNodeCount = 0 -- 已检查节点数
    local checkedEdgeCount = 0 -- 已检查边数
    local checkedAbilityTemplateCount = 0 -- 已检查模板数

    for nodeId, nodeDef in pairs(exportedData.nodes or {}) do
      checkedNodeCount = checkedNodeCount + 1
      nodeExistsById[nodeId] = true
      assert.is_string(nodeDef.Kind)
      assert.is_number(tonumber(nodeDef.UiMapID))
      assert.is_string(nodeDef.Name_lang)
      assert.is_string(nodeDef.WalkClusterKey)
      assert.is_table(generatedNodes[tonumber(nodeDef.UiMapID)])
      if nodeDef.Kind == "taxi" then
        assert.is_number(tonumber(nodeDef.TaxiNodeID))
      end
    end

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      checkedEdgeCount = checkedEdgeCount + 1
      assert.is_true(nodeExistsById[edgeDef.FromNodeID] == true)
      assert.is_true(nodeExistsById[edgeDef.ToNodeID] == true)
      assert.equals(1, tonumber(edgeDef.StepCost))
      assert.is_string(edgeDef.Mode)
      assert.is_table(edgeDef.TraversedUiMapIDs)
      assert.is_table(edgeDef.TraversedUiMapNames)
      assert.equals(#edgeDef.TraversedUiMapIDs, #edgeDef.TraversedUiMapNames)
      if edgeDef.Mode == "taxi" then
        assert.is_number(tonumber(edgeDef.FromTaxiNodeID))
        assert.is_number(tonumber(edgeDef.ToTaxiNodeID))
      end
    end

    for templateID, templateDef in pairs(abilityTemplateData.templates or {}) do
      checkedAbilityTemplateCount = checkedAbilityTemplateCount + 1
      assert.equals(templateID, templateDef.TemplateID)
      assert.is_string(templateDef.Mode)
      assert.is_number(tonumber(templateDef.SpellID))
      assert.is_string(templateDef.TargetRuleKind)
      assert.is_string(templateDef.Label)
      assert.is_true(templateDef.SelfUseOnly == true)
      if templateDef.TargetRuleKind == "fixed_node" then
        assert.is_string(templateDef.ToNodeID)
        assert.is_true(nodeExistsById[templateDef.ToNodeID] == true)
      end
    end

    assert.is_true(checkedNodeCount > 0)
    assert.is_true(checkedEdgeCount > 0)
    assert.is_true(checkedAbilityTemplateCount > 0)
  end)

  it("no_longer_exports_map_link_or_waypoint_link_runtime_edges_for_v1", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    for _, edgeDef in ipairs(exportedData.edges or {}) do
      assert.is_string(edgeDef.Mode)
      assert.is_string(edgeDef.Source)
      assert.not_equals("MAP_LINK", edgeDef.Mode)
      assert.not_equals("WAYPOINT_LINK", edgeDef.Mode)
      assert.not_equals("uimaplink", edgeDef.Source)
      assert.not_equals("waypointedge_resolved", edgeDef.Source)
    end
  end)

  it("exports_runtime_edges_as_a_dense_sequence_for_ipairs_consumers", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local pairCount = 0 -- 使用 pairs 看到的元素数
    local sequenceLength = #exportedData.edges -- Lua 连续数组长度

    for edgeIndex, edgeDef in pairs(exportedData.edges or {}) do
      pairCount = pairCount + 1
      assert.is_number(tonumber(edgeIndex))
      assert.is_table(edgeDef)
    end

    for edgeIndex = 1, sequenceLength do
      assert.is_table(exportedData.edges[edgeIndex])
    end

    assert.equals(pairCount, sequenceLength)
    assert.is_true(sequenceLength > 0)
  end)

  it("does_not_export_areatrigger_runtime_edges_before_a_static_destination_source_exists", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local areatriggerNodeCount = 0 -- 当前导出的 areatrigger 节点数
    local areatriggerEdgeCount = 0 -- 当前导出的 areatrigger 边数

    for _, nodeDef in pairs(exportedData.nodes or {}) do
      if type(nodeDef) == "table" and nodeDef.Kind == "areatrigger" then
        areatriggerNodeCount = areatriggerNodeCount + 1
      end
    end

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if type(edgeDef) == "table" and edgeDef.Mode == "areatrigger" then
        areatriggerEdgeCount = areatriggerEdgeCount + 1
      end
    end

    assert.equals(0, areatriggerNodeCount)
    assert.equals(0, areatriggerEdgeCount)
  end)

  it("exports_silvermoon_travel_nodes_and_edges_needed_for_eastern_kingdoms_routes", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local portal119 = exportedData.nodes["portal_119"] -- 银月城宝珠的提瑞斯法出口
    local portal557 = exportedData.nodes["portal_557"] -- 幽魂之地前往东瘟疫之地的出口
    local portalRoomNodeIDList = { "portal_101", "portal_115", "portal_120", "portal_122", "portal_129", "portal_132", "portal_140", "portal_144", "portal_203", "portal_218", "portal_285" } -- 奥格探路者大厅及同房间落点
    local hasSilvermoonTaxiEdge = false -- 银月城飞行点是否接入公共 taxi 图
    local hasSilvermoonOrgrimmarPortalEdge = false -- 银月城到奥格入口边是否导出
    local hasSilvermoonTirisfalPortalEdge = false -- 银月城宝珠边是否导出
    local hasGhostlandsEplPortalEdge = false -- 幽魂之地到东瘟疫之地边是否导出

    assert.is_table(portal119)
    assert.equals(18, tonumber(portal119.UiMapID))
    assert.equals("uimap_18", portal119.WalkClusterKey)

    assert.is_table(portal557)
    assert.equals(23, tonumber(portal557.UiMapID))
    assert.equals("uimap_23", portal557.WalkClusterKey)

    for _, nodeID in ipairs(portalRoomNodeIDList) do
      local portalRoomNode = exportedData.nodes[nodeID] -- 奥格探路者大厅内应并入奥格主城簇的节点
      assert.is_table(portalRoomNode)
      assert.equals(85, tonumber(portalRoomNode.UiMapID))
      assert.equals("uimap_85", portalRoomNode.WalkClusterKey)
    end

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if edgeDef.FromNodeID == "portal_117" and edgeDef.ToNodeID == "portal_101" then
        hasSilvermoonOrgrimmarPortalEdge = true
      end
      if edgeDef.FromNodeID == "portal_118" and edgeDef.ToNodeID == "portal_119" then
        hasSilvermoonTirisfalPortalEdge = true
      end
      if edgeDef.FromNodeID == "portal_556" and edgeDef.ToNodeID == "portal_557" then
        hasGhostlandsEplPortalEdge = true
      end
      if tonumber(edgeDef.FromTaxiNodeID) == 82 or tonumber(edgeDef.ToTaxiNodeID) == 82 then
        hasSilvermoonTaxiEdge = true
      end
    end

    assert.is_true(hasSilvermoonOrgrimmarPortalEdge)
    assert.is_true(hasSilvermoonTirisfalPortalEdge)
    assert.is_true(hasGhostlandsEplPortalEdge)
    assert.is_true(hasSilvermoonTaxiEdge)
  end)

  it("exports_orgrimmar_to_borean_tundra_zeppelin_as_waypoint_transport", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local orgrimmarZeppelinNode = exportedData.nodes["transport_150"] -- 奥格瑞玛去北风苔原的飞艇起点
    local boreanZeppelinNode = exportedData.nodes["transport_151"] -- 战歌要塞回奥格的飞艇起点
    local zeppelinEdge = nil -- 奥格瑞玛 -> 北风苔原的公共交通边

    assert.is_table(orgrimmarZeppelinNode)
    assert.equals(85, tonumber(orgrimmarZeppelinNode.UiMapID))
    assert.equals("uimap_85", orgrimmarZeppelinNode.WalkClusterKey)

    assert.is_table(boreanZeppelinNode)
    assert.equals(114, tonumber(boreanZeppelinNode.UiMapID))
    assert.equals("uimap_114", boreanZeppelinNode.WalkClusterKey)

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if edgeDef.FromNodeID == "transport_150" and edgeDef.ToNodeID == "transport_151" then
        zeppelinEdge = edgeDef
        break
      end
    end

    assert.is_table(zeppelinEdge)
    assert.equals("waypoint_transport", zeppelinEdge.Source)
    assert.equals("transport", zeppelinEdge.Mode)
    assert.equals("Horde", zeppelinEdge.FactionRequirement)
    assert.is_nil(zeppelinEdge.FromTaxiNodeID)
    assert.is_nil(zeppelinEdge.ToTaxiNodeID)
    assert.is_true(string.find(tostring(zeppelinEdge.Label or ""), "北风苔原", 1, true) ~= nil)
  end)

  it("exports_the_12_0_quelthalas_taxi_chain_needed_for_zulaman", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 统一静态路由图
    local silvermoonTaxi = exportedData.nodes["taxi_3131"] -- 圣光秘殿，银月城
    local eversongTaxi = exportedData.nodes["taxi_3133"] -- 晴风村，永歌森林
    local ghostlandsTaxi = exportedData.nodes["taxi_3134"] -- 塔奎林，永歌森林（12.0）
    local zulamanTaxi = exportedData.nodes["taxi_3106"] -- 石洗营地，祖阿曼
    local hasSilvermoonToEversongEdge = false -- 银月城 -> 永歌森林
    local hasEversongToGhostlandsEdge = false -- 永歌森林 -> 塔奎林
    local hasGhostlandsToZulamanEdge = false -- 塔奎林 -> 祖阿曼

    assert.is_table(silvermoonTaxi)
    assert.equals(2393, tonumber(silvermoonTaxi.UiMapID))
    assert.equals("uimap_2395", silvermoonTaxi.WalkClusterKey)

    assert.is_table(eversongTaxi)
    assert.equals(2395, tonumber(eversongTaxi.UiMapID))
    assert.equals("uimap_2395", eversongTaxi.WalkClusterKey)

    assert.is_table(ghostlandsTaxi)
    assert.equals(2395, tonumber(ghostlandsTaxi.UiMapID))
    assert.equals("uimap_2395", ghostlandsTaxi.WalkClusterKey)

    assert.is_table(zulamanTaxi)
    assert.equals(2437, tonumber(zulamanTaxi.UiMapID))
    assert.equals("uimap_2437", zulamanTaxi.WalkClusterKey)

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if edgeDef.FromNodeID == "taxi_3131" and edgeDef.ToNodeID == "taxi_3133" then
        hasSilvermoonToEversongEdge = true
      end
      if edgeDef.FromNodeID == "taxi_3133" and edgeDef.ToNodeID == "taxi_3134" then
        hasEversongToGhostlandsEdge = true
      end
      if edgeDef.FromNodeID == "taxi_3129" and edgeDef.ToNodeID == "taxi_3106" then
        hasGhostlandsToZulamanEdge = true
      end
    end

    assert.is_true(hasSilvermoonToEversongEdge)
    assert.is_true(hasEversongToGhostlandsEdge)
    assert.is_true(hasGhostlandsToZulamanEdge)
  end)

  it("exports_navigation_map_assignments_without_region_coordinate_fields", function()
    dofile("Toolbox/Data/NavigationMapAssignments.lua")

    local assignmentsData = Toolbox.Data.NavigationMapAssignments -- UiMap 与 MapID 关系数据
    local firstAssignment = nil -- 任取一条导出关系
    for _, assignmentDef in pairs(assignmentsData.assignments or {}) do
      firstAssignment = assignmentDef
      break
    end

    assert.is_table(firstAssignment)
    assert.is_number(tonumber(firstAssignment.UiMapID))
    assert.is_number(tonumber(firstAssignment.MapID))
    assert.is_nil(firstAssignment.UiMinX)
    assert.is_nil(firstAssignment.UiMinY)
    assert.is_nil(firstAssignment.UiMaxX)
    assert.is_nil(firstAssignment.UiMaxY)
    assert.is_nil(firstAssignment.RegionX0)
    assert.is_nil(firstAssignment.RegionY0)
    assert.is_nil(firstAssignment.RegionX1)
    assert.is_nil(firstAssignment.RegionY1)
  end)
end)
