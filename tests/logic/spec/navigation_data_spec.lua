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
