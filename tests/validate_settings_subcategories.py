from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def read_text(*parts: str) -> str:
    return (ROOT.joinpath(*parts)).read_text(encoding="utf-8")


def require_contains(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def require_file(*parts: str) -> None:
    path = ROOT.joinpath(*parts)
    if not path.exists():
        raise AssertionError(f"missing file: {path}")


def validate_settings_host() -> None:
    text = read_text("Toolbox", "UI", "SettingsHost.lua")
    for needle, label in [
        ("RegisterCanvasLayoutCategory", "settings category api"),
        ("RegisterCanvasLayoutSubcategory", "settings subcategory api"),
        ("BuildOverviewPage", "overview page builder"),
        ("BuildAboutPage", "about page builder"),
        ("BuildModulePage", "module page builder"),
        ("BuildSharedModuleControls", "shared module controls builder"),
        ("Toolbox.SettingsHost:Open()", "settings open function"),
        ("Toolbox.GameMenu_Init()", "game menu init function"),
    ]:
        require_contains(text, needle, label)

    if "BuildDungeonRaidDirectorySection" in text:
        raise AssertionError("legacy directory section builder should be removed from SettingsHost")


def validate_config() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "Config.lua")
    for needle, label in [
        ("chat_notify = {", "chat_notify defaults"),
        ("mover = {", "mover defaults"),
        ("blizzardDragHitMode", "mover hit mode default"),
        ("allowDragInCombat", "mover combat drag default"),
        ("micromenu_panels = {", "micromenu defaults (legacy)"),
        ("tooltip_anchor = {", "tooltip defaults"),
        ("encounter_journal = {", "encounter journal module defaults"),
        ("mountFilterEnabled = true", "encounter journal mount filter default"),
        ("lockoutOverlayEnabled = true", "encounter journal lockout overlay default"),
        ("minimap_button = {", "minimap button module defaults"),
        ("showMinimapButton", "minimap button visibility default"),
        ("minimapPos", "minimap button angle storage"),
        ("debug = false", "module debug defaults"),
    ]:
        require_contains(text, needle, label)


def validate_module_registry() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "ModuleRegistry.lua")
    for needle, label in [
        ("settingsIntroKey", "settings intro key contract"),
        ("settingsOrder", "settings order contract"),
        ("OnEnabledSettingChanged", "enabled callback contract"),
        ("OnDebugSettingChanged", "debug callback contract"),
        ("ResetToDefaultsAndRebuild", "reset callback contract"),
    ]:
        require_contains(text, needle, label)


def validate_locales() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "Locales.lua")
    for needle, label in [
        ("SETTINGS_OVERVIEW_TITLE", "overview title locale"),
        ("SETTINGS_ABOUT_TITLE", "about title locale"),
        ("SETTINGS_MODULE_ENABLE", "shared enable locale"),
        ("SETTINGS_MODULE_DEBUG", "shared debug locale"),
        ("SETTINGS_MODULE_RESET_REBUILD", "shared reset locale"),
        ("MODULE_ENCOUNTER_JOURNAL", "encounter journal module locale"),
        ("MODULE_ENCOUNTER_JOURNAL_INTRO", "encounter journal intro locale"),
        ("EJ_MOUNT_FILTER_LABEL", "encounter journal mount filter locale"),
        ("MODULE_MINIMAP_BUTTON", "minimap button module locale"),
    ]:
        require_contains(text, needle, label)


def validate_modules() -> None:
    files = [
        "ChatNotify.lua",
        "EncounterJournal.lua",
        "MinimapButton.lua",
        "Mover.lua",
        "TooltipAnchor.lua",
    ]
    for file_name in files:
        require_file("Toolbox", "Modules", file_name)
        text = read_text("Toolbox", "Modules", file_name)
        common_needles = [
            ("settingsIntroKey", "settings intro key"),
            ("settingsOrder", "settings order"),
            ("OnEnabledSettingChanged", "enabled callback"),
            ("ResetToDefaultsAndRebuild", "reset callback"),
        ]
        for needle, label in common_needles:
            require_contains(text, needle, f"{file_name} {label}")

        # EncounterJournal 当前不暴露模块级 debug 开关回调，其余模块保留。
        if file_name != "EncounterJournal.lua":
            require_contains(text, "OnDebugSettingChanged", f"{file_name} debug callback")

    require_file("Toolbox", "Modules", "MicroMenuPanels.lua")
    micromenu = read_text("Toolbox", "Modules", "MicroMenuPanels.lua")
    require_contains(micromenu, "Toolbox.Mover.BlizzardPanelsRefresh", "micromenu refresh delegate to mover")


