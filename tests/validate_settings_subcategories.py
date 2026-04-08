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


def main() -> int:
    validate_settings_host()
    validate_config()
    validate_module_registry()
    validate_locales()
    validate_modules()
    validate_toc()
    validate_encounter_journal_regressions()
    print("OK: settings subcategories structure validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
