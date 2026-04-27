from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS_DIR = ROOT / "DataContracts"
CONTRACT_ID_PATTERN = re.compile(r"^[a-z0-9_]+$")


EXPECTED_GENERATED_CONTRACTS = {
    "instance_map_ids": {
        "lua_file": "Toolbox/Data/InstanceMapIDs.lua",
        "lua_table": "Toolbox.Data.InstanceMapIDs",
        "root_type": "map_scalar",
    },
    "instance_drops_mount": {
        "lua_file": "Toolbox/Data/InstanceDrops_Mount.lua",
        "lua_table": "Toolbox.Data.MountDrops",
        "root_type": "map_array",
    },
    "instance_questlines": {
        "lua_file": "Toolbox/Data/InstanceQuestlines.lua",
        "lua_table": "Toolbox.Data.InstanceQuestlines",
        "root_type": "document",
    },
    "quest_type_names": {
        "lua_file": "Toolbox/Data/QuestTypeNames.lua",
        "lua_table": "Toolbox.Data.QuestTypeNames",
        "root_type": "map_scalar",
    },
    "navigation_map_nodes": {
        "lua_file": "Toolbox/Data/NavigationMapNodes.lua",
        "lua_table": "Toolbox.Data.NavigationMapNodes",
        "root_type": "document",
    },
    "navigation_map_assignments": {
        "lua_file": "Toolbox/Data/NavigationMapAssignments.lua",
        "lua_table": "Toolbox.Data.NavigationMapAssignments",
        "root_type": "document",
    },
    "navigation_instance_entrances": {
        "lua_file": "Toolbox/Data/NavigationInstanceEntrances.lua",
        "lua_table": "Toolbox.Data.NavigationInstanceEntrances",
        "root_type": "document",
    },
    "navigation_taxi_edges": {
        "lua_file": "Toolbox/Data/NavigationTaxiEdges.lua",
        "lua_table": "Toolbox.Data.NavigationTaxiEdges",
        "root_type": "document",
    },
    "navigation_route_edges": {
        "lua_file": "Toolbox/Data/NavigationRouteEdges.lua",
        "lua_table": "Toolbox.Data.NavigationRouteEdges",
        "root_type": "document",
    },
    "instance_entrances": {
        "lua_file": "Toolbox/Data/InstanceEntrances.lua",
        "lua_table": "Toolbox.Data.InstanceEntrances",
        "root_type": "document",
    },
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read_text(*parts: str) -> str:
    file_path = ROOT.joinpath(*parts)
    require(file_path.exists(), f"missing file: {file_path}")
    return file_path.read_text(encoding="utf-8")


def parse_tagged_header(text: str) -> dict[str, str]:
    header_start = text.find("--[[")
    header_end = text.find("]]", header_start + 4)
    require(header_start == 0 and header_end > header_start, "missing tagged header block at file start")
    header_text = text[header_start : header_end + 2]
    metadata: dict[str, str] = {}
    for raw_line in header_text.splitlines():
        line_text = raw_line.strip()
        if not line_text.startswith("@"):
            continue
        key_text, _, value_text = line_text.partition(" ")
        metadata[key_text[1:]] = value_text.strip()
    return metadata


def load_contract(contract_id: str) -> dict:
    contract_path = CONTRACTS_DIR / f"{contract_id}.json"
    require(contract_path.exists(), f"missing contract file: {contract_path}")
    raw_text = contract_path.read_text(encoding="utf-8")
    try:
        return json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"invalid JSON in {contract_path}: {exc}") from exc


def validate_contract(contract_id: str, expected_meta: dict[str, str]) -> None:
    data = load_contract(contract_id)
    for section_name in (
        "contract",
        "output",
        "source",
        "structure",
        "validation",
        "versioning",
    ):
        require(section_name in data, f"{contract_id}: missing top-level section {section_name}")

    contract_block = data["contract"]
    output_block = data["output"]
    structure_block = data["structure"]
    versioning_block = data["versioning"]

    require(isinstance(contract_block, dict), f"{contract_id}: contract section must be object")
    require(isinstance(output_block, dict), f"{contract_id}: output section must be object")
    require(isinstance(structure_block, dict), f"{contract_id}: structure section must be object")
    require(isinstance(versioning_block, dict), f"{contract_id}: versioning section must be object")

    require(contract_block.get("contract_id") == contract_id, f"{contract_id}: contract.contract_id mismatch")
    require(CONTRACT_ID_PATTERN.fullmatch(contract_id) is not None, f"{contract_id}: invalid contract_id format")
    require(
        contract_block.get("source_of_truth") == "WoWPlugin",
        f"{contract_id}: contract.source_of_truth must be WoWPlugin",
    )
    schema_version = contract_block.get("schema_version")
    require(isinstance(schema_version, int) and schema_version > 0, f"{contract_id}: schema_version must be positive integer")
    require(
        versioning_block.get("current_schema_version") == schema_version,
        f"{contract_id}: versioning.current_schema_version mismatch",
    )
    require(
        output_block.get("lua_file") == expected_meta["lua_file"],
        f"{contract_id}: output.lua_file mismatch",
    )
    require(
        output_block.get("lua_table") == expected_meta["lua_table"],
        f"{contract_id}: output.lua_table mismatch",
    )
    require(
        structure_block.get("root_type") == expected_meta["root_type"],
        f"{contract_id}: structure.root_type mismatch",
    )

    lua_text = read_text(*expected_meta["lua_file"].split("/"))
    header_metadata = parse_tagged_header(lua_text)
    require(header_metadata.get("contract_id") == contract_id, f"{contract_id}: lua header contract_id mismatch")
    require(
        header_metadata.get("schema_version") == str(schema_version),
        f"{contract_id}: lua header schema_version mismatch",
    )
    require(
        header_metadata.get("contract_file") == f"WoWPlugin/DataContracts/{contract_id}.json",
        f"{contract_id}: lua header contract_file mismatch",
    )
    require(header_metadata.get("contract_snapshot"), f"{contract_id}: lua header contract_snapshot missing")
    require(header_metadata.get("generated_at"), f"{contract_id}: lua header generated_at missing")
    require(header_metadata.get("generated_by"), f"{contract_id}: lua header generated_by missing")
    require(header_metadata.get("data_source") == "wow.db", f"{contract_id}: lua header data_source mismatch")


