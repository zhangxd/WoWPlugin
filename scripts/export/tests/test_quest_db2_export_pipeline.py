from __future__ import annotations

import csv
import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.export.quest_db2_export_pipeline import (
    ensure_export_indexes,
    fetch_export_rows,
    load_race_faction_masks,
    normalize_faction_condition,
    write_export_csv,
)


def create_schema(sqlite_conn: sqlite3.Connection) -> None:
    """创建导出脚本所需的最小测试表结构。"""

    sqlite_conn.execute("CREATE TABLE questlinexquest (QuestID TEXT, QuestLineID TEXT)")
    sqlite_conn.execute("CREATE TABLE questline (ID TEXT, Name_lang TEXT)")
    sqlite_conn.execute("CREATE TABLE questpoiblob (QuestID TEXT, UiMapID TEXT, MapID TEXT)")
    sqlite_conn.execute("CREATE TABLE uimap (ID TEXT, Type TEXT, Name_lang TEXT, ParentUiMapID TEXT)")
    sqlite_conn.execute("CREATE TABLE map (ID TEXT, MapName_lang TEXT, ExpansionID TEXT)")
    sqlite_conn.execute("CREATE TABLE uimapassignment (UiMapID TEXT, AreaID TEXT, MapID TEXT)")
    sqlite_conn.execute("CREATE TABLE areatable (ID TEXT, AreaName_lang TEXT, ParentAreaID TEXT, ContentTuningID TEXT)")
    sqlite_conn.execute("CREATE TABLE contenttuning (ID TEXT, ExpansionID TEXT)")
    sqlite_conn.execute("CREATE TABLE questinfo (ID TEXT, InfoName_lang TEXT)")
    sqlite_conn.execute(
        """
        CREATE TABLE chrraces (
            ID TEXT,
            Name_lang TEXT,
            PlayableRaceBit TEXT,
            Alliance TEXT
        )
        """
    )
    sqlite_conn.execute(
        """
        CREATE TABLE questv2clitask (
            ID TEXT,
            QuestTitle_lang TEXT,
            ConditionID TEXT,
            FiltRaces TEXT,
            BreadCrumbID TEXT,
            FiltActiveQuest TEXT,
            FiltClasses TEXT,
            FiltNonActiveQuest TEXT,
            FiltCompletedQuest_0 TEXT,
            FiltCompletedQuest_1 TEXT,
            FiltCompletedQuest_2 TEXT,
            QuestInfoID TEXT
        )
        """
    )
    sqlite_conn.execute(
        """
        CREATE TABLE playercondition (
            ID TEXT,
            RaceMask TEXT,
            ClassMask TEXT,
            PrevQuestID_0 TEXT,
            PrevQuestID_1 TEXT,
            PrevQuestID_2 TEXT,
            PrevQuestID_3 TEXT,
            PrevQuestLogic TEXT,
            CurrentCompletedQuestID_0 TEXT,
            CurrentCompletedQuestID_1 TEXT,
            CurrentCompletedQuestID_2 TEXT,
            CurrentCompletedQuestID_3 TEXT,
            CurrentCompletedQuestLogic TEXT,
            ModifierTreeID TEXT
        )
        """
    )


