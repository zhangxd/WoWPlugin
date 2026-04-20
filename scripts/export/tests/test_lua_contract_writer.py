from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from scripts.export.contract_model import load_contract_document
from scripts.export.lua_contract_writer import build_contract_header, render_contract_lua


def build_map_scalar_contract() -> dict:
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
            "sql": "SELECT ...",
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


def build_map_array_contract() -> dict:
    data = build_map_scalar_contract()
    data["contract"]["contract_id"] = "instance_drops_mount"
    data["contract"]["summary"] = "副本坐骑掉落 itemID 集合"
    data["output"]["lua_file"] = "Toolbox/Data/InstanceDrops_Mount.lua"
    data["output"]["lua_table"] = "Toolbox.Data.MountDrops"
    data["source"]["query"]["select"] = ["journal_instance_id", "item_id", "instance_name"]
    data["structure"] = {
        "root_type": "map_array",
        "lua_shape": "[journal_instance_id] = { item_id, ... }",
        "key_field": "journal_instance_id",
        "value_field": "item_id",
        "comment_field": "instance_name",
        "fields": []
    }
    data["validation"]["required_fields"] = ["journal_instance_id", "item_id"]
    data["validation"]["non_null_fields"] = ["journal_instance_id", "item_id"]
    data["validation"]["unique_keys"] = [["journal_instance_id", "item_id"]]
    data["validation"]["sort_rules"] = [
        {"field": "journal_instance_id", "direction": "asc"},
        {"field": "item_id", "direction": "asc"}
    ]
    return data


def build_map_scalar_string_contract() -> dict:
    data = build_map_scalar_contract()
    data["contract"]["contract_id"] = "quest_type_names"
    data["contract"]["summary"] = "任务类型名称映射表"
    data["output"]["lua_file"] = "Toolbox/Data/QuestTypeNames.lua"
    data["output"]["lua_table"] = "Toolbox.Data.QuestTypeNames"
    data["source"]["query"]["select"] = ["quest_info_id", "quest_type_name"]
    data["structure"] = {
        "root_type": "map_scalar",
        "lua_shape": "[quest_info_id] = quest_type_name",
        "key_field": "quest_info_id",
        "value_field": "quest_type_name",
        "fields": []
    }
    data["validation"]["required_fields"] = ["quest_info_id", "quest_type_name"]
    data["validation"]["non_null_fields"] = ["quest_info_id", "quest_type_name"]
    data["validation"]["unique_keys"] = [["quest_info_id"]]
    data["validation"]["sort_rules"] = [
        {"field": "quest_info_id", "direction": "asc"}
    ]
    return data


def build_document_contract() -> dict:
    return {
        "contract": {
            "contract_id": "instance_questlines",
            "schema_version": 1,
            "summary": "冒险手册任务页签静态任务线文档",
            "source_of_truth": "WoWPlugin",
            "status": "active"
        },
        "output": {
            "lua_file": "Toolbox/Data/InstanceQuestlines.lua",
            "lua_table": "Toolbox.Data.InstanceQuestlines",
            "write_header": True
        },
        "source": {
            "database": "wow.db",
            "tables": ["questline", "questlinexquest", "questpoiblob"],
            "sql": "SELECT ...",
            "query": {
                "from": "questline",
                "joins": [],
                "select": ["quest_line_id", "quest_line_name", "quest_id", "order_index", "quest_ui_map_id", "quest_line_ui_map_id"],
                "where": [],
                "group_by": [],
                "order_by": ["quest_line_id ASC", "order_index ASC", "quest_id ASC"],
                "row_granularity": "一行代表一个任务线与任务关联"
            }
        },
        "structure": {
            "root_type": "document",
            "lua_shape": "Toolbox.Data.InstanceQuestlines = { schemaVersion, sourceMode, generatedAt, quests, questLines, questLineQuestIDs }",
            "fields": [],
            "document_blocks": [
                {
                    "name": "metadata",
                    "metadata": {
                        "schemaVersion": 3,
                        "sourceMode": "live",
                        "generatedAt": "@generated_at"
                    }
                },
                {
                    "name": "quests",
                    "block_type": "map_object",
                    "key_field": "quest_id",
                    "dedupe_by": ["quest_id"],
                    "required_fields": ["quest_id", "quest_ui_map_id"],
                    "sort_by": ["quest_id"],
                    "value_template": {
                        "ID": "quest_id",
                        "UiMapID": "quest_ui_map_id"
                    }
                },
                {
                    "name": "questLines",
                    "block_type": "map_object",
                    "key_field": "quest_line_id",
                    "dedupe_by": ["quest_line_id"],
                    "required_fields": ["quest_line_id", "quest_line_name", "quest_line_ui_map_id"],
                    "sort_by": ["quest_line_id"],
                    "value_template": {
                        "ID": "quest_line_id",
                        "Name_lang": "quest_line_name",
                        "UiMapID": "quest_line_ui_map_id"
                    }
                },
                {
                    "name": "questLineQuestIDs",
                    "block_type": "map_array_grouped",
                    "key_field": "quest_line_id",
                    "value_field": "quest_id",
                    "required_fields": ["quest_line_id", "quest_id"],
                    "dedupe_by": ["quest_line_id", "quest_id"],
                    "sort_by": ["quest_line_id", "order_index", "quest_id"]
                }
            ]
        },
        "validation": {
            "required_fields": ["quest_line_id", "quest_id", "order_index"],
            "unique_keys": [["quest_line_id", "quest_id", "order_index"]],
            "non_null_fields": ["quest_line_id", "quest_id", "order_index"],
            "sort_rules": [
                {"field": "quest_line_id", "direction": "asc"},
                {"field": "order_index", "direction": "asc"},
                {"field": "quest_id", "direction": "asc"}
            ]
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "初始契约版本"}]
        }
    }


