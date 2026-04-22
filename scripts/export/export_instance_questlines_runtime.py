#!/usr/bin/env python3
"""[Internal] 聚合任务行生成正式 InstanceQuestlines.lua。

生产任务导出入口已统一为：
`scripts/export/export_quest_achievement_merged_from_db.py`
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

UNKNOWN_EXPANSION_ID = 99
UNKNOWN_UI_MAP_ID = 999999
UNKNOWN_UI_MAP_NAME = "未归属地图"


@dataclass
class QuestRuntimeEntry:
    """正式任务节点。"""

    quest_id: int
    quest_name: str
    quest_line_ids: list[int]
    ui_map_ids: list[int]
    faction_tags: list[str]
    faction_conditions: list[str]
    race_mask_values: list[int]
    class_mask_values: list[int]
    content_expansion_id: int | None


@dataclass
class QuestLineRuntimeEntry:
    """正式任务线节点。"""

    quest_line_id: int
    quest_line_name: str
    quest_ids: list[int]
    ui_map_id: int | None
    ui_map_ids: list[int]
    primary_ui_map_id: int | None
    primary_ui_map_name: str
    primary_map_count: int
    primary_map_share: float
    faction_tags: list[str]
    race_mask_values: list[int]
    class_mask_values: list[int]
    content_expansion_id: int | None


@dataclass
class CampaignRuntimeEntry:
    """正式战役节点。"""

    campaign_id: int
    campaign_name: str
    quest_line_ids: list[int]


@dataclass
class AchievementRuntimeEntry:
    """正式成就节点。"""

    achievement_id: int
    achievement_name: str
    quest_line_ids: list[int]
    content_expansion_id: int


@dataclass
class InstanceQuestlinesRuntimeModel:
    """正式运行时模型。"""

    generated_at: str
    quests: dict[int, QuestRuntimeEntry]
    quest_lines: dict[int, QuestLineRuntimeEntry]
    campaigns: dict[int, CampaignRuntimeEntry]
    expansions: dict[int, list[int]]
    expansion_campaigns: dict[int, list[int]]
    achievements: dict[int, AchievementRuntimeEntry]
    expansion_achievements: dict[int, list[int]]


def script_root() -> Path:
    return Path(__file__).resolve().parent


def wowplugin_root() -> Path:
    return script_root().parents[1]


def wowtools_root() -> Path:
    return wowplugin_root().parent / "WoWTools"


def default_csv_path() -> Path:
    return wowtools_root() / "outputs" / "toolbox" / "quest_expansion_map.csv"


def default_db_path() -> Path:
    return wowtools_root() / "data" / "sqlite" / "wow.db"


def default_output_path() -> Path:
    return wowplugin_root() / "Toolbox" / "Data" / "InstanceQuestlines.lua"


def open_csv_reader(csv_path: Path) -> tuple[csv.DictReader, object]:
    last_error: Exception | None = None
    for encoding in ("utf-8-sig", "utf-8", "gb18030", "cp936"):
        try:
            csv_file = csv_path.open("r", encoding=encoding, newline="")
            reader = csv.DictReader(csv_file)
            next(reader, None)  # 第二行中文字段名
            return reader, csv_file
        except Exception as error:  # noqa: PERF203
            last_error = error
            try:
                csv_file.close()
            except Exception:
                pass
    raise RuntimeError(f"unable to decode csv: {csv_path}") from last_error


def collect_positive_ints(values: list[str | int]) -> list[int]:
    seen_values: set[int] = set()
    collected_values: list[int] = []
    for value_object in values:
        if value_object in ("", None):
            continue
        normalized_value = int(value_object)
        if normalized_value <= 0 or normalized_value in seen_values:
            continue
        seen_values.add(normalized_value)
        collected_values.append(normalized_value)
    return collected_values


def collect_non_empty_strings(values: list[str]) -> list[str]:
    seen_values: set[str] = set()
    collected_values: list[str] = []
    for value_text in values:
        if not value_text:
            continue
        if value_text in seen_values:
            continue
        seen_values.add(value_text)
        collected_values.append(value_text)
    return collected_values


def load_ordered_quest_line_members(db_path: Path) -> tuple[dict[int, list[int]], dict[int, str]]:
    """从 wow.db 读取任务线顺序和名称。"""

    sqlite_conn = sqlite3.connect(str(db_path))
    sqlite_conn.row_factory = sqlite3.Row
    try:
        ordered_quest_ids_by_line: dict[int, list[int]] = defaultdict(list)
        quest_line_name_by_id: dict[int, str] = {}
        query = """
        SELECT
          CAST(qlxq.QuestLineID AS INTEGER) AS quest_line_id,
          ql.Name_lang AS quest_line_name,
          CAST(qlxq.QuestID AS INTEGER) AS quest_id
        FROM questlinexquest qlxq
        LEFT JOIN questline ql ON ql.ID = qlxq.QuestLineID
        WHERE TRIM(qlxq.QuestLineID) <> ''
          AND TRIM(qlxq.QuestID) <> ''
          AND CAST(qlxq.QuestLineID AS INTEGER) > 0
          AND CAST(qlxq.QuestID AS INTEGER) > 0
        ORDER BY
          CAST(qlxq.QuestLineID AS INTEGER),
          CAST(qlxq.OrderIndex AS INTEGER),
          CAST(qlxq.QuestID AS INTEGER)
        """
        for row in sqlite_conn.execute(query).fetchall():
            quest_line_id = int(row["quest_line_id"])
            quest_id = int(row["quest_id"])
            if quest_id not in ordered_quest_ids_by_line[quest_line_id]:
                ordered_quest_ids_by_line[quest_line_id].append(quest_id)
            if row["quest_line_name"]:
                quest_line_name_by_id.setdefault(quest_line_id, row["quest_line_name"])
        return dict(ordered_quest_ids_by_line), quest_line_name_by_id
    finally:
        sqlite_conn.close()


def load_campaign_links(db_path: Path) -> list[dict[str, int | str]]:
    """从 wow.db 读取战役到任务线的关系。"""

    sqlite_conn = sqlite3.connect(str(db_path))
    sqlite_conn.row_factory = sqlite3.Row
    try:
        query = """
        SELECT
          CAST(cxq.CampaignID AS INTEGER) AS campaign_id,
          CAST(cxq.QuestLineID AS INTEGER) AS quest_line_id,
          CAST(cxq.OrderIndex AS INTEGER) AS order_index,
          c.Title_lang AS campaign_name
        FROM campaignxquestline cxq
        LEFT JOIN campaign c ON c.ID = cxq.CampaignID
        WHERE TRIM(COALESCE(cxq.CampaignID, '')) <> ''
          AND TRIM(COALESCE(cxq.QuestLineID, '')) <> ''
          AND CAST(cxq.CampaignID AS INTEGER) > 0
          AND CAST(cxq.QuestLineID AS INTEGER) > 0
        ORDER BY
          CAST(cxq.CampaignID AS INTEGER),
          CAST(cxq.OrderIndex AS INTEGER),
          CAST(cxq.QuestLineID AS INTEGER)
        """
        campaign_link_rows = []
        for row in sqlite_conn.execute(query).fetchall():
            campaign_link_rows.append(
                {
                    "campaign_id": int(row["campaign_id"] or 0),
                    "quest_line_id": int(row["quest_line_id"] or 0),
                    "order_index": int(row["order_index"] or 0),
                    "campaign_name": (row["campaign_name"] or "").strip(),
                }
            )
        return campaign_link_rows
    except sqlite3.OperationalError:
        # 兼容缺少战役表的精简数据库（此时不导出战役分组）。
        return []
    finally:
        sqlite_conn.close()


def build_instance_questlines_model(
    csv_rows: list[dict[str, str]],
    ordered_quest_ids_by_line: dict[int, list[int]],
    quest_line_name_by_id: dict[int, str],
    campaign_link_rows: list[dict[str, int | str]] | None = None,
) -> InstanceQuestlinesRuntimeModel:
    """从 CSV 行和 DB 顺序构建正式 InstanceQuestlines 运行时模型。"""

    quest_aggregate: dict[int, dict[str, object]] = {}
    quest_line_aggregate: dict[int, dict[str, object]] = {}
    achievement_aggregate: dict[int, dict[str, object]] = {}

    for row in csv_rows:
        quest_line_id_text = row.get("QuestLineID") or ""
        if quest_line_id_text == "":
            continue

        quest_id = int(row["QuestID"])
        quest_name = row.get("QuestName") or ""
        ui_map_id = int(row["UiMapID"]) if row.get("UiMapID") else 0
        ui_map_name = row.get("ZoneName") or ""
        content_expansion_id = int(row["ContentExpansionID"]) if row.get("ContentExpansionID") else None
        faction_tag = row.get("FactionTag") or ""
        faction_condition = row.get("FactionCondition") or ""
        race_mask_value = int(row["FactionMaskRaw"]) if row.get("FactionMaskRaw") else None
        class_mask_value = int(row["ClassMaskRaw"]) if row.get("ClassMaskRaw") else None

        quest_line_ids = collect_positive_ints((row.get("QuestLineID") or "").split("="))
        quest_line_names = (row.get("QuestLineNames") or "").split("=")
        achievement_id_texts = (row.get("AchievementIDs") or "").split("=")
        achievement_names = (row.get("AchievementNames") or "").split("=")
        achievement_expansion_texts = (row.get("AchievementExpansionIDs") or "").split("=")

        quest_state = quest_aggregate.setdefault(
            quest_id,
            {
                "name": quest_name,
                "quest_line_ids": [],
                "ui_map_ids": [],
                "faction_tags": [],
                "faction_conditions": [],
                "race_mask_values": [],
                "class_mask_values": [],
                "content_expansion_id": content_expansion_id,
            },
        )
        quest_state["quest_line_ids"] = collect_positive_ints(list(quest_state["quest_line_ids"]) + quest_line_ids)
        if ui_map_id > 0:
            quest_state["ui_map_ids"] = collect_positive_ints(list(quest_state["ui_map_ids"]) + [ui_map_id])
        quest_state["faction_tags"] = collect_non_empty_strings(list(quest_state["faction_tags"]) + [faction_tag])
        quest_state["faction_conditions"] = collect_non_empty_strings(list(quest_state["faction_conditions"]) + [faction_condition])
        if race_mask_value is not None:
            quest_state["race_mask_values"] = collect_positive_ints(list(quest_state["race_mask_values"]) + [race_mask_value])
        if class_mask_value is not None:
            quest_state["class_mask_values"] = collect_positive_ints(list(quest_state["class_mask_values"]) + [class_mask_value])
        if quest_state["content_expansion_id"] is None and content_expansion_id is not None:
            quest_state["content_expansion_id"] = content_expansion_id

        for index, quest_line_id in enumerate(quest_line_ids):
            csv_quest_line_name = quest_line_names[index] if index < len(quest_line_names) else ""
            quest_line_name = quest_line_name_by_id.get(quest_line_id, csv_quest_line_name)
            line_state = quest_line_aggregate.setdefault(
                quest_line_id,
                {
                    "name": quest_line_name,
                    "quest_ids_seen": set(),
                    "ui_map_counter": Counter(),
                    "ui_map_name_by_id": {},
                    "faction_tags": [],
                    "race_mask_values": [],
                    "class_mask_values": [],
                    "content_expansion_id": content_expansion_id,
                },
            )
            line_state["quest_ids_seen"].add(quest_id)
            if ui_map_id > 0:
                line_state["ui_map_counter"][ui_map_id] += 1
                if ui_map_name:
                    line_state["ui_map_name_by_id"].setdefault(ui_map_id, ui_map_name)
            line_state["faction_tags"] = collect_non_empty_strings(list(line_state["faction_tags"]) + [faction_tag])
            if race_mask_value is not None:
                line_state["race_mask_values"] = collect_positive_ints(list(line_state["race_mask_values"]) + [race_mask_value])
            if class_mask_value is not None:
                line_state["class_mask_values"] = collect_positive_ints(list(line_state["class_mask_values"]) + [class_mask_value])
            if line_state["content_expansion_id"] is None and content_expansion_id is not None:
                line_state["content_expansion_id"] = content_expansion_id

        for index, achievement_id_text in enumerate(achievement_id_texts):
            if achievement_id_text in ("", None):
                continue
            achievement_id = int(achievement_id_text)
            if achievement_id <= 0:
                continue

            achievement_name = achievement_names[index] if index < len(achievement_names) else ""
            achievement_expansion_text = achievement_expansion_texts[index] if index < len(achievement_expansion_texts) else ""
            achievement_expansion_id = int(achievement_expansion_text) if achievement_expansion_text not in ("", None) else None
            if achievement_expansion_id is not None and achievement_expansion_id < 0:
                achievement_expansion_id = None

            achievement_state = achievement_aggregate.setdefault(
                achievement_id,
                {
                    "name": "",
                    "quest_line_ids": [],
                    "category_expansion_counter": Counter(),
                    "fallback_expansion_counter": Counter(),
                },
            )

            if achievement_state["name"] == "" and achievement_name != "":
                achievement_state["name"] = achievement_name
            achievement_state["quest_line_ids"] = collect_positive_ints(
                list(achievement_state["quest_line_ids"]) + quest_line_ids
            )
            if achievement_expansion_id is not None:
                achievement_state["category_expansion_counter"][achievement_expansion_id] += 1
            if content_expansion_id is not None:
                achievement_state["fallback_expansion_counter"][content_expansion_id] += 1

    quests = {
        quest_id: QuestRuntimeEntry(
            quest_id=quest_id,
            quest_name=quest_state["name"],
            quest_line_ids=quest_state["quest_line_ids"],
            ui_map_ids=quest_state["ui_map_ids"],
            faction_tags=sorted(quest_state["faction_tags"]),
            faction_conditions=quest_state["faction_conditions"],
            race_mask_values=quest_state["race_mask_values"],
            class_mask_values=quest_state["class_mask_values"],
            content_expansion_id=quest_state["content_expansion_id"],
        )
        for quest_id, quest_state in sorted(quest_aggregate.items())
    }

    quest_lines: dict[int, QuestLineRuntimeEntry] = {}
    expansions: dict[int, list[int]] = defaultdict(list)
    for quest_line_id, line_state in sorted(quest_line_aggregate.items()):
        ordered_quest_ids = [quest_id for quest_id in ordered_quest_ids_by_line.get(quest_line_id, []) if quest_id in line_state["quest_ids_seen"]]
        trailing_quest_ids = sorted(line_state["quest_ids_seen"] - set(ordered_quest_ids))
        quest_ids = ordered_quest_ids + trailing_quest_ids

        ui_map_counter = line_state["ui_map_counter"]
        sorted_ui_map_items = sort_ui_map_counter(ui_map_counter)
        ui_map_ids = [ui_map_id for ui_map_id, _ in sorted_ui_map_items]
        if ui_map_counter:
            primary_ui_map_id, primary_map_count = sorted_ui_map_items[0]
            total_map_rows = sum(ui_map_counter.values())
            primary_map_share = primary_map_count / total_map_rows
            primary_ui_map_name = line_state["ui_map_name_by_id"].get(primary_ui_map_id, "")
            ui_map_id = primary_ui_map_id
        else:
            ui_map_id = UNKNOWN_UI_MAP_ID
            primary_ui_map_id = None
            primary_map_count = 0
            primary_map_share = 0.0
            primary_ui_map_name = UNKNOWN_UI_MAP_NAME

        content_expansion_id = line_state["content_expansion_id"]
        if content_expansion_id is not None:
            expansions[content_expansion_id].append(quest_line_id)

        quest_lines[quest_line_id] = QuestLineRuntimeEntry(
            quest_line_id=quest_line_id,
            quest_line_name=line_state["name"],
            quest_ids=quest_ids,
            ui_map_id=ui_map_id,
            ui_map_ids=ui_map_ids,
            primary_ui_map_id=primary_ui_map_id,
            primary_ui_map_name=primary_ui_map_name,
            primary_map_count=primary_map_count,
            primary_map_share=primary_map_share,
            faction_tags=sorted(line_state["faction_tags"]),
            race_mask_values=line_state["race_mask_values"],
            class_mask_values=line_state["class_mask_values"],
            content_expansion_id=content_expansion_id,
        )

    for expansion_id in expansions:
        expansions[expansion_id].sort()

    valid_quest_line_ids = set(quest_lines.keys())
    campaign_aggregate: dict[int, dict[str, object]] = {}
    for campaign_link_row in campaign_link_rows or []:
        campaign_id = int(campaign_link_row.get("campaign_id") or 0)
        quest_line_id = int(campaign_link_row.get("quest_line_id") or 0)
        order_index = int(campaign_link_row.get("order_index") or 0)
        if campaign_id <= 0 or quest_line_id <= 0 or quest_line_id not in valid_quest_line_ids:
            continue

        campaign_state = campaign_aggregate.setdefault(
            campaign_id,
            {
                "campaign_name": "",
                "quest_line_seen": set(),
                "quest_line_items": [],
            },
        )
        if campaign_state["campaign_name"] == "":
            campaign_name = str(campaign_link_row.get("campaign_name") or "").strip()
            campaign_state["campaign_name"] = campaign_name if campaign_name != "" else f"Campaign #{campaign_id}"
        if quest_line_id in campaign_state["quest_line_seen"]:
            continue
        campaign_state["quest_line_seen"].add(quest_line_id)
        campaign_state["quest_line_items"].append((order_index, quest_line_id))

    campaigns: dict[int, CampaignRuntimeEntry] = {}
    expansion_campaigns: dict[int, list[int]] = defaultdict(list)
    for campaign_id, campaign_state in sorted(campaign_aggregate.items()):
        ordered_quest_line_ids = [
            quest_line_id
            for _, quest_line_id in sorted(campaign_state["quest_line_items"], key=lambda item: (item[0], item[1]))
        ]
        if not ordered_quest_line_ids:
            continue

        campaigns[campaign_id] = CampaignRuntimeEntry(
            campaign_id=campaign_id,
            campaign_name=str(campaign_state["campaign_name"]),
            quest_line_ids=ordered_quest_line_ids,
        )

        expansion_vote_counter: dict[int, int] = {}
        for quest_line_id in ordered_quest_line_ids:
            content_expansion_id = quest_lines[quest_line_id].content_expansion_id
            if content_expansion_id is None:
                continue
            expansion_vote_counter[content_expansion_id] = expansion_vote_counter.get(content_expansion_id, 0) + 1
        if expansion_vote_counter:
            primary_expansion_id = sorted(expansion_vote_counter.items(), key=lambda item: (-item[1], item[0]))[0][0]
            expansion_campaigns[primary_expansion_id].append(campaign_id)

    for expansion_id in expansion_campaigns:
        expansion_campaigns[expansion_id].sort()

    achievements: dict[int, AchievementRuntimeEntry] = {}
    expansion_achievements: dict[int, list[int]] = defaultdict(list)
    for achievement_id, achievement_state in sorted(achievement_aggregate.items()):
        category_expansion_counter = achievement_state["category_expansion_counter"]
        fallback_expansion_counter = achievement_state["fallback_expansion_counter"]
        if category_expansion_counter:
            content_expansion_id = sorted(category_expansion_counter.items(), key=lambda item: (-item[1], item[0]))[0][0]
        elif fallback_expansion_counter:
            content_expansion_id = sorted(fallback_expansion_counter.items(), key=lambda item: (-item[1], item[0]))[0][0]
        else:
            content_expansion_id = UNKNOWN_EXPANSION_ID

        quest_line_ids = collect_positive_ints(list(achievement_state["quest_line_ids"]))
        achievement_name = str(achievement_state["name"] or "").strip()
        if achievement_name == "":
            achievement_name = f"Achievement #{achievement_id}"

        achievements[achievement_id] = AchievementRuntimeEntry(
            achievement_id=achievement_id,
            achievement_name=achievement_name,
            quest_line_ids=quest_line_ids,
            content_expansion_id=content_expansion_id,
        )
        expansion_achievements[content_expansion_id].append(achievement_id)

    for expansion_id in expansion_achievements:
        expansion_achievements[expansion_id].sort()

    return InstanceQuestlinesRuntimeModel(
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        quests=quests,
        quest_lines=quest_lines,
        campaigns=campaigns,
        expansions=dict(sorted(expansions.items())),
        expansion_campaigns=dict(sorted(expansion_campaigns.items())),
        achievements=achievements,
        expansion_achievements=dict(sorted(expansion_achievements.items())),
    )


def format_int_array(values: list[int]) -> str:
    if not values:
        return "{}"
    return "{ " + ", ".join(str(value) for value in values) + " }"


def format_string_array(values: list[str]) -> str:
    if not values:
        return "{}"
    return "{ " + ", ".join(format_lua_string(value) for value in values) + " }"


def format_lua_string(value: str) -> str:
    escaped_value = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped_value}"'


def format_optional_number(value: int | None) -> str:
    return "nil" if value is None else str(value)


def sort_ui_map_counter(ui_map_counter: Counter[int]) -> list[tuple[int, int]]:
    """按出现次数降序、UiMapID 升序稳定排序。"""

    return sorted(ui_map_counter.items(), key=lambda item: (-item[1], item[0]))


def write_instance_questlines_lua(
    output_path: Path,
    model: InstanceQuestlinesRuntimeModel,
    data_source: str = "wow.db",
    generated_by: str = "WoWPlugin/scripts/export/export_instance_questlines_runtime.py",
) -> None:
    """写入正式 InstanceQuestlines.lua。"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "--[[",
        "@contract_id instance_questlines",
        "@schema_version 8",
        "@contract_file WoWPlugin/DataContracts/instance_questlines.json",
        f"@contract_snapshot runtime-only (generated by {generated_by})",
        f"@generated_by {generated_by}",
        f"@generated_at {model.generated_at}",
        f"@data_source {data_source}",
        "@summary 冒险手册任务页签静态任务线与成就文档（CSV 聚合版）",
        "@overwrite_notice 此文件由工具生成，手改会被覆盖",
        "]]",
        "",
        "Toolbox.Data = Toolbox.Data or {}",
        "",
        "Toolbox.Data.InstanceQuestlines = {",
        "  schemaVersion = 8,",
        '  sourceMode = "live",',
        f'  generatedAt = "{model.generated_at}",',
        "",
        "  quests = {",
    ]

    for quest_id, quest_entry in model.quests.items():
        comment_name = quest_entry.quest_name or "未命名任务"
        lines.extend(
            [
                f"    [{quest_id}] = {{ -- {comment_name}",
                f"      ID = {quest_id},",
                f"      QuestLineIDs = {format_int_array(quest_entry.quest_line_ids)},",
                f"      UiMapIDs = {format_int_array(quest_entry.ui_map_ids)},",
                f"      FactionTags = {format_string_array(quest_entry.faction_tags)},",
                f"      FactionConditions = {format_string_array(quest_entry.faction_conditions)},",
                f"      RaceMaskValues = {format_int_array(quest_entry.race_mask_values)},",
                f"      ClassMaskValues = {format_int_array(quest_entry.class_mask_values)},",
                f"      ContentExpansionID = {format_optional_number(quest_entry.content_expansion_id)},",
                "    },",
            ]
        )

    lines.extend(
        [
            "  },",
            "",
            "  questLines = {",
        ]
    )

    for quest_line_id, quest_line_entry in model.quest_lines.items():
        comment_name = quest_line_entry.quest_line_name or "未命名任务线"
        name_line = (
            f"      Name_lang = {format_lua_string(quest_line_entry.quest_line_name)},"
            if quest_line_entry.quest_line_name
            else None
        )
        lines.extend(
            [
                f"    [{quest_line_id}] = {{ -- {comment_name}",
                f"      ID = {quest_line_id},",
            ]
            + ([name_line] if name_line is not None else [])
            + [
                f"      UiMapID = {format_optional_number(quest_line_entry.ui_map_id)},",
                f"      QuestIDs = {format_int_array(quest_line_entry.quest_ids)},",
                f"      UiMapIDs = {format_int_array(quest_line_entry.ui_map_ids)},",
                f"      PrimaryUiMapID = {format_optional_number(quest_line_entry.primary_ui_map_id)}, -- {quest_line_entry.primary_ui_map_name or '无地图'}",
                f"      PrimaryMapCount = {quest_line_entry.primary_map_count},",
                f"      PrimaryMapShare = {quest_line_entry.primary_map_share:.4f},",
                f"      FactionTags = {format_string_array(quest_line_entry.faction_tags)},",
                f"      RaceMaskValues = {format_int_array(quest_line_entry.race_mask_values)},",
                f"      ClassMaskValues = {format_int_array(quest_line_entry.class_mask_values)},",
                f"      ContentExpansionID = {format_optional_number(quest_line_entry.content_expansion_id)},",
                "    },",
            ]
        )

    lines.extend(
        [
            "  },",
            "",
            "  campaigns = {",
        ]
    )
    for campaign_id, campaign_entry in model.campaigns.items():
        name_line = (
            f"      Name_lang = {format_lua_string(campaign_entry.campaign_name)},"
            if campaign_entry.campaign_name != ""
            else None
        )
        lines.extend(
            [
                f"    [{campaign_id}] = {{",
                f"      ID = {campaign_id},",
            ]
            + ([name_line] if name_line is not None else [])
            + [
                f"      QuestLineIDs = {format_int_array(campaign_entry.quest_line_ids)},",
                "    },",
            ]
        )

    lines.extend(
        [
            "  },",
            "",
            "  expansions = {",
        ]
    )
    for expansion_id, quest_line_ids in model.expansions.items():
        lines.append(f"    [{expansion_id}] = {format_int_array(quest_line_ids)},")
    lines.extend(
        [
            "  },",
            "",
            "  expansionCampaigns = {",
        ]
    )
    for expansion_id, campaign_ids in model.expansion_campaigns.items():
        lines.append(f"    [{expansion_id}] = {format_int_array(campaign_ids)},")
    lines.extend(
        [
            "  },",
            "",
            "  achievements = {",
        ]
    )
    for achievement_id, achievement_entry in model.achievements.items():
        name_line = (
            f"      Name_lang = {format_lua_string(achievement_entry.achievement_name)},"
            if achievement_entry.achievement_name != ""
            else None
        )
        lines.extend(
            [
                f"    [{achievement_id}] = {{",
                f"      ID = {achievement_id},",
            ]
            + ([name_line] if name_line is not None else [])
            + [
                f"      QuestLineIDs = {format_int_array(achievement_entry.quest_line_ids)},",
                f"      ContentExpansionID = {achievement_entry.content_expansion_id},",
                "    },",
            ]
        )
    lines.extend(
        [
            "  },",
            "",
            "  expansionAchievements = {",
        ]
    )
    for expansion_id, achievement_ids in model.expansion_achievements.items():
        lines.append(f"    [{expansion_id}] = {format_int_array(achievement_ids)},")
    lines.extend(
        [
            "  },",
            "}",
            "",
        ]
    )
    output_path.write_text("\n".join(lines), encoding="utf-8")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="[Internal] 从任务行 CSV 聚合生成正式 InstanceQuestlines.lua。生产导出请使用统一入口脚本。"
    )
    parser.add_argument("--csv", type=Path, default=default_csv_path(), help="quest_expansion_map.csv path")
    parser.add_argument("--db", type=Path, default=default_db_path(), help="wow.db path for ordered questline members")
    parser.add_argument("--output", type=Path, default=default_output_path(), help="InstanceQuestlines.lua output path")
    return parser


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()

    reader, csv_file = open_csv_reader(args.csv)
    try:
        csv_rows = list(reader)
    finally:
        csv_file.close()

    ordered_quest_ids_by_line, quest_line_name_by_id = load_ordered_quest_line_members(args.db)
    campaign_link_rows = load_campaign_links(args.db)
    model = build_instance_questlines_model(
        csv_rows,
        ordered_quest_ids_by_line,
        quest_line_name_by_id,
        campaign_link_rows=campaign_link_rows,
    )
    write_instance_questlines_lua(args.output, model)
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
