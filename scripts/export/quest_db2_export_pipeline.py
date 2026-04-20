#!/usr/bin/env python3
"""[Deprecated] 从 wow.db 导出任务到地图/资料片映射 CSV。

对外任务导出入口已统一为：
`scripts/export/export_quest_achievement_merged_from_db.py`
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from pathlib import Path


EXPANSION_NAMES = {
    0: "Classic",
    1: "The Burning Crusade",
    2: "Wrath of the Lich King",
    3: "Cataclysm",
    4: "Mists of Pandaria",
    5: "Warlords of Draenor",
    6: "Legion",
    7: "Battle for Azeroth",
    8: "Shadowlands",
    9: "Dragonflight",
    10: "The War Within",
    11: "Midnight",
    12: "The Last Titan",
    99: "Unknown Questline",
}

UNKNOWN_EXPANSION_ID = 99

OUTPUT_FIELDNAMES = [
    "QuestID",
    "QuestName",
    "QuestLineID",
    "QuestLineNames",
    "QuestTypeID",
    "QuestTypeName",
    "UiMapID",
    "UiMapType",
    "ZoneName",
    "MapID",
    "MapName",
    "MapExpansionID",
    "MapExpansionName",
    "ContentExpansionID",
    "ContentExpansionName",
    "PrevQuestIDs",
    "PrevQuestLogic",
    "NextQuestIDs",
    "ExclusiveToQuestIDs",
    "BreadcrumbQuestID",
    "FactionTag",
    "FactionCondition",
    "FactionMaskRaw",
    "ClassCondition",
    "ClassMaskRaw",
    "StoryCondition",
    "StoryLogicRaw",
    "PrevQuestLogicRaw",
    "ModifierTreeID",
    "ConditionFlags",
]

OUTPUT_FIELD_LABELS_ZH = {
    "QuestID": "任务ID",
    "QuestName": "任务名称",
    "QuestLineID": "任务线ID",
    "QuestLineNames": "任务线名称",
    "QuestTypeID": "任务类型ID",
    "QuestTypeName": "任务类型名称",
    "UiMapID": "界面地图ID",
    "UiMapType": "界面地图类型",
    "ZoneName": "区域名称",
    "MapID": "地图ID",
    "MapName": "地图名称",
    "MapExpansionID": "地图资料片ID",
    "MapExpansionName": "地图资料片名称",
    "ContentExpansionID": "任务资料片ID",
    "ContentExpansionName": "任务资料片名称",
    "PrevQuestIDs": "前置任务ID列表",
    "PrevQuestLogic": "前置任务逻辑",
    "NextQuestIDs": "后续任务ID列表",
    "ExclusiveToQuestIDs": "完成条件候选任务ID列表",
    "BreadcrumbQuestID": "引导任务ID",
    "FactionTag": "阵营标记",
    "FactionCondition": "阵营条件摘要",
    "FactionMaskRaw": "阵营掩码原始值",
    "ClassCondition": "职业条件摘要",
    "ClassMaskRaw": "职业掩码原始值",
    "StoryCondition": "剧情条件摘要",
    "StoryLogicRaw": "剧情逻辑原始值",
    "PrevQuestLogicRaw": "前置逻辑原始值",
    "ModifierTreeID": "条件树ID",
    "ConditionFlags": "条件标记",
}

EXPORT_SQL = """
WITH quest_line_rows AS (
  SELECT DISTINCT
    qlxq.QuestID AS quest_id_text,
    CAST(qlxq.QuestID AS INTEGER) AS quest_id,
    CAST(qlxq.QuestLineID AS INTEGER) AS quest_line_id,
    ql.Name_lang AS quest_line_name
  FROM questlinexquest qlxq
  LEFT JOIN questline ql ON ql.ID = qlxq.QuestLineID
  WHERE TRIM(qlxq.QuestID) <> ''
    AND TRIM(qlxq.QuestLineID) <> ''
    AND CAST(qlxq.QuestID AS INTEGER) > 0
    AND CAST(qlxq.QuestLineID AS INTEGER) > 0
),
quest_line_grouped AS (
  SELECT
    quest_id_text,
    GROUP_CONCAT(quest_line_id, '=') AS quest_line_ids,
    GROUP_CONCAT(COALESCE(quest_line_name, ''), '=') AS quest_line_names
  FROM (
    SELECT quest_id_text, quest_id, quest_line_id, quest_line_name
    FROM quest_line_rows
    ORDER BY quest_id, quest_line_id
  )
  GROUP BY quest_id_text
),
quest_base_rows AS (
  SELECT DISTINCT
    quest_id_text,
    quest_id
  FROM quest_line_rows
),
quest_poi_rows AS (
  SELECT DISTINCT
    qpb.QuestID AS quest_id_text,
    CAST(qpb.QuestID AS INTEGER) AS quest_id,
    qpb.UiMapID AS ui_map_id_text,
    CAST(qpb.UiMapID AS INTEGER) AS ui_map_id,
    qpb.MapID AS map_id_text,
    CAST(qpb.MapID AS INTEGER) AS map_id
  FROM questpoiblob qpb
  WHERE TRIM(qpb.QuestID) <> ''
    AND TRIM(qpb.UiMapID) <> ''
    AND CAST(qpb.QuestID AS INTEGER) > 0
    AND CAST(qpb.UiMapID AS INTEGER) > 0
)
SELECT
  qb.quest_id AS QuestID,
  qct.QuestTitle_lang AS QuestName,
  qlg.quest_line_ids AS QuestLineID,
  qlg.quest_line_names AS QuestLineNames,
  CAST(qct.QuestInfoID AS INTEGER) AS QuestTypeID,
  qi.InfoName_lang AS QuestTypeName,
  qpr.ui_map_id AS UiMapID,
  CAST(ui.Type AS INTEGER) AS UiMapType,
  ui.Name_lang AS ZoneName,
  qpr.map_id AS MapID,
  map.MapName_lang AS MapName,
  CAST(map.ExpansionID AS INTEGER) AS ExpansionID,
  CAST(qct.BreadCrumbID AS INTEGER) AS BreadCrumbID,
  CAST(qct.FiltRaces AS INTEGER) AS FiltRaces,
  CAST(pc.PrevQuestID_0 AS INTEGER) AS PrevQuestID0,
  CAST(pc.PrevQuestID_1 AS INTEGER) AS PrevQuestID1,
  CAST(pc.PrevQuestID_2 AS INTEGER) AS PrevQuestID2,
  CAST(pc.PrevQuestID_3 AS INTEGER) AS PrevQuestID3,
  CAST(pc.PrevQuestLogic AS INTEGER) AS PrevQuestLogic,
  CAST(qct.FiltCompletedQuest_0 AS INTEGER) AS FiltCompletedQuest0,
  CAST(qct.FiltCompletedQuest_1 AS INTEGER) AS FiltCompletedQuest1,
  CAST(qct.FiltCompletedQuest_2 AS INTEGER) AS FiltCompletedQuest2,
  CAST(qct.FiltActiveQuest AS INTEGER) AS FiltActiveQuest,
  CAST(qct.FiltClasses AS INTEGER) AS FiltClasses,
  CAST(qct.FiltNonActiveQuest AS INTEGER) AS FiltNonActiveQuest,
  CAST(pc.CurrentCompletedQuestID_0 AS INTEGER) AS CurrentCompletedQuestID0,
  CAST(pc.CurrentCompletedQuestID_1 AS INTEGER) AS CurrentCompletedQuestID1,
  CAST(pc.CurrentCompletedQuestID_2 AS INTEGER) AS CurrentCompletedQuestID2,
  CAST(pc.CurrentCompletedQuestID_3 AS INTEGER) AS CurrentCompletedQuestID3,
  CAST(pc.CurrentCompletedQuestLogic AS INTEGER) AS CurrentCompletedQuestLogic,
  CAST(pc.RaceMask AS INTEGER) AS RaceMask,
  CAST(pc.ClassMask AS INTEGER) AS ClassMask,
  CAST(pc.ModifierTreeID AS INTEGER) AS ModifierTreeID
