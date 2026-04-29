from pathlib import Path
import sys
import json


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


def read_encounter_journal_bundle_text() -> str:
    paths = [
        ("Toolbox", "Modules", "EncounterJournal.lua"),
        ("Toolbox", "Modules", "EncounterJournal", "Shared.lua"),
        ("Toolbox", "Modules", "EncounterJournal", "DetailEnhancer.lua"),
        ("Toolbox", "Modules", "EncounterJournal", "LockoutOverlay.lua"),
    ]
    texts = []
    for parts in paths:
        require_file(*parts)
        texts.append(read_text(*parts))
    return "\n".join(texts)


def extract_tagged_header_metadata(text: str) -> dict[str, str]:
    header_start = text.find("--[[")
    header_end = text.find("]]", header_start + 4)
    if header_start != 0 or header_end <= header_start:
        raise AssertionError("missing tagged header block at file start")
    header_text = text[header_start : header_end + 2]
    metadata: dict[str, str] = {}
    for raw_line in header_text.splitlines():
        line_text = raw_line.strip()
        if not line_text.startswith("@"):
            continue
        key_text, _, value_text = line_text.partition(" ")
        metadata[key_text[1:]] = value_text.strip()
    return metadata


def validate_settings_host() -> None:
    text = read_text("Toolbox", "UI", "SettingsHost.lua")
    for needle, label in [
        ("RegisterCanvasLayoutCategory", "settings category api"),
        ("RegisterCanvasLayoutSubcategory", "settings subcategory api"),
        ("BuildLeafPage", "leaf page builder"),
        ("BuildModuleSection", "module section builder"),
        ("BuildAboutPage", "about page builder"),
        ("BuildModulePrimaryControls", "module primary controls builder"),
        ("BuildModuleSecondaryControls", "module secondary controls builder"),
        ("GetPreferredLeafPageKey", "preferred leaf page helper"),
        ("OpenToPageKey", "open to page helper"),
        ('key = "general"', "general leaf page"),
        ('key = "interface"', "interface leaf page"),
        ('key = "map"', "map leaf page"),
        ('key = "quest"', "quest leaf page"),
        ('key = "encounter_journal"', "encounter journal leaf page"),
        ('key = "about"', "about leaf page"),
        ("Toolbox.SettingsHost:Open()", "settings open function"),
        ("Toolbox.GameMenu_Init()", "game menu init function"),
    ]:
        require_contains(text, needle, label)

    if "BuildDungeonRaidDirectorySection" in text:
        raise AssertionError("legacy directory section builder should be removed from SettingsHost")
    if "BuildPreviewSection" in text:
        raise AssertionError("settings overview preview section builder should be removed from SettingsHost")
    if "SETTINGS_PREVIEW_" in text:
        raise AssertionError("settings overview preview locale references should be removed from SettingsHost")
    for removed_needle, removed_label in [
        ("BuildOverviewPage", "legacy overview page builder"),
        ("BuildModulePage", "legacy module page builder"),
        ("BuildModuleSubPage", "legacy module subpage builder"),
        ("BuildOverviewModuleList", "legacy overview module list builder"),
        ("module.GetSettingsPages", "legacy module extra page registration"),
        ('ShowStandalonePageByKey("overview")', "legacy overview standalone open"),
    ]:
        if removed_needle in text:
            raise AssertionError(f"{removed_label} should be removed from SettingsHost")