def build_document_grouped_object_contract() -> dict:
    data = build_document_contract()
    data["contract"]["contract_id"] = "instance_questlines_grouped_objects"
    data["structure"]["document_blocks"] = [
        {
            "name": "metadata",
            "metadata": {
                "schemaVersion": 4,
                "sourceMode": "live",
                "generatedAt": "@generated_at"
            }
        },
        {
            "name": "questLineXQuest",
            "block_type": "map_array_objects_grouped",
            "key_field": "quest_line_id",
            "required_fields": ["quest_line_id", "quest_id", "order_index"],
            "dedupe_by": ["quest_line_id", "quest_id", "order_index"],
            "sort_by": ["quest_line_id", "order_index", "quest_id"],
            "value_template": {
                "QuestID": "quest_id",
                "OrderIndex": "order_index"
            }
        }
    ]
    return data


def build_document_dataset_contract() -> dict:
    data = build_document_grouped_object_contract()
    data["contract"]["contract_id"] = "instance_questlines_datasets"
    data["source"]["sql"] = "SELECT 1"
    data["source"]["query"] = {
        "from": "dual",
        "joins": [],
        "select": ["placeholder"],
        "where": [],
        "group_by": [],
        "order_by": [],
        "row_granularity": "占位查询"
    }
    data["source"]["datasets"] = {
        "quests": {
            "sql": "SELECT ...",
            "query": {
                "from": "quests",
                "joins": [],
                "select": ["quest_id", "quest_ui_map_id"],
                "where": [],
                "group_by": [],
                "order_by": [],
                "row_granularity": "任务"
            }
        },
        "links": {
            "sql": "SELECT ...",
            "query": {
                "from": "links",
                "joins": [],
                "select": ["quest_line_id", "quest_id", "order_index"],
                "where": [],
                "group_by": [],
                "order_by": [],
                "row_granularity": "任务线链接"
            }
        }
    }
    data["structure"]["document_blocks"] = [
        {
            "name": "metadata",
            "metadata": {
                "schemaVersion": 4,
                "sourceMode": "live",
                "generatedAt": "@generated_at"
            }
        },
        {
            "name": "quests",
            "dataset": "quests",
            "block_type": "map_object",
            "key_field": "quest_id",
            "required_fields": ["quest_id", "quest_ui_map_id"],
            "dedupe_by": ["quest_id"],
            "sort_by": ["quest_id"],
            "value_template": {
                "ID": "quest_id",
                "UiMapID": "quest_ui_map_id"
            }
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
                "OrderIndex": "order_index"
            }
        }
    ]
    return data


def build_document_object_comment_contract() -> dict:
    data = build_document_contract()
    data["contract"]["contract_id"] = "instance_questlines_object_comment"
    data["structure"]["document_blocks"] = [
        {
            "name": "metadata",
            "metadata": {
                "schemaVersion": 4,
                "sourceMode": "live",
                "generatedAt": "@generated_at"
            }
        },
        {
            "name": "questLines",
            "block_type": "map_object",
            "key_field": "quest_line_id",
            "required_fields": ["quest_line_id", "quest_line_name", "quest_line_ui_map_id"],
            "dedupe_by": ["quest_line_id"],
            "sort_by": ["quest_line_id"],
            "value_template": {
                "ID": "quest_line_id",
                "UiMapID": "quest_line_ui_map_id"
            },
            "comment_template": {
                "Name_lang": "quest_line_name"
            }
        }
    ]
    return data


