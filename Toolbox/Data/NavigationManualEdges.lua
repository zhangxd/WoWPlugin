--[[
  手工维护：navigation 玩法路径边。
  这些边来自职业技能、主城 / 传送门房、炉石类能力等玩法规则，不由 wow.db 直接生成。
  DB 生成的地图基础节点见 NavigationMapNodes.lua；本文件只维护第一版高价值路径边。
]]

Toolbox.Data = Toolbox.Data or {}

local DEFAULT_DIRECT_COST = 180 -- 无可用交通边时的保守直达估算

--- 构建手工路径节点。
---@param uiMapID number 节点对应 UiMapID
---@param name string 节点显示名
---@return table nodeDef 节点定义
local function node(uiMapID, name)
  return {
    UiMapID = uiMapID,
    Name_lang = name,
  }
end

--- 构建目标地图可用的候选中转点。
---@param nodeId string 中转节点 ID
---@param cost number 中转点到目标的估算耗时
---@param label string 中转点到目标的步骤文案
---@return table viaNodeDef 候选中转点定义
local function via(nodeId, cost, label)
  return {
    node = nodeId,
    cost = cost,
    label = label,
  }
end

--- 构建目标地图规则。
---@param viaNodeList table 候选中转点列表
---@param directCost number|nil 直接前往估算耗时；nil 时使用保守默认值
---@return table targetRule 目标规则
local function target(viaNodeList, directCost)
  return {
    directCost = directCost or DEFAULT_DIRECT_COST,
    viaNodes = viaNodeList,
  }
end

--- 构建需要职业 / 技能确认的起点边。
---@param edgeId string 边 ID
---@param toNodeId string 终点节点 ID
---@param label string 步骤文案
---@param classFile string 职业文件名
---@param spellID number 技能 ID
---@param faction string|nil 阵营限制；nil 表示不限制
---@return table edge 路径边
local function spellEdge(edgeId, toNodeId, label, classFile, spellID, faction)
  local requirements = {
    classFile = classFile,
    spellID = spellID,
  } -- 职业技能边要求
  if faction then
    requirements.faction = faction
  end
  return {
    id = edgeId,
    from = "current",
    to = toNodeId,
    cost = 10,
    label = label,
    requirements = requirements,
  }
end

--- 构建公共传送门边。
---@param edgeId string 边 ID
---@param fromNodeId string 起点节点 ID
---@param toNodeId string 终点节点 ID
---@param label string 步骤文案
---@param cost number|nil 估算耗时；nil 时使用 20
---@return table edge 路径边
local function portalEdge(edgeId, fromNodeId, toNodeId, label, cost)
  return {
    id = edgeId,
    from = fromNodeId,
    to = toNodeId,
    cost = cost or 20,
    label = label,
  }
end