def validate_config() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "Config.lua")
    for needle, label in [
        ('settingsLastLeafPage = "general"', "settings preferred leaf page default"),
        ("chat_notify = {", "chat_notify defaults"),
        ("mover = {", "mover defaults"),
        ("blizzardDragHitMode", "mover hit mode default"),
        ("allowDragInCombat", "mover combat drag default"),
        ("micromenu_panels = {", "micromenu defaults (legacy)"),
        ("tooltip_anchor = {", "tooltip defaults"),
        ("encounter_journal = {", "encounter journal module defaults"),
        ("mountFilterEnabled = true", "encounter journal mount filter default"),
        ("navigation = {", "navigation module defaults"),
        ("lastTargetUiMapID = 0", "navigation last target map default"),
        ("quest = {", "quest module defaults"),
        ("questNavModeKey = \"active_log\"", "quest mode default"),
        ("questInspectorLastQuestID = 0", "quest inspector last quest id default"),
        ("questlineTreeCollapsed = {}", "quest collapse state default"),
        ("minimap_button = {", "minimap button module defaults"),
        ("showMinimapButton", "minimap button visibility default"),
        ("minimapPos", "minimap button angle storage"),
        ("debug = false", "module debug defaults"),
    ]:
        require_contains(text, needle, label)
    if "lockoutOverlayEnabled = true" in text:
        raise AssertionError("encounter journal lockout overlay default should be removed from config defaults")
    if "detailMountOnlyEnabled = false" in text:
        raise AssertionError("encounter journal detail mount-only default should be removed from config defaults")
    if "drd.ejLockoutOverlayEnabled" in text:
        raise AssertionError("encounter journal legacy overlay migration should be removed from config")
    if "encJournalDb.lockoutOverlayEnabled = drd.ejLockoutOverlayEnabled" in text:
        raise AssertionError("encounter journal overlay migration assignment should be removed from config")
    if "encJournalDb.ejLockoutOverlayEnabled" in text:
        raise AssertionError("encounter journal legacy overlay alias cleanup should be removed from config")
    for removed_key in [
        "buttonShape = \"round\"",
        "flyoutExpand = \"vertical\"",
        "flyoutLauncherGap = 0",
        "flyoutPad = 4",
        "flyoutGap = 0",
    ]:
        if removed_key in text:
            raise AssertionError(f"minimap button removed config key should not remain: {removed_key}")
    for cleanup_needle, cleanup_label in [
        ("minimapButtonDb.buttonShape = nil", "minimap button shape cleanup"),
        ("minimapButtonDb.flyoutExpand = nil", "minimap flyout expand cleanup"),
        ("minimapButtonDb.flyoutLauncherGap = nil", "minimap flyout launcher gap cleanup"),
        ("minimapButtonDb.flyoutPad = nil", "minimap flyout pad cleanup"),
        ("minimapButtonDb.flyoutGap = nil", "minimap flyout gap cleanup"),
    ]:
        require_contains(text, cleanup_needle, cleanup_label)


def validate_module_registry() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "ModuleRegistry.lua")
    for needle, label in [
        ("settingsIntroKey", "settings intro key contract"),
        ("settingsOrder", "settings order contract"),
        ("GetSettingsPages", "extra settings page contract"),
        ("OnEnabledSettingChanged", "enabled callback contract"),
        ("OnDebugSettingChanged", "debug callback contract"),
        ("ResetToDefaultsAndRebuild", "reset callback contract"),
    ]:
        require_contains(text, needle, label)