class LuaContractWriterTests(unittest.TestCase):
    def load_contract(self, raw_data: dict, contract_id: str) -> object:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            contract_path = temp_dir / f"{contract_id}.json"
            contract_path.write_text(json.dumps(raw_data, ensure_ascii=False, indent=2), encoding="utf-8")
            return load_contract_document(contract_path)

    def test_build_contract_header_emits_tagged_metadata_block(self) -> None:
        contract_document = self.load_contract(build_map_scalar_contract(), "instance_map_ids")
        header_text = build_contract_header(
            contract_document,
            contract_file=Path("WoWPlugin/DataContracts/instance_map_ids.json"),
            contract_snapshot=Path("WoWTools/outputs/toolbox/contract_snapshots/instance_map_ids/instance_map_ids__schema_v1__20260411T102233Z.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="WoWPlugin/scripts/export/export_toolbox_one.py",
        )

        self.assertEqual(
            header_text,
            "--[[\n"
            "@contract_id instance_map_ids\n"
            "@schema_version 1\n"
            "@contract_file WoWPlugin/DataContracts/instance_map_ids.json\n"
            "@contract_snapshot WoWTools/outputs/toolbox/contract_snapshots/instance_map_ids/instance_map_ids__schema_v1__20260411T102233Z.json\n"
            "@generated_at 2026-04-11T10:22:33Z\n"
            "@generated_by WoWPlugin/scripts/export/export_toolbox_one.py\n"
            "@data_source wow.db\n"
            "@summary 副本 journalInstanceID 到 MapID 的静态映射\n"
            "@overwrite_notice 此文件由工具生成，手改会被覆盖\n"
            "]]"
        )

    def test_render_contract_lua_supports_map_scalar(self) -> None:
        contract_document = self.load_contract(build_map_scalar_contract(), "instance_map_ids")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"journal_instance_id": 63, "map_id": 36, "comment_name": "Deadmines"},
                {"journal_instance_id": 64, "map_id": 33, "comment_name": "Shadowfang Keep"}
            ],
            contract_file=Path("WoWPlugin/DataContracts/instance_map_ids.json"),
            contract_snapshot=Path("snapshots/instance_map_ids.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("Toolbox.Data.InstanceMapIDs = {", rendered_text)
        self.assertIn("[63] = 36, -- Deadmines", rendered_text)
        self.assertIn("[64] = 33, -- Shadowfang Keep", rendered_text)

    def test_render_contract_lua_supports_map_array(self) -> None:
        contract_document = self.load_contract(build_map_array_contract(), "instance_drops_mount")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"journal_instance_id": 76, "item_id": 68824, "instance_name": "Zul'Gurub"},
                {"journal_instance_id": 76, "item_id": 68823, "instance_name": "Zul'Gurub"},
                {"journal_instance_id": 78, "item_id": 69224, "instance_name": "Firelands"}
            ],
            contract_file=Path("WoWPlugin/DataContracts/instance_drops_mount.json"),
            contract_snapshot=Path("snapshots/instance_drops_mount.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("Toolbox.Data.MountDrops = {", rendered_text)
        self.assertIn("[76] = { 68823, 68824 }, -- Zul'Gurub", rendered_text)
        self.assertIn("[78] = { 69224 }, -- Firelands", rendered_text)

    def test_render_contract_lua_supports_string_values_in_map_scalar(self) -> None:
        contract_document = self.load_contract(build_map_scalar_string_contract(), "quest_type_names")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"quest_info_id": 1, "quest_type_name": "Group Quest"},
                {"quest_info_id": 2, "quest_type_name": 'Daily "Special"'},
            ],
            contract_file=Path("WoWPlugin/DataContracts/quest_type_names.json"),
            contract_snapshot=Path("snapshots/quest_type_names.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("Toolbox.Data.QuestTypeNames = {", rendered_text)
        self.assertIn('[1] = "Group Quest",', rendered_text)
        self.assertIn('[2] = "Daily \\"Special\\"",', rendered_text)

    def test_render_contract_lua_supports_document(self) -> None:
        contract_document = self.load_contract(build_document_contract(), "instance_questlines")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"quest_line_id": 5531, "quest_line_name": "Mock QuestLine A", "quest_id": 84956, "order_index": 1, "quest_ui_map_id": 2371, "quest_line_ui_map_id": 2371},
                {"quest_line_id": 5531, "quest_line_name": "Mock QuestLine A", "quest_id": 84957, "order_index": 2, "quest_ui_map_id": 2371, "quest_line_ui_map_id": 2371},
                {"quest_line_id": 5531, "quest_line_name": "Mock QuestLine A", "quest_id": 84958, "order_index": 3, "quest_ui_map_id": 2371, "quest_line_ui_map_id": 2371}
            ],
            contract_file=Path("WoWPlugin/DataContracts/instance_questlines.json"),
            contract_snapshot=Path("snapshots/instance_questlines.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("Toolbox.Data.InstanceQuestlines = {", rendered_text)
        self.assertIn("schemaVersion = 3,", rendered_text)
        self.assertIn('sourceMode = "live",', rendered_text)
        self.assertIn("[84956] = { ID = 84956, UiMapID = 2371 },", rendered_text)
        self.assertIn('[5531] = { ID = 5531, Name_lang = "Mock QuestLine A", UiMapID = 2371 },', rendered_text)
        self.assertIn("[5531] = { 84956, 84957, 84958 },", rendered_text)

    def test_render_contract_lua_supports_grouped_object_arrays_in_document(self) -> None:
        contract_document = self.load_contract(build_document_grouped_object_contract(), "instance_questlines_grouped_objects")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"quest_line_id": 5531, "quest_id": 84956, "order_index": 1},
                {"quest_line_id": 5531, "quest_id": 84957, "order_index": 2},
                {"quest_line_id": 5532, "quest_id": 85001, "order_index": 1},
            ],
            contract_file=Path("WoWPlugin/DataContracts/instance_questlines_grouped_objects.json"),
            contract_snapshot=Path("snapshots/instance_questlines_grouped_objects.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("schemaVersion = 4,", rendered_text)
        self.assertIn("questLineXQuest = {", rendered_text)
        self.assertIn("    [5531] = {", rendered_text)
        self.assertIn("      { QuestID = 84956, OrderIndex = 1 },", rendered_text)
        self.assertIn("      { QuestID = 84957, OrderIndex = 2 },", rendered_text)
        self.assertIn("    [5532] = {", rendered_text)

    def test_render_contract_lua_supports_document_blocks_from_named_datasets(self) -> None:
        contract_document = self.load_contract(build_document_dataset_contract(), "instance_questlines_datasets")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[],
            dataset_rows_by_name={
                "quests": [
                    {"quest_id": 84956, "quest_ui_map_id": 2371},
                    {"quest_id": 84957, "quest_ui_map_id": 2371},
                ],
                "links": [
                    {"quest_line_id": 5531, "quest_id": 84956, "order_index": 1},
                    {"quest_line_id": 5531, "quest_id": 84957, "order_index": 2},
                ],
            },
            contract_file=Path("WoWPlugin/DataContracts/instance_questlines_datasets.json"),
            contract_snapshot=Path("snapshots/instance_questlines_datasets.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn("[84956] = { ID = 84956, UiMapID = 2371 },", rendered_text)
        self.assertIn("questLineXQuest = {", rendered_text)
        self.assertIn("      { QuestID = 84957, OrderIndex = 2 },", rendered_text)

    def test_render_contract_lua_supports_object_comments_in_document_blocks(self) -> None:
        contract_document = self.load_contract(build_document_object_comment_contract(), "instance_questlines_object_comment")
        rendered_text = render_contract_lua(
            contract_document,
            rows=[
                {"quest_line_id": 5531, "quest_line_name": "Mock QuestLine A", "quest_id": 84956, "order_index": 1, "quest_ui_map_id": 2371, "quest_line_ui_map_id": 2371},
            ],
            contract_file=Path("WoWPlugin/DataContracts/instance_questlines_object_comment.json"),
            contract_snapshot=Path("snapshots/instance_questlines_object_comment.json"),
            generated_at=datetime(2026, 4, 11, 10, 22, 33, tzinfo=timezone.utc),
            generated_by="writer-test",
        )
        self.assertIn('[5531] = { ID = 5531, UiMapID = 2371 }, -- Name_lang = "Mock QuestLine A"', rendered_text)


if __name__ == "__main__":
    unittest.main()
