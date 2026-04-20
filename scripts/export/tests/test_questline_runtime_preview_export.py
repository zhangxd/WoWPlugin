from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.export.questline_runtime_preview_export import (
    build_runtime_preview_model,
    write_runtime_preview_lua,
)


class QuestlineRuntimePreviewExportTests(unittest.TestCase):
    def test_build_runtime_preview_model_filters_rows_without_questline(self) -> None:
        model = build_runtime_preview_model(
            [
                {
                    "QuestID": "1001",
                    "QuestName": "Quest Alpha",
                    "QuestLineID": "501",
                    "QuestLineNames": "Line Alpha",
                    "UiMapID": "12",
                    "ZoneName": "Map A",
                    "FactionTag": "alliance",
                    "FactionCondition": "alliance",
                    "FactionMaskRaw": "1",
                    "ContentExpansionID": "9",
                },
                {
                    "QuestID": "1001",
                    "QuestName": "Quest Alpha",
                    "QuestLineID": "501",
                    "QuestLineNames": "Line Alpha",
                    "UiMapID": "13",
                    "ZoneName": "Map B",
                    "FactionTag": "alliance",
                    "FactionCondition": "alliance",
                    "FactionMaskRaw": "1",
                    "ContentExpansionID": "9",
                },
                {
                    "QuestID": "1002",
                    "QuestName": "Quest Beta",
                    "QuestLineID": "",
                    "QuestLineNames": "",
                    "UiMapID": "99",
                    "ZoneName": "Ignored Map",
                    "FactionTag": "",
                    "FactionCondition": "",
                    "FactionMaskRaw": "",
                    "ContentExpansionID": "",
                },
            ]
        )

        self.assertEqual(sorted(model.quests.keys()), [1001])
        self.assertEqual(sorted(model.quest_lines.keys()), [501])
        self.assertEqual(model.quests[1001].ui_map_ids, [12, 13])
        self.assertEqual(model.quest_lines[501].primary_ui_map_id, 12)
        self.assertAlmostEqual(model.quest_lines[501].primary_map_share, 0.5)

    def test_write_runtime_preview_lua_includes_comments_and_core_fields(self) -> None:
        model = build_runtime_preview_model(
            [
                {
                    "QuestID": "1001",
                    "QuestName": "Quest Alpha",
                    "QuestLineID": "501",
                    "QuestLineNames": "Line Alpha",
                    "UiMapID": "12",
                    "ZoneName": "Map A",
                    "FactionTag": "alliance",
                    "FactionCondition": "alliance",
                    "FactionMaskRaw": "1",
                    "ContentExpansionID": "9",
                }
            ]
        )

        with tempfile.TemporaryDirectory() as temp_dir_name:
            output_path = Path(temp_dir_name) / "preview.lua"
            write_runtime_preview_lua(output_path, model)
            output_text = output_path.read_text(encoding="utf-8")

        self.assertIn("InstanceQuestlinesRuntimePreview", output_text)
        self.assertIn("[1001] = { -- Quest Alpha", output_text)
        self.assertIn("QuestLineIDs = { 501 }", output_text)
        self.assertIn("UiMapIDs = { 12 }", output_text)
        self.assertIn('FactionTags = { "alliance" }', output_text)
        self.assertIn("ContentExpansionID = 9", output_text)
        self.assertIn("[501] = { -- Line Alpha", output_text)
        self.assertIn("PrimaryUiMapID = 12, -- Map A", output_text)


if __name__ == "__main__":
    unittest.main()
