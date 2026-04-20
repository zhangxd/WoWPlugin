#!/usr/bin/env python3
"""Export merged quest + achievement task data directly from wow.db.

Single-entry quest export script:
1) Export merged quest-achievement CSV for auditing.
2) Export WoWPlugin InstanceQuestlines.lua runtime data.
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path
import sys

try:
    from scripts.export.export_instance_questlines_runtime import (
        build_instance_questlines_model,
        load_ordered_quest_line_members,
        write_instance_questlines_lua,
    )
except ModuleNotFoundError:
    # Allow running as `python scripts/export/xxx.py` from arbitrary cwd.
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from scripts.export.export_instance_questlines_runtime import (
        build_instance_questlines_model,
        load_ordered_quest_line_members,
        write_instance_questlines_lua,
    )


EXPANSION_NAMES = {
    0: "经典旧世",
    1: "燃烧的远征",
    2: "巫妖王之怒",
    3: "大地的裂变",
    4: "熊猫人之谜",
    5: "德拉诺之王",
    6: "军团再临",
    7: "争霸艾泽拉斯",
    8: "暗影国度",
    9: "巨龙时代",
    10: "地心之战",
    11: "至暗之夜",
}

MAP_EXPANSION_TO_ACHIEVEMENT_CODE = {index: index for index in range(12)}

EXPANSION_KEYWORDS = [
    (0, ("经典旧世", "东部王国", "卡利姆多")),
    (1, ("燃烧的远征", "外域")),
    (2, ("巫妖王之怒", "诺森德")),
    (3, ("大地的裂变", "大灾变")),
    (4, ("熊猫人之谜", "潘达利亚")),
    (5, ("德拉诺之王", "德拉诺")),
    (6, ("军团再临", "军团")),
    (7, ("争霸艾泽拉斯",)),
    (8, ("暗影国度", "暗影界", "盟约圣所")),
    (9, ("巨龙时代", "巨龙群岛")),
    (10, ("地心之战",)),
    (11, ("至暗之夜",)),
]

FACTION_NAMES = {
    "-1": "全阵营",
    "0": "部落",
    "1": "联盟",
}

DEFAULT_UNKNOWN_ORDER = 2_147_483_647


def script_root() -> Path:
    return Path(__file__).resolve().parent


def wowplugin_root() -> Path:
    return script_root().parents[1]


def wowtools_root() -> Path:
    return wowplugin_root().parent / "WoWTools"


def default_db_path() -> Path:
    return wowtools_root() / "data" / "sqlite" / "wow.db"


def default_output_path() -> Path:
    return wowtools_root() / "outputs" / "toolbox" / "quest_achievement_merged_from_db.csv"


def default_lua_output_path() -> Path:
    return wowplugin_root() / "Toolbox" / "Data" / "InstanceQuestlines.lua"


def to_positive_int(value: object) -> int | None:
    if value in (None, ""):
        return None
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    if number <= 0:
        return None
    return number


def to_int_or_none(value: object) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def majority_int(values: list[int]) -> int | None:
    if not values:
        return None
    value_counter = Counter(values)
    highest_count = max(value_counter.values())
    candidates = [value for value, count in value_counter.items() if count == highest_count]
    return min(candidates)


def select_preferred_expansion(values: list[int]) -> int | None:
    """Prefer non-classic expansions when both classic and modern values are present."""

    if not values:
        return None
    non_classic_values = [value for value in values if value != 0]
    if non_classic_values:
        return majority_int(non_classic_values)
    return majority_int(values)


def resolve_effective_mask(*mask_values: object) -> int | None:
    normalized_masks: list[int] = []
    for value in mask_values:
        normalized = to_positive_int(value)
        if normalized is not None:
            normalized_masks.append(normalized)
    if not normalized_masks:
        return None

    effective_mask = normalized_masks[0]
    for additional_mask in normalized_masks[1:]:
        intersection = effective_mask & additional_mask
        if intersection > 0:
            effective_mask = intersection
    return effective_mask


def load_race_faction_masks(sqlite_conn: sqlite3.Connection) -> tuple[int, int]:
    alliance_mask = 0
    horde_mask = 0
    query = """
    SELECT PlayableRaceBit, Alliance
    FROM chrraces
    WHERE TRIM(COALESCE(PlayableRaceBit, '')) <> ''
    """
    for playable_race_bit, alliance_code in sqlite_conn.execute(query).fetchall():
        race_bit = to_int_or_none(playable_race_bit)
        if race_bit is None or race_bit < 0:
            continue
        race_mask = 1 << race_bit
        team = to_int_or_none(alliance_code)
        if team == 0:
            alliance_mask |= race_mask
        elif team == 1:
            horde_mask |= race_mask
    return alliance_mask, horde_mask


def faction_id_from_race_mask(race_mask: int | None, alliance_mask: int, horde_mask: int) -> str:
    if race_mask is None or race_mask <= 0:
        return "-1"
    is_alliance = (race_mask & alliance_mask) != 0
    is_horde = (race_mask & horde_mask) != 0
    if is_alliance and not is_horde:
        return "1"
    if is_horde and not is_alliance:
        return "0"
    return "-1"


def load_category_map(sqlite_conn: sqlite3.Connection) -> dict[str, tuple[str, str]]:
    category_map: dict[str, tuple[str, str]] = {}
    for category_id, category_name, parent_id in sqlite_conn.execute(
        "SELECT ID, Name_lang, Parent FROM achievement_category"
    ).fetchall():
        category_map[str(category_id)] = (category_name or "", str(parent_id) if parent_id is not None else "")
    return category_map


def collect_category_path_names(category_id: str, category_map: dict[str, tuple[str, str]]) -> list[str]:
    names: list[str] = []
    current_id = category_id
    visited_ids: set[str] = set()
    while current_id and current_id not in visited_ids and current_id != "-1":
        visited_ids.add(current_id)
        current_entry = category_map.get(current_id)
        if current_entry is None:
            break
        current_name, parent_id = current_entry
        if current_name:
            names.append(current_name)
        current_id = parent_id
    return names


def infer_achievement_expansion_code(
    category_id: str,
    achievement_title: str,
    category_map: dict[str, tuple[str, str]],
) -> int | None:
    candidate_texts = collect_category_path_names(category_id, category_map)
    if achievement_title:
        candidate_texts.append(achievement_title)
    for expansion_code, keywords in EXPANSION_KEYWORDS:
        for text in candidate_texts:
            if any(keyword in text for keyword in keywords):
                return expansion_code
    return None


def normalize_achievement_faction(faction_value: object) -> str:
    if faction_value is None:
        return "-1"
    text_value = str(faction_value).strip()
    if text_value in ("-1", "0", "1"):
        return text_value
    return "-1"


def resolve_faction_from_achievements(achievement_ids: list[int], achievement_faction_by_id: dict[int, str]) -> str | None:
    faction_values = {
        achievement_faction_by_id[achievement_id]
        for achievement_id in achievement_ids
        if achievement_id in achievement_faction_by_id
    }
    if not faction_values:
        return None
    if "-1" in faction_values:
        return "-1"
    if "0" in faction_values and "1" in faction_values:
        return "-1"
    if "0" in faction_values:
        return "0"
    if "1" in faction_values:
        return "1"
    return "-1"


def fetch_rows(sqlite_conn: sqlite3.Connection) -> list[dict[str, object]]:
    category_map = load_category_map(sqlite_conn)
    alliance_mask, horde_mask = load_race_faction_masks(sqlite_conn)

    questline_name_by_id: dict[int, str] = {}
    for questline_id, questline_name in sqlite_conn.execute("SELECT ID, Name_lang FROM questline").fetchall():
        questline_key = to_positive_int(questline_id)
        if questline_key is not None:
            questline_name_by_id[questline_key] = questline_name or ""

    quest_name_by_id: dict[int, str] = {}
    quest_condition_masks: dict[int, tuple[object, object]] = {}
    quest_condition_query = """
    SELECT
      qct.ID,
      qct.QuestTitle_lang,
      qct.FiltRaces,
      pc.RaceMask
    FROM questv2clitask qct
    LEFT JOIN playercondition pc ON pc.ID = qct.ConditionID
    """
    for quest_id, quest_title, filt_races, race_mask in sqlite_conn.execute(quest_condition_query).fetchall():
        quest_key = to_positive_int(quest_id)
        if quest_key is None:
            continue
        quest_name_by_id[quest_key] = quest_title or ""
        quest_condition_masks[quest_key] = (filt_races, race_mask)

    pair_order_by_key: dict[tuple[int, int], int] = {}
    quest_to_lines: dict[int, set[int]] = defaultdict(set)
    pair_query = """
    SELECT
      CAST(QuestLineID AS INTEGER) AS quest_line_id,
      CAST(QuestID AS INTEGER) AS quest_id,
      MIN(
        CASE
          WHEN TRIM(COALESCE(OrderIndex, '')) = '' THEN ?
          ELSE CAST(OrderIndex AS INTEGER)
        END
      ) AS quest_order
    FROM questlinexquest
    WHERE TRIM(COALESCE(QuestLineID, '')) <> ''
      AND TRIM(COALESCE(QuestID, '')) <> ''
      AND CAST(QuestLineID AS INTEGER) > 0
      AND CAST(QuestID AS INTEGER) > 0
    GROUP BY CAST(QuestLineID AS INTEGER), CAST(QuestID AS INTEGER)
    """
    for quest_line_id, quest_id, quest_order in sqlite_conn.execute(pair_query, (DEFAULT_UNKNOWN_ORDER,)).fetchall():
        line_key = to_positive_int(quest_line_id)
        quest_key = to_positive_int(quest_id)
        if line_key is None or quest_key is None:
            continue
        pair_key = (line_key, quest_key)
        pair_order_by_key[pair_key] = int(quest_order) if quest_order is not None else DEFAULT_UNKNOWN_ORDER
        quest_to_lines[quest_key].add(line_key)

    pair_map_expansion_candidates: dict[tuple[int, int], list[int]] = defaultdict(list)
    line_map_expansion_candidates: dict[int, list[int]] = defaultdict(list)
    map_expansion_query = """
    SELECT
      CAST(qxq.QuestLineID AS INTEGER) AS quest_line_id,
      CAST(qxq.QuestID AS INTEGER) AS quest_id,
      CAST(map.ExpansionID AS INTEGER) AS map_expansion_id
    FROM questlinexquest qxq
    JOIN questpoiblob qpb ON qpb.QuestID = qxq.QuestID
    JOIN map ON map.ID = qpb.MapID
    WHERE TRIM(COALESCE(qxq.QuestLineID, '')) <> ''
      AND TRIM(COALESCE(qxq.QuestID, '')) <> ''
      AND CAST(qxq.QuestLineID AS INTEGER) > 0
      AND CAST(qxq.QuestID AS INTEGER) > 0
      AND TRIM(COALESCE(map.ExpansionID, '')) <> ''
      AND CAST(map.ExpansionID AS INTEGER) >= 0
      AND CAST(map.ExpansionID AS INTEGER) <= 11
    """
    for quest_line_id, quest_id, map_expansion_id in sqlite_conn.execute(map_expansion_query).fetchall():
        line_key = to_positive_int(quest_line_id)
        quest_key = to_positive_int(quest_id)
        if line_key is None or quest_key is None:
            continue
        map_expansion_code = MAP_EXPANSION_TO_ACHIEVEMENT_CODE.get(int(map_expansion_id))
        if map_expansion_code is None:
            continue
        pair_key = (line_key, quest_key)
        pair_map_expansion_candidates[pair_key].append(map_expansion_code)
        line_map_expansion_candidates[line_key].append(map_expansion_code)

    pair_map_expansion_by_key: dict[tuple[int, int], int] = {}
    for pair_key, expansion_values in pair_map_expansion_candidates.items():
        selected = select_preferred_expansion(expansion_values)
        if selected is not None:
            pair_map_expansion_by_key[pair_key] = selected

    line_map_expansion_by_id: dict[int, int] = {}
    for line_id, expansion_values in line_map_expansion_candidates.items():
        selected = select_preferred_expansion(expansion_values)
        if selected is not None:
            line_map_expansion_by_id[line_id] = selected

    achievement_name_by_id: dict[int, str] = {}
    achievement_faction_by_id: dict[int, str] = {}
    achievement_expansion_by_id: dict[int, int] = {}
    achievement_query = "SELECT ID, Title_lang, Category, Faction FROM achievement"
    for achievement_id, title, category_id, faction_value in sqlite_conn.execute(achievement_query).fetchall():
        achievement_key = to_positive_int(achievement_id)
        if achievement_key is None:
            continue
        achievement_name_by_id[achievement_key] = title or ""
        achievement_faction_by_id[achievement_key] = normalize_achievement_faction(faction_value)
        inferred_expansion = infer_achievement_expansion_code(
            category_id=str(category_id) if category_id is not None else "",
            achievement_title=title or "",
            category_map=category_map,
        )
        if inferred_expansion is not None:
            achievement_expansion_by_id[achievement_key] = inferred_expansion

    pair_achievement_ids: dict[tuple[int, int], set[int]] = defaultdict(set)
    line_achievement_ids: dict[int, set[int]] = defaultdict(set)
    achievement_quest_query = """
    WITH RECURSIVE tree(achievement_id, node_id) AS (
      SELECT ID, Criteria_tree
      FROM achievement
      WHERE Criteria_tree IS NOT NULL
        AND Criteria_tree <> ''
        AND Criteria_tree <> '0'
      UNION ALL
      SELECT tree.achievement_id, ct.ID
      FROM criteriatree ct
      JOIN tree ON ct.Parent = tree.node_id
    )
    SELECT DISTINCT
      CAST(tree.achievement_id AS INTEGER) AS achievement_id,
      CAST(c.Asset AS INTEGER) AS quest_id
    FROM tree
    JOIN criteriatree ct ON ct.ID = tree.node_id
    JOIN criteria c ON c.ID = ct.CriteriaID
    WHERE c.Type = '27'
      AND c.Asset IS NOT NULL
      AND c.Asset <> ''
      AND c.Asset <> '0'
    """
    for achievement_id, quest_id in sqlite_conn.execute(achievement_quest_query).fetchall():
        achievement_key = to_positive_int(achievement_id)
        quest_key = to_positive_int(quest_id)
        if achievement_key is None or quest_key is None:
            continue
        for line_id in quest_to_lines.get(quest_key, set()):
            pair_achievement_ids[(line_id, quest_key)].add(achievement_key)
            line_achievement_ids[line_id].add(achievement_key)

    line_achievement_expansion_by_id: dict[int, int] = {}
    line_achievement_faction_by_id: dict[int, str] = {}
    for line_id, achievement_ids in line_achievement_ids.items():
        expansion_values = [
            achievement_expansion_by_id[achievement_id]
            for achievement_id in achievement_ids
            if achievement_id in achievement_expansion_by_id
        ]
        selected_expansion = select_preferred_expansion(expansion_values)
        if selected_expansion is not None:
            line_achievement_expansion_by_id[line_id] = selected_expansion

        selected_faction = resolve_faction_from_achievements(
            sorted(achievement_ids),
            achievement_faction_by_id,
        )
        if selected_faction is not None:
            line_achievement_faction_by_id[line_id] = selected_faction

    rows: list[dict[str, object]] = []
    for pair_key in sorted(
        pair_order_by_key,
        key=lambda item: (item[0], pair_order_by_key[item], item[1]),
    ):
        line_id, quest_id = pair_key
        achievement_ids = sorted(pair_achievement_ids.get(pair_key, set()))
        achievement_names = [achievement_name_by_id.get(achievement_id, "") for achievement_id in achievement_ids]

        achievement_expansion_values = [
            achievement_expansion_by_id[achievement_id]
            for achievement_id in achievement_ids
            if achievement_id in achievement_expansion_by_id
        ]
        if achievement_expansion_values:
            expansion_id = select_preferred_expansion(achievement_expansion_values)
            expansion_source = "achievement"
        elif line_id in line_achievement_expansion_by_id:
            expansion_id = line_achievement_expansion_by_id[line_id]
            expansion_source = "achievement_line"
        elif pair_key in pair_map_expansion_by_key:
            expansion_id = pair_map_expansion_by_key[pair_key]
            expansion_source = "map"
        elif line_id in line_map_expansion_by_id:
            expansion_id = line_map_expansion_by_id[line_id]
            expansion_source = "questline_map"
        else:
            expansion_id = None
            expansion_source = "unknown"

        faction_from_achievements = resolve_faction_from_achievements(achievement_ids, achievement_faction_by_id)
        if faction_from_achievements is not None:
            faction_id = faction_from_achievements
            faction_source = "achievement"
        elif line_id in line_achievement_faction_by_id:
            faction_id = line_achievement_faction_by_id[line_id]
            faction_source = "achievement_line"
        else:
            filt_races, race_mask = quest_condition_masks.get(quest_id, ("", ""))
            effective_race_mask = resolve_effective_mask(filt_races, race_mask)
            faction_id = faction_id_from_race_mask(effective_race_mask, alliance_mask, horde_mask)
            faction_source = "quest_condition" if effective_race_mask is not None else "default"

        rows.append(
            {
                "任务线id": line_id,
                "任务线名字": questline_name_by_id.get(line_id, ""),
                "任务id": quest_id,
                "任务名字": quest_name_by_id.get(quest_id, ""),
                "任务order": pair_order_by_key[pair_key],
                "资料片id": expansion_id if expansion_id is not None else "",
                "资料片名字": EXPANSION_NAMES.get(expansion_id, "") if expansion_id is not None else "",
                "资料片来源": expansion_source,
                "阵营id": faction_id,
                "阵营名字": FACTION_NAMES.get(faction_id, "全阵营"),
                "阵营来源": faction_source,
                "成就数量": len(achievement_ids),
                "成就id列表": "=".join(str(achievement_id) for achievement_id in achievement_ids),
                "成就名字列表": "=".join(achievement_names),
            }
        )

    return rows


def build_primary_uimap_by_quest(sqlite_conn: sqlite3.Connection) -> dict[int, tuple[int, str]]:
    """Return primary UiMap (id, name) for each quest from questpoiblob density."""

    uimap_name_by_id: dict[int, str] = {}
    for ui_map_id, zone_name in sqlite_conn.execute(
        "SELECT CAST(ID AS INTEGER), Name_lang FROM uimap WHERE TRIM(COALESCE(ID, '')) <> ''"
    ).fetchall():
        normalized_ui_map_id = to_positive_int(ui_map_id)
        if normalized_ui_map_id is not None:
            uimap_name_by_id[normalized_ui_map_id] = zone_name or ""

    primary_uimap_by_quest: dict[int, tuple[int, str]] = {}
    query = """
    SELECT
      CAST(QuestID AS INTEGER) AS quest_id,
      CAST(UiMapID AS INTEGER) AS ui_map_id,
      COUNT(*) AS point_count
    FROM questpoiblob
    WHERE TRIM(COALESCE(QuestID, '')) <> ''
      AND TRIM(COALESCE(UiMapID, '')) <> ''
      AND CAST(QuestID AS INTEGER) > 0
      AND CAST(UiMapID AS INTEGER) > 0
    GROUP BY CAST(QuestID AS INTEGER), CAST(UiMapID AS INTEGER)
    ORDER BY CAST(QuestID AS INTEGER), point_count DESC, CAST(UiMapID AS INTEGER)
    """
    for quest_id, ui_map_id, _ in sqlite_conn.execute(query).fetchall():
        normalized_quest_id = to_positive_int(quest_id)
        normalized_ui_map_id = to_positive_int(ui_map_id)
        if normalized_quest_id is None or normalized_ui_map_id is None:
            continue
        if normalized_quest_id in primary_uimap_by_quest:
            continue
        primary_uimap_by_quest[normalized_quest_id] = (
            normalized_ui_map_id,
            uimap_name_by_id.get(normalized_ui_map_id, ""),
        )
    return primary_uimap_by_quest


def to_runtime_faction_values(faction_id: str) -> tuple[str, str]:
    """Convert normalized faction id into runtime-facing faction tag/condition."""

    if faction_id == "1":
        return "alliance", "alliance"
    if faction_id == "0":
        return "horde", "horde"
    return "shared", "alliance=horde"


def build_runtime_rows_for_wowplugin(
    merged_rows: list[dict[str, object]],
    primary_uimap_by_quest: dict[int, tuple[int, str]],
) -> list[dict[str, str]]:
    """Build row shape consumed by build_instance_questlines_model."""

    runtime_rows: list[dict[str, str]] = []
    for merged_row in merged_rows:
        quest_id = int(merged_row["任务id"])
        quest_line_id = int(merged_row["任务线id"])
        ui_map_id, zone_name = primary_uimap_by_quest.get(quest_id, (0, ""))
        faction_id = str(merged_row["阵营id"])
        faction_tag, faction_condition = to_runtime_faction_values(faction_id)
        content_expansion_id = merged_row.get("资料片id")
        content_expansion_text = (
            ""
            if content_expansion_id in (None, "")
            else str(content_expansion_id)
        )
        runtime_rows.append(
            {
                "QuestID": str(quest_id),
                "QuestName": str(merged_row["任务名字"] or ""),
                "QuestLineID": str(quest_line_id),
                "QuestLineNames": str(merged_row["任务线名字"] or ""),
                "UiMapID": str(ui_map_id) if ui_map_id > 0 else "",
                "ZoneName": zone_name,
                "FactionTag": faction_tag,
                "FactionCondition": faction_condition,
                "FactionMaskRaw": "",
                "ClassMaskRaw": "",
                "ContentExpansionID": content_expansion_text,
            }
        )
    return runtime_rows


def write_csv(output_path: Path, rows: list[dict[str, object]]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "任务线id",
        "任务线名字",
        "任务id",
        "任务名字",
        "任务order",
        "资料片id",
        "资料片名字",
        "资料片来源",
        "阵营id",
        "阵营名字",
        "阵营来源",
        "成就数量",
        "成就id列表",
        "成就名字列表",
    ]
    with output_path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Merge quest + achievement task data from wow.db and export WoWPlugin InstanceQuestlines.lua."
    )
    parser.add_argument("--db", type=Path, default=default_db_path(), help="Path to wow.db")
    parser.add_argument("--output-csv", type=Path, default=default_output_path(), help="Merged CSV output path")
    parser.add_argument("--output-lua", type=Path, default=default_lua_output_path(), help="InstanceQuestlines.lua output path")
    parser.add_argument("--skip-csv", action="store_true", help="Skip writing merged CSV")
    parser.add_argument("--skip-lua", action="store_true", help="Skip writing InstanceQuestlines.lua")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    sqlite_conn = sqlite3.connect(str(args.db))
    try:
        rows = fetch_rows(sqlite_conn)
        primary_uimap_by_quest = build_primary_uimap_by_quest(sqlite_conn)
    finally:
        sqlite_conn.close()

    if not args.skip_csv:
        write_csv(args.output_csv, rows)
        print(args.output_csv)

    if not args.skip_lua:
        runtime_rows = build_runtime_rows_for_wowplugin(rows, primary_uimap_by_quest)
        ordered_quest_ids_by_line, quest_line_name_by_id = load_ordered_quest_line_members(args.db)
        runtime_model = build_instance_questlines_model(runtime_rows, ordered_quest_ids_by_line, quest_line_name_by_id)
        write_instance_questlines_lua(args.output_lua, runtime_model)
        print(args.output_lua)
    print(f"rows={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
