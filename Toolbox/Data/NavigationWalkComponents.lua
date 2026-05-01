--[[
@contract_id navigation_walk_components
@schema_version 1
@contract_file WoWPlugin/DataContracts/navigation_walk_components.json
@contract_snapshot WoWTools/outputs/toolbox/contract_snapshots/navigation_walk_components/navigation_walk_components__schema_v1__20260501T172046Z.json
@generated_at 2026-05-01T17:20:46Z
@generated_by WoWPlugin/scripts/export/export_toolbox_one.py
@data_source wow.db
@summary navigation 首批 walk component 正式导出（主城 / 传送门房 / 港口与飞艇塔 / 常用交通落点）
@overwrite_notice 此文件由工具生成，手改会被覆盖
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.NavigationWalkComponents = {
  schemaVersion = 1,
  sourceMode = "live",
  generatedAt = "2026-05-01T17:20:46Z",

  components = {
    ["eastern_plaguelands_arrival"] = { ComponentID = "eastern_plaguelands_arrival", DisplayName = "东瘟疫之地入口", MemberNodeIDs = { 21, 3222, 3225 }, EntryNodeIDs = { 21, 3222, 3225 }, PreferredAnchorNodeID = 3225 },
    ["ghostlands_saltherils_path"] = { ComponentID = "ghostlands_saltherils_path", DisplayName = "萨拉斯小径", MemberNodeIDs = { 93, 3223, 3224 }, EntryNodeIDs = { 3223, 3224 }, PreferredAnchorNodeID = 3224 },
    ["orgrimmar_city"] = { ComponentID = "orgrimmar_city", DisplayName = "奥格瑞玛", MemberNodeIDs = { 83, 3249, 3251 }, EntryNodeIDs = { 83, 3249, 3251 }, PreferredAnchorNodeID = 83 },
    ["orgrimmar_portal_room"] = { ComponentID = "orgrimmar_portal_room", DisplayName = "奥格瑞玛传送门房", MemberNodeIDs = { 2805, 2819, 2824, 2826, 2831, 2834, 2842, 2846, 2896, 2910, 2977, 3198 }, EntryNodeIDs = { 2805, 2819, 2977 }, PreferredAnchorNodeID = 2805 },
    ["silvermoon_city"] = { ComponentID = "silvermoon_city", DisplayName = "银月城", MemberNodeIDs = { 1554, 2821, 2822, 3197, 3200 }, EntryNodeIDs = { 1554, 2821, 2822, 3197 }, PreferredAnchorNodeID = 1554 },
    ["stormwind_city"] = { ComponentID = "stormwind_city", DisplayName = "暴风城", MemberNodeIDs = { 82, 2782, 3199, 3201, 3236, 3237 }, EntryNodeIDs = { 82, 3201, 3236, 3237 }, PreferredAnchorNodeID = 82 },
  },

  nodeAssignments = {
    [21] = { NodeID = 21, ComponentID = "eastern_plaguelands_arrival", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "东瘟疫之地" },
    [82] = { NodeID = 82, ComponentID = "stormwind_city", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [83] = { NodeID = 83, ComponentID = "orgrimmar_city", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [93] = { NodeID = 93, ComponentID = "ghostlands_saltherils_path", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "幽魂之地" },
    [1554] = { NodeID = 1554, ComponentID = "silvermoon_city", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2782] = { NodeID = 2782, ComponentID = "stormwind_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "暴风城港口" },
    [2805] = { NodeID = 2805, ComponentID = "orgrimmar_portal_room", Role = "anchor", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "探路者大厅" },
    [2819] = { NodeID = 2819, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2821] = { NodeID = 2821, ComponentID = "silvermoon_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "日怒之塔" },
    [2822] = { NodeID = 2822, ComponentID = "silvermoon_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "内部圣殿" },
    [2824] = { NodeID = 2824, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2826] = { NodeID = 2826, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2831] = { NodeID = 2831, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2834] = { NodeID = 2834, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2842] = { NodeID = 2842, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2846] = { NodeID = 2846, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2896] = { NodeID = 2896, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2910] = { NodeID = 2910, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [2977] = { NodeID = 2977, ComponentID = "orgrimmar_portal_room", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [3197] = { NodeID = 3197, ComponentID = "silvermoon_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "银月城传送门落点" },
    [3198] = { NodeID = 3198, ComponentID = "orgrimmar_portal_room", Role = "technical", HiddenInSemanticChain = true, DisplayProxyNodeID = 2805, VisibleName = "奥格瑞玛传送门房" },
    [3199] = { NodeID = 3199, ComponentID = "stormwind_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "巫师圣殿" },
    [3200] = { NodeID = 3200, ComponentID = "silvermoon_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "银月城传送门落点" },
    [3201] = { NodeID = 3201, ComponentID = "stormwind_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "巫师圣殿" },
    [3222] = { NodeID = 3222, ComponentID = "eastern_plaguelands_arrival", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "东瘟疫之地入口" },
    [3223] = { NodeID = 3223, ComponentID = "ghostlands_saltherils_path", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "萨拉斯小径" },
    [3224] = { NodeID = 3224, ComponentID = "ghostlands_saltherils_path", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "萨拉斯小径" },
    [3225] = { NodeID = 3225, ComponentID = "eastern_plaguelands_arrival", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "东瘟疫之地入口" },
    [3236] = { NodeID = 3236, ComponentID = "stormwind_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "暴风城地铁入口" },
    [3237] = { NodeID = 3237, ComponentID = "stormwind_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = "暴风城港口" },
    [3249] = { NodeID = 3249, ComponentID = "orgrimmar_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
    [3251] = { NodeID = 3251, ComponentID = "orgrimmar_city", Role = "hub", HiddenInSemanticChain = false, DisplayProxyNodeID = nil, VisibleName = nil },
  },

  displayProxies = {
    [3198] = { NodeID = 3198, ComponentID = "orgrimmar_portal_room", DisplayProxyNodeID = 2805, VisibleName = "奥格瑞玛传送门房" },
  },
}
