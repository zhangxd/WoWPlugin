--[[
  物品信息（领域对外 API）：展示用同步信息仍以数字 itemID + GetItemInfo 为主（12.0 仍可用）；
  若未来暴雪收紧全局 API，可改为 Item:CreateFromItemID + ContinueOnItemLoad 异步加载。
]]

Toolbox.Item = Toolbox.Item or {}

---@param itemID number
---@return string|nil itemName
---@return string|nil itemLink
function Toolbox.Item.GetItemNameAndLink(itemID)
  if not itemID then
    return nil, nil
  end
  if GetItemInfo then
    local name, link = GetItemInfo(itemID)
    return name, link
  end
  return nil, nil
end

--- 为 GameTooltip 设置物品（用于掉落行悬停）。
function Toolbox.Item.SetTooltipItemByID(tooltip, itemID)
  if not tooltip or not itemID then
    return
  end
  if tooltip.SetItemByID then
    tooltip:SetItemByID(itemID)
  elseif GameTooltip_ShowCompareItem then
    -- 兜底：部分皮肤 Tooltip 仅支持 hyperlink
    local _, link = Toolbox.Item.GetItemNameAndLink(itemID)
    if link then
      tooltip:SetHyperlink(link)
    end
  end
end
