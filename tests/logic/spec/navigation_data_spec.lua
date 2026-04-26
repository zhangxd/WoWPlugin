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

  it("manual_edges_reference_existing_nodes", function()
    dofile("Toolbox/Data/NavigationMapNodes.lua")
    dofile("Toolbox/Data/NavigationManualEdges.lua")

    local manualData = Toolbox.Data.NavigationManualEdges -- 手工路径边数据
    local generatedNodes = Toolbox.Data.NavigationMapNodes.nodes -- 导出的地图节点
    local nodeExistsById = {
      current = true,
      target = true,
    } -- 路径图运行时虚拟节点

    for nodeId, nodeDef in pairs(manualData.nodes or {}) do
      nodeExistsById[nodeId] = true
      local uiMapID = tonumber(nodeDef.UiMapID) -- 手工节点对应地图 ID
      if uiMapID then
        assert.is_table(generatedNodes[uiMapID])
      end
    end

    for _, edge in ipairs(manualData.edges or {}) do
      assert.is_true(nodeExistsById[edge.from] == true)
      assert.is_true(nodeExistsById[edge.to] == true)
      assert.is_number(edge.cost)
      assert.is_true(edge.cost >= 0)
      assert.is_string(edge.label)
    end

    for uiMapID, targetRule in pairs(manualData.targetRules or {}) do
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
end)
