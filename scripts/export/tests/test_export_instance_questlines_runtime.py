from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.export.export_instance_questlines_runtime import (
    build_instance_questlines_model,
    load_ordered_quest_line_members,
    write_instance_questlines_lua,
)


def build_csv_rows() -> list[dict[str, str]]:
    return [
        {
            "QuestID": "2002",
            "QuestName": "Second Quest",
            "QuestLineID": "601",
            "QuestLineNames": "Shared Line",
            "UiMapID": "2112",
            "ZoneName": "Valdrakken",
            "FactionTag": "shared",
            "FactionCondition": "alliance=horde",
            "FactionMaskRaw": "",
            "ClassMaskRaw": "8",
            "ContentExpansionID": "9",
        },
        {
            "QuestID": "2001",
            "QuestName": "First Quest",
            "QuestLineID": "601",
            "QuestLineNames": "Shared Line",
            "UiMapID": "21",
            "ZoneName": "Silverpine Forest",
            "FactionTag": "alliance",
            "FactionCondition": "alliance",
            "FactionMaskRaw": "1",
            "ClassMaskRaw": "",
            "ContentExpansionID": "9",
        },
        {
            "QuestID": "2003",
            "QuestName": "Ignored Quest",
            "QuestLineID": "",
            "QuestLineNames": "",
            "UiMapID": "99",
            "ZoneName": "Ignored",
            "FactionTag": "",
            "FactionCondition": "",
            "FactionMaskRaw": "",
            "ClassMaskRaw": "",
            "ContentExpansionID": "",
        },
    ]


class ExportInstanceQuestlinesRuntimeTests(unittest.TestCase):
    def test_build_instance_questlines_model_preserves_db_order(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                sqlite_conn.execute("CREATE TABLE questlinexquest (QuestLineID TEXT, QuestID TEXT, OrderIndex TEXT)")
                sqlite_conn.execute("CREATE TABLE questline (ID TEXT, Name_lang TEXT)")
                sqlite_conn.executemany(
                    "INSERT INTO questlinexquest VALUES (?, ?, ?)",
                    [
                        ("601", "2001", "0"),
                        ("601", "2002", "1"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO questline VALUES ('601', 'Shared Line')")
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            ordered_quest_ids_by_line, quest_line_name_by_id = load_ordered_quest_line_members(db_path)

        model = build_instance_questlines_model(build_csv_rows(), ordered_quest_ids_by_line, quest_line_name_by_id)
        self.assertEqual(sorted(model.quests.keys()), [2001, 2002])
        self.assertEqual(model.quest_lines[601].quest_ids, [2001, 2002])
        self.assertEqual(model.quest_lines[601].ui_map_id, 21)
        self.assertEqual(model.quest_lines[601].ui_map_ids, [21, 2112])
        self.assertEqual(model.quest_lines[601].faction_tags, ["alliance", "shared"])
        self.assertEqual(model.quest_lines[601].class_mask_values, [8])
        self.assertEqual(model.expansions, {9: [601]})

    def test_write_instance_questlines_lua_outputs_extended_schema_v6(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                sqlite_conn.execute("CREATE TABLE questlinexquest (QuestLineID TEXT, QuestID TEXT, OrderIndex TEXT)")
                sqlite_conn.execute("CREATE TABLE questline (ID TEXT, Name_lang TEXT)")
                sqlite_conn.executemany(
                    "INSERT INTO questlinexquest VALUES (?, ?, ?)",
                    [
                        ("601", "2001", "0"),
                        ("601", "2002", "1"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO questline VALUES ('601', 'Shared Line')")
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            ordered_quest_ids_by_line, quest_line_name_by_id = load_ordered_quest_line_members(db_path)
            model = build_instance_questlines_model(build_csv_rows(), ordered_quest_ids_by_line, quest_line_name_by_id)

            output_path = Path(temp_dir_name) / "InstanceQuestlines.lua"
            write_instance_questlines_lua(output_path, model)
            output_text = output_path.read_text(encoding="utf-8")

        self.assertIn("Toolbox.Data.InstanceQuestlines = {", output_text)
        self.assertIn("schemaVersion = 6", output_text)
        self.assertIn('[2001] = { -- First Quest', output_text)
        self.assertIn("QuestLineIDs = { 601 }", output_text)
        self.assertIn('FactionConditions = { "alliance" }', output_text)
        self.assertIn("ClassMaskValues = { 8 }", output_text)
        self.assertIn('[601] = { -- Shared Line', output_text)
        self.assertIn('Name_lang = "Shared Line"', output_text)
        self.assertIn("UiMapID = 21", output_text)
        self.assertIn("PrimaryUiMapID = 21, -- Silverpine Forest", output_text)
        self.assertIn("[9] = { 601 }", output_text)

    def test_build_instance_questlines_model_assigns_unknown_map_to_mapless_lines(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                sqlite_conn.execute("CREATE TABLE questlinexquest (QuestLineID TEXT, QuestID TEXT, OrderIndex TEXT)")
                sqlite_conn.execute("CREATE TABLE questline (ID TEXT, Name_lang TEXT)")
                sqlite_conn.execute("INSERT INTO questlinexquest VALUES ('801', '4001', '0')")
                sqlite_conn.execute("INSERT INTO questline VALUES ('801', 'No Map Line')")
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            ordered_quest_ids_by_line, quest_line_name_by_id = load_ordered_quest_line_members(db_path)

        csv_rows = [
            {
                "QuestID": "4001",
                "QuestName": "Mapless Quest",
                "QuestLineID": "801",
                "QuestLineNames": "No Map Line",
                "UiMapID": "",
                "ZoneName": "",
                "FactionTag": "",
                "FactionCondition": "",
                "FactionMaskRaw": "",
                "ClassMaskRaw": "",
                "ContentExpansionID": "99",
            }
        ]

        model = build_instance_questlines_model(csv_rows, ordered_quest_ids_by_line, quest_line_name_by_id)
        self.assertEqual([4001], model.quest_lines[801].quest_ids)
        self.assertEqual(999999, model.quest_lines[801].ui_map_id)
        self.assertEqual([], model.quest_lines[801].ui_map_ids)
        self.assertIsNone(model.quest_lines[801].primary_ui_map_id)
        self.assertEqual("未归属地图", model.quest_lines[801].primary_ui_map_name)
        self.assertEqual({99: [801]}, model.expansions)

    def test_write_instance_questlines_lua_omits_empty_name_lang_field(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            model = build_instance_questlines_model(
                [
                    {
                        "QuestID": "5001",
                        "QuestName": "",
                        "QuestLineID": "901",
                        "QuestLineNames": "",
                        "UiMapID": "",
                        "ZoneName": "",
                        "FactionTag": "",
                        "FactionCondition": "",
                        "FactionMaskRaw": "",
                        "ClassMaskRaw": "",
                        "ContentExpansionID": "99",
                    }
                ],
                {901: [5001]},
                {},
            )

            output_path = Path(temp_dir_name) / "InstanceQuestlines.lua"
            write_instance_questlines_lua(output_path, model)
            output_text = output_path.read_text(encoding="utf-8")

        self.assertIn("[901] = { -- 未命名任务线", output_text)
        self.assertNotIn('Name_lang = ""', output_text)


if __name__ == "__main__":
    unittest.main()
