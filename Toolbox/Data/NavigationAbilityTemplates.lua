--[[
@contract_id navigation_ability_templates
@schema_version 1
@contract_file WoWPlugin/DataContracts/navigation_ability_templates.json
@contract_snapshot WoWTools/outputs/toolbox/contract_snapshots/navigation_ability_templates/navigation_ability_templates__schema_v1__20260428T211105Z.json
@generated_at 2026-04-28T21:11:05Z
@generated_by WoWPlugin/scripts/export/export_toolbox_one.py
@data_source wow.db
@summary navigation V1 能力模板（炉石 + 可静态解析目标的职业旅行法术）
@overwrite_notice 此文件由工具生成，手改会被覆盖
]]

Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.NavigationAbilityTemplates = {
  schemaVersion = 1,
  sourceMode = "live",
  generatedAt = "2026-04-28T21:11:05Z",

  templates = {
    ["spell_3561"] = { TemplateID = "spell_3561", Mode = "class_teleport", SpellID = 3561, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_84", Label = "传送：暴风城", SelfUseOnly = true },
    ["spell_3562"] = { TemplateID = "spell_3562", Mode = "class_teleport", SpellID = 3562, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_87", Label = "传送：铁炉堡", SelfUseOnly = true },
    ["spell_3563"] = { TemplateID = "spell_3563", Mode = "class_teleport", SpellID = 3563, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_90", Label = "传送：幽暗城", SelfUseOnly = true },
    ["spell_3565"] = { TemplateID = "spell_3565", Mode = "class_teleport", SpellID = 3565, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_89", Label = "传送：达纳苏斯", SelfUseOnly = true },
    ["spell_3566"] = { TemplateID = "spell_3566", Mode = "class_teleport", SpellID = 3566, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_88", Label = "传送：雷霆崖", SelfUseOnly = true },
    ["spell_3567"] = { TemplateID = "spell_3567", Mode = "class_teleport", SpellID = 3567, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_85", Label = "传送：奥格瑞玛", SelfUseOnly = true },
    ["spell_8690"] = { TemplateID = "spell_8690", Mode = "hearthstone", SpellID = 8690, ClassFile = nil, FactionGroup = nil, TargetRuleKind = "hearth_bind", ToNodeID = nil, Label = "炉石", SelfUseOnly = true },
    ["spell_10059"] = { TemplateID = "spell_10059", Mode = "class_portal", SpellID = 10059, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_84", Label = "传送门：暴风城", SelfUseOnly = true },
    ["spell_11416"] = { TemplateID = "spell_11416", Mode = "class_portal", SpellID = 11416, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_87", Label = "传送门：铁炉堡", SelfUseOnly = true },
    ["spell_11417"] = { TemplateID = "spell_11417", Mode = "class_portal", SpellID = 11417, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_85", Label = "传送门：奥格瑞玛", SelfUseOnly = true },
    ["spell_11418"] = { TemplateID = "spell_11418", Mode = "class_portal", SpellID = 11418, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_90", Label = "传送门：幽暗城", SelfUseOnly = true },
    ["spell_11419"] = { TemplateID = "spell_11419", Mode = "class_portal", SpellID = 11419, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_89", Label = "传送门：达纳苏斯", SelfUseOnly = true },
    ["spell_11420"] = { TemplateID = "spell_11420", Mode = "class_portal", SpellID = 11420, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_88", Label = "传送门：雷霆崖", SelfUseOnly = true },
    ["spell_18960"] = { TemplateID = "spell_18960", Mode = "class_teleport", SpellID = 18960, ClassFile = "DRUID", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_80", Label = "传送：月光林地", SelfUseOnly = true },
    ["spell_32266"] = { TemplateID = "spell_32266", Mode = "class_portal", SpellID = 32266, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_103", Label = "传送门：埃索达", SelfUseOnly = true },
    ["spell_32267"] = { TemplateID = "spell_32267", Mode = "class_portal", SpellID = 32267, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_110", Label = "传送门：银月城（燃烧的远征）", SelfUseOnly = true },
    ["spell_32271"] = { TemplateID = "spell_32271", Mode = "class_teleport", SpellID = 32271, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_103", Label = "传送：埃索达", SelfUseOnly = true },
    ["spell_32272"] = { TemplateID = "spell_32272", Mode = "class_teleport", SpellID = 32272, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_110", Label = "传送：银月城", SelfUseOnly = true },
    ["spell_33690"] = { TemplateID = "spell_33690", Mode = "class_teleport", SpellID = 33690, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_111", Label = "传送：沙塔斯", SelfUseOnly = true },
    ["spell_33691"] = { TemplateID = "spell_33691", Mode = "class_portal", SpellID = 33691, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_111", Label = "传送门：沙塔斯", SelfUseOnly = true },
    ["spell_35715"] = { TemplateID = "spell_35715", Mode = "class_teleport", SpellID = 35715, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_111", Label = "传送：沙塔斯", SelfUseOnly = true },
    ["spell_35717"] = { TemplateID = "spell_35717", Mode = "class_portal", SpellID = 35717, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_111", Label = "传送门：沙塔斯", SelfUseOnly = true },
    ["spell_53140"] = { TemplateID = "spell_53140", Mode = "class_teleport", SpellID = 53140, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_501", Label = "传送：达拉然 - 诺森德", SelfUseOnly = true },
    ["spell_53142"] = { TemplateID = "spell_53142", Mode = "class_portal", SpellID = 53142, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_501", Label = "传送门：达拉然 - 诺森德", SelfUseOnly = true },
    ["spell_88342"] = { TemplateID = "spell_88342", Mode = "class_teleport", SpellID = 88342, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_244", Label = "传送：托尔巴拉德", SelfUseOnly = true },
    ["spell_88344"] = { TemplateID = "spell_88344", Mode = "class_teleport", SpellID = 88344, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_244", Label = "传送：托尔巴拉德", SelfUseOnly = true },
    ["spell_88345"] = { TemplateID = "spell_88345", Mode = "class_portal", SpellID = 88345, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_244", Label = "传送门：托尔巴拉德", SelfUseOnly = true },
    ["spell_88346"] = { TemplateID = "spell_88346", Mode = "class_portal", SpellID = 88346, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_244", Label = "传送门：托尔巴拉德", SelfUseOnly = true },
    ["spell_120146"] = { TemplateID = "spell_120146", Mode = "class_portal", SpellID = 120146, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_501", Label = "远古传送门：达拉然", SelfUseOnly = true },
    ["spell_132620"] = { TemplateID = "spell_132620", Mode = "class_portal", SpellID = 132620, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_390", Label = "传送门：锦绣谷", SelfUseOnly = true },
    ["spell_132621"] = { TemplateID = "spell_132621", Mode = "class_teleport", SpellID = 132621, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_390", Label = "传送：锦绣谷", SelfUseOnly = true },
    ["spell_132626"] = { TemplateID = "spell_132626", Mode = "class_portal", SpellID = 132626, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_390", Label = "传送门：锦绣谷", SelfUseOnly = true },
    ["spell_132627"] = { TemplateID = "spell_132627", Mode = "class_teleport", SpellID = 132627, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_390", Label = "传送：锦绣谷", SelfUseOnly = true },
    ["spell_176242"] = { TemplateID = "spell_176242", Mode = "class_teleport", SpellID = 176242, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_624", Label = "传送：战争之矛", SelfUseOnly = true },
    ["spell_176244"] = { TemplateID = "spell_176244", Mode = "class_portal", SpellID = 176244, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_624", Label = "传送门：战争之矛", SelfUseOnly = true },
    ["spell_193759"] = { TemplateID = "spell_193759", Mode = "class_teleport", SpellID = 193759, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_734", Label = "传送：守护者圣殿", SelfUseOnly = true },
    ["spell_224869"] = { TemplateID = "spell_224869", Mode = "class_teleport", SpellID = 224869, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_626", Label = "传送：达拉然 - 破碎群岛", SelfUseOnly = true },
    ["spell_224871"] = { TemplateID = "spell_224871", Mode = "class_portal", SpellID = 224871, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_626", Label = "传送门：达拉然 - 破碎群岛", SelfUseOnly = true },
    ["spell_281400"] = { TemplateID = "spell_281400", Mode = "class_portal", SpellID = 281400, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_1161", Label = "传送门：伯拉勒斯", SelfUseOnly = true },
    ["spell_281402"] = { TemplateID = "spell_281402", Mode = "class_portal", SpellID = 281402, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_1165", Label = "传送门：达萨罗", SelfUseOnly = true },
    ["spell_281403"] = { TemplateID = "spell_281403", Mode = "class_teleport", SpellID = 281403, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_1161", Label = "传送：伯拉勒斯", SelfUseOnly = true },
    ["spell_281404"] = { TemplateID = "spell_281404", Mode = "class_teleport", SpellID = 281404, ClassFile = "MAGE", FactionGroup = "Horde", TargetRuleKind = "fixed_node", ToNodeID = "uimap_1165", Label = "传送：达萨罗", SelfUseOnly = true },
    ["spell_344587"] = { TemplateID = "spell_344587", Mode = "class_teleport", SpellID = 344587, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_1670", Label = "传送：奥利波斯", SelfUseOnly = true },
    ["spell_344597"] = { TemplateID = "spell_344597", Mode = "class_portal", SpellID = 344597, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_1670", Label = "传送门：奥利波斯", SelfUseOnly = true },
    ["spell_395277"] = { TemplateID = "spell_395277", Mode = "class_teleport", SpellID = 395277, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_2112", Label = "传送：瓦德拉肯", SelfUseOnly = true },
    ["spell_395289"] = { TemplateID = "spell_395289", Mode = "class_portal", SpellID = 395289, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_2112", Label = "传送门：瓦德拉肯", SelfUseOnly = true },
    ["spell_446534"] = { TemplateID = "spell_446534", Mode = "class_portal", SpellID = 446534, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_2339", Label = "传送门：多恩诺嘉尔", SelfUseOnly = true },
    ["spell_446540"] = { TemplateID = "spell_446540", Mode = "class_teleport", SpellID = 446540, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_2339", Label = "传送：多恩诺嘉尔", SelfUseOnly = true },
    ["spell_1259190"] = { TemplateID = "spell_1259190", Mode = "class_teleport", SpellID = 1259190, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_110", Label = "传送：银月城", SelfUseOnly = true },
    ["spell_1259194"] = { TemplateID = "spell_1259194", Mode = "class_portal", SpellID = 1259194, ClassFile = "MAGE", FactionGroup = nil, TargetRuleKind = "fixed_node", ToNodeID = "uimap_110", Label = "传送门：银月城", SelfUseOnly = true },
  },
}
