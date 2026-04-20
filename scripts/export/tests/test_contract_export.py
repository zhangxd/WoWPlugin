from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.export.toolbox_db_export import export_targets


def build_contract() -> dict:
    return {
        "contract": {
            "contract_id": "instance_map_ids",
            "schema_version": 1,
            "summary": "副本 journalInstanceID 到 MapID 的静态映射",
            "source_of_truth": "WoWPlugin",
            "status": "active"
        },
        "output": {
            "lua_file": "Toolbox/Data/InstanceMapIDs.lua",
            "lua_table": "Toolbox.Data.InstanceMapIDs",
            "write_header": True
        },
        "source": {
            "database": "wow.db",
            "tables": ["journalinstance"],
            "sql": "SELECT CAST(ID AS INTEGER) AS journal_instance_id, CAST(MapID AS INTEGER) AS map_id, Name_lang AS comment_name FROM journalinstance ORDER BY CAST(ID AS INTEGER)",
            "query": {
                "from": "journalinstance",
                "joins": [],
                "select": ["journal_instance_id", "map_id", "comment_name"],
                "where": [],
                "group_by": [],
                "order_by": ["journal_instance_id ASC"],
                "row_granularity": "一行代表一个副本映射"
            }
        },
        "structure": {
            "root_type": "map_scalar",
            "lua_shape": "[journal_instance_id] = map_id",
            "key_field": "journal_instance_id",
            "value_field": "map_id",
            "comment_field": "comment_name",
            "fields": []
        },
        "validation": {
            "required_fields": ["journal_instance_id", "map_id"],
            "unique_keys": [["journal_instance_id"]],
            "non_null_fields": ["journal_instance_id", "map_id"],
            "sort_rules": [{"field": "journal_instance_id", "direction": "asc"}]
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "初始契约版本"}]
        }
    }


def build_dataset_contract(dataset_sql: str) -> dict:
    return {
        "contract": {
            "contract_id": "instance_questlines",
            "schema_version": 1,
            "summary": "测试 datasets 校验路径",
            "source_of_truth": "WoWPlugin",
            "status": "active",
        },
        "output": {
            "lua_file": "Toolbox/Data/InstanceQuestlines.lua",
            "lua_table": "Toolbox.Data.InstanceQuestlines",
            "write_header": True,
        },
        "source": {
            "database": "wow.db",
            "tables": [],
            "sql": "SELECT 1 AS placeholder",
            "query": {
                "from": "placeholder",
                "joins": [],
                "select": ["placeholder"],
                "where": [],
                "group_by": [],
                "order_by": [],
                "row_granularity": "占位查询",
            },
            "datasets": {
                "links": {
                    "sql": dataset_sql,
                    "query": {
                        "from": "links",
                        "joins": [],
                        "select": ["quest_line_id", "quest_id", "order_index"],
                        "where": [],
                        "group_by": [],
                        "order_by": [],
                        "row_granularity": "任务线链接",
                    },
                },
            },
        },
        "structure": {
            "root_type": "document",
            "lua_shape": "Toolbox.Data.InstanceQuestlines = { schemaVersion, sourceMode, generatedAt, questLineXQuest }",
            "fields": [],
            "document_blocks": [
                {
                    "name": "metadata",
                    "metadata": {
                        "schemaVersion": 1,
                        "sourceMode": "live",
                        "generatedAt": "@generated_at",
                    },
                },
                {
                    "name": "questLineXQuest",
                    "dataset": "links",
                    "block_type": "map_array_objects_grouped",
                    "key_field": "quest_line_id",
                    "required_fields": ["quest_line_id", "quest_id", "order_index"],
                    "dedupe_by": ["quest_line_id", "quest_id", "order_index"],
                    "sort_by": ["quest_line_id", "order_index", "quest_id"],
                    "value_template": {
                        "QuestID": "quest_id",
                        "OrderIndex": "order_index",
                    },
                },
            ],
        },
        "validation": {
            "required_fields": ["quest_line_id", "quest_id", "order_index"],
            "unique_keys": [["quest_line_id", "quest_id", "order_index"]],
            "non_null_fields": ["quest_line_id", "quest_id", "order_index"],
            "sort_rules": [
                {"field": "quest_line_id", "direction": "asc"},
                {"field": "order_index", "direction": "asc"},
                {"field": "quest_id", "direction": "asc"},
            ],
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "初始契约版本"}],
        },
    }


class ContractExportIntegrationTests(unittest.TestCase):
    def test_export_targets_writes_contract_tagged_lua_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_map_ids.json"
            contract_path.write_text(json.dumps(build_contract(), ensure_ascii=False, indent=2), encoding="utf-8")

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.execute("CREATE TABLE journalinstance (ID TEXT, MapID TEXT, Name_lang TEXT)")
            sqlite_conn.execute("INSERT INTO journalinstance VALUES ('63', '36', 'Deadmines')")
            sqlite_conn.execute("INSERT INTO journalinstance VALUES ('64', '33', 'Shadowfang Keep')")
            sqlite_conn.commit()
            sqlite_conn.close()

            written_files = export_targets(
                target_ids=["instance_map_ids"],
                db_path=db_path,
                data_dir=output_dir,
                contract_dir=contracts_dir,
                snapshot_dir=snapshots_dir,
                generated_by="test-suite",
            )

            self.assertEqual(len(written_files), 1)
            output_path = output_dir / "InstanceMapIDs.lua"
            self.assertEqual(written_files[0], output_path)
            output_text = output_path.read_text(encoding="utf-8")
            self.assertIn("@contract_id instance_map_ids", output_text)
            self.assertIn("@schema_version 1", output_text)
            self.assertIn("Toolbox.Data.InstanceMapIDs = {", output_text)
            self.assertIn("[63] = 36, -- Deadmines", output_text)
            self.assertIn("[64] = 33, -- Shadowfang Keep", output_text)

    def test_export_targets_rejects_duplicate_rows_in_dataset_validation_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_questlines.json"
            contract_path.write_text(
                json.dumps(
                    build_dataset_contract(
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, 1 AS order_index "
                        "UNION ALL "
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, 1 AS order_index"
                    ),
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.close()

            with self.assertRaisesRegex(ValueError, "duplicate key group"):
                export_targets(
                    target_ids=["instance_questlines"],
                    db_path=db_path,
                    data_dir=output_dir,
                    contract_dir=contracts_dir,
                    snapshot_dir=snapshots_dir,
                    generated_by="test-suite",
                )

    def test_export_targets_rejects_null_rows_in_dataset_validation_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_questlines.json"
            contract_path.write_text(
                json.dumps(
                    build_dataset_contract(
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, NULL AS order_index"
                    ),
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.close()

            with self.assertRaisesRegex(ValueError, "non-null field order_index is empty"):
                export_targets(
                    target_ids=["instance_questlines"],
                    db_path=db_path,
                    data_dir=output_dir,
                    contract_dir=contracts_dir,
                    snapshot_dir=snapshots_dir,
                    generated_by="test-suite",
                )


if __name__ == "__main__":
    unittest.main()