Toolbox.Data.NavigationManualEdges = {
  schemaVersion = 2,
  nodes = {
    orgrimmar = node(85, "奥格瑞玛"),
    silvermoon = node(110, "银月城"),
    thunder_bluff = node(88, "雷霆崖"),
    undercity = node(90, "幽暗城"),
    shattrath = node(111, "沙塔斯城"),
    warspear = node(624, "战争之矛"),
    azsuna = node(630, "阿苏纳"),
    zuldazar = node(862, "祖达萨"),
    oribos = node(1670, "奥利波斯"),
    valdrakken = node(2112, "瓦德拉肯"),
    dornogal = node(2339, "多恩诺嘉尔"),
    acherus = node(647, "阿彻鲁斯：黑锋要塞"),
    dreamgrove = node(747, "梦境林地"),
    dreamway = node(715, "翡翠梦境之路"),
    moonglade = node(80, "月光林地"),
    kun_lai = node(379, "昆莱山"),
  },
  targetRules = {
    [1] = target({
      via("orgrimmar", 25, "从奥格瑞玛前往杜隆塔尔目标"),
    }),
    [85] = target({
      via("orgrimmar", 0, "到达奥格瑞玛"),
    }),
    [88] = target({
      via("thunder_bluff", 0, "到达雷霆崖"),
      via("orgrimmar", 20, "从奥格瑞玛前往雷霆崖"),
    }),
    [90] = target({
      via("undercity", 0, "到达幽暗城"),
      via("orgrimmar", 20, "从奥格瑞玛前往幽暗城"),
    }),
    [110] = target({
      via("silvermoon", 0, "到达银月城"),
      via("orgrimmar", 20, "从奥格瑞玛前往银月城"),
    }),
    [111] = target({
      via("shattrath", 0, "到达沙塔斯城"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往沙塔斯城"),
    }),
    [198] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往海加尔山"),
      via("dreamway", 20, "通过翡翠梦境之路前往海加尔山"),
    }),
    [203] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往瓦丝琪尔"),
    }),
    [207] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往深岩之洲"),
    }),
    [241] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往暮光高地"),
    }),
    [249] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往奥丹姆"),
    }),
    [371] = target({
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往翡翠林"),
    }),
    [379] = target({
      via("kun_lai", 0, "到达昆莱山"),
    }),
    [624] = target({
      via("warspear", 0, "到达战争之矛"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往战争之矛"),
    }),
    [630] = target({
      via("azsuna", 0, "到达阿苏纳"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往阿苏纳"),
    }),
    [647] = target({
      via("acherus", 0, "到达阿彻鲁斯：黑锋要塞"),
    }),
    [715] = target({
      via("dreamway", 0, "到达翡翠梦境之路"),
      via("dreamgrove", 8, "从梦境林地进入翡翠梦境之路"),
    }),
    [747] = target({
      via("dreamgrove", 0, "到达梦境林地"),
    }),
    [862] = target({
      via("zuldazar", 0, "到达祖达萨"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往祖达萨"),
    }),
    [1670] = target({
      via("oribos", 0, "到达奥利波斯"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往奥利波斯"),
    }),
    [2112] = target({
      via("valdrakken", 0, "到达瓦德拉肯"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往瓦德拉肯"),
    }),
    [2339] = target({
      via("dornogal", 0, "到达多恩诺嘉尔"),
      via("orgrimmar", 15, "使用奥格瑞玛传送门前往多恩诺嘉尔"),
    }),
  },
  edges = {
    spellEdge("mage_teleport_orgrimmar", "orgrimmar", "传送：奥格瑞玛", "MAGE", 3567, "Horde"),
    spellEdge("mage_teleport_silvermoon", "silvermoon", "传送：银月城", "MAGE", 32272, "Horde"),
    spellEdge("mage_teleport_thunder_bluff", "thunder_bluff", "传送：雷霆崖", "MAGE", 3566, "Horde"),
    spellEdge("mage_teleport_undercity", "undercity", "传送：幽暗城", "MAGE", 3563, "Horde"),
    spellEdge("mage_teleport_shattrath_horde", "shattrath", "传送：沙塔斯城", "MAGE", 35715, "Horde"),
    spellEdge("death_knight_death_gate_acherus", "acherus", "死亡之门：阿彻鲁斯", "DEATHKNIGHT", 50977),
    spellEdge("druid_dreamwalk_dreamgrove", "dreamgrove", "梦境行者：梦境林地", "DRUID", 193753),
    spellEdge("druid_teleport_moonglade", "moonglade", "传送：月光林地", "DRUID", 18960),
    spellEdge("monk_zen_pilgrimage_kun_lai", "kun_lai", "禅宗朝圣：晴日峰", "MONK", 126892),
    portalEdge("silvermoon_portal_orgrimmar", "silvermoon", "orgrimmar", "使用银月城传送门前往奥格瑞玛"),
    portalEdge("orgrimmar_portal_silvermoon", "orgrimmar", "silvermoon", "使用奥格瑞玛传送门前往银月城"),
    portalEdge("thunder_bluff_portal_orgrimmar", "thunder_bluff", "orgrimmar", "使用雷霆崖传送门前往奥格瑞玛"),
    portalEdge("orgrimmar_portal_thunder_bluff", "orgrimmar", "thunder_bluff", "使用奥格瑞玛传送门前往雷霆崖"),
    portalEdge("undercity_portal_orgrimmar", "undercity", "orgrimmar", "使用幽暗城传送门前往奥格瑞玛"),
    portalEdge("orgrimmar_portal_undercity", "orgrimmar", "undercity", "使用奥格瑞玛传送门前往幽暗城"),
    portalEdge("dreamgrove_portal_dreamway", "dreamgrove", "dreamway", "从梦境林地进入翡翠梦境之路", 8),
  },
}