def validate_toc_loads_generated_data(expected_contracts: dict[str, dict[str, str]]) -> None:
    toc_text = read_text("Toolbox", "Toolbox.toc")
    for contract_id, expected_meta in expected_contracts.items():
        lua_file = expected_meta["lua_file"]
        if not lua_file.startswith("Toolbox/Data/"):
            continue
        toc_entry = lua_file.removeprefix("Toolbox/").replace("/", "\\")
        require(toc_entry in toc_text, f"{contract_id}: missing TOC data entry {toc_entry}")


def validate_navigation_instance_entrance_regressions() -> None:
    lua_text = read_text("Toolbox", "Data", "NavigationInstanceEntrances.lua")
    razorfen_downs_match = re.search(r"\[233\]\s*=\s*\{([^}]+)\}", lua_text)
    require(razorfen_downs_match is not None, "navigation_instance_entrances: missing Razorfen Downs journalInstanceID 233")
    razorfen_downs_row = razorfen_downs_match.group(1)
    require("Name_lang = \"剃刀高地\"" in razorfen_downs_row, "navigation_instance_entrances: Razorfen Downs name mismatch")
    require("InstanceMapID = 129" in razorfen_downs_row, "navigation_instance_entrances: Razorfen Downs instance map trace missing")
    require("TargetUiMapID = 64" in razorfen_downs_row, "navigation_instance_entrances: Razorfen Downs must target the external Thousand Needles map")
    require("TargetX = 0.762069" in razorfen_downs_row, "navigation_instance_entrances: Razorfen Downs target X mismatch")
    require("TargetY = 0.521909" in razorfen_downs_row, "navigation_instance_entrances: Razorfen Downs target Y mismatch")


def validate_instance_entrance_regressions() -> None:
    lua_text = read_text("Toolbox", "Data", "InstanceEntrances.lua")
    dire_maul_center_match = re.search(r"\[230\]\s*=\s*\{(.*?)\n\s*\},", lua_text, re.S)
    require(dire_maul_center_match is not None, "instance_entrances: missing Dire Maul center garden journalInstanceID 230")
    dire_maul_center_rows = dire_maul_center_match.group(1)
    require(
        'Source = "areapoi"' in dire_maul_center_rows,
        "instance_entrances: Dire Maul center garden must use exact areapoi source",
    )
    require(
        "AreaPoiID = 6501" in dire_maul_center_rows,
        "instance_entrances: Dire Maul center garden must keep areaPoiID 6501",
    )
    require(
        "HintUiMapID = 69" in dire_maul_center_rows,
        "instance_entrances: Dire Maul center garden must hint the Feralas uiMapID 69",
    )
    require(
        'Source = "journalinstanceentrance"' not in dire_maul_center_rows,
        "instance_entrances: Dire Maul center garden must not use split-wing journalinstanceentrance rows",
    )

    gordok_match = re.search(r"\[1277\]\s*=\s*\{(.*?)\n\s*\},", lua_text, re.S)
    require(gordok_match is not None, "instance_entrances: missing Gordok Council journalInstanceID 1277")
    gordok_rows = gordok_match.group(1)
    require(
        'Source = "journalinstanceentrance"' in gordok_rows,
        "instance_entrances: Gordok Council must keep journalinstanceentrance source",
    )


def main() -> int:
    for contract_id, expected_meta in EXPECTED_GENERATED_CONTRACTS.items():
        validate_contract(contract_id, expected_meta)
    validate_toc_loads_generated_data(EXPECTED_GENERATED_CONTRACTS)
    validate_navigation_instance_entrance_regressions()
    validate_instance_entrance_regressions()
    print("OK: data contracts validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