def validate_toc() -> None:
    text = read_text("Toolbox", "Toolbox.toc")
    require_contains(text, "Modules\\EncounterJournal.lua", "encounter journal module toc entry")
    require_contains(text, "Modules\\MinimapButton.lua", "minimap button module toc entry")
    require_contains(text, "## Interface: 120000, 120001", "retail toc compatibility range")


def validate_encounter_journal_regressions() -> None:
    text = read_text("Toolbox", "Modules", "EncounterJournal.lua")
    # 调度器应使用可取消句柄，避免 C_Timer.After 防抖失效导致并发刷新。
    require_contains(text, "C_Timer.NewTimer", "encounter journal uses cancellable timer")
    # 关闭叠加后应主动清理已绘制文本，避免残留显示。
    require_contains(text, "function LockoutOverlay:clearAllFrames()", "encounter journal clear overlay helper")
    require_contains(text, "self:clearAllFrames()", "encounter journal clears overlays when disabled")
    # 模块禁用后应停用高频更新事件，避免后台空调度。
    require_contains(text, 'eventFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")', "encounter journal unregisters lockout event when disabled")
    require_contains(text, 'eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")', "encounter journal re-registers lockout event when enabled")
    require_contains(text, "if isModuleEnabled() then", "encounter journal guards update callbacks by enabled state")


def validate_mover_regressions() -> None:
    text = read_text("Toolbox", "Modules", "Mover.lua")
    # RegisterFrame 在模块关闭时也要登记，便于后续重新开启自动生效。
    require_contains(text, "pushAddonRegistry(frame, key, opts)", "mover pushes addon registry in RegisterFrame")
    require_contains(text, "if db.enabled == false then", "mover register disabled guard")
    if text.find("pushAddonRegistry(frame, key, opts)") > text.find("if db.enabled == false then"):
        raise AssertionError("mover should push addon registry before disabled guard")
    # 模块关闭时除暴雪面板外，还要关闭已登记自定义 frame 的拖动行为。
    require_contains(text, "disableAddonRegisteredFrames()", "mover disables addon-registered drags when disabled")


def validate_tooltip_anchor_regressions() -> None:
    module_text = read_text("Toolbox", "Modules", "TooltipAnchor.lua")
    core_text = read_text("Toolbox", "Core", "API", "Tooltip.lua")
    # 设置页应暴露 follow 模式，和 locale 文案保持一致。
    require_contains(module_text, 'makeMode("follow"', "tooltip anchor follow mode option")
    # 核心锚点逻辑应识别 follow 模式（与 cursor 同行为兼容）。
    require_contains(
        core_text,
        'db.mode ~= "cursor" and db.mode ~= "follow"',
        "tooltip core treats follow mode as active cursor anchor",
    )


def validate_minimap_button_regressions() -> None:
    text = read_text("Toolbox", "Modules", "MinimapButton.lua")
    # flyout 目录排序应先看 order，再按 id 兜底，避免声明顺序与显示顺序不一致。
    require_contains(text, "local leftOrder = tonumber(leftDef and leftDef.order) or 100", "minimap flyout order sort left")
    require_contains(text, "local rightOrder = tonumber(rightDef and rightDef.order) or 100", "minimap flyout order sort right")
    require_contains(text, "if leftOrder ~= rightOrder then", "minimap flyout order priority compare")
    require_contains(text, "return leftId < rightId", "minimap flyout order tie-break by id")


