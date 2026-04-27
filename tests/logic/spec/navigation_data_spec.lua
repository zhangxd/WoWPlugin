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

  it("exported_navigation_edges_reference_existing_nodes", function()
    dofile("Toolbox/Data/NavigationMapNodes.lua")
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    local generatedNodes = Toolbox.Data.NavigationMapNodes.nodes -- 导出的地图节点
    local nodeExistsById = {
      current = true,
      target = true,
    } -- 路径图运行时虚拟节点

    for nodeId, nodeDef in pairs(exportedData.nodes or {}) do
      nodeExistsById[nodeId] = true
      local uiMapID = tonumber(nodeDef.UiMapID) -- 导出节点对应地图 ID
      if uiMapID and uiMapID > 0 then
        assert.is_table(generatedNodes[uiMapID])
      end
    end

    for _, edge in ipairs(exportedData.edges or {}) do
      assert.is_true(nodeExistsById[edge.from] == true)
      assert.is_true(nodeExistsById[edge.to] == true)
      assert.is_number(edge.cost)
      assert.is_true(edge.cost >= 0)
      assert.is_string(edge.label)
    end

    for uiMapID, targetRule in pairs(exportedData.targetRules or {}) do
      assert.is_table(generatedNodes[uiMapID])
      local targetNodeId = targetRule.targetNode or "target" -- 目标节点 ID，未声明时使用运行时默认目标
      assert.is_true(nodeExistsById[targetNodeId] == true)
      if targetRule.viaNode then
        assert.is_true(nodeExistsById[targetRule.viaNode] == true)
      end
      for _, viaNodeDef in ipairs(targetRule.viaNodes or {}) do
        assert.is_true(nodeExistsById[viaNodeDef.node] == true)
        assert.is_number(viaNodeDef.cost)
        assert.is_true(viaNodeDef.cost >= 0)
        assert.is_string(viaNodeDef.label)
      end
    end
  end)

  it("does_not_export_coordinate_derived_map_connection_edges", function()
    dofile("Toolbox/Data/NavigationRouteEdges.lua")

    local exportedData = Toolbox.Data.NavigationRouteEdges -- 契约导出的统一路径边数据
    for _, nodeDef in pairs(exportedData.nodes or {}) do
      assert.equals("uimap", nodeDef.Source)
    end

    for _, edge in ipairs(exportedData.edges or {}) do
      assert.not_equals("MAP_REGION", edge.mode)
      assert.not_equals("MAP_TRACE", edge.mode)
      assert.not_equals("uimapassignment_region", edge.source)
      assert.not_equals("taxipathnode_trace", edge.source)
      assert.not_equals("waypoint_safeloc", edge.source)
      assert.not_equals("WAYPOINT_ACCESS", edge.mode)

      if edge.mode == "MAP_LINK" then
        assert.equals("uimaplink", edge.source)
      elseif edge.mode == "WAYPOINT_LINK" then
        assert.equals("waypointedge_resolved", edge.source)
      else
        error("unexpected edge mode: " .. tostring(edge.mode))
      end
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
