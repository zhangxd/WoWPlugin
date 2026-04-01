--[[
  副本锁定数据门面（12.0+）。
  暴雪仍将角色锁定列表暴露为 GetNumSavedInstances / GetSavedInstanceInfo / GetSavedInstanceEncounterInfo；
  至暗之夜暂无替代用的 C_Lockouts 公开表，故集中封装于此，便于日后若 API 迁移时单点替换。
  返回值顺序以 warcraft.wiki.gg API_GetSavedInstanceInfo 为准。
]]

Toolbox.Lockouts = Toolbox.Lockouts or {}

---@return number
function Toolbox.Lockouts.GetNumSavedInstances()
  if GetNumSavedInstances then
    return GetNumSavedInstances() or 0
  end
  return 0
end

--[[
  @return name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid,
          maxPlayers, difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
]]
function Toolbox.Lockouts.GetSavedInstanceInfo(index)
  if not GetSavedInstanceInfo then
    return nil
  end
  return GetSavedInstanceInfo(index)
end

--[[
  @return bossName, fileDataID, isKilled, unknown4
]]
function Toolbox.Lockouts.GetSavedInstanceEncounterInfo(instanceIndex, encounterIndex)
  if not GetSavedInstanceEncounterInfo then
    return nil
  end
  return GetSavedInstanceEncounterInfo(instanceIndex, encounterIndex)
end