def validate_locales() -> None:
    text = read_text("Toolbox", "Core", "Foundation", "Locales.lua")
    for needle, label in [
        ("SETTINGS_PAGE_GENERAL_TITLE", "general page title locale"),
        ("SETTINGS_PAGE_INTERFACE_TITLE", "interface page title locale"),
        ("SETTINGS_PAGE_MAP_TITLE", "map page title locale"),
        ("SETTINGS_PAGE_QUEST_TITLE", "quest page title locale"),
        ("SETTINGS_PAGE_ENCOUNTER_JOURNAL_TITLE", "encounter journal page title locale"),
        ("SETTINGS_PAGE_ABOUT_TITLE", "about page title locale"),
        ("SETTINGS_ABOUT_TITLE", "about title locale"),
        ("SETTINGS_MODULE_ENABLE", "shared enable locale"),
        ("SETTINGS_MODULE_DEBUG", "shared debug locale"),
        ("SETTINGS_MODULE_RESET_REBUILD", "shared reset locale"),
        ("MODULE_ENCOUNTER_JOURNAL", "encounter journal module locale"),
        ("MODULE_ENCOUNTER_JOURNAL_INTRO", "encounter journal intro locale"),
        ("MODULE_NAVIGATION", "navigation module locale"),
        ("MODULE_NAVIGATION_INTRO", "navigation intro locale"),
        ("NAVIGATION_WORLD_MAP_BUTTON", "navigation world map button locale"),
        ("MODULE_QUEST", "quest module locale"),
        ("MODULE_QUEST_INTRO", "quest module intro locale"),
        ("EJ_MOUNT_FILTER_LABEL", "encounter journal mount filter locale"),
        ("EJ_QUEST_INSPECTOR_INPUT_LABEL", "encounter journal inspector input label locale"),
        ("EJ_QUEST_INSPECTOR_QUERY_BUTTON", "encounter journal inspector query button locale"),
        ("EJ_QUEST_INSPECTOR_RESULT_TITLE", "encounter journal inspector result title locale"),
        ("EJ_QUEST_INSPECTOR_EMPTY", "encounter journal inspector empty locale"),
        ("EJ_QUEST_INSPECTOR_INVALID_ID", "encounter journal inspector invalid id locale"),
        ("EJ_ROOT_TAB_SETTINGS_TITLE", "encounter journal root tab settings title locale"),
        ("EJ_ROOT_TAB_SETTINGS_HINT", "encounter journal root tab settings hint locale"),
        ("EJ_ROOT_TAB_SETTINGS_VISIBLE", "encounter journal root tab settings visible locale"),
        ("EJ_ROOT_TAB_SETTINGS_RESET_ORDER", "encounter journal root tab settings reset locale"),
        ("EJ_ROOT_TAB_NAME_UNKNOWN_FMT", "encounter journal root tab unknown name format locale"),
        ("MINIMAP_FLYOUT_QUEST", "quest flyout locale"),
        ("MINIMAP_FLYOUT_QUEST_TOOLTIP", "quest flyout tooltip locale"),
        ("MODULE_MINIMAP_BUTTON", "minimap button module locale"),
    ]:
        require_contains(text, needle, label)
    if "SETTINGS_PREVIEW_" in text:
        raise AssertionError("preview-only settings locale keys should be removed from Locales")
    for removed_key in [
        "DRD_MOUNT_FILTER_ENABLED",
        "EJ_LOCKOUT_OVERLAY_LABEL",
        "EJ_DETAIL_MOUNT_ONLY_LABEL",
        "EJ_DETAIL_MOUNT_ONLY_HINT",
        "MINIMAP_PREVIEW_SECTION",
        "MINIMAP_PREVIEW_DRAG_HINT",
        "MINIMAP_PREVIEW_DRAG_TOOLTIP_LAUNCHER_GAP",
        "MINIMAP_PREVIEW_DRAG_TOOLTIP_PAD",
        "MINIMAP_PREVIEW_DRAG_TOOLTIP_ENTRY_GAP",
        "MINIMAP_FLYOUT_EXPAND_LABEL",
        "MINIMAP_FLYOUT_EXPAND_VERTICAL",
        "MINIMAP_FLYOUT_EXPAND_HORIZONTAL",
        "MINIMAP_FLYOUT_POOL_HINT",
        "MINIMAP_FLYOUT_DROP_HERE",
        "MINIMAP_FLYOUT_ADD_ALL",
        "MINIMAP_SHAPE_LABEL",
        "MINIMAP_SHAPE_ROUND",
        "MINIMAP_SHAPE_SQUARE",
    ]:
        if removed_key in text:
            raise AssertionError(f"encounter journal removed locale key should not remain: {removed_key}")