class QuestDb2ExportPipelineTests(unittest.TestCase):
    def test_write_export_csv_writes_chinese_header_row(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            output_path = Path(temp_dir_name) / "quest_expansion_map.csv"
            write_export_csv(
                output_path,
                [
                    {
                        "QuestID": 1001,
                        "QuestName": "First Quest",
                        "QuestLineID": "501",
                        "QuestLineNames": "Reclaim Gilneas",
                        "QuestTypeID": 81,
                        "QuestTypeName": "地下城",
                        "UiMapID": 12,
                        "UiMapType": 3,
                        "ZoneName": "Elwynn Forest",
                        "MapID": 34,
                        "MapName": "Eastern Kingdoms",
                        "MapExpansionID": 0,
                        "MapExpansionName": "Classic",
                        "ContentExpansionID": 0,
                        "ContentExpansionName": "Classic",
                        "PrevQuestIDs": "",
                        "PrevQuestLogic": "",
                        "NextQuestIDs": "",
                        "ExclusiveToQuestIDs": "",
                        "BreadcrumbQuestID": "",
                        "FactionTag": "alliance",
                        "FactionCondition": "alliance",
                        "FactionMaskRaw": 1,
                        "ClassCondition": "rogue",
                        "ClassMaskRaw": 8,
                        "StoryCondition": "",
                        "StoryLogicRaw": "",
                        "PrevQuestLogicRaw": "",
                        "ModifierTreeID": "",
                        "ConditionFlags": "",
                    }
                ],
            )

            with output_path.open("r", encoding="utf-8", newline="") as output_file:
                csv_reader = csv.reader(output_file)
                english_header = next(csv_reader)
                chinese_header = next(csv_reader)
                first_data_row = next(csv_reader)

        self.assertEqual(english_header[0:3], ["QuestID", "QuestName", "QuestLineID"])
        self.assertEqual(chinese_header[0:8], ["任务ID", "任务名称", "任务线ID", "任务线名称", "任务类型ID", "任务类型名称", "界面地图ID", "界面地图类型"])
        self.assertEqual(first_data_row[0:3], ["1001", "First Quest", "501"])

    def test_normalize_faction_condition_uses_race_masks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.executemany(
                    "INSERT INTO questinfo VALUES (?, ?)",
                    [
                        ("81", "地下城"),
                        ("62", "团队"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO chrraces VALUES (?, ?, ?, ?)",
                    [
                        ("1", "Human", "0", "0"),
                        ("2", "Orc", "1", "1"),
                        ("24", "Pandaren", "23", "2"),
                    ],
                )
                sqlite_conn.commit()
                faction_masks = load_race_faction_masks(sqlite_conn)
            finally:
                sqlite_conn.close()

        self.assertEqual(normalize_faction_condition(1, faction_masks), "alliance")
        self.assertEqual(normalize_faction_condition(2, faction_masks), "horde")
        self.assertEqual(normalize_faction_condition(1 | 2, faction_masks), "alliance=horde")
        self.assertEqual(normalize_faction_condition(1 << 23, faction_masks), "neutral")

    def test_ensure_export_indexes_creates_expected_indexes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                ensure_export_indexes(sqlite_conn)
                index_names = {
                    row[0]
                    for row in sqlite_conn.execute(
                        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'"
                    ).fetchall()
                }
            finally:
                sqlite_conn.close()

        self.assertEqual(
            index_names,
            {
                "idx_areatable_id_contenttuning",
                "idx_contenttuning_id_expansion",
                "idx_qpb_quest_uimap_map",
                "idx_qlxq_quest_line",
                "idx_uimap_id_type",
                "idx_uimapassignment_uimap_area",
                "idx_map_id_expansion",
                "idx_qct_id_condition",
                "idx_pc_id",
            },
        )

    def test_fetch_export_rows_includes_condition_columns(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.executemany(
                    "INSERT INTO questlinexquest VALUES (?, ?)",
                    [
                        ("1001", "501"),
                        ("1002", "501"),
                        ("1003", "502"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questline VALUES (?, ?)",
                    [
                        ("501", "Reclaim Gilneas"),
                        ("502", "Another Line"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questpoiblob VALUES (?, ?, ?)",
                    [
                        ("1001", "12", "34"),
                        ("1002", "12", "34"),
                        ("1003", "13", "35"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO uimap VALUES (?, ?, ?, ?)",
                    [
                        ("12", "3", "Elwynn Forest", ""),
                        ("13", "4", "The Stockade", ""),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO map VALUES (?, ?, ?)",
                    [
                        ("34", "Eastern Kingdoms", "0"),
                        ("35", "Stormwind Vault", "0"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questinfo VALUES (?, ?)",
                    [
                        ("81", "地下城"),
                        ("62", "团队"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO chrraces VALUES (?, ?, ?, ?)",
                    [
                        ("1", "Human", "0", "0"),
                        ("2", "Orc", "1", "1"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questv2clitask VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        ("1001", "First Quest", "9001", "0", "7001", "0", "0", "0", "0", "0", "0", "81"),
                        ("1002", "Second Quest", "9002", "0", "0", "0", "0", "0", "2001", "2002", "0", "62"),
                        ("1003", "", "", "0", "", "0", "0", "0", "0", "0", "0", "0"),
                    ],
                )
                sqlite_conn.execute("UPDATE questv2clitask SET FiltActiveQuest = '3001', FiltNonActiveQuest = '3002' WHERE ID = '1002'")
                sqlite_conn.executemany(
                    "INSERT INTO playercondition VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        ("9001", "1", "8", "900", "901", "0", "0", "1", "0", "0", "0", "0", "0", "3001"),
                        ("9002", "2", "0", "1001", "0", "0", "0", "1", "2001", "2002", "0", "0", "1", "3002"),
                    ],
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

            self.assertEqual(len(export_rows), 3)
            quest_1001 = next(row for row in export_rows if row["QuestID"] == 1001)
            self.assertEqual(quest_1001["QuestName"], "First Quest")
            self.assertEqual(quest_1001["QuestLineNames"], "Reclaim Gilneas")
            self.assertEqual(quest_1001["QuestTypeID"], 81)
            self.assertEqual(quest_1001["QuestTypeName"], "地下城")
            self.assertEqual(quest_1001["MapExpansionID"], 0)
            self.assertEqual(quest_1001["MapExpansionName"], "Classic")
            self.assertEqual(quest_1001["ContentExpansionID"], 0)
            self.assertEqual(quest_1001["ContentExpansionName"], "Classic")
            self.assertEqual(quest_1001["PrevQuestIDs"], "900=901")
            self.assertEqual(quest_1001["PrevQuestLogic"], 1)
            self.assertEqual(quest_1001["NextQuestIDs"], "1002")
            self.assertEqual(quest_1001["ExclusiveToQuestIDs"], "")
            self.assertEqual(quest_1001["BreadcrumbQuestID"], 7001)
            self.assertEqual(quest_1001["FactionTag"], "alliance")
            self.assertEqual(quest_1001["FactionCondition"], "alliance")
            self.assertEqual(quest_1001["FactionMaskRaw"], 1)
            self.assertEqual(quest_1001["ClassCondition"], "rogue")
            self.assertEqual(quest_1001["ClassMaskRaw"], 8)
            self.assertEqual(quest_1001["StoryCondition"], "")
            self.assertEqual(quest_1001["StoryLogicRaw"], "")
            self.assertEqual(quest_1001["PrevQuestLogicRaw"], 1)
            self.assertEqual(quest_1001["ModifierTreeID"], 3001)
            self.assertEqual(quest_1001["ConditionFlags"], "")

            quest_1002 = next(row for row in export_rows if row["QuestID"] == 1002)
            self.assertEqual(quest_1002["QuestName"], "Second Quest")
            self.assertEqual(quest_1002["QuestLineNames"], "Reclaim Gilneas")
            self.assertEqual(quest_1002["QuestTypeID"], 62)
            self.assertEqual(quest_1002["QuestTypeName"], "团队")
            self.assertEqual(quest_1002["PrevQuestIDs"], "1001")
            self.assertEqual(quest_1002["PrevQuestLogic"], 1)
            self.assertEqual(quest_1002["NextQuestIDs"], "")
            self.assertEqual(quest_1002["ExclusiveToQuestIDs"], "2001=2002")
            self.assertEqual(quest_1002["BreadcrumbQuestID"], "")
            self.assertEqual(quest_1002["FactionTag"], "horde")
            self.assertEqual(quest_1002["FactionCondition"], "horde")
            self.assertEqual(quest_1002["FactionMaskRaw"], 2)
            self.assertEqual(quest_1002["ClassCondition"], "")
            self.assertEqual(quest_1002["ClassMaskRaw"], "")
            self.assertEqual(quest_1002["StoryCondition"], "completed:2001=2002;active:3001;non_active:3002")
            self.assertEqual(quest_1002["StoryLogicRaw"], 1)
            self.assertEqual(quest_1002["PrevQuestLogicRaw"], 1)
            self.assertEqual(quest_1002["ModifierTreeID"], 3002)
            self.assertEqual(quest_1002["ConditionFlags"], "has_story_condition")

            quest_1003 = next(row for row in export_rows if row["QuestID"] == 1003)
            self.assertEqual(quest_1003["QuestName"], "")
            self.assertEqual(quest_1003["QuestLineNames"], "Another Line")
            self.assertEqual(quest_1003["QuestTypeID"], "")
            self.assertEqual(quest_1003["QuestTypeName"], "")
            self.assertEqual(quest_1003["FactionTag"], "")
            self.assertEqual(quest_1003["PrevQuestIDs"], "")
            self.assertEqual(quest_1003["NextQuestIDs"], "")
            self.assertEqual(quest_1003["BreadcrumbQuestID"], "")
            self.assertEqual(quest_1003["FactionMaskRaw"], "")
            self.assertEqual(quest_1003["ClassMaskRaw"], "")
            self.assertEqual(quest_1003["StoryLogicRaw"], "")
            self.assertEqual(quest_1003["PrevQuestLogicRaw"], "")
            self.assertEqual(quest_1003["ModifierTreeID"], "")

    def test_fetch_export_rows_uses_max_map_expansion_within_questline(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.executemany(
                    "INSERT INTO questlinexquest VALUES (?, ?)",
                    [
                        ("2001", "601"),
                        ("2002", "601"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questline VALUES (?, ?)",
                    [
                        ("601", "Shared Expansion Line"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questpoiblob VALUES (?, ?, ?)",
                    [
                        ("2001", "21", "0"),
                        ("2002", "2112", "2444"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO uimap VALUES (?, ?, ?, ?)",
                    [
                        ("21", "3", "Silverpine Forest", ""),
                        ("2112", "3", "Valdrakken", ""),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO map VALUES (?, ?, ?)",
                    [
                        ("0", "Eastern Kingdoms", "0"),
                        ("2444", "Dragon Isles", "9"),
                    ],
                )
                sqlite_conn.executemany(
                    "INSERT INTO questv2clitask VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        ("2001", "Classic Map Quest", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"),
                        ("2002", "Dragonflight Map Quest", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"),
                    ],
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_2001 = next(row for row in export_rows if row["QuestID"] == 2001)
        quest_2002 = next(row for row in export_rows if row["QuestID"] == 2002)
        self.assertEqual(quest_2001["MapExpansionID"], 0)
        self.assertEqual(quest_2001["MapExpansionName"], "Classic")
        self.assertEqual(quest_2001["ContentExpansionID"], 9)
        self.assertEqual(quest_2001["ContentExpansionName"], "Dragonflight")
        self.assertEqual(quest_2002["MapExpansionID"], 9)
        self.assertEqual(quest_2002["MapExpansionName"], "Dragonflight")
        self.assertEqual(quest_2002["ContentExpansionID"], 9)
        self.assertEqual(quest_2002["ContentExpansionName"], "Dragonflight")

    def test_fetch_export_rows_falls_back_to_uimap_area_content_tuning_expansion(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.execute("INSERT INTO questlinexquest VALUES ('26122', '541')")
                sqlite_conn.execute("INSERT INTO questline VALUES ('541', '瓦丝琪尔，深渊之喉')")
                sqlite_conn.execute("INSERT INTO questpoiblob VALUES ('26122', '204', '0')")
                sqlite_conn.executemany(
                    "INSERT INTO uimap VALUES (?, ?, ?, ?)",
                    [
                        ("203", "3", "瓦丝琪尔", "13"),
                        ("204", "3", "无底海渊", "203"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO map VALUES ('0', '东部王国', '0')")
                sqlite_conn.execute("INSERT INTO uimapassignment VALUES ('204', '5145', '0')")
                sqlite_conn.executemany(
                    "INSERT INTO areatable VALUES (?, ?, ?, ?)",
                    [
                        ("5145", "无底海渊", "5146", "53"),
                        ("5146", "瓦丝琪尔", "0", "53"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO contenttuning VALUES ('53', '3')")
                sqlite_conn.execute(
                    "INSERT INTO questv2clitask VALUES ('26122', '海中任务', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0')"
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_26122 = next(row for row in export_rows if row["QuestID"] == 26122)
        self.assertEqual(quest_26122["MapExpansionID"], 3)
        self.assertEqual(quest_26122["MapExpansionName"], "Cataclysm")
        self.assertEqual(quest_26122["ContentExpansionID"], 3)
        self.assertEqual(quest_26122["ContentExpansionName"], "Cataclysm")

    def test_fetch_export_rows_uses_filt_races_and_classes_when_player_condition_masks_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.execute("INSERT INTO questlinexquest VALUES ('3001', '701')")
                sqlite_conn.execute("INSERT INTO questline VALUES ('701', 'Faction Filter Line')")
                sqlite_conn.execute("INSERT INTO questpoiblob VALUES ('3001', '12', '34')")
                sqlite_conn.execute("INSERT INTO uimap VALUES ('12', '3', 'Durotar', '')")
                sqlite_conn.execute("INSERT INTO map VALUES ('34', 'Kalimdor', '0')")
                sqlite_conn.execute("INSERT INTO questinfo VALUES ('5', 'Bounty')")
                sqlite_conn.execute(
                    "INSERT INTO questv2clitask VALUES ('3001', 'Faction Quest', '9003', '2', '0', '0', '4', '0', '0', '0', '0', '5')"
                )
                sqlite_conn.execute(
                    "INSERT INTO playercondition VALUES ('9003', '', '', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0')"
                )
                sqlite_conn.executemany(
                    "INSERT INTO chrraces VALUES (?, ?, ?, ?)",
                    [
                        ("1", "Human", "0", "0"),
                        ("2", "Orc", "1", "1"),
                    ],
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_3001 = next(row for row in export_rows if row["QuestID"] == 3001)
        self.assertEqual(quest_3001["FactionTag"], "horde")
        self.assertEqual(quest_3001["FactionCondition"], "horde")
        self.assertEqual(quest_3001["FactionMaskRaw"], 2)
        self.assertEqual(quest_3001["ClassCondition"], "hunter")
        self.assertEqual(quest_3001["ClassMaskRaw"], 4)

    def test_fetch_export_rows_promotes_nested_uimap_to_player_visible_parent_map(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.execute("INSERT INTO questlinexquest VALUES ('33408', '18')")
                sqlite_conn.execute("INSERT INTO questline VALUES ('18', '突袭刀塔堡垒')")
                sqlite_conn.execute("INSERT INTO questpoiblob VALUES ('33408', '526', '1116')")
                sqlite_conn.executemany(
                    "INSERT INTO uimap VALUES (?, ?, ?, ?)",
                    [
                        ("525", "3", "霜火岭", "572"),
                        ("526", "5", "图格尔的巢穴", "525"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO map VALUES ('1116', '德拉诺', '5')")
                sqlite_conn.execute(
                    "INSERT INTO questv2clitask VALUES ('33408', 'Raid Quest', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0')"
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_33408 = next(row for row in export_rows if row["QuestID"] == 33408)
        self.assertEqual(quest_33408["UiMapID"], 525)
        self.assertEqual(quest_33408["UiMapType"], 3)
        self.assertEqual(quest_33408["ZoneName"], "霜火岭")
        self.assertEqual(quest_33408["MapID"], 1116)
        self.assertEqual(quest_33408["MapExpansionID"], 5)

    def test_fetch_export_rows_includes_questline_quest_without_map_and_assigns_unknown_expansion(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.execute("INSERT INTO questlinexquest VALUES ('4001', '801')")
                sqlite_conn.execute("INSERT INTO questline VALUES ('801', 'No Map Line')")
                sqlite_conn.execute(
                    "INSERT INTO questv2clitask VALUES ('4001', 'Mapless Quest', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0')"
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_4001 = next(row for row in export_rows if row["QuestID"] == 4001)
        self.assertEqual(quest_4001["QuestLineID"], "801")
        self.assertEqual(quest_4001["QuestLineNames"], "No Map Line")
        self.assertEqual(quest_4001["UiMapID"], "")
        self.assertEqual(quest_4001["MapID"], "")
        self.assertEqual(quest_4001["MapExpansionID"], 99)
        self.assertEqual(quest_4001["MapExpansionName"], "Unknown Questline")
        self.assertEqual(quest_4001["ContentExpansionID"], 99)
        self.assertEqual(quest_4001["ContentExpansionName"], "Unknown Questline")

    def test_fetch_export_rows_prefers_real_content_expansion_over_unknown_99(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            db_path = Path(temp_dir_name) / "wow.db"
            sqlite_conn = sqlite3.connect(db_path)
            try:
                create_schema(sqlite_conn)
                sqlite_conn.executemany(
                    "INSERT INTO questlinexquest VALUES (?, ?)",
                    [
                        ("5001", "901"),
                        ("5002", "901"),
                    ],
                )
                sqlite_conn.execute("INSERT INTO questline VALUES ('901', 'Mixed Expansion Line')")
                sqlite_conn.execute("INSERT INTO questpoiblob VALUES ('5002', '2112', '2444')")
                sqlite_conn.execute("INSERT INTO uimap VALUES ('2112', '3', 'Valdrakken', '')")
                sqlite_conn.execute("INSERT INTO map VALUES ('2444', 'Dragon Isles', '9')")
                sqlite_conn.executemany(
                    "INSERT INTO questv2clitask VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        ("5001", "Unknown Expansion Quest", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"),
                        ("5002", "Known Expansion Quest", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"),
                    ],
                )
                sqlite_conn.commit()
            finally:
                sqlite_conn.close()

            export_rows = fetch_export_rows(db_path)

        quest_5001 = next(row for row in export_rows if row["QuestID"] == 5001)
        quest_5002 = next(row for row in export_rows if row["QuestID"] == 5002)
        self.assertEqual(quest_5001["MapExpansionID"], 99)
        self.assertEqual(quest_5001["ContentExpansionID"], 9)
        self.assertEqual(quest_5002["MapExpansionID"], 9)
        self.assertEqual(quest_5002["ContentExpansionID"], 9)


if __name__ == "__main__":
    unittest.main()
