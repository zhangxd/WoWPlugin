from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.export.contract_model import load_contract_document


def build_valid_contract(contract_id: str = "instance_map_ids") -> dict:
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


class ContractModelTests(unittest.TestCase):
    def write_contract(self, temp_dir: Path, contract_id: str = "instance_map_ids") -> Path:
        contract_path = temp_dir / f"{contract_id}.json"
        contract_path.write_text(
            json.dumps(build_valid_contract(contract_id), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return contract_path

    def test_load_contract_document_accepts_valid_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contract_path = self.write_contract(temp_dir)
            document = load_contract_document(contract_path)
            self.assertEqual(document.contract.contract_id, "instance_map_ids")
            self.assertEqual(document.contract.schema_version, 1)

    def test_load_contract_document_rejects_filename_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contract_path = temp_dir / "wrong_name.json"
            contract_path.write_text(
                json.dumps(build_valid_contract("instance_map_ids"), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "contract_id"):
                load_contract_document(contract_path)

    def test_load_contract_document_rejects_missing_sections(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contract_path = temp_dir / "instance_map_ids.json"
            broken_contract = build_valid_contract()
            broken_contract.pop("validation")
            contract_path.write_text(json.dumps(broken_contract, ensure_ascii=False, indent=2), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "validation"):
                load_contract_document(contract_path)

    def test_load_contract_document_rejects_version_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contract_path = temp_dir / "instance_map_ids.json"
            broken_contract = build_valid_contract()
            broken_contract["versioning"]["current_schema_version"] = 2
            contract_path.write_text(json.dumps(broken_contract, ensure_ascii=False, indent=2), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "current_schema_version"):
                load_contract_document(contract_path)


if __name__ == "__main__":
    unittest.main()
