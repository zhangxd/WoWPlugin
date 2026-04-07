--[[
  测试 mapID 匹配
]]

function TestMapIDMatch()
  RequestRaidInfo()
  C_Timer.After(0.5, function()
    Toolbox.Chat.PrintAddonMessage("=== 测试 mapID 匹配 ===")

    -- 测试永恒之眼 (journalInstanceID = 756)
    local testJid = 756
    Toolbox.Chat.PrintAddonMessage("测试 journalInstanceID: " .. testJid)

    -- 选择副本并获取所有返回值
    local selectOk = false
    if C_EncounterJournal and C_EncounterJournal.SelectInstance then
      C_EncounterJournal.SelectInstance(testJid)
      selectOk = true
    elseif EJ_SelectInstance then
      EJ_SelectInstance(testJid)
      selectOk = true
    end

    if selectOk then
      local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10
      if C_EncounterJournal and C_EncounterJournal.GetInstanceInfo then
        v1, v2, v3, v4, v5, v6, v7, v8, v9, v10 = C_EncounterJournal.GetInstanceInfo()
      elseif EJ_GetInstanceInfo then
        v1, v2, v3, v4, v5, v6, v7, v8, v9, v10 = EJ_GetInstanceInfo()
      end

      Toolbox.Chat.PrintAddonMessage("  GetInstanceInfo 返回:")
      Toolbox.Chat.PrintAddonMessage("    v1: " .. tostring(v1) .. " type=" .. type(v1))
      Toolbox.Chat.PrintAddonMessage("    v2: " .. tostring(v2) .. " type=" .. type(v2))
      Toolbox.Chat.PrintAddonMessage("    v3: " .. tostring(v3) .. " type=" .. type(v3))
      Toolbox.Chat.PrintAddonMessage("    v4: " .. tostring(v4) .. " type=" .. type(v4))
      Toolbox.Chat.PrintAddonMessage("    v5: " .. tostring(v5) .. " type=" .. type(v5))
      Toolbox.Chat.PrintAddonMessage("    v6: " .. tostring(v6) .. " type=" .. type(v6))
      Toolbox.Chat.PrintAddonMessage("    v7: " .. tostring(v7) .. " type=" .. type(v7))
      Toolbox.Chat.PrintAddonMessage("    v8: " .. tostring(v8) .. " type=" .. type(v8))
      Toolbox.Chat.PrintAddonMessage("    v9: " .. tostring(v9) .. " type=" .. type(v9))
      Toolbox.Chat.PrintAddonMessage("    v10: " .. tostring(v10) .. " type=" .. type(v10))

      -- 检查 GetSavedInstanceInfo
      Toolbox.Chat.PrintAddonMessage("  GetSavedInstanceInfo:")
      local numSaved = GetNumSavedInstances()
      for i = 1, numSaved do
        local savedName, lockoutId, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, v13, savedMapID = GetSavedInstanceInfo(i)
        Toolbox.Chat.PrintAddonMessage("    [" .. i .. "] " .. savedName)
        Toolbox.Chat.PrintAddonMessage("        savedMapID (v14): " .. tostring(savedMapID))
        Toolbox.Chat.PrintAddonMessage("        locked: " .. tostring(locked))
        if v7 then
          Toolbox.Chat.PrintAddonMessage("        v7 匹配? " .. tostring(v7 == savedMapID))
        end
        if v10 then
          Toolbox.Chat.PrintAddonMessage("        v10 匹配? " .. tostring(v10 == savedMapID))
        end
      end
    else
      Toolbox.Chat.PrintAddonMessage("  SelectInstance 失败")
    end

    Toolbox.Chat.PrintAddonMessage("=== 测试完成 ===")
  end)
end

Toolbox.Chat.PrintAddonMessage("输入 /run TestMapIDMatch() 测试 mapID 匹配")