def validate_adventure_journal_tooltip_lockout_feature() -> None:
    ej_api = read_text("Toolbox", "Core", "API", "EncounterJournal.lua")
    minimap = read_text("Toolbox", "Modules", "MinimapButton.lua")
    locales = read_text("Toolbox", "Core", "Foundation", "Locales.lua")

    # EJ API：提供可复用的锁定摘要查询（供 flyout tooltip 使用）。
    require_contains(ej_api, "function Toolbox.EJ.GetSavedInstanceLockoutSummary(", "ej api lockout summary function")
    require_contains(ej_api, "function Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(", "ej api tooltip line builder")

    # Minimap flyout：冒险手册项应带动态 tooltip 增补回调。
    require_contains(minimap, "augmentTooltip = function()", "minimap ej flyout augment tooltip callback")
    require_contains(minimap, "Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines", "minimap uses ej lockout tooltip lines")
    require_contains(minimap, "MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE", "minimap uses lockout section title locale")

    # 本地化：中英都应提供 tooltip 锁定小节文案。
    require_contains(locales, "MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_TITLE", "locale lockout section title")
    require_contains(locales, "MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_EMPTY", "locale lockout empty text")
    require_contains(locales, "MINIMAP_FLYOUT_ADVENTURE_JOURNAL_LOCKOUTS_MORE_FMT", "locale lockout overflow text")


def validate_adventure_journal_lockout_summary_filter_regression() -> None:
    ej_api = read_text("Toolbox", "Core", "API", "EncounterJournal.lua")

    # 回归：副本重置摘要不应被 isLocked 强约束过滤，否则会漏掉有效 CD。
    require_contains(
        ej_api,
        "if ok and resetTime and resetTime > 0 then",
        "ej lockout summary keeps active reset entries without hard isLocked gate",
    )
    if "if ok and isLocked and resetTime and resetTime > 0 then" in ej_api:
        raise AssertionError("ej lockout summary should not require isLocked before including active reset entries")


def validate_map_coordinate_feature() -> None:
    config_text = read_text("Toolbox", "Core", "Foundation", "Config.lua")
    locale_text = read_text("Toolbox", "Core", "Foundation", "Locales.lua")
    minimap_module_text = read_text("Toolbox", "Modules", "MinimapButton.lua")

    # 坐标显示配置默认值。
    require_contains(config_text, "showCoordsOnMinimap = true", "minimap coords visibility default")
    require_contains(config_text, 'minimapCoordsAnchor = "bottom"', "minimap coords anchor default")

    # 本地化键（中英共用同一键集，最终由 Locale_Apply 合并）。
    require_contains(locale_text, "MINIMAP_COORDS_PLAYER_FMT", "locale minimap player coords format")
    require_contains(locale_text, "WORLD_MAP_COORDS_PLAYER_FMT", "locale world map player coords format")
    require_contains(locale_text, "WORLD_MAP_COORDS_MOUSE_FMT", "locale world map mouse coords format")
    require_contains(locale_text, "WORLD_MAP_COORDS_UNKNOWN", "locale unknown coords text")

    # 模块实现要包含刷新逻辑与可见性控制。
    require_contains(minimap_module_text, "updateMinimapCoordsText()", "minimap coords refresh function")
    require_contains(minimap_module_text, "updateWorldMapCoordsText()", "world map coords refresh function")
    require_contains(minimap_module_text, "refreshCoordinateDisplays()", "coordinate display lifecycle refresh")
    require_contains(minimap_module_text, "showCoordsOnMinimap", "module uses minimap coords visibility setting")
    require_contains(minimap_module_text, "minimapCoordsAnchor", "module uses minimap coords anchor setting")


def validate_encounter_journal_detail_page_feature() -> None:
    config_text = read_text("Toolbox", "Core", "Foundation", "Config.lua")
    locale_text = read_text("Toolbox", "Core", "Foundation", "Locales.lua")
    api_text = read_text("Toolbox", "Core", "API", "EncounterJournal.lua")
    module_text = read_text("Toolbox", "Modules", "EncounterJournal.lua")

    # 模块存档：详情页“仅坐骑”开关状态。
    require_contains(config_text, "detailMountOnlyEnabled", "encounter journal detail mount-only setting default")

    # 领域 API：详情页筛选与难度匹配锁定查询所需接口。
    require_contains(api_text, "function Toolbox.EJ.GetMountItemSetForInstance(", "ej api mount item set helper")
    require_contains(api_text, "function Toolbox.EJ.GetSelectedDifficultyID(", "ej api selected difficulty helper")
    require_contains(api_text, "function Toolbox.EJ.GetLockoutForInstanceAndDifficulty(", "ej api difficulty lockout helper")

    # 详情页增强：仅坐骑筛选 + 标题后锁定文本。
    require_contains(module_text, "detailMountOnlyEnabled", "encounter journal module uses detail mount-only setting")
    require_contains(module_text, "EncounterJournal_LootUpdate", "encounter journal hooks detail loot update")
    require_contains(module_text, "EJ_SetDifficulty", "encounter journal hooks difficulty switch")
    require_contains(module_text, "EJ_DETAIL_MOUNT_ONLY_LABEL", "encounter journal detail mount-only locale key")
    require_contains(module_text, "EJ_DETAIL_LOCKOUT_FMT", "encounter journal detail lockout locale key")

    # 本地化：详情页筛选与“重置：xxxx”文案键。
    require_contains(locale_text, "EJ_DETAIL_MOUNT_ONLY_LABEL", "locale detail mount-only label")
    require_contains(locale_text, "EJ_DETAIL_LOCKOUT_FMT", "locale detail lockout format")
    require_contains(locale_text, "EJ_DETAIL_LOCKOUT_NONE", "locale detail lockout empty")


