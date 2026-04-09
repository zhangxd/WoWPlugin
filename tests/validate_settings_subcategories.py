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
        ("rootTabOrderIds = {}", "encounter journal root tab order ids default"),
        ("rootTabHiddenIds = {}", "encounter journal root tab hidden ids default"),
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
        ("EJ_ROOT_TAB_SETTINGS_TITLE", "encounter journal root tab settings title locale"),
        ("EJ_ROOT_TAB_SETTINGS_HINT", "encounter journal root tab settings hint locale"),
        ("EJ_ROOT_TAB_SETTINGS_VISIBLE", "encounter journal root tab settings visible locale"),
        ("EJ_ROOT_TAB_SETTINGS_RESET_ORDER", "encounter journal root tab settings reset locale"),
        ("EJ_ROOT_TAB_NAME_UNKNOWN_FMT", "encounter journal root tab unknown name format locale"),
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
    # 列表 hook 未触发时也要主动创建“仅坐骑”按钮，避免入口缺失。
    require_contains(text, "local function refreshAll()\n  MountFilter:createUI()", "encounter journal creates mount filter ui in unified refresh path")
    require_contains(text, "local function refreshAfterHookInit()", "encounter journal defines deterministic post-hook init refresh helper")
    require_contains(
        text,
        'if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then\n      self:UnregisterEvent("ADDON_LOADED")\n      initHooks()\n      refreshAfterHookInit()',
        "encounter journal runs deterministic refresh right after hook init on addon loaded",
    )
    require_contains(
        text,
        'if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then\n    initHooks()\n    refreshAfterHookInit()',
        "encounter journal runs deterministic refresh when ej was already loaded",
    )
    require_contains(text, "MountFilter:createUI()\n          MountFilter:updateVisibility()", "encounter journal creates mount filter ui on EJ OnShow")
    require_contains(text, "return Toolbox.EJ.IsRaidOrDungeonInstanceListTab() == true", "encounter journal mount filter visibility delegates to ej domain api")
    require_contains(text, "local anchorTarget = instSel.ExpansionDropdown or instSel", "encounter journal mount filter anchor falls back when expansion dropdown missing")
    require_contains(text, "if Toolbox.EJ.IsRaidOrDungeonInstanceListTab() ~= true then", "encounter journal lockout overlay is gated by raid or dungeon tab")
    require_contains(text, "local instId = elementData.instanceID or elementData.journalInstanceID", "encounter journal instance id extraction uses dedicated fields")
    if "elementData.id" in text:
        raise AssertionError("encounter journal instance id extraction should not fallback to generic elementData.id")
    if "nested.id" in text:
        raise AssertionError("encounter journal instance id extraction should not fallback to generic nested.id")

    ej_api_text = read_text("Toolbox", "Core", "API", "EncounterJournal.lua")
    require_contains(ej_api_text, "local journalIsOpen = true", "ej domain api checks encounter journal open state before tab check")
    require_contains(ej_api_text, "if not journalIsOpen then", "ej domain api exits when encounter journal is closed")
    require_contains(ej_api_text, "local dungeonTabButton = encounterJournalFrame.dungeonsTab", "ej domain api resolves dungeon tab from encounter journal instance only")
    require_contains(ej_api_text, "local raidTabButton = encounterJournalFrame.raidsTab", "ej domain api resolves raid tab from encounter journal instance only")
    if "_G.EncounterJournalDungeonTab" in ej_api_text or "_G.EncounterJournalRaidTab" in ej_api_text:
        raise AssertionError("ej domain api should not fallback raid or dungeon detection to global tab names")
    if "EncounterJournalTab1" in ej_api_text or "EncounterJournalTab2" in ej_api_text:
        raise AssertionError("ej domain api should not fallback raid or dungeon detection to generic EncounterJournalTabN slots")
    require_contains(ej_api_text, "local selectedRootTabID = encounterJournalFrame.selectedTab", "ej domain api reads selected root tab id from encounter journal")
    if "PanelTemplates_GetSelectedTab" in ej_api_text:
        raise AssertionError("ej domain api should not fallback selected tab detection to panel template helper")
    require_contains(ej_api_text, "return selectedRootTabID == dungeonTabID or selectedRootTabID == raidTabID", "ej domain api compares selected root tab id against dungeon and raid ids")


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
    data_text = read_text("Toolbox", "Data", "InstanceQuestlines.lua")
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
    require_contains(locale_text, "EJ_QUESTLINE_PROGRESS_FMT", "questline tree progress locale")

    require_contains(questline_api_text, "Toolbox.Questlines", "questline namespace")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetChainProgress(", "questline chain progress api")
    require_contains(questline_api_text, "function Toolbox.Questlines.ValidateInstanceQuestlinesData(", "questline strict validation api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestTabModel(", "questline quest tab model api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestListByQuestLineID(", "questline list api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestDetailByID(", "quest detail api")
    if "function Toolbox.Questlines.GetExpansionTree(" in questline_api_text:
        raise AssertionError("questline api should not keep legacy GetExpansionTree compatibility")
    if "function Toolbox.Questlines.GetInstanceTree(" in questline_api_text:
        raise AssertionError("questline api should not keep legacy GetInstanceTree compatibility")
    require_contains(data_text, "schemaVersion = 2", "questline data schema v2")
    require_contains(data_text, "quests = {", "questline data quests table")
    require_contains(data_text, "questLines = {", "questline data questlines table")
    require_contains(data_text, "questLineQuestIDs = {", "questline data questline quest map")
    require_contains(data_text, "expansionQuestLineIDs = {", "questline data expansion questline map")

    require_contains(module_text, "QuestlineTreeView", "encounter journal questline tree view")
    require_contains(module_text, "questlineTreeEnabled", "encounter journal questline tree setting usage")
    require_contains(module_text, "Toolbox.Questlines.GetQuestTabModel", "encounter journal uses quest tab model api")
    require_contains(module_text, "Toolbox.Questlines.GetQuestLinesForSelection", "encounter journal uses selection questline query api")
    require_contains(module_text, "Toolbox.Questlines.GetQuestListByQuestLineID", "encounter journal uses questline task list api")
    require_contains(module_text, "Toolbox.Questlines.GetQuestDetailByID", "encounter journal uses quest detail api")
    if "Toolbox.Questlines.GetExpansionTree" in module_text:
        raise AssertionError("encounter journal should not fallback to legacy GetExpansionTree api")
    require_contains(module_text, "selectedKind", "encounter journal quest tab uses selection state machine")
    require_contains(module_text, "leftTree", "encounter journal quest tab has left tree container")
    require_contains(module_text, "rightContent", "encounter journal quest tab has right content container")
    require_contains(module_text, "EJ_QUESTLINE_TREE_LABEL", "encounter journal renders questline tab label")
    require_contains(module_text, "if journalFrame and type(journalFrame.Tabs) == \"table\" then", "encounter journal reads native root tabs from encounter journal tabs list")
    if "_G.EncounterJournalRaidTab" in module_text or "_G.EncounterJournalTutorialsTab" in module_text:
        raise AssertionError("encounter journal should not fallback raid/tutorial mapping to explicit global names")
    if "_G.EncounterJournalTab2" in module_text or "_G.EncounterJournalTab3" in module_text or '_G[\"EncounterJournalTab\" .. tabIndex]' in module_text:
        raise AssertionError("encounter journal should not use generic EncounterJournalTabN fallback slots")
    require_contains(module_text, 'rootTabButton:SetPoint("LEFT", previousTab, "RIGHT", 3, 0)', "encounter journal rebuilds bottom tab chain with fixed spacing")
    require_contains(module_text, 'rootTabButton:SetPoint("TOPLEFT", self.hostJournalFrame, "BOTTOMLEFT", 11, 2)', "encounter journal reanchors first visible root tab to default origin")
    require_contains(module_text, "PanelTabButtonTemplate", "encounter journal quest tab uses tab template")
    require_contains(module_text, "hookVanillaTabsOnce", "encounter journal synchronizes with native tab switches")
    require_contains(module_text, "local canShow = treeEnabled and journalShown", "encounter journal quest tab visibility bound to journal page")
    require_contains(module_text, "EJ_HideNonInstancePanels", "encounter journal hides non-instance native panels when showing quest tab")
    require_contains(module_text, "hideNativeRootChrome", "encounter journal has a dedicated native chrome hide step for quest tab")
    require_contains(module_text, "EncounterJournal_HideGreatVaultButton", "encounter journal hides journeys-only great vault button when showing quest tab")
    require_contains(module_text, "self.hostJournalFrame.navBar", "encounter journal hides native navigation bar when showing quest tab")
    require_contains(module_text, "self.hostJournalFrame.searchBox", "encounter journal hides native search box when showing quest tab")
    require_contains(module_text, "self.hostJournalFrame.JourneysFrame", "encounter journal hides journeys frame when showing quest tab")
    require_contains(module_text, "deselectAllNativeTabs", "encounter journal clears native tab selected visuals when quest tab is active")
    require_contains(module_text, "pendingNativeSelection", "encounter journal tracks native tab transition intent to avoid redundant restores")
    require_contains(module_text, "buildDefaultRootTabOrderIds", "encounter journal builds default root tab order ids dynamically")
    require_contains(module_text, "if #defaultOrderIds == 0 then\n    return { QUEST_ROOT_TAB_ID }", "encounter journal default order does not synthesize native ids when tabs are unavailable")
    require_contains(module_text, "getRootTabHiddenIdsTable", "encounter journal reads root tab hidden ids config")
    require_contains(module_text, "getConfiguredRootTabOrderIds", "encounter journal reads root tab order ids config")
    require_contains(module_text, "buildEffectiveRootTabOrderIds", "encounter journal normalizes configured root tab order ids")
    require_contains(module_text, "local defaultOrderIds = buildDefaultRootTabOrderIds() -- 当前客户端可用的默认顺序", "encounter journal reset order uses runtime default order builder")
    require_contains(module_text, "resolveNativeRootTabId", "encounter journal maps native tab buttons to numeric ids")
    require_contains(module_text, "readRootTabDisplayName", "encounter journal reads tab names dynamically at runtime")
    require_contains(module_text, "buildRootTabDisplayNameById", "encounter journal builds root tab id-name map for settings")
    require_contains(module_text, "setNativeRootTabShown", "encounter journal applies show/hide to native root tabs via config")
    require_contains(module_text, "local shouldShow = not hiddenByConfig", "encounter journal root tab visibility is driven by config state")
    if "visibleByBlizzard and not hiddenByConfig" in module_text:
        raise AssertionError("encounter journal root tab visibility should not be gated by previous frame shown state")
    require_contains(module_text, "QUEST_ROOT_TAB_ID", "encounter journal has fixed custom quest root tab id")
    require_contains(module_text, "shouldShowQuestTab = isQuestlineTreeEnabled() and rootTabHiddenIds[QUEST_ROOT_TAB_ID] ~= true", "encounter journal supports hiding quest tab through id config")
    require_contains(module_text, "EJ_ROOT_TAB_SETTINGS_TITLE", "encounter journal settings exposes root tab order section")
    require_contains(module_text, "moveRootTabByIndex", "encounter journal settings supports row move actions")
    require_contains(module_text, "rowFrame:RegisterForDrag(\"LeftButton\")", "encounter journal settings enables mouse drag reorder")
    require_contains(module_text, "rootTabListScrollFrame", "encounter journal settings uses a dedicated scroll frame for tab rows")
    require_contains(module_text, "rootTabHiddenIds[currentRootTabId] = visibleChecked and nil or true", "encounter journal settings writes per-id tab visibility flags")
    require_contains(module_text, "showDragPreview(", "encounter journal settings shows drag preview while reordering rows")
    require_contains(module_text, "updateDragPreviewPosition()", "encounter journal settings updates drag preview position with cursor")
    require_contains(module_text, "dragRowFrame:SetAlpha(0.45)", "encounter journal settings fades dragged source row")
    require_contains(module_text, "hideDragPreview()", "encounter journal settings hides drag preview after drop")
    require_contains(module_text, "rootStateStrategies", "encounter journal uses root-state strategy pattern for tab surface switching")
    require_contains(module_text, "function QuestlineTreeView:resolveRootState(", "encounter journal resolves target root state before applying strategy")
    require_contains(module_text, "function QuestlineTreeView:applyRootState(", "encounter journal applies root-state strategy through a single entry")
    require_contains(module_text, "previousRootState == \"quest\"", "encounter journal restores native tab only on quest->native transition")
    require_contains(module_text, "currentRootState == \"native\"", "encounter journal guards native restore by target state")
    require_contains(module_text, "UIPanelScrollFrameTemplate", "encounter journal quest tree uses scrollable container")
    require_contains(module_text, "self.scrollFrame:SetScrollChild(self.scrollChild)", "encounter journal quest tree binds scroll child")
    require_contains(module_text, "collapseState[rowData.collapseKey]", "encounter journal quest tree writes collapsed state on row click")
    if 'CreateFrame("Button", "ToolboxEJQuestlineTab", infoFrame, "UIPanelButtonTemplate")' in module_text:
        raise AssertionError("questline entry should be a tab template, not a plain panel button template")


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