FROM quest_base_rows qb
LEFT JOIN quest_poi_rows qpr ON qpr.quest_id_text = qb.quest_id_text
LEFT JOIN uimap ui ON ui.ID = qpr.ui_map_id_text
LEFT JOIN map ON map.ID = qpr.map_id_text
LEFT JOIN quest_line_grouped qlg ON qlg.quest_id_text = qb.quest_id_text
LEFT JOIN questv2clitask qct ON qct.ID = qb.quest_id_text
LEFT JOIN questinfo qi ON qi.ID = qct.QuestInfoID
LEFT JOIN playercondition pc ON pc.ID = qct.ConditionID
ORDER BY
  CAST(map.ExpansionID AS INTEGER),
  ui.Name_lang,
  qb.quest_id
""".strip()

CLASS_MASK_LABELS = [
    (1, "warrior"),
    (2, "paladin"),
    (4, "hunter"),
    (8, "rogue"),
    (16, "priest"),
    (32, "death_knight"),
    (64, "shaman"),
    (128, "mage"),
    (256, "warlock"),
    (512, "monk"),
    (1024, "druid"),
    (2048, "demon_hunter"),
    (4096, "evoker"),
]


def collect_positive_ints(values: list[object]) -> list[int]:
    """收集并去重正整数值。"""

    collected_values: list[int] = []
    for value in values:
        if value in (None, ""):
            continue
        normalized_value = int(value)
        if normalized_value <= 0 or normalized_value in collected_values:
            continue
        collected_values.append(normalized_value)
    return collected_values


def join_ints(values: list[int]) -> str:
    """将整数列表编码为导出字符串。"""

    return "=".join(str(value) for value in values)


def load_race_faction_masks(sqlite_conn: sqlite3.Connection) -> dict[str, int]:
    """从 chrraces 读取可玩种族位并聚合为阵营掩码。"""

    faction_masks = {
        "alliance": 0,
        "horde": 0,
        "neutral": 0,
    }
    query = """
    SELECT PlayableRaceBit, Alliance
    FROM chrraces
    WHERE TRIM(PlayableRaceBit) <> ''
      AND CAST(PlayableRaceBit AS INTEGER) >= 0
    """
    for playable_race_bit, alliance_code in sqlite_conn.execute(query).fetchall():
        normalized_race_bit = int(playable_race_bit)
        race_mask = 1 << normalized_race_bit
        normalized_alliance_code = int(alliance_code)
        if normalized_alliance_code == 0:
            faction_masks["alliance"] |= race_mask
        elif normalized_alliance_code == 1:
            faction_masks["horde"] |= race_mask
        elif normalized_alliance_code == 2:
            faction_masks["neutral"] |= race_mask
    return faction_masks


def normalize_faction_condition(race_mask: object, faction_masks: dict[str, int]) -> str:
    """将阵营条件归一化为稳定文本。"""

    if race_mask in (None, ""):
        return ""
    normalized_race_mask = int(race_mask)
    if normalized_race_mask <= 0:
        return ""

    matched_factions: list[str] = []
    residual_mask = normalized_race_mask
    for faction_name in ("alliance", "horde", "neutral"):
        faction_mask = faction_masks.get(faction_name, 0)
        if faction_mask and (normalized_race_mask & faction_mask):
            matched_factions.append(faction_name)
            residual_mask &= ~faction_mask
    if residual_mask != 0 or not matched_factions:
        return str(normalized_race_mask)
    return "=".join(matched_factions)


def derive_faction_tag(faction_condition: str) -> str:
    """将阵营条件摘要归一化为稳定阵营标记。"""

    if faction_condition in ("alliance", "horde", "neutral"):
        return faction_condition
    if faction_condition == "alliance=horde":
        return "shared"
    return ""


def normalize_class_condition(class_mask: object) -> str:
    """将职业条件归一化为稳定文本。"""

    if class_mask in (None, ""):
        return ""
    normalized_class_mask = int(class_mask)
    if normalized_class_mask <= 0:
        return ""
    class_tokens = [
        class_name
        for class_value, class_name in CLASS_MASK_LABELS
        if normalized_class_mask & class_value
    ]
    if class_tokens:
        return "=".join(class_tokens)
    return str(normalized_class_mask)


def resolve_effective_mask(*mask_values: object) -> int | str:
    """合并多个掩码来源，优先保留更严格且非空的结果。"""

    normalized_masks: list[int] = []
    for mask_value in mask_values:
        if mask_value in (None, ""):
            continue
        normalized_mask = int(mask_value)
        if normalized_mask <= 0:
            continue
        normalized_masks.append(normalized_mask)

    if not normalized_masks:
        return ""

    effective_mask = normalized_masks[0]
    for additional_mask in normalized_masks[1:]:
        intersected_mask = effective_mask & additional_mask
        if intersected_mask > 0:
            effective_mask = intersected_mask
    return effective_mask


def build_story_condition(
    completed_quest_ids: list[int],
    active_quest_id: object,
    non_active_quest_id: object,
    completed_quest_logic: object,
) -> tuple[str, list[str]]:
    """生成剧情条件摘要与附加标记。"""

    if not completed_quest_ids and active_quest_id in (None, "", 0) and non_active_quest_id in (None, "", 0):
        return "", []

    _ = completed_quest_logic  # 当前 CSV 仅导出稳定摘要，不单列暴露剧情逻辑值。
    story_parts: list[str] = []
    if completed_quest_ids:
        story_parts.append(f"completed:{join_ints(completed_quest_ids)}")
    if active_quest_id not in (None, "", 0):
        story_parts.append(f"active:{int(active_quest_id)}")
    if non_active_quest_id not in (None, "", 0):
        story_parts.append(f"non_active:{int(non_active_quest_id)}")
    return ";".join(story_parts), ["has_story_condition"]


def script_root() -> Path:
    """返回 export 脚本目录。"""

    return Path(__file__).resolve().parent


def wowplugin_root() -> Path:
    """返回 WoWPlugin 根目录。"""

    return script_root().parents[1]


def wowtools_root() -> Path:
    """返回 WoWTools 根目录。"""

    return wowplugin_root().parent / "WoWTools"


def default_db_path() -> Path:
    """返回默认 wow.db 路径。"""

    return wowtools_root() / "data" / "sqlite" / "wow.db"


def default_output_path() -> Path:
    """返回默认导出文件路径。"""

    return wowtools_root() / "outputs" / "toolbox" / "quest_expansion_map.csv"


def ensure_export_indexes(sqlite_conn: sqlite3.Connection) -> None:
    """为导出查询补齐必要索引，避免大表联接时反复全表扫描。"""

    index_statements = [
        "CREATE INDEX IF NOT EXISTS idx_qpb_quest_uimap_map ON questpoiblob (QuestID, UiMapID, MapID)",
        "CREATE INDEX IF NOT EXISTS idx_qlxq_quest_line ON questlinexquest (QuestID, QuestLineID)",
        "CREATE INDEX IF NOT EXISTS idx_uimap_id_type ON uimap (ID, Type)",
        "CREATE INDEX IF NOT EXISTS idx_map_id_expansion ON map (ID, ExpansionID)",
        "CREATE INDEX IF NOT EXISTS idx_qct_id_condition ON questv2clitask (ID, ConditionID)",
        "CREATE INDEX IF NOT EXISTS idx_pc_id ON playercondition (ID)",
        "CREATE INDEX IF NOT EXISTS idx_uimapassignment_uimap_area ON uimapassignment (UiMapID, AreaID)",
        "CREATE INDEX IF NOT EXISTS idx_areatable_id_contenttuning ON areatable (ID, ContentTuningID)",
        "CREATE INDEX IF NOT EXISTS idx_contenttuning_id_expansion ON contenttuning (ID, ExpansionID)",
    ]
    for index_statement in index_statements:
        sqlite_conn.execute(index_statement)
    sqlite_conn.commit()


def table_has_columns(sqlite_conn: sqlite3.Connection, table_name: str, required_columns: list[str]) -> bool:
    """检查表是否存在且包含给定列。"""

    try:
        available_columns = {
            row[1]
            for row in sqlite_conn.execute(f'PRAGMA table_info({table_name})').fetchall()
        }
    except sqlite3.OperationalError:
        return False
    return all(column_name in available_columns for column_name in required_columns)


def build_uimap_expansion_fallbacks(sqlite_conn: sqlite3.Connection) -> dict[int, int]:
    """基于 UiMap -> Area -> ContentTuning 构建资料片 fallback。"""

    if not table_has_columns(sqlite_conn, "uimapassignment", ["UiMapID", "AreaID"]):
        return {}
    if not table_has_columns(sqlite_conn, "areatable", ["ID", "ContentTuningID"]):
        return {}
    if not table_has_columns(sqlite_conn, "contenttuning", ["ID", "ExpansionID"]):
        return {}

    direct_expansion_by_uimap: dict[int, int] = {}
    for ui_map_id, expansion_id in sqlite_conn.execute(
        """
        SELECT
          CAST(ua.UiMapID AS INTEGER) AS UiMapID,
          CAST(ct.ExpansionID AS INTEGER) AS ExpansionID
        FROM uimapassignment ua
        JOIN areatable area ON area.ID = ua.AreaID
        JOIN contenttuning ct ON ct.ID = area.ContentTuningID
        WHERE TRIM(COALESCE(ua.UiMapID, '')) <> ''
          AND TRIM(COALESCE(area.ContentTuningID, '')) <> ''
          AND TRIM(COALESCE(ct.ExpansionID, '')) <> ''
          AND CAST(ua.UiMapID AS INTEGER) > 0
          AND CAST(ct.ExpansionID AS INTEGER) >= 0
        """
    ).fetchall():
        current_value = direct_expansion_by_uimap.get(ui_map_id, -1)
        direct_expansion_by_uimap[ui_map_id] = max(current_value, expansion_id)

    parent_by_uimap: dict[int, int] = {}
    if table_has_columns(sqlite_conn, "uimap", ["ID", "ParentUiMapID"]):
        for ui_map_id, parent_ui_map_id in sqlite_conn.execute(
            """
            SELECT
              CAST(ID AS INTEGER) AS UiMapID,
              CAST(ParentUiMapID AS INTEGER) AS ParentUiMapID
            FROM uimap
            WHERE TRIM(COALESCE(ID, '')) <> ''
              AND CAST(ID AS INTEGER) > 0
            """
        ).fetchall():
            if parent_ui_map_id > 0:
                parent_by_uimap[ui_map_id] = parent_ui_map_id

    resolved_expansion_by_uimap: dict[int, int] = {}
    for ui_map_id in set(direct_expansion_by_uimap) | set(parent_by_uimap):
        visited_ui_maps: set[int] = set()
        current_ui_map_id = ui_map_id
        resolved_expansion_id: int | None = None
        while current_ui_map_id > 0 and current_ui_map_id not in visited_ui_maps:
            visited_ui_maps.add(current_ui_map_id)
            if current_ui_map_id in direct_expansion_by_uimap:
                resolved_expansion_id = direct_expansion_by_uimap[current_ui_map_id]
                break
            current_ui_map_id = parent_by_uimap.get(current_ui_map_id, 0)
        if resolved_expansion_id is not None:
            resolved_expansion_by_uimap[ui_map_id] = resolved_expansion_id

    return resolved_expansion_by_uimap


def build_player_visible_uimap_rows(sqlite_conn: sqlite3.Connection) -> dict[int, dict[str, object]]:
    """将原始 UiMap 归并为更适合玩家导航的可见地图层。"""

    if not table_has_columns(sqlite_conn, "uimap", ["ID", "ParentUiMapID", "Type", "Name_lang"]):
        return {}

    raw_uimap_by_id: dict[int, dict[str, object]] = {}
    for row in sqlite_conn.execute(
        """
        SELECT
          CAST(ID AS INTEGER) AS UiMapID,
          CAST(ParentUiMapID AS INTEGER) AS ParentUiMapID,
          CAST(Type AS INTEGER) AS UiMapType,
          Name_lang
        FROM uimap
        WHERE TRIM(COALESCE(ID, '')) <> ''
          AND CAST(ID AS INTEGER) > 0
        """
    ).fetchall():
        raw_uimap_by_id[int(row[0])] = {
            "ui_map_id": int(row[0]),
            "parent_ui_map_id": int(row[1]),
            "ui_map_type": int(row[2]) if row[2] is not None else 0,
            "zone_name": row[3] or "",
        }

    visible_uimap_by_id: dict[int, dict[str, object]] = {}
    preferred_types = {3, 4}
    for ui_map_id, row in raw_uimap_by_id.items():
        current_ui_map_id = ui_map_id
        visited_ui_map_ids: set[int] = set()
        chosen_row: dict[str, object] | None = None
        while current_ui_map_id > 0 and current_ui_map_id not in visited_ui_map_ids:
            visited_ui_map_ids.add(current_ui_map_id)
            current_row = raw_uimap_by_id.get(current_ui_map_id)
            if current_row is None:
                break
            if int(current_row.get("ui_map_type") or 0) in preferred_types:
                chosen_row = current_row
                break
            current_ui_map_id = int(current_row.get("parent_ui_map_id") or 0)
        if chosen_row is None:
            chosen_row = row
        visible_uimap_by_id[ui_map_id] = {
            "ui_map_id": chosen_row["ui_map_id"],
            "ui_map_type": chosen_row["ui_map_type"],
            "zone_name": chosen_row["zone_name"],
        }

    return visible_uimap_by_id


def resolve_map_expansion(
    map_id: object,
    map_expansion_id: object,
    ui_map_id: object,
    uimap_expansion_fallbacks: dict[int, int],
) -> int | str:
    """解析任务地图资料片，必要时走 UiMap fallback。"""

    normalized_map_id = int(map_id) if map_id not in (None, "") else 0
    normalized_map_expansion_id = int(map_expansion_id) if map_expansion_id not in (None, "") else ""
    normalized_ui_map_id = int(ui_map_id) if ui_map_id not in (None, "") else 0

    if normalized_map_id > 0:
        return normalized_map_expansion_id if normalized_map_expansion_id != "" else UNKNOWN_EXPANSION_ID

    fallback_expansion_id = uimap_expansion_fallbacks.get(normalized_ui_map_id)
    if fallback_expansion_id is not None:
        return fallback_expansion_id
    if normalized_map_expansion_id != "":
        return normalized_map_expansion_id
    return UNKNOWN_EXPANSION_ID


def select_preferred_content_expansion(expansion_ids: list[int | str]) -> int | str:
    """在线内优先选择真实资料片；只有全缺失时才回退 99。"""

    normalized_expansions = [int(expansion_id) for expansion_id in expansion_ids if expansion_id != ""]
    if not normalized_expansions:
        return ""

    known_expansions = [
        expansion_id
        for expansion_id in normalized_expansions
        if expansion_id != UNKNOWN_EXPANSION_ID
    ]
    if known_expansions:
        return max(known_expansions)
    return UNKNOWN_EXPANSION_ID


def fetch_export_rows(db_path: Path) -> list[dict[str, object]]:
    """执行导出查询并返回行列表。"""

    sqlite_conn = sqlite3.connect(str(db_path))
    sqlite_conn.row_factory = sqlite3.Row
    try:
        ensure_export_indexes(sqlite_conn)
        faction_masks = load_race_faction_masks(sqlite_conn)
        uimap_expansion_fallbacks = build_uimap_expansion_fallbacks(sqlite_conn)
        visible_uimap_rows = build_player_visible_uimap_rows(sqlite_conn)
        export_rows: list[dict[str, object]] = []
        prev_quest_index: dict[int, list[int]] = {}
        for row in sqlite_conn.execute(EXPORT_SQL).fetchall():
            normalized_map_expansion_id = resolve_map_expansion(
                map_id=row["MapID"],
                map_expansion_id=row["ExpansionID"],
                ui_map_id=row["UiMapID"],
                uimap_expansion_fallbacks=uimap_expansion_fallbacks,
            )
            raw_ui_map_id = int(row["UiMapID"]) if row["UiMapID"] not in (None, "") else 0
            visible_ui_map_row = visible_uimap_rows.get(raw_ui_map_id)
            display_ui_map_id = visible_ui_map_row["ui_map_id"] if visible_ui_map_row else raw_ui_map_id
            display_ui_map_type = visible_ui_map_row["ui_map_type"] if visible_ui_map_row else (
                int(row["UiMapType"]) if row["UiMapType"] not in (None, "") else ""
            )
            display_zone_name = visible_ui_map_row["zone_name"] if visible_ui_map_row else (row["ZoneName"] or "")
            effective_race_mask = resolve_effective_mask(row["RaceMask"], row["FiltRaces"])
            effective_class_mask = resolve_effective_mask(row["ClassMask"], row["FiltClasses"])
            prev_quest_ids = collect_positive_ints(
                [
                    row["PrevQuestID0"],
                    row["PrevQuestID1"],
                    row["PrevQuestID2"],
                    row["PrevQuestID3"],
                ]
            )
            completed_quest_ids = collect_positive_ints(
                [
                    row["CurrentCompletedQuestID0"],
                    row["CurrentCompletedQuestID1"],
                    row["CurrentCompletedQuestID2"],
                    row["CurrentCompletedQuestID3"],
                ]
            )
            exclusive_quest_ids = collect_positive_ints(
                [
                    row["FiltCompletedQuest0"],
                    row["FiltCompletedQuest1"],
                    row["FiltCompletedQuest2"],
                ]
            )
            story_condition, condition_flags = build_story_condition(
                completed_quest_ids=completed_quest_ids,
                active_quest_id=row["FiltActiveQuest"],
                non_active_quest_id=row["FiltNonActiveQuest"],
                completed_quest_logic=row["CurrentCompletedQuestLogic"],
            )
            quest_id = int(row["QuestID"])
            quest_line_ids = collect_positive_ints((row["QuestLineID"] or "").split("="))
            for prev_quest_id in prev_quest_ids:
                prev_quest_index.setdefault(prev_quest_id, []).append(quest_id)
            faction_condition = normalize_faction_condition(effective_race_mask, faction_masks)
            export_rows.append(
                {
                    "QuestID": quest_id,
                    "QuestName": row["QuestName"] or "",
                    "QuestLineID": row["QuestLineID"] or "",
                    "QuestLineNames": row["QuestLineNames"] or "",
                    "QuestTypeID": int(row["QuestTypeID"]) if row["QuestTypeID"] not in (None, 0, "") else "",
                    "QuestTypeName": row["QuestTypeName"] or "",
                    "UiMapID": display_ui_map_id if display_ui_map_id > 0 else "",
                    "UiMapType": display_ui_map_type if display_ui_map_type != "" else "",
                    "ZoneName": display_zone_name,
                    "MapID": int(row["MapID"]) if row["MapID"] not in (None, "") else "",
                    "MapName": row["MapName"] or "",
                    "MapExpansionID": normalized_map_expansion_id,
                    "MapExpansionName": EXPANSION_NAMES.get(normalized_map_expansion_id, "") if normalized_map_expansion_id != "" else "",
                    "ContentExpansionID": "",
                    "ContentExpansionName": "",
                    "PrevQuestIDs": join_ints(prev_quest_ids),
                    "PrevQuestLogic": int(row["PrevQuestLogic"]) if row["PrevQuestLogic"] not in (None, "") else "",
                    "NextQuestIDs": "",
                    "ExclusiveToQuestIDs": join_ints(exclusive_quest_ids),
                    "BreadcrumbQuestID": int(row["BreadCrumbID"]) if row["BreadCrumbID"] not in (None, 0, "") else "",
                    "FactionTag": derive_faction_tag(faction_condition),
                    "FactionCondition": faction_condition,
                    "FactionMaskRaw": effective_race_mask if effective_race_mask != "" else "",
                    "ClassCondition": normalize_class_condition(effective_class_mask),
                    "ClassMaskRaw": effective_class_mask if effective_class_mask != "" else "",
                    "StoryCondition": story_condition,
                    "StoryLogicRaw": int(row["CurrentCompletedQuestLogic"]) if row["CurrentCompletedQuestLogic"] not in (None, 0, "") else "",
                    "PrevQuestLogicRaw": int(row["PrevQuestLogic"]) if row["PrevQuestLogic"] not in (None, 0, "") else "",
                    "ModifierTreeID": int(row["ModifierTreeID"]) if row["ModifierTreeID"] not in (None, 0, "") else "",
                    "ConditionFlags": "=".join(condition_flags),
                    "_QuestLineIDs": quest_line_ids,
                }
            )
        questline_expansion_index: dict[int, int] = {}
        for export_row in export_rows:
            map_expansion_id = export_row["MapExpansionID"]
            if map_expansion_id == "":
                continue
            for quest_line_id in export_row["_QuestLineIDs"]:
                current_value = questline_expansion_index.get(quest_line_id, "")
                questline_expansion_index[quest_line_id] = select_preferred_content_expansion(
                    [current_value, map_expansion_id]
                )
        for export_row in export_rows:
            next_quest_ids = sorted(set(prev_quest_index.get(export_row["QuestID"], [])))
            export_row["NextQuestIDs"] = join_ints(next_quest_ids)
            content_expansion_ids = [
                questline_expansion_index[quest_line_id]
                for quest_line_id in export_row["_QuestLineIDs"]
                if quest_line_id in questline_expansion_index
            ]
            content_expansion_id = select_preferred_content_expansion(content_expansion_ids)
            if content_expansion_id == "":
                content_expansion_id = export_row["MapExpansionID"]
            export_row["ContentExpansionID"] = content_expansion_id if content_expansion_id != "" else ""
            export_row["ContentExpansionName"] = (
                EXPANSION_NAMES.get(content_expansion_id, "")
                if content_expansion_id != ""
                else ""
            )
            export_row.pop("_QuestLineIDs", None)
        return export_rows
    finally:
        sqlite_conn.close()


def write_export_csv(output_path: Path, export_rows: list[dict[str, object]]) -> None:
    """将导出结果写入 CSV。"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=OUTPUT_FIELDNAMES)
        writer.writeheader()
        writer.writerow({field_name: OUTPUT_FIELD_LABELS_ZH[field_name] for field_name in OUTPUT_FIELDNAMES})
        writer.writerows(export_rows)


def build_argument_parser() -> argparse.ArgumentParser:
    """构建命令行参数解析器。"""

    parser = argparse.ArgumentParser(description="从 wow.db 导出任务地图资料片映射 CSV。")
    parser.add_argument(
        "--db",
        type=Path,
        default=default_db_path(),
        help="SQLite database path (default: WoWTools/data/sqlite/wow.db)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=default_output_path(),
        help="CSV output path (default: WoWTools/outputs/toolbox/quest_expansion_map.csv)",
    )
    return parser


def main() -> int:
    """命令行入口。"""

    print(
        "[DEPRECATED] 请使用 scripts/export/export_quest_achievement_merged_from_db.py "
        "作为唯一任务导出入口。",
        file=sys.stderr,
    )

    parser = build_argument_parser()
    args = parser.parse_args()

    export_rows = fetch_export_rows(args.db)
    write_export_csv(args.output, export_rows)
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
