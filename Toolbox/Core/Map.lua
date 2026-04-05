--[[
  世界地图（领域对外 API）：优先 C_Map.OpenWorldMap（现代客户端），避免直接依赖可能变更的全局 OpenWorldMap。
]]

Toolbox.Map = Toolbox.Map or {}

---@param uiMapID number|nil
function Toolbox.Map.OpenWorldMap(uiMapID)
  if not uiMapID or type(uiMapID) ~= "number" then
    return false
  end
  if C_Map and C_Map.OpenWorldMap then
    local ok = pcall(C_Map.OpenWorldMap, uiMapID)
    return ok
  end
  if OpenWorldMap then
    OpenWorldMap(uiMapID)
    return true
  end
  return false
end
