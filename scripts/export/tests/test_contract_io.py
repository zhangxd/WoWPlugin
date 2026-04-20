from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.export.contract_io import load_contract, write_contract_snapshot


def build_contract(contract_id: str = "instance_map_ids") -> dict:
    return {
        "contract": {
            "contract_id": contract_id,
            "schema_version": 1,
            "summary": "test contract",
            "source_of_truth": "WoWPlugin",
            "status": "active",
        },
        "output": {
            "lua_file": "Toolbox/Data/InstanceMapIDs.lua",
            "lua_table": "Toolbox.Data.InstanceMapIDs",
            "write_header": True,
        },
        "source": {
            "database": "wow.db",
            "tables": ["journalinstance"],
            "sql": "SELECT 1 AS journal_instance_id, 2 AS map_id",
            "query": {
                "from": "journalinstance",
                "joins": [],
                "select": ["journal_instance_id", "map_id"],
                "where": [],
                "group_by": [],
                "order_by": [],
                "row_granularity": "one row per mapping",
            },
        },
        "structure": {
            "root_type": "map_scalar",
            "lua_shape": "[journal_instance_id] = map_id",
            "key_field": "journal_instance_id",
            "value_field": "map_id",
            "comment_field": "comment_name",
            "fields": [],
        },
        "validation": {
            "required_fields": ["journal_instance_id", "map_id"],
            "unique_keys": [["journal_instance_id"]],
            "non_null_fields": ["journal_instance_id", "map_id"],
            "sort_rules": [{"field": "journal_instance_id", "direction": "asc"}],
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "initial"}],
        },
    }


class ContractIoTests(unittest.TestCase):
    def write_contract(self, contracts_dir: Path, contract_id: str = "instance_map_ids") -> Path:
        contract_path = contracts_dir / f"{contract_id}.json"
        contract_path.write_text(json.dumps(build_contract(contract_id), ensure_ascii=False, indent=2), encoding="utf-8")
        return contract_path

    def test_load_contract_reads_contract_by_id(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            contracts_dir = Path(temp_dir_name)
            self.write_contract(contracts_dir)
            contract_document = load_contract("instance_map_ids", contracts_dir)
            self.assertEqual(contract_document.contract.contract_id, "instance_map_ids")

    def test_write_contract_snapshot_uses_expected_path_format(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contracts_dir = temp_dir / "contracts"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            source_path = self.write_contract(contracts_dir)
            contract_document = load_contract("instance_map_ids", contracts_dir)
            timestamp = datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc)

            snapshot_path = write_contract_snapshot(
                contract_document,
                source_path=source_path,
                snapshots_root=snapshots_dir,
                timestamp=timestamp,
            )

            expected_path = snapshots_dir / "instance_map_ids" / "instance_map_ids__schema_v1__20260411T102233Z.json"
            self.assertEqual(snapshot_path, expected_path)
            self.assertTrue(snapshot_path.exists())
            self.assertEqual(snapshot_path.read_text(encoding="utf-8"), source_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
