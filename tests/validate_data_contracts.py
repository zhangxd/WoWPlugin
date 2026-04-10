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
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read_text(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text(encoding="utf-8")


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


def main() -> int:
    for contract_id, expected_meta in EXPECTED_GENERATED_CONTRACTS.items():
        validate_contract(contract_id, expected_meta)
    print("OK: data contracts validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
