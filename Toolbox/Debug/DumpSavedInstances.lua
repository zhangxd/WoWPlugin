--[[
  转储所有 GetSavedInstanceInfo 的返回值
]]

function DumpAllSavedInstances()
  RequestRaidInfo()
  C_Timer.After(0.5, function()
    local numSaved = GetNumSavedInstances()
    print("=== GetSavedInstanceInfo 完整转储 ===")
    print("共", numSaved, "个已保存副本")

    for i = 1, numSaved do
      local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14 = GetSavedInstanceInfo(i)
      print("\n[" .. i .. "]")
      print("  v1 (name):", v1)
      print("  v2 (id):", v2)
      print("  v3 (reset):", v3)
      print("  v4 (difficulty):", v4)
      print("  v5 (locked):", v5)
      print("  v6 (extended):", v6)
      print("  v7 (instanceIDMostSig):", v7)
      print("  v8 (isRaid):", v8)
      print("  v9 (maxPlayers):", v9)
      print("  v10 (difficultyName):", v10)
      print("  v11 (numEncounters):", v11)
      print("  v12 (encounterProgress):", v12)
      print("  v13:", v13)
      print("  v14:", v14)
    end

    print("\n=== 转储完成 ===")
  end)
end

print("输入 /run DumpAllSavedInstances() 转储所有副本信息")
