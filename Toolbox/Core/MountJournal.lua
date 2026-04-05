--[[
  坐骑收藏（领域对外 API）：仅使用 C_MountJournal（12.0+），供副本掉落等模块查询「物品是否为坐骑 / 是否已学会」。
]]

Toolbox.MountJournal = Toolbox.MountJournal or {}
local MJ = C_MountJournal

---@param itemID number
---@return number|nil mountID
function Toolbox.MountJournal.GetMountFromItem(itemID)
  if not itemID or not MJ or not MJ.GetMountFromItem then
    return nil
  end
  local ok, mid = pcall(MJ.GetMountFromItem, itemID)
  if ok and type(mid) == "number" and mid > 0 then
    return mid
  end
  return nil
end

---@param mountID number
---@return boolean|nil isCollected
function Toolbox.MountJournal.IsCollected(mountID)
  if not mountID or not MJ or not MJ.GetMountInfoByID then
    return nil
  end
  -- 第 11 个返回值为 isCollected（见 warcraft.wiki.gg API_C_MountJournal.GetMountInfoByID）
  local ok, _, _, _, _, _, _, _, _, _, isCollected = pcall(MJ.GetMountInfoByID, mountID)
  if ok then
    return isCollected == true
  end
  return nil
end
