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
        ("dungeon_raid_directory = {", "directory module defaults"),
        ("ej_mount_filter = {", "ej module defaults"),
        ("minimap_button = {", "minimap button module defaults"),
        ("showMinimapButton", "minimap button visibility default"),
        ("minimapPos", "minimap button angle storage"),
        ("debug = false", "module debug defaults"),
        ("debugChat", "legacy debug migration reference"),
        ("dungeonRaidDirectoryDebugChat", "legacy directory debug migration reference"),
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
        ("MODULE_DUNGEON_RAID_DIRECTORY", "directory module locale"),
        ("MODULE_EJ_MOUNT_FILTER", "ej module locale"),
        ("MODULE_MINIMAP_BUTTON", "minimap button module locale"),
    ]:
        require_contains(text, needle, label)


def validate_modules() -> None:
    files = [
        "ChatNotify.lua",
        "MinimapButton.lua",
        "Mover.lua",
        "TooltipAnchor.lua",
        "EJMountFilter.lua",
        "DungeonRaidDirectory.lua",
    ]
    for file_name in files:
        require_file("Toolbox", "Modules", file_name)
        text = read_text("Toolbox", "Modules", file_name)
        for needle, label in [
            ("settingsIntroKey", "settings intro key"),
            ("settingsOrder", "settings order"),
            ("OnEnabledSettingChanged", "enabled callback"),
            ("OnDebugSettingChanged", "debug callback"),
            ("ResetToDefaultsAndRebuild", "reset callback"),
        ]:
            require_contains(text, needle, f"{file_name} {label}")

    require_file("Toolbox", "Modules", "MicroMenuPanels.lua")
    micromenu = read_text("Toolbox", "Modules", "MicroMenuPanels.lua")
    require_contains(micromenu, "Toolbox.Mover.BlizzardPanelsRefresh", "micromenu refresh delegate to mover")

    ej_filter = read_text("Toolbox", "Modules", "EJMountFilter.lua")
    require_contains(ej_filter, "ensureDirectoryBuildForCurrentList", "ej filter self-heal helper")
    require_contains(ej_filter, "Toolbox.DungeonRaidDirectory.RebuildCache()", "ej filter rebuild fallback")


def validate_toc() -> None:
    text = read_text("Toolbox", "Toolbox.toc")
    require_contains(text, "Modules\\DungeonRaidDirectory.lua", "directory module toc entry")
    require_contains(text, "Modules\\MinimapButton.lua", "minimap button module toc entry")
    require_contains(text, "## Interface: 120000, 120001", "retail toc compatibility range")


def main() -> int:
    validate_settings_host()
    validate_config()
    validate_module_registry()
    validate_locales()
    validate_modules()
    validate_toc()
    print("OK: settings subcategories structure validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
