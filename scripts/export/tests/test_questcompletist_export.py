from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.export.toolbox_db_export import (
    export_targets,
    load_questcompletist_storylines,
)


def build_instance_questlines_contract() -> dict:
    return {
        "contract": {
            "contract_id": "instance_questlines",
            "schema_version": 6,
            "summary": "冒险手册任务页签静态任务线文档",
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
            "tables": ["questline", "questlinexquest", "questpoiblob", "uimap", "map"],
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
            "supplemental_sources": [
                {
                    "type": "questcompletist",
                    "dataset": "core_links",
                    "env_var": "WOW_QUESTCOMPLETIST_DIR",
                    "entry_file": "qcQuest.lua",
                }
            ],
            "datasets": {
                "core_links": {
                    "sql": """
SELECT
  CAST(ql.ID AS INTEGER) AS quest_line_id,
  ql.Name_lang AS quest_line_name,
  CAST(qlxq.QuestID AS INTEGER) AS quest_id,
  CAST(qlxq.OrderIndex AS INTEGER) AS order_index,
  CAST(qpb.UiMapID AS INTEGER) AS quest_ui_map_id
FROM questline ql
JOIN questlinexquest qlxq ON qlxq.QuestLineID = ql.ID
LEFT JOIN questpoiblob qpb ON qpb.QuestID = qlxq.QuestID
ORDER BY CAST(ql.ID AS INTEGER), CAST(qlxq.OrderIndex AS INTEGER), CAST(qlxq.QuestID AS INTEGER)
""".strip(),
                }
            },
        },
        "structure": {
            "root_type": "document",
            "lua_shape": "Toolbox.Data.InstanceQuestlines = { schemaVersion, sourceMode, generatedAt, quests, questLines, expansions }",
            "fields": [],
            "document_blocks": [
                {
                    "name": "metadata",
                    "metadata": {
                        "schemaVersion": 6,
                        "sourceMode": "live",
                        "generatedAt": "@generated_at",
                    },
                },
                {
                    "name": "quests",
                    "dataset": "quests",
                    "block_type": "map_object",
                    "key_field": "quest_id",
                    "dedupe_by": ["quest_id"],
                    "required_fields": ["quest_id"],
                    "sort_by": ["quest_id"],
                    "value_template": {
                        "ID": "quest_id",
                    },
                },
                {
                    "name": "questLines",
                    "dataset": "quest_lines",
                    "block_type": "map_object",
                    "key_field": "quest_line_id",
                    "dedupe_by": ["quest_line_id"],
                    "required_fields": [
                        "quest_line_id",
                        "quest_line_name",
                        "quest_line_ui_map_id",
                        "quest_ids",
                    ],
                    "sort_by": ["quest_line_id"],
                    "value_template": {
                        "ID": "quest_line_id",
                        "UiMapID": "quest_line_ui_map_id",
                        "QuestIDs": "quest_ids",
                    },
                    "comment_template": {
                        "Name_lang": "quest_line_name",
                    },
                },
                {
                    "name": "expansions",
                    "dataset": "expansions",
                    "block_type": "map_array_grouped",
                    "key_field": "expansion_id",
                    "value_field": "quest_line_id",
                    "required_fields": ["expansion_id", "quest_line_id"],
                    "dedupe_by": ["expansion_id", "quest_line_id"],
                    "sort_by": ["expansion_id", "quest_line_id"],
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
            "current_schema_version": 6,
            "change_log": [
                {"schema_version": 6, "summary": "测试契约"}
            ],
        },
    }


class QuestCompletistSupplementTests(unittest.TestCase):
    def test_load_questcompletist_storylines_parses_storyline_and_previous_quest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            addon_dir = Path(temp_dir_name)
            addon_dir.mkdir(parents=True, exist_ok=True)
            (addon_dir / "qcQuest.lua").write_text(
                "\n".join(
                    [
                        "qcQuestLines = {",
                        '  [5459] = "Heroic Homecoming",',
                        "}",
                        "qcQuestDatabase={",
                        '[90840]={90840,"What\'s Your Specialty?",7,"Stormwind City",194,1,2,67108863,8191,0,0,0,5459,0},',
                        '[90842]={90842,"Home Is Where the Hearth Is",7,"Stormwind City",194,1,2,67108863,8191,0,0,0,5459,90840},',
                        "}",
                    ]
                ),
                encoding="utf-8",
            )

            storyline_bundle = load_questcompletist_storylines(addon_dir)

            self.assertEqual(storyline_bundle["storyline_names"][5459], "Heroic Homecoming")
            self.assertEqual(storyline_bundle["quest_records"][90840]["storyline_id"], 5459)
            self.assertEqual(storyline_bundle["quest_records"][90840]["previous_quest_id"], 0)
            self.assertEqual(storyline_bundle["quest_records"][90842]["previous_quest_id"], 90840)

    def test_export_targets_merges_questcompletist_and_overrides_existing_order(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            addon_dir = temp_dir / "QuestCompletist"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)
            addon_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_questlines.json"
            contract_path.write_text(
                json.dumps(build_instance_questlines_contract(), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

            (addon_dir / "qcQuest.lua").write_text(
                "\n".join(
                    [
                        "qcQuestLines = {",
                        '  [5459] = "Heroic Homecoming",',
                        "}",
                        "qcQuestDatabase={",
                        '[90840]={90840,"What\'s Your Specialty?",7,"Stormwind City",194,1,2,67108863,8191,0,0,0,5459,0},',
                        '[90842]={90842,"Home Is Where the Hearth Is",7,"Stormwind City",194,1,2,67108863,8191,0,0,0,5459,90840},',
                        '[90843]={90843,"Aiding the Dragon Isles",7,"Stormwind City",194,1,2,67108863,8191,0,0,0,5459,90842},',
                        "}",
                    ]
                ),
                encoding="utf-8",
            )

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.executescript(
                """
CREATE TABLE questline (ID INTEGER, Name_lang TEXT);
CREATE TABLE questlinexquest (QuestLineID INTEGER, QuestID INTEGER, OrderIndex INTEGER);
CREATE TABLE questpoiblob (QuestID INTEGER, ID INTEGER, MapID INTEGER, UiMapID INTEGER, ObjectiveID INTEGER);
CREATE TABLE uimap (ID INTEGER, ParentUiMapID INTEGER, Type INTEGER);
CREATE TABLE map (ID INTEGER, ExpansionID INTEGER);
INSERT INTO questline VALUES (100, 'Old Line');
INSERT INTO questlinexquest VALUES (100, 90840, 5);
INSERT INTO questlinexquest VALUES (100, 90842, 6);
INSERT INTO questpoiblob VALUES (70001, 90840, 70001, 194, 0);
INSERT INTO questpoiblob VALUES (70002, 90842, 70002, 194, 0);
INSERT INTO questpoiblob VALUES (70003, 90843, 70003, 194, 0);
INSERT INTO uimap VALUES (194, 947, 2);
INSERT INTO uimap VALUES (947, 0, 3);
INSERT INTO map VALUES (70001, 0);
INSERT INTO map VALUES (70002, 0);
INSERT INTO map VALUES (70003, 0);
"""
            )
            sqlite_conn.commit()
            sqlite_conn.close()

            written_files = export_targets(
                target_ids=["instance_questlines"],
                db_path=db_path,
                data_dir=output_dir,
                contract_dir=contracts_dir,
                snapshot_dir=snapshots_dir,
                generated_by="test-suite",
                questcompletist_dir=addon_dir,
            )

            self.assertEqual(len(written_files), 1)
            output_text = (output_dir / "InstanceQuestlines.lua").read_text(encoding="utf-8")
            self.assertIn("schemaVersion = 6,", output_text)
            self.assertIn('[5459] = { ID = 5459, UiMapID = 947, QuestIDs = { 90840, 90842, 90843 } }, -- Name_lang = "Heroic Homecoming"', output_text)
            self.assertIn("[0] = { 5459 },", output_text)
            self.assertIn("[90840] = { ID = 90840 },", output_text)
            self.assertNotIn("questLineXQuest = {", output_text)
            self.assertNotIn("OrderIndex =", output_text)


if __name__ == "__main__":
    unittest.main()