def validate_encounter_journal_micro_button_tooltip_lockouts_feature() -> None:
    module_text = read_text("Toolbox", "Modules", "EncounterJournal.lua")

    # 右下角微型菜单「冒险手册」按钮：悬停 tooltip 需追加副本 CD 摘要。
    require_contains(module_text, "_G.EJMicroButton", "encounter journal retail micro button global reference")
    require_contains(module_text, "_G.EncounterJournalMicroButton", "encounter journal legacy micro button fallback")
    require_contains(module_text, 'microButton:HookScript("OnEnter"', "encounter journal hooks micro button OnEnter")
    require_contains(module_text, "Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines", "micro button tooltip uses shared ej lockout summary api")
    require_contains(module_text, "refreshAdventureGuideMicroButtonTooltipIfOwned()", "encounter journal refreshes micro button tooltip on lockout update")


def validate_encounter_journal_questline_tree_feature() -> None:
    toc_text = read_text("Toolbox", "Toolbox.toc")
    config_text = read_text("Toolbox", "Core", "Foundation", "Config.lua")
    locale_text = read_text("Toolbox", "Core", "Foundation", "Locales.lua")
    module_text = read_text("Toolbox", "Modules", "EncounterJournal.lua")
    require_file("Toolbox", "Data", "InstanceQuestlines.lua")
    require_file("Toolbox", "Core", "API", "QuestlineProgress.lua")
    questline_api_text = read_text("Toolbox", "Core", "API", "QuestlineProgress.lua")

    require_contains(toc_text, "Data\\InstanceQuestlines.lua", "questline data toc entry")
    require_contains(toc_text, "Core\\API\\QuestlineProgress.lua", "questline api toc entry")

    require_contains(config_text, "questlineTreeEnabled", "encounter journal questline tree setting default")
    require_contains(config_text, "questlineTreeCollapsed", "encounter journal questline tree collapsed default")

    require_contains(locale_text, "EJ_QUESTLINE_TREE_LABEL", "questline tree label locale")
    require_contains(locale_text, "EJ_QUESTLINE_TREE_EMPTY", "questline tree empty locale")
    require_contains(locale_text, "EJ_QUESTLINE_TREE_TYPE_MAP", "questline tree map type locale")

    require_contains(questline_api_text, "Toolbox.Questlines", "questline namespace")
    require_contains(questline_api_text, "function Toolbox.Questlines.RegisterType(", "questline register type api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetInstanceTree(", "questline instance tree api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetChainProgress(", "questline chain progress api")

    require_contains(module_text, "QuestlineTreeView", "encounter journal questline tree view")
    require_contains(module_text, "questlineTreeEnabled", "encounter journal questline tree setting usage")
    require_contains(module_text, "Toolbox.Questlines.GetInstanceTree", "encounter journal uses questline api")


def main() -> int:
    validate_settings_host()
    validate_config()
    validate_module_registry()
    validate_locales()
    validate_modules()
    validate_toc()
    validate_encounter_journal_regressions()
    validate_mover_regressions()
    validate_tooltip_anchor_regressions()
    validate_minimap_button_regressions()
    validate_adventure_journal_tooltip_lockout_feature()
    validate_adventure_journal_lockout_summary_filter_regression()
    validate_map_coordinate_feature()
    validate_encounter_journal_detail_page_feature()
    validate_encounter_journal_micro_button_tooltip_lockouts_feature()
    validate_encounter_journal_questline_tree_feature()
    print("OK: settings subcategories structure validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