def validate_modules() -> None:
    files = [
        "ChatNotify.lua",
        "EncounterJournal.lua",
        "Navigation.lua",
        "Quest.lua",
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

        if file_name == "Quest.lua" and "GetSettingsPages = function()" in text:
            raise AssertionError("Quest module should no longer register a standalone settings subpage")

    require_file("Toolbox", "Modules", "MicroMenuPanels.lua")
    micromenu = read_text("Toolbox", "Modules", "MicroMenuPanels.lua")
    require_contains(micromenu, "Toolbox.Mover.BlizzardPanelsRefresh", "micromenu refresh delegate to mover")


def validate_toc() -> None:
    text = read_text("Toolbox", "Toolbox.toc")
    require_contains(text, "Core\\Foundation\\Runtime.lua", "runtime adapter toc entry")
    require_contains(text, "Core\\API\\Navigation.lua", "navigation api toc entry")
    require_contains(text, "Data\\NavigationMapNodes.lua", "navigation map nodes toc entry")
    require_contains(text, "Data\\NavigationMapAssignments.lua", "navigation map assignments toc entry")
    require_contains(text, "Data\\NavigationInstanceEntrances.lua", "navigation instance entrances toc entry")
    require_contains(text, "Data\\NavigationTaxiEdges.lua", "navigation taxi edges toc entry")
    require_contains(text, "Data\\NavigationRouteEdges.lua", "navigation unified route edges toc entry")
    if "Data\\NavigationManualEdges.lua" in text:
        raise AssertionError("navigation manual edges must not be loaded from TOC")
    require_contains(text, "Modules\\EncounterJournal\\Shared.lua", "encounter journal shared toc entry")
    require_contains(text, "Modules\\EncounterJournal\\DetailEnhancer.lua", "encounter journal detail enhancer toc entry")
    require_contains(text, "Modules\\EncounterJournal\\LockoutOverlay.lua", "encounter journal lockout overlay toc entry")
    require_contains(text, "Modules\\EncounterJournal.lua", "encounter journal module toc entry")
    require_contains(text, "Modules\\Navigation\\Shared.lua", "navigation shared toc entry")
    require_contains(text, "Modules\\Navigation\\RouteBar.lua", "navigation routebar toc entry")
    require_contains(text, "Modules\\Navigation\\WorldMap.lua", "navigation worldmap toc entry")
    require_contains(text, "Modules\\Navigation.lua", "navigation module toc entry")
    require_contains(text, "Modules\\Quest\\Shared.lua", "quest shared toc entry")
    require_contains(text, "Modules\\Quest\\QuestNavigation.lua", "quest navigation toc entry")
    require_contains(text, "Modules\\Quest.lua", "quest module toc entry")
    require_contains(text, "Modules\\MinimapButton.lua", "minimap button module toc entry")
    require_contains(text, "## Interface: 120000, 120001", "retail toc compatibility range")


def validate_encounter_journal_regressions() -> None:
    text = read_encounter_journal_bundle_text()
    # 调度器应通过 Runtime 统一走可取消句柄，避免 C_Timer.After 防抖失效导致并发刷新。
    require_contains(text, "Runtime.NewTimer", "encounter journal uses runtime cancellable timer")
    # 关闭叠加后应主动清理已绘制文本，避免残留显示。
    require_contains(text, "function LockoutOverlay:clearAllFrames()", "encounter journal clear overlay helper")
    require_contains(text, "self:clearAllFrames()", "encounter journal clears overlays when disabled")
    # 模块禁用后应停用高频更新事件，避免后台空调度。
    require_contains(text, 'eventFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")', "encounter journal unregisters lockout event when disabled")
    require_contains(text, 'eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")', "encounter journal re-registers lockout event when enabled")
    require_contains(text, "if isModuleEnabled() then", "encounter journal guards update callbacks by enabled state")
    # 列表 hook 未触发时也要主动创建“仅坐骑”按钮，避免入口缺失。
    require_contains(text, "local function refreshAll()", "encounter journal defines unified refresh path")
    require_contains(text, "MountFilter:createUI()", "encounter journal creates mount filter ui in unified refresh path")
    require_contains(text, "local function refreshAfterHookInit()", "encounter journal defines deterministic post-hook init refresh helper")
    require_contains(
        text,
        'if event == "ADDON_LOADED" and name == "Blizzard_EncounterJournal" then\n      self:UnregisterEvent("ADDON_LOADED")\n      initHooks()\n      refreshAfterHookInit()',
        "encounter journal runs deterministic refresh right after hook init on addon loaded",
    )
    require_contains(
        text,
        'if Runtime.IsAddOnLoaded("Blizzard_EncounterJournal") then\n    initHooks()\n    refreshAfterHookInit()',
        "encounter journal runs deterministic refresh through runtime adapter when ej was already loaded",
    )
    require_contains(text, "MountFilter:createUI()", "encounter journal creates mount filter ui on EJ OnShow")
    require_contains(text, "MountFilter:updateVisibility()", "encounter journal refreshes mount filter visibility on EJ OnShow")
    require_contains(text, "return Toolbox.EJ.IsRaidOrDungeonInstanceListTab() == true", "encounter journal mount filter visibility delegates to ej domain api")
    require_contains(text, "local anchorTarget = instSel.ExpansionDropdown or instSel", "encounter journal mount filter anchor falls back when expansion dropdown missing")
    require_contains(text, "if Toolbox.EJ.IsRaidOrDungeonInstanceListTab() ~= true then", "encounter journal lockout overlay is gated by raid or dungeon tab")
    require_contains(text, "moduleDb.mountFilterEnabled = btn:GetChecked() and true or false", "encounter journal mount filter button persists state")
    if "DRD_MOUNT_FILTER_ENABLED" in text:
        raise AssertionError("encounter journal settings page should not keep mount filter setting label")
    if "lockoutOverlayEnabled" in text:
        raise AssertionError("encounter journal runtime should not keep overlay toggle setting references")
    if "detailMountOnlyEnabled" in text:
        raise AssertionError("encounter journal runtime should not keep detail mount-only setting references")
    if "applyMountOnlyFilter" in text:
        raise AssertionError("encounter journal detail mount-only filter implementation should be removed")
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
    require_contains(ej_api_text, "if selectedRootTabID ~= dungeonTabID and selectedRootTabID ~= raidTabID then", "ej domain api compares selected root tab id against dungeon and raid ids before continuing")
    require_contains(ej_api_text, "local instanceSelectFrame = encounterJournalFrame.instanceSelect", "ej domain api checks the live instanceSelect frame instead of only root tab state")
    require_contains(ej_api_text, "local listShownSuccess, listShown = pcall(function() return instanceSelectFrame:IsShown() end)", "ej domain api verifies instanceSelect visibility before treating the page as list state")


def validate_mover_regressions() -> None:
    text = read_text("Toolbox", "Modules", "Mover.lua")
    # RegisterFrame 在模块关闭时也要登记，便于后续重新开启自动生效。
    require_contains(text, "pushAddonRegistry(frame, key, opts)", "mover pushes addon registry in RegisterFrame")
    require_contains(text, "if db.enabled == false then", "mover register disabled guard")
    if text.find("pushAddonRegistry(frame, key, opts)") > text.find("if db.enabled == false then"):
        raise AssertionError("mover should push addon registry before disabled guard")
    # 模块关闭时除暴雪面板外，还要关闭已登记自定义 frame 的拖动行为。
    require_contains(text, "disableAddonRegisteredFrames()", "mover disables addon-registered drags when disabled")
    # 大地图顶部导航条位于 TitleCanvasSpacerFrame 内，不能直接把整块 Spacer 注册成拖动面，否则会吞掉导航点击。
    require_contains(text, "ensureWorldMapDragHandle", "mover uses a dedicated world map drag handle")
    if "return frame.TitleCanvasSpacerFrame" in text:
        raise AssertionError("mover should not bind drag directly to WorldMapFrame.TitleCanvasSpacerFrame")
    require_contains(
        text,
        'if key == "EncounterJournal" or key == "MerchantFrame" then',
        "mover special-cases encounter journal and merchant frame drag handling",
    )
    require_contains(text, 'mode = HIT_TITLEBAR', "mover forces encounter journal and merchant frame back to titlebar drag mode")


def validate_tooltip_anchor_regressions() -> None:
    module_text = read_text("Toolbox", "Modules", "TooltipAnchor.lua")
    core_text = read_text("Toolbox", "Core", "API", "Tooltip.lua")
    # 设置页应暴露 follow 模式，和 locale 文案保持一致。
    require_contains(module_text, 'makeMode("follow"', "tooltip anchor follow mode option")
    # 核心逻辑应继续识别 follow 模式，并恢复全局默认锚点 hook。
    require_contains(
        core_text,
        'mode ~= "cursor" and mode ~= "follow"',
        "tooltip core treats follow mode as active cursor hook mode",
    )
    require_contains(
        core_text,
        'hooksecurefunc("GameTooltip_SetDefaultAnchor"',
        "tooltip core registers global GameTooltip_SetDefaultAnchor hook",
    )
    require_contains(
        core_text,
        'tooltip:SetOwner(ownerFrame, "ANCHOR_CURSOR_LEFT", offsetX, offsetY)',
        "tooltip core overrides owner to cursor anchor",
    )
    if "UberTooltips" in core_text:
        raise AssertionError("tooltip core should not keep UberTooltips runtime logic after rollback")


def validate_minimap_button_regressions() -> None:
    text = read_text("Toolbox", "Modules", "MinimapButton.lua")
    # flyout 目录排序应先看 order，再按 id 兜底，避免声明顺序与显示顺序不一致。
    require_contains(text, "local leftOrder = tonumber(leftDef and leftDef.order) or 100", "minimap flyout order sort left")
    require_contains(text, "local rightOrder = tonumber(rightDef and rightDef.order) or 100", "minimap flyout order sort right")
    require_contains(text, "if leftOrder ~= rightOrder then", "minimap flyout order priority compare")
    require_contains(text, "return leftId < rightId", "minimap flyout order tie-break by id")
    for removed_needle, removed_label in [
        ("getButtonShape()", "minimap button shape helper"),
        ("getFlyoutExpand()", "minimap flyout expand helper"),
        ("previewWrap", "minimap preview wrapper"),
        ("previewLauncher", "minimap preview launcher"),
        ("previewFlyout", "minimap preview flyout"),
        ("flyoutPool", "minimap flyout pool"),
        ("flyoutDropBar", "minimap flyout drop bar"),
        ("flyoutAddAllBtn", "minimap flyout add-all button"),
        ("shapeRound", "minimap round shape checkbox"),
        ("shapeSquare", "minimap square shape checkbox"),
        ("expandV", "minimap vertical expand checkbox"),
        ("expandH", "minimap horizontal expand checkbox"),
        ("MINIMAP_PREVIEW_", "minimap preview locale usage"),
        ("MINIMAP_FLYOUT_EXPAND_", "minimap expand locale usage"),
        ("MINIMAP_SHAPE_", "minimap shape locale usage"),
        ("MINIMAP_FLYOUT_POOL_HINT", "minimap flyout pool hint locale usage"),
        ("MINIMAP_FLYOUT_DROP_HERE", "minimap flyout drop bar locale usage"),
        ("MINIMAP_FLYOUT_ADD_ALL", "minimap flyout add-all locale usage"),
    ]:
        if removed_needle in text:
            raise AssertionError(f"{removed_label} should be removed from MinimapButton")


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
    module_text = read_encounter_journal_bundle_text()

    # 领域 API：详情页锁定标签所需接口。
    require_contains(api_text, "function Toolbox.EJ.GetSelectedDifficultyID(", "ej api selected difficulty helper")
    require_contains(api_text, "function Toolbox.EJ.GetLockoutForInstanceAndDifficulty(", "ej api difficulty lockout helper")

    # 详情页增强：仅保留标题后锁定文本。
    require_contains(module_text, "EncounterJournal_LootUpdate", "encounter journal hooks detail loot update")
    require_contains(module_text, "EJ_SetDifficulty", "encounter journal hooks difficulty switch")
    require_contains(module_text, "EJ_DETAIL_LOCKOUT_FMT", "encounter journal detail lockout locale key")

    # 本地化：仅保留“重置：xxxx”文案键。
    require_contains(locale_text, "EJ_DETAIL_LOCKOUT_FMT", "locale detail lockout format")
    require_contains(locale_text, "EJ_DETAIL_LOCKOUT_NONE", "locale detail lockout empty")
    if "detailMountOnlyEnabled" in config_text:
        raise AssertionError("encounter journal detail mount-only setting should be removed from config")
    if "EJ_DETAIL_MOUNT_ONLY_LABEL" in locale_text or "EJ_DETAIL_MOUNT_ONLY_HINT" in locale_text:
        raise AssertionError("encounter journal detail mount-only locale keys should be removed")
    if "detailMountOnlyEnabled" in module_text or "applyMountOnlyFilter" in module_text:
        raise AssertionError("encounter journal detail mount-only behavior should be removed from module code")


def validate_encounter_journal_micro_button_tooltip_lockouts_feature() -> None:
    module_text = read_encounter_journal_bundle_text()

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
    module_text = "\n".join(
        [
            read_text("Toolbox", "Modules", "Quest.lua"),
            read_text("Toolbox", "Modules", "Quest", "Shared.lua"),
            read_text("Toolbox", "Modules", "Quest", "QuestNavigation.lua"),
        ]
    )
    data_text = read_text("Toolbox", "Data", "InstanceQuestlines.lua")
    require_file("Toolbox", "Data", "InstanceQuestlines.lua")
    require_file("Toolbox", "Core", "API", "QuestlineProgress.lua")
    questline_api_text = read_text("Toolbox", "Core", "API", "QuestlineProgress.lua")

    require_contains(toc_text, "Data\\InstanceQuestlines.lua", "questline data toc entry")
    require_contains(toc_text, "Core\\API\\QuestlineProgress.lua", "questline api toc entry")
    require_contains(toc_text, "Modules\\Quest\\QuestNavigation.lua", "quest module quest navigation toc entry")
    require_contains(toc_text, "Modules\\Quest.lua", "quest module toc entry")

    require_contains(config_text, "questlineTreeEnabled", "encounter journal questline tree setting default")
    require_contains(config_text, "questNavExpansionID", "quest navigation expansion default")
    require_contains(config_text, "questNavModeKey", "quest navigation mode default")
    require_contains(config_text, "questNavSelectedMapID", "quest navigation selected map default")
    require_contains(config_text, "questNavExpandedQuestLineID", "quest navigation expanded questline default")
    require_contains(config_text, "quest = {", "quest module config bucket")

    require_contains(locale_text, "EJ_QUESTLINE_TREE_LABEL", "questline tree label locale")
    require_contains(locale_text, "EJ_QUESTLINE_TREE_EMPTY", "questline tree empty locale")
    require_contains(locale_text, "EJ_QUESTLINE_TREE_TYPE_MAP", "questline tree map type locale")
    require_contains(locale_text, "EJ_QUESTLINE_PROGRESS_FMT", "questline tree progress locale")
    require_contains(locale_text, "EJ_QUEST_EXPANSION_UNKNOWN_FMT", "questline expansion fallback locale")
    require_contains(locale_text, "QUEST_VIEW_TAB_ACTIVE", "quest current-task tab locale")
    require_contains(locale_text, "QUEST_VIEW_TAB_QUESTLINE", "quest questline tab locale")
    require_contains(locale_text, "QUEST_VIEW_RECENT_TOGGLE_COLLAPSE", "quest recent-collapse locale")

    require_contains(questline_api_text, "Toolbox.Questlines", "questline namespace")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetChainProgress(", "questline chain progress api")
    require_contains(questline_api_text, "function Toolbox.Questlines.ValidateInstanceQuestlinesData(", "questline strict validation api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestTabModel(", "questline quest tab model api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestNavigationModel(", "questline navigation model api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestListByQuestLineID(", "questline list api")
    require_contains(questline_api_text, "function Toolbox.Questlines.GetQuestDetailByID(", "quest detail api")
    if "function Toolbox.Questlines.GetExpansionTree(" in questline_api_text:
        raise AssertionError("questline api should not keep legacy GetExpansionTree compatibility")
    if "function Toolbox.Questlines.GetInstanceTree(" in questline_api_text:
        raise AssertionError("questline api should not keep legacy GetInstanceTree compatibility")
    if (
        "schemaVersion = 3" not in data_text
        and "schemaVersion = 4" not in data_text
        and "schemaVersion = 5" not in data_text
        and "schemaVersion = 6" not in data_text
        and "schemaVersion = 7" not in data_text
        and "schemaVersion = 8" not in data_text
        and "schemaVersion = 9" not in data_text
    ):
        raise AssertionError("missing questline data schema version: expected schemaVersion = 3, 4, 5, 6, 7, 8 or 9")
    require_contains(data_text, 'sourceMode = "live"', "questline data source mode")
    require_contains(data_text, "generatedAt = ", "questline data generated timestamp")
    require_contains(data_text, "quests = {", "questline data quests table")
    require_contains(data_text, "questLines = {", "questline data questlines table")
    if "questLineQuestIDs = {" not in data_text and "questLineXQuest = {" not in data_text and "QuestIDs = {" not in data_text:
        raise AssertionError("missing questline data questline relation block")
    if "ExpansionID =" not in data_text and "expansions = {" not in data_text:
        raise AssertionError("missing questline expansion grouping field")
    require_contains(questline_api_text, "function Toolbox.Questlines.SetDataOverride(", "questline mock data override api")

    require_contains(module_text, "QuestlineTreeView", "quest module questline tree view")
    require_contains(module_text, "questlineTreeEnabled", "quest module questline tree setting usage")
    require_contains(module_text, "Toolbox.Questlines.GetQuestNavigationModel", "quest module uses quest navigation model api")
    require_contains(module_text, "Toolbox.Questlines.GetQuestListByQuestLineID", "quest module uses questline task list api")
    require_contains(module_text, "Toolbox.Questlines.GetQuestDetailByID", "quest module uses quest detail api")
    require_contains(module_text, "selectedExpansionID", "quest module keeps selected expansion state")
    require_contains(module_text, "selectedModeKey", "quest module keeps selected mode state")
    require_contains(module_text, "breadcrumbButtons", "quest module has breadcrumb navigation buttons")
    require_contains(module_text, "detailPopupFrame", "quest module uses popup for quest detail")
    require_contains(module_text, "function QuestlineTreeView:getBottomTabModeKeys(", "quest module exposes bottom tab mode list")
    require_contains(module_text, "\"active_log\"", "quest module keeps active_log mode")
    require_contains(module_text, "\"map_questline\"", "quest module keeps map_questline mode")
    if "quest_type" in module_text:
        raise AssertionError("quest module should not keep quest_type mode")
    require_contains(module_text, "if self.selectedModeKey == \"active_log\" then", "quest active_log branch")
    require_contains(module_text, "getActiveLogRootText(localeTable)", "quest active_log root breadcrumb text")
    require_contains(module_text, "getQuestlineRootText(localeTable)", "quest questline root breadcrumb text")
    require_contains(module_text, "activeLogCurrentPanel", "quest active_log current panel")
    require_contains(module_text, "activeLogRecentPanel", "quest active_log recent panel")
    require_contains(module_text, "activeLogRecentToggleButton", "quest active_log recent toggle")
    require_contains(module_text, "Toolbox.Quest.OpenMainFrame", "quest module exposes open api")


def validate_generated_data_contract_headers() -> None:
    expected_headers = {
        "InstanceMapIDs.lua": "instance_map_ids",
        "InstanceDrops_Mount.lua": "instance_drops_mount",
        "InstanceQuestlines.lua": "instance_questlines",
    }
    for file_name, contract_id in expected_headers.items():
        text = read_text("Toolbox", "Data", file_name)
        metadata = extract_tagged_header_metadata(text)
        require_contains(text, "@generated_at", f"{file_name} generated_at tag")
        require_contains(text, "@generated_by", f"{file_name} generated_by tag")
        require_contains(text, "@contract_snapshot", f"{file_name} contract_snapshot tag")
        if metadata.get("contract_id") != contract_id:
            raise AssertionError(f"{file_name} contract_id mismatch: expected {contract_id}")
        expected_contract_file = f"WoWPlugin/DataContracts/{contract_id}.json"
        if metadata.get("contract_file") != expected_contract_file:
            raise AssertionError(f"{file_name} contract_file mismatch: expected {expected_contract_file}")
        contract_path = ROOT / "DataContracts" / f"{contract_id}.json"
        contract_data = json.loads(contract_path.read_text(encoding="utf-8"))
        expected_schema_version = str(contract_data["contract"]["schema_version"])
        if metadata.get("schema_version") != expected_schema_version:
            raise AssertionError(f"{file_name} schema_version mismatch")
        if metadata.get("data_source") != "wow.db":
            raise AssertionError(f"{file_name} data_source mismatch")


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
    validate_generated_data_contract_headers()
    print("OK: settings subcategories structure validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
