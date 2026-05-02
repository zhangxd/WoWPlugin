describe("Navigation data", function()
  local originalToolbox = nil -- 原始 Toolbox 全局

  -- 按 Kind + Source + SourceID 查找运行时导出的节点，避免依赖旧字符串节点键。
  local function findNodeByOrigin(exportedData, expectedKind, expectedSource, expectedSourceID)
    local matchedNode = nil -- 命中的节点定义
    local matchedCount = 0 -- 命中的节点数量

    for nodeID, nodeDef in pairs(exportedData.nodes or {}) do
      if type(nodeDef) == "table"
        and nodeDef.Kind == expectedKind
        and nodeDef.Source == expectedSource
        and tonumber(nodeDef.SourceID) == tonumber(expectedSourceID) then
        matchedCount = matchedCount + 1
        matchedNode = nodeDef
        assert.equals(tonumber(nodeID), tonumber(nodeDef.NodeID))
      end
    end

    assert.equals(1, matchedCount)
    return matchedNode
  end

  -- 按数字 NodeID 查找运行时边，适配导出节点键迁移后的口径。
  local function findEdgeByNodeIDs(exportedData, fromNodeID, toNodeID)
    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if tonumber(edgeDef.FromNodeID) == tonumber(fromNodeID)
        and tonumber(edgeDef.ToNodeID) == tonumber(toNodeID) then
        return edgeDef
      end
    end

    return nil
  end

  -- 在 localEdges 中查找显式本地接线，避免退回旧 cluster 隐式补边。
  local function findLocalEdgeByNodeIDs(exportedData, fromNodeID, toNodeID)
    for _, edgeDef in pairs(exportedData.localEdges or {}) do
      if tonumber(edgeDef.FromNodeID) == tonumber(fromNodeID)
        and tonumber(edgeDef.ToNodeID) == tonumber(toNodeID) then
        return edgeDef
      end
    end

    return nil
  end

  -- 判断数组里是否包含指定数字节点 ID，避免组件键名变化导致测试耦合到命名。
  local function arrayContainsNumericValue(valueArray, expectedValue)
    for _, currentValue in ipairs(valueArray or {}) do
      if tonumber(currentValue) == tonumber(expectedValue) then
        return true
      end
    end

    return false
  end

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
      nodeExistsById[tonumber(nodeId)] = true
      assert.equals(tonumber(nodeId), tonumber(nodeDef.NodeID))
      assert.is_string(nodeDef.Kind)
      assert.is_number(tonumber(nodeDef.UiMapID))
      assert.is_string(nodeDef.Name_lang)
      assert.is_nil(nodeDef.WalkClusterNodeID)
      assert.is_nil(nodeDef.WalkClusterKey)
      assert.is_table(generatedNodes[tonumber(nodeDef.UiMapID)])
      if nodeDef.Kind == "taxi" then
        assert.is_number(tonumber(nodeDef.TaxiNodeID))
      end
    end

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      checkedEdgeCount = checkedEdgeCount + 1
      assert.is_true(nodeExistsById[tonumber(edgeDef.FromNodeID)] == true)
      assert.is_true(nodeExistsById[tonumber(edgeDef.ToNodeID)] == true)
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
        assert.is_number(tonumber(templateDef.ToNodeID))
        assert.is_true(nodeExistsById[tonumber(templateDef.ToNodeID)] == true)
      end
    end

    assert.is_true(checkedNodeCount > 0)
    assert.is_true(checkedEdgeCount > 0)
    assert.is_true(checkedAbilityTemplateCount > 0)
  end)

  it("exports_the_12_0_silvermoon_mage_templates_to_the_new_silvermoon_anchor", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")
    dofile("Toolbox/Data/NavigationAbilityTemplates.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local abilityTemplateData = Toolbox.Data.NavigationAbilityTemplates -- 导出的能力模板
    local newSilvermoonNode = findNodeByOrigin(exportedData, "map_anchor", "uimap", 2393) -- 12.0 银月城锚点
    local teleportTemplate = abilityTemplateData.templates["spell_1259190"] -- 12.0 银月城传送模板
    local portalTemplate = abilityTemplateData.templates["spell_1259194"] -- 12.0 银月城传送门模板

    assert.is_table(teleportTemplate)
    assert.is_table(portalTemplate)
    assert.equals(tonumber(newSilvermoonNode.NodeID), tonumber(teleportTemplate.ToNodeID))
    assert.equals(tonumber(newSilvermoonNode.NodeID), tonumber(portalTemplate.ToNodeID))
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
    local portal101 = findNodeByOrigin(exportedData, "portal", "portal", 101) -- 奥格探路者大厅落点
    local portal115 = findNodeByOrigin(exportedData, "portal", "portal", 115) -- 奥格至银月城传送门
    local portal117 = findNodeByOrigin(exportedData, "portal", "portal", 117) -- 银月城传送回奥格的入口
    local portal118 = findNodeByOrigin(exportedData, "portal", "portal", 118) -- 银月城前往提瑞斯法的宝珠入口
    local portal119 = findNodeByOrigin(exportedData, "portal", "portal", 119) -- 银月城宝珠的提瑞斯法出口
    local portal120 = findNodeByOrigin(exportedData, "portal", "portal", 120) -- 奥格至沙塔斯传送门
    local portal122 = findNodeByOrigin(exportedData, "portal", "portal", 122) -- 奥格至阿什兰传送门
    local portal129 = findNodeByOrigin(exportedData, "portal", "portal", 129) -- 奥格至阿苏纳传送门
    local portal132 = findNodeByOrigin(exportedData, "portal", "portal", 132) -- 奥格至祖达萨传送门
    local portal140 = findNodeByOrigin(exportedData, "portal", "portal", 140) -- 奥格至翡翠林传送门
    local portal144 = findNodeByOrigin(exportedData, "portal", "portal", 144) -- 奥格至晶歌森林传送门
    local portal203 = findNodeByOrigin(exportedData, "portal", "portal", 203) -- 奥格至时光之穴传送门
    local portal218 = findNodeByOrigin(exportedData, "portal", "portal", 218) -- 奥格至奥利波斯传送门
    local portal285 = findNodeByOrigin(exportedData, "portal", "portal", 285) -- 奥利波斯同房间出口
    local portal556 = findNodeByOrigin(exportedData, "portal", "portal", 556) -- 幽魂之地前往东瘟疫之地的入口
    local portal557 = findNodeByOrigin(exportedData, "portal", "portal", 557) -- 幽魂之地前往东瘟疫之地的出口
    local hasSilvermoonTaxiEdge = false -- 银月城飞行点是否接入公共 taxi 图

    assert.is_table(portal119)
    assert.equals(18, tonumber(portal119.UiMapID))

    assert.is_table(portal557)
    assert.equals(23, tonumber(portal557.UiMapID))

    for _, portalRoomNode in ipairs({
      portal101,
      portal115,
      portal120,
      portal122,
      portal129,
      portal132,
      portal140,
      portal144,
      portal203,
      portal218,
      portal285,
    }) do
      assert.is_table(portalRoomNode)
      assert.equals(85, tonumber(portalRoomNode.UiMapID))
    end

    for _, edgeDef in ipairs(exportedData.edges or {}) do
      if tonumber(edgeDef.FromTaxiNodeID) == 82 or tonumber(edgeDef.ToTaxiNodeID) == 82 then
        hasSilvermoonTaxiEdge = true
      end
    end

    assert.is_table(findEdgeByNodeIDs(exportedData, portal117.NodeID, portal101.NodeID))
    assert.is_table(findEdgeByNodeIDs(exportedData, portal118.NodeID, portal119.NodeID))
    assert.is_table(findEdgeByNodeIDs(exportedData, portal556.NodeID, portal557.NodeID))
    assert.is_true(hasSilvermoonTaxiEdge)
  end)

  it("exports_orgrimmar_to_borean_tundra_zeppelin_as_waypoint_transport", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local orgrimmarZeppelinNode = findNodeByOrigin(exportedData, "transport", "waypoint_transport", 150) -- 奥格瑞玛去北风苔原的飞艇起点
    local boreanZeppelinNode = findNodeByOrigin(exportedData, "transport", "waypoint_transport", 151) -- 战歌要塞回奥格的飞艇起点
    local zeppelinEdge = findEdgeByNodeIDs(exportedData, orgrimmarZeppelinNode.NodeID, boreanZeppelinNode.NodeID) -- 奥格瑞玛 -> 北风苔原的公共交通边

    assert.is_table(orgrimmarZeppelinNode)
    assert.equals(85, tonumber(orgrimmarZeppelinNode.UiMapID))

    assert.is_table(boreanZeppelinNode)
    assert.equals(114, tonumber(boreanZeppelinNode.UiMapID))

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
    local silvermoonTaxi = findNodeByOrigin(exportedData, "taxi", "taxi", 3131) -- 圣光秘殿，银月城
    local eversongTaxi = findNodeByOrigin(exportedData, "taxi", "taxi", 3133) -- 晴风村，永歌森林
    local ghostlandsTaxi = findNodeByOrigin(exportedData, "taxi", "taxi", 3134) -- 塔奎林，永歌森林（12.0）
    local zulamanHubTaxi = findNodeByOrigin(exportedData, "taxi", "taxi", 3129) -- 影盆岗哨，祖阿曼
    local zulamanTaxi = findNodeByOrigin(exportedData, "taxi", "taxi", 3106) -- 石洗营地，祖阿曼
    assert.is_table(silvermoonTaxi)
    assert.equals(2393, tonumber(silvermoonTaxi.UiMapID))

    assert.is_table(eversongTaxi)
    assert.equals(2395, tonumber(eversongTaxi.UiMapID))

    assert.is_table(ghostlandsTaxi)
    assert.equals(2395, tonumber(ghostlandsTaxi.UiMapID))

    assert.is_table(zulamanTaxi)
    assert.equals(2437, tonumber(zulamanTaxi.UiMapID))

    assert.is_table(findEdgeByNodeIDs(exportedData, silvermoonTaxi.NodeID, eversongTaxi.NodeID))
    assert.is_table(findEdgeByNodeIDs(exportedData, eversongTaxi.NodeID, ghostlandsTaxi.NodeID))
    assert.is_table(findEdgeByNodeIDs(exportedData, zulamanHubTaxi.NodeID, zulamanTaxi.NodeID))
  end)

  it("exports_the_orgrimmar_public_portal_arrival_into_a_formal_walk_component_with_explicit_local_edges", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")
    dofile("Toolbox/Data/NavigationWalkComponents.lua")

    local exportedRouteData = Toolbox.Data.NavigationRouteEdges -- 导出的统一路线边数据
    local walkComponentData = Toolbox.Data.NavigationWalkComponents -- 导出的正式步行组件数据
    local silvermoonPortalArrival = findNodeByOrigin(exportedRouteData, "portal", "portal", 116) -- 奥格公共传送门的银月城落点
    local silvermoonMapAnchor = findNodeByOrigin(exportedRouteData, "map_anchor", "uimap", 2393) -- 12.0 银月城锚点
    local arrivalAssignment = walkComponentData.nodeAssignments[tonumber(silvermoonPortalArrival.NodeID)] -- 落点节点归属
    local assignedComponent = nil -- 落点实际归属的正式步行组件
    local localEdge = nil -- 落点到本地锚点的显式步行边

    assert.is_table(arrivalAssignment)
    assert.equals("arrival_connector", arrivalAssignment.Role)
    assert.is_string(arrivalAssignment.ComponentID)
    assignedComponent = walkComponentData.components[arrivalAssignment.ComponentID]

    assert.is_table(assignedComponent)
    assert.equals(tonumber(silvermoonMapAnchor.NodeID), tonumber(assignedComponent.PreferredAnchorNodeID))
    assert.is_true(arrayContainsNumericValue(assignedComponent.MemberNodeIDs, silvermoonPortalArrival.NodeID))
    assert.is_true(arrayContainsNumericValue(assignedComponent.EntryNodeIDs, silvermoonPortalArrival.NodeID))
    localEdge = findLocalEdgeByNodeIDs(walkComponentData, silvermoonPortalArrival.NodeID, silvermoonMapAnchor.NodeID)
    assert.is_table(localEdge)
    assert.equals("walk_local", localEdge.Mode)
    assert.is_table(localEdge.TraversedUiMapIDs)
    assert.is_table(localEdge.TraversedUiMapNames)
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

  it("exports_walk_components_with_component_membership_connector_roles_and_local_edges", function()
    dofile("Toolbox/Data/NavigationWalkComponents.lua")

    local exportedData = Toolbox.Data.NavigationWalkComponents -- 步行组件正式导出数据
    local componentCount = 0 -- 已检查组件数量
    local assignmentCount = 0 -- 已检查归属数量
    local localEdgeCount = 0 -- 已检查本地接线数量
    local proxyCount = 0 -- 已检查代理数量

    assert.is_table(exportedData.components)
    assert.is_table(exportedData.nodeAssignments)
    assert.is_table(exportedData.localEdges)
    assert.is_table(exportedData.displayProxies)

    for componentID, componentDef in pairs(exportedData.components) do
      componentCount = componentCount + 1
      assert.equals(componentID, componentDef.ComponentID)
      assert.is_string(componentDef.DisplayName)
      assert.is_table(componentDef.MemberNodeIDs)
      assert.is_table(componentDef.EntryNodeIDs)
      assert.is_true(#componentDef.MemberNodeIDs > 0)
      assert.is_true(#componentDef.EntryNodeIDs > 0)
      assert.is_number(tonumber(componentDef.PreferredAnchorNodeID))
      assert.is_true(arrayContainsNumericValue(componentDef.MemberNodeIDs, componentDef.PreferredAnchorNodeID))
    end

    for nodeID, assignmentDef in pairs(exportedData.nodeAssignments) do
      assignmentCount = assignmentCount + 1
      local componentDef = exportedData.components[assignmentDef.ComponentID] -- 归属声明引用的正式组件
      local proxyDef = assignmentDef.DisplayProxyNodeID ~= nil and exportedData.displayProxies[tonumber(nodeID)] or nil -- 当前节点的显示代理定义

      assert.equals(tonumber(nodeID), tonumber(assignmentDef.NodeID))
      assert.is_string(assignmentDef.ComponentID)
      assert.is_string(assignmentDef.Role)
      assert.is_true(assignmentDef.Role == "anchor"
        or assignmentDef.Role == "landmark"
        or assignmentDef.Role == "departure_connector"
        or assignmentDef.Role == "arrival_connector"
        or assignmentDef.Role == "technical")
      assert.is_boolean(assignmentDef.HiddenInSemanticChain)
      assert.is_table(componentDef)
      assert.is_true(arrayContainsNumericValue(componentDef.MemberNodeIDs, assignmentDef.NodeID))
      if assignmentDef.DisplayProxyNodeID ~= nil then
        assert.is_number(tonumber(assignmentDef.DisplayProxyNodeID))
        assert.is_table(proxyDef)
        assert.equals(assignmentDef.ComponentID, proxyDef.ComponentID)
        assert.equals(tonumber(assignmentDef.DisplayProxyNodeID), tonumber(proxyDef.DisplayProxyNodeID))
      end
      if assignmentDef.VisibleName ~= nil then
        assert.is_string(assignmentDef.VisibleName)
      end
    end

    for proxyNodeID, proxyDef in pairs(exportedData.displayProxies) do
      proxyCount = proxyCount + 1
      assert.equals(tonumber(proxyNodeID), tonumber(proxyDef.NodeID))
      assert.is_string(proxyDef.ComponentID)
      assert.is_number(tonumber(proxyDef.DisplayProxyNodeID))
      assert.is_string(proxyDef.VisibleName)
      assert.is_table(exportedData.components[proxyDef.ComponentID])
    end

    for localEdgeID, localEdgeDef in pairs(exportedData.localEdges) do
      localEdgeCount = localEdgeCount + 1
      assert.equals(localEdgeID, localEdgeDef.LocalEdgeID)
      assert.is_string(localEdgeDef.ComponentID)
      assert.is_number(tonumber(localEdgeDef.FromNodeID))
      assert.is_number(tonumber(localEdgeDef.ToNodeID))
      assert.equals("walk_local", localEdgeDef.Mode)
      assert.equals(1, tonumber(localEdgeDef.StepCost))
      assert.is_table(localEdgeDef.TraversedUiMapIDs)
      assert.is_table(localEdgeDef.TraversedUiMapNames)
      assert.is_table(exportedData.components[localEdgeDef.ComponentID])
    end

    assert.is_true(componentCount > 0)
    assert.is_true(assignmentCount > 0)
    assert.is_true(localEdgeCount > 0)
    assert.is_true(proxyCount > 0)
  end)
end)
