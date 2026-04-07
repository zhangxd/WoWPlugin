--[[
  解析 GetSavedInstanceInfo 返回的实例 ID
]]

function ParseInstanceID()
  RequestRaidInfo()
  C_Timer.After(0.5, function()
    print("=== 解析实例 ID ===")

    -- 已知的 mapID
    local knownMaps = {
      [616] = { name = "永恒之眼", jid = 756 },
      [532] = { name = "卡拉赞", jid = 745 },
    }

    local numSaved = GetNumSavedInstances()
    for i = 1, numSaved do
      local name, id = GetSavedInstanceInfo(i)
      print("\n" .. name .. " (ID: " .. id .. ")")

      -- 尝试各种位运算提取 mapID
      local low8 = bit.band(id, 0xFF)
      local low10 = bit.band(id, 0x3FF)
      local low12 = bit.band(id, 0xFFF)
      local low16 = bit.band(id, 0xFFFF)

      print("  低8位:", low8, knownMaps[low8] and "✓ " .. knownMaps[low8].name or "")
      print("  低10位:", low10, knownMaps[low10] and "✓ " .. knownMaps[low10].name or "")
      print("  低12位:", low12, knownMaps[low12] and "✓ " .. knownMaps[low12].name or "")
      print("  低16位:", low16, knownMaps[low16] and "✓ " .. knownMaps[low16].name or "")
    end

    print("\n=== 解析完成 ===")
  end)
end

print("输入 /run ParseInstanceID() 解析实例 ID")
