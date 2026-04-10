--[[
  任务类型名称映射表。
  数据来源：manual（手工维护）。
  用途：将运行时 `C_QuestLog.GetQuestType(questID)` 返回的 typeID 映射到本地化键。
  说明：
    1. 该文件不是数据库生成产物。
    2. 若某个 typeID 未配置映射，运行时使用 `EJ_QUEST_TYPE_UNKNOWN_FMT` 兜底显示。
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.QuestTypeNames = {
  -- [typeID] = "LOCALE_KEY",
}
