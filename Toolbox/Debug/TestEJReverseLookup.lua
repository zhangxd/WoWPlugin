--[[
  测试 EJ API 能否反向查找
]]

function TestEJReverseLookup()
  RequestRaidInfo()
  C_Timer.After(0.5, function()
    print("=== 测试 EJ 反向查找 ===")

    -- 测试已知的副本
    local testCases = {
      { name = "永恒之眼", jid = 756, mapId = 616 },
      { name = "卡拉赞", jid = 745, mapId = 532 },
    }

    for _, tc in ipairs(testCases) do
      print("\n测试:", tc.name)
      print("  已知 journalInstanceID:", tc.jid)
      print("  已知 mapID:", tc.mapId)

      -- 测试 EJ_GetInstanceForMap
      if EJ_GetInstanceForMap then
        local result = EJ_GetInstanceForMap(tc.mapId)
        print("  EJ_GetInstanceForMap(" .. tc.mapId .. ") =", result)
      end

      -- 测试 C_EncounterJournal.GetInstanceForGameMap
      if C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        local result = C_EncounterJournal.GetInstanceForGameMap(tc.mapId)
        print("  C_EncounterJournal.GetInstanceForGameMap(" .. tc.mapId .. ") =", result)
      end

      -- 选择这个副本，看看能获取什么信息
      if Toolbox.EJ.SelectInstance(tc.jid) then
        local name, jid2 = Toolbox.EJ.GetInstanceInfoFlat()
        print("  SelectInstance 后 GetInstanceInfoFlat:", name, jid2)
      end
    end

    -- 检查 GetSavedInstanceInfo 返回的 ID
    print("\n\n=== GetSavedInstanceInfo 的 ID ===")
    local numSaved = GetNumSavedInstances()
    for i = 1, numSaved do
      local name, id = GetSavedInstanceInfo(i)
      print(name, "ID:", id)

      -- 尝试各种位运算提取可能的 mapID
      if Toolbox.Data and Toolbox.Data.InstanceMapIDs then
        for jid, mapId in pairs(Toolbox.Data.InstanceMapIDs) do
          -- 检查 ID 的低位是否包含 mapID
          if bit.band(id, 0xFFFF) == mapId then
            print("  -> 低16位匹配 mapID", mapId, "journalInstanceID", jid)
          end
          if bit.band(id, 0xFFF) == mapId then
            print("  -> 低12位匹配 mapID", mapId, "journalInstanceID", jid)
          end
        end
      end
    end

    print("\n=== 测试完成 ===")
  end)
end

print("输入 /run TestEJReverseLookup() 测试反向查找")
