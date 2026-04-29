#!/usr/bin/env python3
"""Toolbox Data 导出工具（从 data/sqlite/wow.db 按契约生成 Lua 静态表）。"""

from __future__ import annotations

import argparse
from collections import defaultdict
import os
import re
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Mapping

try:
    from .contract_io import (
        default_contract_dir,
        default_snapshot_root,
        default_wowplugin_root,
        default_wowtools_root,
        iter_active_contracts,
        load_contract,
        write_contract_snapshot,
    )
    from .lua_contract_writer import render_contract_lua
except ImportError:  # pragma: no cover - script mode fallback
    from contract_io import (
        default_contract_dir,
        default_snapshot_root,
        default_wowplugin_root,
        default_wowtools_root,
        iter_active_contracts,
        load_contract,
        write_contract_snapshot,
    )
    from lua_contract_writer import render_contract_lua


def workspace_root() -> Path:
    """返回 WoWProject 工作区根目录。"""

    return Path(__file__).resolve().parents[3]


def default_db_path() -> Path:
    """返回默认数据库路径。"""

    return default_wowtools_root() / "data" / "sqlite" / "wow.db"


def default_data_dir() -> Path:
    """返回默认输出 Data 目录。"""

    return default_wowplugin_root() / "Toolbox" / "Data"


def to_workspace_relative(path_value: Path) -> Path:
    """尽量返回相对工作区根目录的路径，否则返回原路径。"""

    try:
        return path_value.resolve().relative_to(workspace_root().resolve())
    except ValueError:
        return path_value


def to_contract_logical_path(contract_path: Path) -> Path:
    """将契约路径归一化为 WoWPlugin 逻辑路径。"""

    return Path("WoWPlugin") / "DataContracts" / contract_path.name


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


QUESTCOMPLETIST_LINE_PATTERN = re.compile(r'^\[(\d+)\]\s*=\s*\{(.+)\},$')
QUESTCOMPLETIST_NAME_PATTERN = re.compile(r'^\[(\d+)\]\s*=\s*"((?:\\.|[^"])*)",?$')


def parse_lua_list_payload(payload: str) -> list[Any]:
    """解析单行 Lua 数组字面量内容。"""

    values: list[Any] = []
    current_chars: list[str] = []
    in_string = False
    escape_next = False

    def flush_value() -> None:
        token = "".join(current_chars).strip()
        current_chars.clear()
        if token == "":
            return
        if token == "nil":
            values.append(None)
        elif token == "true":
            values.append(True)
        elif token == "false":
            values.append(False)
        elif token.startswith('"') and token.endswith('"'):
            inner_text = token[1:-1]
            values.append(bytes(inner_text, "utf-8").decode("unicode_escape"))
        else:
            try:
                values.append(int(token))
            except ValueError:
                values.append(token)

    for char in payload:
        if in_string:
            current_chars.append(char)
            if escape_next:
                escape_next = False
                continue
            if char == "\\":
                escape_next = True
                continue
            if char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
            current_chars.append(char)
            continue
        if char == ",":
            flush_value()
            continue
        current_chars.append(char)

    flush_value()
    return values


def extract_table_block_lines(lua_text: str, table_name: str) -> list[str]:
    """提取指定 Lua 表块的行内容。"""

    all_lines = lua_text.splitlines()
    start_index = next((index for index, line in enumerate(all_lines) if line.strip().startswith(f"{table_name}")), None)
    require(start_index is not None, f"missing Lua table: {table_name}")

    block_lines: list[str] = []
    brace_depth = 0
    entered = False
    for raw_line in all_lines[start_index:]:
        line_text = raw_line.strip()
        if not entered:
            brace_depth += line_text.count("{") - line_text.count("}")
            entered = True
            continue
        if brace_depth <= 0:
            break
        block_lines.append(line_text)
        brace_depth += line_text.count("{") - line_text.count("}")
        if brace_depth <= 0:
            block_lines.pop()
            break
    return block_lines


def load_questcompletist_storylines(addon_dir: Path) -> dict[str, Any]:
    """读取 QuestCompletist 的任务线名称与任务记录。"""

    quest_file_path = addon_dir / "qcQuest.lua"
    require(quest_file_path.exists(), f"QuestCompletist qcQuest.lua does not exist: {quest_file_path}")
    lua_text = quest_file_path.read_text(encoding="utf-8")

    storyline_names: dict[int, str] = {}
    for line_text in extract_table_block_lines(lua_text, "qcQuestLines"):
        match = QUESTCOMPLETIST_NAME_PATTERN.match(line_text)
        if match is None:
            continue
        storyline_id = int(match.group(1))
        storyline_name = bytes(match.group(2), "utf-8").decode("unicode_escape")
        storyline_names[storyline_id] = storyline_name

    quest_records: dict[int, dict[str, int]] = {}
    for line_text in extract_table_block_lines(lua_text, "qcQuestDatabase"):
        match = QUESTCOMPLETIST_LINE_PATTERN.match(line_text)
        if match is None:
            continue
        row_values = parse_lua_list_payload(match.group(2))
        if len(row_values) < 14:
            continue
        quest_id = int(row_values[0])
        storyline_id = int(row_values[12] or 0)
        previous_quest_id = int(row_values[13] or 0)
        if storyline_id <= 0:
            continue
        quest_records[quest_id] = {
            "storyline_id": storyline_id,
            "previous_quest_id": previous_quest_id,
        }

    return {
        "storyline_names": storyline_names,
        "quest_records": quest_records,
    }


def pick_majority_value(values: Iterable[int]) -> int | None:
    """按出现次数优先、数值升序次之选择最佳值。"""

    vote_counter: dict[int, int] = {}
    for value in values:
        if value <= 0:
            continue
        vote_counter[value] = vote_counter.get(value, 0) + 1
    if not vote_counter:
        return None
    return sorted(vote_counter.items(), key=lambda item: (-item[1], item[0]))[0][0]


def fetch_best_map_ids_for_quests(
    sqlite_conn: sqlite3.Connection,
    quest_ids: Iterable[int],
) -> dict[int, int]:
    """查询任务的最佳 UiMapID。"""

    unique_quest_ids = sorted({int(quest_id) for quest_id in quest_ids if int(quest_id) > 0})
    if not unique_quest_ids:
        return {}

    placeholders = ",".join("?" for _ in unique_quest_ids)
    query_text = f"""
SELECT
  CAST(QuestID AS INTEGER) AS quest_id,
  CAST(UiMapID AS INTEGER) AS ui_map_id
FROM questpoiblob
WHERE CAST(QuestID AS INTEGER) IN ({placeholders})
  AND CAST(UiMapID AS INTEGER) > 0
"""
    vote_rows = sqlite_conn.execute(query_text, unique_quest_ids).fetchall()
    votes_by_quest_id: dict[int, list[int]] = {}
    for row in vote_rows:
        quest_id = int(row["quest_id"])
        votes_by_quest_id.setdefault(quest_id, []).append(int(row["ui_map_id"]))
    return {
        quest_id: best_map_id
        for quest_id, vote_values in votes_by_quest_id.items()
        for best_map_id in [pick_majority_value(vote_values)]
        if best_map_id is not None
    }


def fetch_expansion_ids_for_maps(
    sqlite_conn: sqlite3.Connection,
    map_ids: Iterable[int],
) -> dict[int, int]:
    """查询 UiMapID 对应的 ExpansionID。"""

    unique_map_ids = sorted({int(map_id) for map_id in map_ids if int(map_id) > 0})
    if not unique_map_ids:
        return {}

    placeholders = ",".join("?" for _ in unique_map_ids)
    query_text = f"""
SELECT
  CAST(ID AS INTEGER) AS map_id,
  CAST(ExpansionID AS INTEGER) AS expansion_id
FROM map
WHERE CAST(ID AS INTEGER) IN ({placeholders})
"""
    return {
        int(row["map_id"]): int(row["expansion_id"])
        for row in sqlite_conn.execute(query_text, unique_map_ids).fetchall()
    }


def fetch_blob_info_by_blob_ids(
    sqlite_conn: sqlite3.Connection,
    blob_ids: Iterable[int],
) -> dict[int, dict[str, int]]:
    """按 QuestPOIBlob.ID 读取 blob 记录的 MapID 与 UiMapID。"""

    unique_blob_ids = sorted({int(blob_id) for blob_id in blob_ids if int(blob_id) > 0})
    if not unique_blob_ids:
        return {}

    placeholders = ",".join("?" for _ in unique_blob_ids)
    query_text = f"""
SELECT
  CAST(ID AS INTEGER) AS blob_id,
  CAST(MapID AS INTEGER) AS map_id,
  CAST(UiMapID AS INTEGER) AS ui_map_id
FROM questpoiblob
WHERE CAST(ID AS INTEGER) IN ({placeholders})
"""
    return {
        int(row["blob_id"]): {
            "map_id": int(row["map_id"] or 0),
            "ui_map_id": int(row["ui_map_id"] or 0),
        }
        for row in sqlite_conn.execute(query_text, unique_blob_ids).fetchall()
    }


def fetch_uimap_parent_rows(
    sqlite_conn: sqlite3.Connection,
    map_ids: Iterable[int],
) -> dict[int, dict[str, int]]:
    """批量读取 UiMap 节点的 parent/type 信息。"""

    pending_ids = {int(map_id) for map_id in map_ids if int(map_id) > 0}
    loaded_rows: dict[int, dict[str, int]] = {}

    while pending_ids:
        batch_ids = sorted(pending_ids)
        pending_ids = set()
        placeholders = ",".join("?" for _ in batch_ids)
        query_text = f"""
SELECT
  CAST(ID AS INTEGER) AS map_id,
  CAST(ParentUiMapID AS INTEGER) AS parent_map_id,
  CAST(Type AS INTEGER) AS map_type
FROM uimap
WHERE CAST(ID AS INTEGER) IN ({placeholders})
"""
        for row in sqlite_conn.execute(query_text, batch_ids).fetchall():
            map_id = int(row["map_id"])
            parent_map_id = int(row["parent_map_id"] or 0)
            loaded_rows[map_id] = {
                "parent_map_id": parent_map_id,
                "map_type": int(row["map_type"] or 0),
            }
            if parent_map_id > 0 and parent_map_id not in loaded_rows:
                pending_ids.add(parent_map_id)

    return loaded_rows


def resolve_type3_uimap(
    start_map_id: int | None,
    uimap_rows_by_id: Mapping[int, Mapping[str, int]],
) -> int | None:
    """从当前 UiMap 沿父链向上查找第一个 type == 3 的节点。"""

    current_map_id = int(start_map_id or 0)
    seen_ids: set[int] = set()
    while current_map_id > 0 and current_map_id not in seen_ids:
        seen_ids.add(current_map_id)
        current_row = uimap_rows_by_id.get(current_map_id)
        if current_row is None:
            return None
        if int(current_row.get("map_type", 0)) == 3:
            return current_map_id
        current_map_id = int(current_row.get("parent_map_id", 0))
    return None


def build_instance_questlines_schema_v6_datasets(
    sqlite_conn: sqlite3.Connection,
    core_link_rows: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    """将 core_links 聚合为 schema v6/v7 数据块。"""

    rows_by_quest_line_id: dict[int, list[dict[str, Any]]] = {}
    for row in core_link_rows:
        quest_line_id = int(row.get("quest_line_id") or 0)
        quest_id = int(row.get("quest_id") or 0)
        if quest_line_id <= 0 or quest_id <= 0:
            continue
        rows_by_quest_line_id.setdefault(quest_line_id, []).append(row)

    first_quest_ids = []
    for storyline_rows in rows_by_quest_line_id.values():
        ordered_rows = sorted(
            storyline_rows,
            key=lambda item: (int(item.get("order_index") or 0), int(item.get("quest_id") or 0)),
        )
        if ordered_rows:
            first_quest_ids.append(int(ordered_rows[0]["quest_id"]))

    blob_info_by_id = fetch_blob_info_by_blob_ids(sqlite_conn, first_quest_ids)
    uimap_rows_by_id = fetch_uimap_parent_rows(
        sqlite_conn,
        [blob_info.get("ui_map_id", 0) for blob_info in blob_info_by_id.values()],
    )

    resolved_map_by_quest_line_id: dict[int, int] = {}
    expansion_id_by_quest_line_id: dict[int, int] = {}
    expansion_by_map_id = fetch_expansion_ids_for_maps(
        sqlite_conn,
        [blob_info.get("map_id", 0) for blob_info in blob_info_by_id.values()],
    )
    for quest_line_id, storyline_rows in rows_by_quest_line_id.items():
        ordered_rows = sorted(
            storyline_rows,
            key=lambda item: (int(item.get("order_index") or 0), int(item.get("quest_id") or 0)),
        )
        if not ordered_rows:
            continue
        first_quest_id = int(ordered_rows[0]["quest_id"])
        blob_info = blob_info_by_id.get(first_quest_id) or {}
        resolved_map_id = resolve_type3_uimap(blob_info.get("ui_map_id"), uimap_rows_by_id)
        if resolved_map_id is not None:
            resolved_map_by_quest_line_id[quest_line_id] = resolved_map_id
        expansion_id = expansion_by_map_id.get(int(blob_info.get("map_id", 0)))
        if expansion_id is not None:
            expansion_id_by_quest_line_id[quest_line_id] = expansion_id

    quest_rows: list[dict[str, Any]] = []
    quest_line_rows: list[dict[str, Any]] = []
    expansion_rows: list[dict[str, Any]] = []
    campaign_rows: list[dict[str, Any]] = []
    expansion_campaign_rows: list[dict[str, Any]] = []
    seen_quest_ids: set[int] = set()
    quest_line_expansion_by_id: dict[int, int] = {}

    for quest_line_id in sorted(rows_by_quest_line_id):
        resolved_map_id = resolved_map_by_quest_line_id.get(quest_line_id)
        if resolved_map_id is None:
            continue
        expansion_id = expansion_id_by_quest_line_id.get(quest_line_id)
        if expansion_id is None:
            continue

        ordered_rows = sorted(
            rows_by_quest_line_id[quest_line_id],
            key=lambda item: (int(item.get("order_index") or 0), int(item.get("quest_id") or 0)),
        )
        ordered_quest_ids: list[int] = []
        seen_quest_ids_in_line: set[int] = set()
        for row in ordered_rows:
            quest_id = int(row["quest_id"])
            if quest_id in seen_quest_ids_in_line:
                continue
            seen_quest_ids_in_line.add(quest_id)
            ordered_quest_ids.append(quest_id)
        if not ordered_quest_ids:
            continue

        quest_line_rows.append(
            {
                "quest_line_id": quest_line_id,
                "quest_line_name": ordered_rows[0].get("quest_line_name"),
                "quest_line_ui_map_id": resolved_map_id,
                "quest_line_expansion_id": expansion_id,
                "quest_ids": ordered_quest_ids,
            }
        )
        quest_line_expansion_by_id[quest_line_id] = expansion_id
        expansion_rows.append(
            {
                "expansion_id": expansion_id,
                "quest_line_id": quest_line_id,
            }
        )

        for quest_id in ordered_quest_ids:
            if quest_id in seen_quest_ids:
                continue
            seen_quest_ids.add(quest_id)
            quest_rows.append({"quest_id": quest_id})

    valid_quest_line_ids = {int(row["quest_line_id"]) for row in quest_line_rows}
    campaign_link_rows = sqlite_conn.execute(
        """
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
    ).fetchall()

    campaign_entry_by_id: dict[int, dict[str, Any]] = {}
    for link_row in campaign_link_rows:
        campaign_id = int(link_row["campaign_id"] or 0)
        quest_line_id = int(link_row["quest_line_id"] or 0)
        if campaign_id <= 0 or quest_line_id <= 0 or quest_line_id not in valid_quest_line_ids:
            continue

        campaign_entry = campaign_entry_by_id.get(campaign_id)
        if campaign_entry is None:
            campaign_name = (link_row["campaign_name"] or "").strip()
            if campaign_name == "":
                campaign_name = f"Campaign #{campaign_id}"
            campaign_entry = {
                "campaign_id": campaign_id,
                "campaign_name": campaign_name,
                "quest_line_items": [],
                "quest_line_seen": set(),
            }
            campaign_entry_by_id[campaign_id] = campaign_entry

        if quest_line_id in campaign_entry["quest_line_seen"]:
            continue
        campaign_entry["quest_line_seen"].add(quest_line_id)
        campaign_entry["quest_line_items"].append(
            (
                int(link_row["order_index"] or 0),
                quest_line_id,
            )
        )

    for campaign_id in sorted(campaign_entry_by_id):
        campaign_entry = campaign_entry_by_id[campaign_id]
        ordered_quest_line_ids = [
            quest_line_id
            for _, quest_line_id in sorted(
                campaign_entry["quest_line_items"],
                key=lambda item: (item[0], item[1]),
            )
        ]
        if not ordered_quest_line_ids:
            continue
        campaign_rows.append(
            {
                "campaign_id": campaign_id,
                "campaign_name": campaign_entry["campaign_name"],
                "quest_line_ids": ordered_quest_line_ids,
            }
        )

        expansion_vote_counter: dict[int, int] = {}
        for quest_line_id in ordered_quest_line_ids:
            expansion_id = quest_line_expansion_by_id.get(quest_line_id)
            if expansion_id is None:
                continue
            expansion_vote_counter[expansion_id] = expansion_vote_counter.get(expansion_id, 0) + 1

        if expansion_vote_counter:
            primary_expansion_id = sorted(
                expansion_vote_counter.items(),
                key=lambda item: (-item[1], item[0]),
            )[0][0]
            expansion_campaign_rows.append(
                {
                    "expansion_id": primary_expansion_id,
                    "campaign_id": campaign_id,
                }
            )

    return {
        "quests": quest_rows,
        "quest_lines": quest_line_rows,
        "campaigns": campaign_rows,
        "expansions": expansion_rows,
        "expansion_campaigns": expansion_campaign_rows,
    }


def build_storyline_order(
    storyline_members: Mapping[int, int],
    existing_order_by_quest_id: Mapping[int, int],
) -> list[int]:
    """根据前置任务链与现有顺序生成稳定的任务线顺序。"""

    child_quests_by_parent: dict[int, list[int]] = {}
    in_degree_by_quest_id: dict[int, int] = {}
    for quest_id, previous_quest_id in storyline_members.items():
        if previous_quest_id > 0 and previous_quest_id in storyline_members and previous_quest_id != quest_id:
            child_quests_by_parent.setdefault(previous_quest_id, []).append(quest_id)
            in_degree_by_quest_id[quest_id] = 1
        else:
            in_degree_by_quest_id[quest_id] = 0

    def sort_key(quest_id: int) -> tuple[int, int]:
        return (existing_order_by_quest_id.get(quest_id, 10**9), quest_id)

    ready_quest_ids = sorted(
        [quest_id for quest_id, in_degree in in_degree_by_quest_id.items() if in_degree == 0],
        key=sort_key,
    )
    ordered_quest_ids: list[int] = []

    while ready_quest_ids:
        quest_id = ready_quest_ids.pop(0)
        ordered_quest_ids.append(quest_id)
        for child_quest_id in sorted(child_quests_by_parent.get(quest_id, []), key=sort_key):
            in_degree_by_quest_id[child_quest_id] -= 1
            if in_degree_by_quest_id[child_quest_id] == 0:
                ready_quest_ids.append(child_quest_id)
        ready_quest_ids.sort(key=sort_key)

    unresolved_quest_ids = sorted(
        [quest_id for quest_id in storyline_members if quest_id not in ordered_quest_ids],
        key=sort_key,
    )
    ordered_quest_ids.extend(unresolved_quest_ids)
    return ordered_quest_ids


def merge_instance_questlines_with_questcompletist(
    sqlite_conn: sqlite3.Connection,
    existing_rows: list[dict[str, Any]],
    addon_dir: Path,
) -> list[dict[str, Any]]:
    """将 QuestCompletist 的任务线关系并入 core_links。"""

    storyline_bundle = load_questcompletist_storylines(addon_dir)
    quest_records = dict(storyline_bundle["quest_records"])
    if not quest_records:
        return existing_rows

    existing_order_by_quest_id = {
        int(row["quest_id"]): int(row["order_index"])
        for row in existing_rows
        if row.get("quest_id") not in (None, "")
        and row.get("order_index") not in (None, "")
    }
    existing_name_by_line_id = {
        int(row["quest_line_id"]): row.get("quest_line_name")
        for row in existing_rows
        if row.get("quest_line_id") not in (None, "")
    }
    quest_map_by_quest_id = {
        int(row["quest_id"]): int(row["quest_ui_map_id"])
        for row in existing_rows
        if row.get("quest_id") not in (None, "")
        and row.get("quest_ui_map_id") not in (None, "")
    }

    missing_map_quest_ids = [quest_id for quest_id in quest_records if quest_id not in quest_map_by_quest_id]
    quest_map_by_quest_id.update(fetch_best_map_ids_for_quests(sqlite_conn, missing_map_quest_ids))

    storyline_members_by_id: dict[int, dict[int, int]] = {}
    for quest_id, quest_record in quest_records.items():
        storyline_id = int(quest_record["storyline_id"])
        previous_quest_id = int(quest_record["previous_quest_id"])
        storyline_members_by_id.setdefault(storyline_id, {})[int(quest_id)] = previous_quest_id

    storyline_map_by_id: dict[int, int] = {}
    for storyline_id, storyline_members in storyline_members_by_id.items():
        best_map_id = pick_majority_value(
            quest_map_by_quest_id.get(quest_id, 0) for quest_id in storyline_members
        )
        if best_map_id is not None:
            storyline_map_by_id[storyline_id] = best_map_id

    expansion_by_map_id = fetch_expansion_ids_for_maps(sqlite_conn, storyline_map_by_id.values())

    overridden_quest_ids = set(quest_records.keys())
    preserved_rows = [row for row in existing_rows if int(row["quest_id"]) not in overridden_quest_ids]

    merged_rows = list(preserved_rows)
    for storyline_id in sorted(storyline_members_by_id):
        storyline_members = storyline_members_by_id[storyline_id]
        ordered_quest_ids = build_storyline_order(storyline_members, existing_order_by_quest_id)
        storyline_name = storyline_bundle["storyline_names"].get(
            storyline_id,
            existing_name_by_line_id.get(storyline_id, f"Questline {storyline_id}"),
        )
        storyline_map_id = storyline_map_by_id.get(storyline_id)
        storyline_expansion_id = expansion_by_map_id.get(storyline_map_id) if storyline_map_id is not None else None

        for order_index, quest_id in enumerate(ordered_quest_ids):
            merged_rows.append(
                {
                    "quest_line_id": storyline_id,
                    "quest_line_name": storyline_name,
                    "quest_id": quest_id,
                    "order_index": order_index,
                    "quest_ui_map_id": quest_map_by_quest_id.get(quest_id),
                    "quest_line_ui_map_id": storyline_map_id,
                    "quest_line_expansion_id": storyline_expansion_id,
                }
            )
    return merged_rows


def normalize_navigation_name(raw_value: Any) -> str:
    """归一化导航名，便于做静态匹配。"""

    return re.sub(r"\s+", "", str(raw_value or "")).strip().lower()


def navigation_map_category(map_type: int) -> int:
    """将 UiMap.Type 收敛为导航用的大类。"""

    numeric_type = int(map_type or 0)
    if numeric_type in (3, 6):
        return 3
    if numeric_type in (4, 5):
        return 4
    return numeric_type


def navigation_type_rank(map_type: int) -> int:
    """给导航地图类型分配稳定优先级。"""

    numeric_type = int(map_type or 0)
    if numeric_type == 3:
        return 0
    if numeric_type == 6:
        return 1
    if numeric_type in (4, 5):
        return 2
    map_category = navigation_map_category(numeric_type)
    if map_category == 3:
        return 3
    if map_category == 4:
        return 4
    return 5


def build_navigation_uimap_context(sqlite_conn: sqlite3.Connection) -> dict[str, Any]:
    """构建导航导出所需的 UiMap 上下文与 walk cluster 信息。"""

    uimap_by_id: dict[int, dict[str, Any]] = {}
    primary_map_id_by_uimap_id: dict[int, int] = {}
    assignment_rows_by_uimap_id: dict[int, list[dict[str, Any]]] = defaultdict(list)
    assignment_candidate_rows_by_map_id: dict[int, list[dict[str, Any]]] = defaultdict(list)
    candidate_local_map_ids_by_primary_map_id: dict[int, list[int]] = defaultdict(list)

    for row in sqlite_conn.execute(
        """
SELECT
  CAST(ID AS INTEGER) AS ui_map_id,
  COALESCE(NULLIF(TRIM(Name_lang), ''), 'UiMap #' || CAST(ID AS TEXT)) AS map_name,
  CAST(COALESCE(ParentUiMapID, 0) AS INTEGER) AS parent_ui_map_id,
  CAST(COALESCE(Type, 0) AS INTEGER) AS map_type,
  CAST(COALESCE(System, 0) AS INTEGER) AS system_id
FROM uimap
WHERE CAST(ID AS INTEGER) > 0
"""
    ):
        ui_map_id = int(row["ui_map_id"])
        uimap_by_id[ui_map_id] = {
            "ui_map_id": ui_map_id,
            "name": str(row["map_name"]),
            "parent_ui_map_id": int(row["parent_ui_map_id"] or 0),
            "map_type": int(row["map_type"] or 0),
            "system_id": int(row["system_id"] or 0),
        }

    for row in sqlite_conn.execute(
        """
SELECT
  CAST(UiMapID AS INTEGER) AS ui_map_id,
  CAST(MapID AS INTEGER) AS map_id,
  CAST(Region_0 AS REAL) AS region_x0,
  CAST(Region_1 AS REAL) AS region_y0,
  CAST(Region_3 AS REAL) AS region_x1,
  CAST(Region_4 AS REAL) AS region_y1
FROM uimapassignment
WHERE CAST(UiMapID AS INTEGER) > 0
  AND TRIM(COALESCE(MapID, '')) <> ''
"""
    ):
        ui_map_id = int(row["ui_map_id"] or 0)
        if ui_map_id <= 0:
            continue
        map_id = int(row["map_id"] or 0)
        min_x = min(float(row["region_x0"] or 0), float(row["region_x1"] or 0))
        max_x = max(float(row["region_x0"] or 0), float(row["region_x1"] or 0))
        min_y = min(float(row["region_y0"] or 0), float(row["region_y1"] or 0))
        max_y = max(float(row["region_y0"] or 0), float(row["region_y1"] or 0))
        assignment_rows_by_uimap_id[ui_map_id].append(
            {
                "map_id": map_id,
                "min_x": min_x,
                "max_x": max_x,
                "min_y": min_y,
                "max_y": max_y,
                "area": abs((max_x - min_x) * (max_y - min_y)),
            }
        )
        map_row = uimap_by_id.get(ui_map_id)
        if map_row is not None and int(map_row["system_id"]) == 0 and navigation_map_category(int(map_row["map_type"] or 0)) >= 3:
            assignment_candidate_rows_by_map_id[map_id].append(
                {
                    "candidate_ui_map_id": ui_map_id,
                    "candidate_name": str(map_row["name"]),
                    "candidate_type": int(map_row["map_type"] or 0),
                    "candidate_area": abs((max_x - min_x) * (max_y - min_y)),
                    "min_x": min_x,
                    "max_x": max_x,
                    "min_y": min_y,
                    "max_y": max_y,
                }
            )
        if ui_map_id not in primary_map_id_by_uimap_id:
            primary_map_id_by_uimap_id[ui_map_id] = map_id
        else:
            primary_map_id_by_uimap_id[ui_map_id] = min(primary_map_id_by_uimap_id[ui_map_id], map_id)

    canonical_same_name_uimap_id_by_key: dict[tuple[str, int, int], int] = {}
    for ui_map_id, row in uimap_by_id.items():
        if int(row["system_id"]) != 0:
            continue
        map_category = navigation_map_category(int(row["map_type"]))
        if map_category < 3:
            continue
        primary_map_id = int(primary_map_id_by_uimap_id.get(ui_map_id, -1))
        canonical_key = (
            normalize_navigation_name(row["name"]),
            primary_map_id,
            map_category,
        )
        current_best = canonical_same_name_uimap_id_by_key.get(canonical_key)
        if current_best is None or ui_map_id < current_best:
            canonical_same_name_uimap_id_by_key[canonical_key] = ui_map_id

    canonical_local_uimap_id_cache: dict[int, int] = {}

    def canonical_local_uimap_id(ui_map_id: int) -> int:
        numeric_ui_map_id = int(ui_map_id or 0)
        if numeric_ui_map_id <= 0:
            return 0
        cached_value = canonical_local_uimap_id_cache.get(numeric_ui_map_id)
        if cached_value is not None:
            return cached_value

        row = uimap_by_id.get(numeric_ui_map_id)
        if row is None:
            canonical_local_uimap_id_cache[numeric_ui_map_id] = numeric_ui_map_id
            return numeric_ui_map_id

        base_ui_map_id = numeric_ui_map_id
        current_map_type = int(row["map_type"] or 0)
        if current_map_type in (4, 5):
            parent_ui_map_id = int(row["parent_ui_map_id"] or 0)
            while parent_ui_map_id > 0:
                parent_row = uimap_by_id.get(parent_ui_map_id)
                if parent_row is None:
                    break
                if navigation_map_category(int(parent_row["map_type"] or 0)) == 3:
                    base_ui_map_id = parent_ui_map_id
                    break
                parent_ui_map_id = int(parent_row["parent_ui_map_id"] or 0)

        base_row = uimap_by_id.get(base_ui_map_id, row)
        canonical_key = (
            normalize_navigation_name(base_row["name"]),
            int(primary_map_id_by_uimap_id.get(base_ui_map_id, primary_map_id_by_uimap_id.get(numeric_ui_map_id, -1))),
            navigation_map_category(int(base_row["map_type"] or 0)),
        )
        resolved_ui_map_id = int(canonical_same_name_uimap_id_by_key.get(canonical_key, base_ui_map_id))
        canonical_local_uimap_id_cache[numeric_ui_map_id] = resolved_ui_map_id
        return resolved_ui_map_id

    aggregate_bounds_by_uimap_id: dict[int, dict[str, Any]] = {}
    for ui_map_id, assignment_rows in assignment_rows_by_uimap_id.items():
        if not assignment_rows:
            continue
        min_x = min(row["min_x"] for row in assignment_rows)
        max_x = max(row["max_x"] for row in assignment_rows)
        min_y = min(row["min_y"] for row in assignment_rows)
        max_y = max(row["max_y"] for row in assignment_rows)
        aggregate_bounds_by_uimap_id[ui_map_id] = {
            "map_id": int(primary_map_id_by_uimap_id.get(ui_map_id, -1)),
            "min_x": min_x,
            "max_x": max_x,
            "min_y": min_y,
            "max_y": max_y,
            "area": abs((max_x - min_x) * (max_y - min_y)),
        }

    for ui_map_id, row in uimap_by_id.items():
        if int(row["system_id"]) != 0 or navigation_map_category(int(row["map_type"] or 0)) < 3:
            continue
        primary_map_id = int(primary_map_id_by_uimap_id.get(ui_map_id, -1))
        candidate_local_map_ids_by_primary_map_id[primary_map_id].append(ui_map_id)

    walk_cluster_uimap_id_by_uimap_id: dict[int, int] = {}
    for ui_map_id, row in uimap_by_id.items():
        if int(row["system_id"]) != 0 or navigation_map_category(int(row["map_type"] or 0)) < 3:
            continue
        cluster_ui_map_id = canonical_local_uimap_id(ui_map_id)
        current_bounds = aggregate_bounds_by_uimap_id.get(ui_map_id)
        if current_bounds is not None and navigation_map_category(int(row["map_type"] or 0)) == 3:
            best_container_ui_map_id = None
            best_container_area = None
            primary_map_id = int(current_bounds["map_id"])
            for candidate_ui_map_id in candidate_local_map_ids_by_primary_map_id.get(primary_map_id, []):
                if candidate_ui_map_id == ui_map_id:
                    continue
                candidate_row = uimap_by_id.get(candidate_ui_map_id)
                candidate_bounds = aggregate_bounds_by_uimap_id.get(candidate_ui_map_id)
                if candidate_row is None or candidate_bounds is None:
                    continue
                if navigation_map_category(int(candidate_row["map_type"] or 0)) != 3:
                    continue
                if candidate_bounds["area"] <= current_bounds["area"]:
                    continue
                if (
                    candidate_bounds["min_x"] <= current_bounds["min_x"]
                    and candidate_bounds["max_x"] >= current_bounds["max_x"]
                    and candidate_bounds["min_y"] <= current_bounds["min_y"]
                    and candidate_bounds["max_y"] >= current_bounds["max_y"]
                ):
                    if best_container_area is None or candidate_bounds["area"] < best_container_area:
                        best_container_area = candidate_bounds["area"]
                        best_container_ui_map_id = candidate_ui_map_id
            if best_container_ui_map_id is not None:
                cluster_ui_map_id = canonical_local_uimap_id(best_container_ui_map_id)
        walk_cluster_uimap_id_by_uimap_id[ui_map_id] = int(cluster_ui_map_id)

    return {
        "uimap_by_id": uimap_by_id,
        "canonical_local_uimap_id": canonical_local_uimap_id,
        "walk_cluster_uimap_id_by_uimap_id": walk_cluster_uimap_id_by_uimap_id,
        "assignment_candidate_rows_by_map_id": assignment_candidate_rows_by_map_id,
    }


def build_navigation_candidate_map_id_list(point_map_id: int) -> list[int]:
    """给一个世界坐标点生成可命中的静态 assignment MapID 列表。"""

    numeric_map_id = int(point_map_id or 0)
    if numeric_map_id == 0:
        return [0]
    return [numeric_map_id, 0]


def find_navigation_point_candidate_rows(
    point_map_id: int,
    pos_x: float,
    pos_y: float,
    ui_map_context: dict[str, Any],
) -> list[dict[str, Any]]:
    """基于静态 assignment 索引，查找一个世界点命中的所有导航 UiMap 候选。"""

    numeric_map_id = int(point_map_id or 0)
    numeric_pos_x = float(pos_x or 0)
    numeric_pos_y = float(pos_y or 0)
    point_candidate_cache = ui_map_context.setdefault("point_candidate_cache", {})
    cache_key = (numeric_map_id, numeric_pos_x, numeric_pos_y)
    cached_rows = point_candidate_cache.get(cache_key)
    if cached_rows is not None:
        return cached_rows

    assignment_candidate_rows_by_map_id = ui_map_context["assignment_candidate_rows_by_map_id"]
    matched_rows: list[dict[str, Any]] = []
    seen_row_key: set[tuple[int, float, float, float, float, float]] = set()
    for candidate_map_id in build_navigation_candidate_map_id_list(numeric_map_id):
        for candidate_row in assignment_candidate_rows_by_map_id.get(candidate_map_id, []):
            if not (
                float(candidate_row["min_x"]) <= numeric_pos_x <= float(candidate_row["max_x"])
                and float(candidate_row["min_y"]) <= numeric_pos_y <= float(candidate_row["max_y"])
            ):
                continue
            row_key = (
                int(candidate_row["candidate_ui_map_id"]),
                float(candidate_row["candidate_area"]),
                float(candidate_row["min_x"]),
                float(candidate_row["max_x"]),
                float(candidate_row["min_y"]),
                float(candidate_row["max_y"]),
            )
            if row_key in seen_row_key:
                continue
            seen_row_key.add(row_key)
            matched_rows.append(
                {
                    "candidate_ui_map_id": int(candidate_row["candidate_ui_map_id"]),
                    "candidate_name": str(candidate_row["candidate_name"]),
                    "candidate_type": int(candidate_row["candidate_type"]),
                    "candidate_area": float(candidate_row["candidate_area"]),
                }
            )

    point_candidate_cache[cache_key] = matched_rows
    return matched_rows


def choose_navigation_ui_map_id(
    candidate_rows: list[dict[str, Any]],
    ui_map_context: dict[str, Any],
    *,
    hint_name: str | None = None,
) -> int:
    """在一组静态候选 UiMap 中选出最适合导航显示的地图。"""

    canonical_local_uimap_id = ui_map_context["canonical_local_uimap_id"]
    uimap_by_id = ui_map_context["uimap_by_id"]
    normalized_hint = normalize_navigation_name(hint_name)
    candidate_group_by_uimap_id: dict[int, dict[str, Any]] = {}

    for candidate_row in candidate_rows:
        raw_candidate_ui_map_id = int(candidate_row.get("candidate_ui_map_id") or 0)
        canonical_ui_map_id = int(canonical_local_uimap_id(raw_candidate_ui_map_id))
        if canonical_ui_map_id <= 0:
            continue
        canonical_row = uimap_by_id.get(canonical_ui_map_id)
        if canonical_row is None:
            continue
        candidate_group_row = candidate_group_by_uimap_id.get(canonical_ui_map_id)
        if candidate_group_row is None:
            candidate_group_row = {
                "ui_map_id": canonical_ui_map_id,
                "canonical_area": None,
                "fallback_area": float(candidate_row.get("candidate_area") or 0),
                "type_rank": navigation_type_rank(int(canonical_row["map_type"] or 0)),
                "name_match_rank": 1,
            }
            candidate_group_by_uimap_id[canonical_ui_map_id] = candidate_group_row
        else:
            candidate_group_row["fallback_area"] = min(
                float(candidate_group_row["fallback_area"]),
                float(candidate_row.get("candidate_area") or 0),
            )

        if raw_candidate_ui_map_id == canonical_ui_map_id:
            direct_area = float(candidate_row.get("candidate_area") or 0)
            if candidate_group_row["canonical_area"] is None:
                candidate_group_row["canonical_area"] = direct_area
            else:
                candidate_group_row["canonical_area"] = min(
                    float(candidate_group_row["canonical_area"]),
                    direct_area,
                )

        candidate_name_set = {
            normalize_navigation_name(candidate_row.get("candidate_name")),
            normalize_navigation_name(canonical_row["name"]),
        }
        if normalized_hint and any(candidate_name and candidate_name in normalized_hint for candidate_name in candidate_name_set):
            candidate_group_row["name_match_rank"] = 0

    if not candidate_group_by_uimap_id:
        return 0

    ordered_groups = sorted(
        candidate_group_by_uimap_id.values(),
        key=lambda item: (
            int(item["name_match_rank"]),
            int(item["type_rank"]),
            float(item["canonical_area"] if item["canonical_area"] is not None else item["fallback_area"]),
            int(item["ui_map_id"]),
        ),
    )
    return int(ordered_groups[0]["ui_map_id"])


def resolve_navigation_pathnode_ui_map_id(
    candidate_rows: list[dict[str, Any]],
    current_ui_map_id: int,
    to_ui_map_id: int,
    ui_map_context: dict[str, Any],
) -> int:
    """为 TaxiPathNode 选择 UiMap，优先保持路径连续，再回退到通用排序。"""

    candidate_ui_map_id_set = {
        int(candidate_row.get("candidate_ui_map_id") or 0)
        for candidate_row in candidate_rows
        if int(candidate_row.get("candidate_ui_map_id") or 0) > 0
    }
    if int(current_ui_map_id or 0) > 0 and int(current_ui_map_id or 0) in candidate_ui_map_id_set:
        return int(current_ui_map_id)
    if int(to_ui_map_id or 0) > 0 and int(to_ui_map_id or 0) in candidate_ui_map_id_set:
        return int(to_ui_map_id)
    return choose_navigation_ui_map_id(candidate_rows, ui_map_context)


def build_navigation_walk_cluster_key(ui_map_id: int, ui_map_context: dict[str, Any]) -> str:
    """把 UiMapID 转成导航运行时使用的 walk cluster key。"""

    walk_cluster_uimap_id_by_uimap_id = ui_map_context["walk_cluster_uimap_id_by_uimap_id"]
    cluster_ui_map_id = int(walk_cluster_uimap_id_by_uimap_id.get(int(ui_map_id or 0), int(ui_map_id or 0)) or 0)
    return f"uimap_{cluster_ui_map_id}"


def build_navigation_ui_map_names(ui_map_id_list: list[int], ui_map_context: dict[str, Any]) -> list[str]:
    """把 UiMapID 序列转成稳定的地图名序列。"""

    name_list: list[str] = []
    uimap_by_id = ui_map_context["uimap_by_id"]
    for ui_map_id in ui_map_id_list:
        map_row = uimap_by_id.get(int(ui_map_id or 0))
        if map_row is None:
            name_list.append(f"UiMap #{int(ui_map_id or 0)}")
        else:
            name_list.append(str(map_row["name"]))
    return name_list


def build_navigation_class_context(sqlite_conn: sqlite3.Connection) -> dict[str, Any]:
    """构建导航能力模板所需的职业映射上下文。"""

    class_file_by_class_mask: dict[int, str] = {}
    class_file_by_skillline_id: dict[int, str] = {}
    class_file_by_normalized_name: dict[str, str] = {}

    for row in sqlite_conn.execute(
        """
SELECT
  CAST(ID AS INTEGER) AS class_id,
  COALESCE(NULLIF(TRIM(Name_lang), ''), '') AS class_name,
  COALESCE(NULLIF(TRIM(Filename), ''), '') AS class_file
FROM chrclasses
WHERE CAST(ID AS INTEGER) > 0
  AND COALESCE(NULLIF(TRIM(Filename), ''), '') <> ''
"""
    ):
        class_id = int(row["class_id"] or 0)
        class_name = str(row["class_name"] or "")
        class_file = str(row["class_file"] or "")
        if class_id <= 0 or class_file == "":
            continue
        class_file_by_class_mask[1 << (class_id - 1)] = class_file
        if class_name != "":
            class_file_by_normalized_name[normalize_navigation_name(class_name)] = class_file

    for row in sqlite_conn.execute(
        """
SELECT
  CAST(ID AS INTEGER) AS skillline_id,
  COALESCE(NULLIF(TRIM(DisplayName_lang), ''), '') AS skillline_name
FROM skillline
WHERE CAST(ID AS INTEGER) > 0
"""
    ):
        skillline_id = int(row["skillline_id"] or 0)
        skillline_name = str(row["skillline_name"] or "")
        class_file = class_file_by_normalized_name.get(normalize_navigation_name(skillline_name))
        if skillline_id > 0 and class_file:
            class_file_by_skillline_id[skillline_id] = class_file

    return {
        "class_file_by_class_mask": class_file_by_class_mask,
        "class_file_by_skillline_id": class_file_by_skillline_id,
    }


def build_navigation_faction_masks(sqlite_conn: sqlite3.Connection) -> dict[str, int]:
    """构建 Alliance / Horde 对应的种族掩码。"""

    faction_masks = {
        "Alliance": 0,
        "Horde": 0,
    }
    for row in sqlite_conn.execute(
        """
SELECT
  CAST(PlayableRaceBit AS INTEGER) AS playable_race_bit,
  CAST(COALESCE(Alliance, -1) AS INTEGER) AS alliance_code
FROM chrraces
WHERE CAST(COALESCE(PlayableRaceBit, -1) AS INTEGER) >= 0
"""
    ):
        playable_race_bit = int(row["playable_race_bit"] or -1)
        alliance_code = int(row["alliance_code"] or -1)
        if playable_race_bit < 0:
            continue
        race_mask = 1 << playable_race_bit
        if alliance_code == 0:
            faction_masks["Alliance"] |= race_mask
        elif alliance_code == 1:
            faction_masks["Horde"] |= race_mask
    return faction_masks


def choose_navigation_faction_group(
    race_mask: int,
    faction_masks: dict[str, int],
) -> str | None:
    """把 RaceMask 收敛成导航模板使用的阵营名。"""

    numeric_race_mask = int(race_mask or 0)
    if numeric_race_mask <= 0:
        return None

    is_alliance = (numeric_race_mask & int(faction_masks.get("Alliance", 0))) != 0
    is_horde = (numeric_race_mask & int(faction_masks.get("Horde", 0))) != 0
    if is_alliance and not is_horde:
        return "Alliance"
    if is_horde and not is_alliance:
        return "Horde"
    return None


def build_navigation_uimap_name_chain(ui_map_id: int, ui_map_context: dict[str, Any]) -> list[str]:
    """返回指定 UiMap 的名称父链。"""

    name_chain: list[str] = []
    uimap_by_id = ui_map_context["uimap_by_id"]
    current_ui_map_id = int(ui_map_id or 0)
    guard_count = 0
    while current_ui_map_id > 0 and guard_count < 16:
        map_row = uimap_by_id.get(current_ui_map_id)
        if map_row is None:
            break
        name_chain.append(str(map_row["name"]))
        current_ui_map_id = int(map_row["parent_ui_map_id"] or 0)
        guard_count += 1
    return name_chain


def choose_navigation_named_uimap_id(
    target_name: str,
    qualifier_text: str,
    ui_map_context: dict[str, Any],
) -> int:
    """按导出的地图名称与限定词选择一个稳定的 UiMap 锚点。"""

    normalized_target_name = normalize_navigation_name(target_name)
    normalized_qualifier = normalize_navigation_name(qualifier_text)
    if normalized_target_name == "":
        return 0

    uimap_by_id = ui_map_context["uimap_by_id"]
    canonical_local_uimap_id = ui_map_context["canonical_local_uimap_id"]
    candidate_ui_map_id_set: set[int] = set()
    for ui_map_id, map_row in uimap_by_id.items():
        if int(map_row["system_id"]) != 0 or navigation_map_category(int(map_row["map_type"] or 0)) < 3:
            continue
        canonical_ui_map_id = int(canonical_local_uimap_id(ui_map_id))
        if canonical_ui_map_id <= 0:
            continue
        canonical_row = uimap_by_id.get(canonical_ui_map_id)
        if canonical_row is None:
            continue
        normalized_candidate_name = normalize_navigation_name(canonical_row["name"])
        if normalized_candidate_name == "":
            continue
        if normalized_target_name not in normalized_candidate_name and normalized_candidate_name not in normalized_target_name:
            continue
        candidate_ui_map_id_set.add(canonical_ui_map_id)

    if not candidate_ui_map_id_set:
        return 0

    def candidate_score(candidate_ui_map_id: int) -> tuple[int, int, int, int]:
        candidate_row = uimap_by_id.get(candidate_ui_map_id, {})
        normalized_candidate_name = normalize_navigation_name(candidate_row.get("name"))
        exact_name_rank = 0 if normalized_candidate_name == normalized_target_name else 1
        qualifier_rank = 0
        if normalized_qualifier:
            qualifier_rank = 1
            for chain_name in build_navigation_uimap_name_chain(candidate_ui_map_id, ui_map_context):
                normalized_chain_name = normalize_navigation_name(chain_name)
                if normalized_chain_name and (
                    normalized_qualifier in normalized_chain_name
                    or normalized_chain_name in normalized_qualifier
                ):
                    qualifier_rank = 0
                    break
        return (
            qualifier_rank,
            exact_name_rank,
            navigation_type_rank(int(candidate_row.get("map_type") or 0)),
            int(candidate_ui_map_id),
        )

    return sorted(candidate_ui_map_id_set, key=candidate_score)[0]


def resolve_navigation_class_file(
    class_mask: int,
    skillline_id: int,
    class_context: dict[str, Any],
) -> str | None:
    """从 ClassMask / SkillLine 恢复类文件名。"""

    numeric_class_mask = int(class_mask or 0)
    if numeric_class_mask > 0 and (numeric_class_mask & (numeric_class_mask - 1)) == 0:
        class_file = class_context["class_file_by_class_mask"].get(numeric_class_mask)
        if class_file:
            return class_file
    return class_context["class_file_by_skillline_id"].get(int(skillline_id or 0))


def parse_navigation_ability_spell(
    spell_id: int,
    spell_name: str,
    has_portal_effect: int,
    has_teleport_effect: int,
) -> dict[str, Any] | None:
    """把候选法术行解析成导航能力模板的中间语义。"""

    normalized_spell_name = str(spell_name or "").strip()
    if normalized_spell_name == "":
        return None

    if normalized_spell_name == "炉石":
        if int(spell_id or 0) != 8690:
            return None
        return {
            "mode": "hearthstone",
            "target_rule_kind": "hearth_bind",
            "target_name": "",
            "qualifier_text": "",
        }

    mode = ""
    target_text = ""
    if normalized_spell_name.startswith("传送门："):
        if int(has_portal_effect or 0) <= 0:
            return None
        mode = "class_portal"
        target_text = normalized_spell_name[len("传送门：") :].strip()
    elif normalized_spell_name.startswith("远古传送门："):
        if int(has_portal_effect or 0) <= 0:
            return None
        mode = "class_portal"
        target_text = normalized_spell_name[len("远古传送门：") :].strip()
    elif normalized_spell_name.startswith("传送："):
        if int(has_teleport_effect or 0) <= 0:
            return None
        mode = "class_teleport"
        target_text = normalized_spell_name[len("传送：") :].strip()
    else:
        return None

    target_text = re.sub(r"（[^）]*）", "", target_text)
    target_text = re.sub(r"\([^)]*\)", "", target_text).strip()
    if target_text == "" or "/" in target_text or "返回" in target_text or "到" in target_text:
        return None

    qualifier_text = ""
    if " - " in target_text:
        target_text, qualifier_text = [part.strip() for part in target_text.split(" - ", 1)]

    if target_text == "":
        return None

    return {
        "mode": mode,
        "target_rule_kind": "fixed_node",
        "target_name": target_text,
        "qualifier_text": qualifier_text,
    }


def enrich_navigation_ability_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把导航能力候选法术补齐为运行时可消费的模板。"""

    template_rows = list(dataset_rows_by_name.get("templates_raw", []))
    if not template_rows:
        dataset_rows_by_name["templates"] = []
        return dataset_rows_by_name

    ui_map_context = build_navigation_uimap_context(sqlite_conn)
    class_context = build_navigation_class_context(sqlite_conn)
    faction_masks = build_navigation_faction_masks(sqlite_conn)

    template_entry_by_id: dict[str, dict[str, Any]] = {}
    for template_row in template_rows:
        spell_id = int(template_row.get("spell_id") or 0)
        spell_name = str(template_row.get("spell_name") or "").strip()
        if spell_id <= 0 or spell_name == "":
            continue

        parsed_template = parse_navigation_ability_spell(
            spell_id,
            spell_name,
            int(template_row.get("has_portal_effect") or 0),
            int(template_row.get("has_teleport_effect") or 0),
        )
        if parsed_template is None:
            continue

        to_node_id = None
        if parsed_template["target_rule_kind"] == "fixed_node":
            target_ui_map_id = choose_navigation_named_uimap_id(
                str(parsed_template["target_name"]),
                str(parsed_template["qualifier_text"]),
                ui_map_context,
            )
            if target_ui_map_id <= 0:
                continue
            to_node_id = f"uimap_{target_ui_map_id}"

        class_file = resolve_navigation_class_file(
            int(template_row.get("class_mask") or 0),
            int(template_row.get("skillline_id") or 0),
            class_context,
        )
        if parsed_template["mode"] != "hearthstone" and class_file is None:
            continue

        template_id = f"spell_{spell_id}"
        template_entry_by_id[template_id] = {
            "template_id": template_id,
            "mode": str(parsed_template["mode"]),
            "spell_id": spell_id,
            "class_file": class_file,
            "faction_group": choose_navigation_faction_group(
                int(template_row.get("race_mask") or 0),
                faction_masks,
            ),
            "target_rule_kind": str(parsed_template["target_rule_kind"]),
            "to_node_id": to_node_id,
            "label": spell_name,
            "self_use_only": True,
        }

    dataset_rows_by_name["templates"] = sorted(
        template_entry_by_id.values(),
        key=lambda row: (int(row["spell_id"]), str(row["template_id"])),
    )
    return dataset_rows_by_name


def fetch_navigation_taxi_node_candidate_rows(
    node_rows: list[dict[str, Any]],
    ui_map_context: dict[str, Any],
) -> dict[int, list[dict[str, Any]]]:
    """批量抓取 TaxiNode 点位命中的 UiMap 候选。"""

    candidate_rows_by_taxi_node_id: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for node_row in node_rows:
        taxi_node_id = int(node_row.get("taxi_node_id") or 0)
        if taxi_node_id <= 0:
            continue
        candidate_rows_by_taxi_node_id[taxi_node_id].extend(
            find_navigation_point_candidate_rows(
                int(node_row.get("map_id") or 0),
                float(node_row.get("pos_x") or 0),
                float(node_row.get("pos_y") or 0),
                ui_map_context,
            )
        )
    return candidate_rows_by_taxi_node_id


def fetch_navigation_taxi_pathnode_rows(
    sqlite_conn: sqlite3.Connection,
    path_id_list: list[int],
) -> dict[int, list[dict[str, Any]]]:
    """批量抓取 TaxiPathNode 基础点位行。"""

    pathnode_rows_by_path_id: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for start_index in range(0, len(path_id_list), 200):
        batch_id_list = path_id_list[start_index : start_index + 200]
        if not batch_id_list:
            continue
        placeholder_text = ",".join("?" for _ in batch_id_list)
        sql_text = f"""
SELECT
  CAST(PathID AS INTEGER) AS path_id,
  CAST(NodeIndex AS INTEGER) AS node_index,
  CAST(ContinentID AS INTEGER) AS map_id,
  CAST(Loc_0 AS REAL) AS pos_x,
  CAST(Loc_1 AS REAL) AS pos_y
FROM taxipathnode
WHERE CAST(PathID AS INTEGER) IN ({placeholder_text})
ORDER BY CAST(PathID AS INTEGER), CAST(NodeIndex AS INTEGER)
"""
        for row in sqlite_conn.execute(sql_text, batch_id_list):
            pathnode_rows_by_path_id[int(row["path_id"])].append(dict(row))
    return pathnode_rows_by_path_id


def fetch_navigation_taxi_pathnode_candidate_rows(
    pathnode_rows_by_path_id: dict[int, list[dict[str, Any]]],
    ui_map_context: dict[str, Any],
) -> dict[tuple[int, int], list[dict[str, Any]]]:
    """批量抓取 TaxiPathNode 点位命中的 UiMap 候选。"""

    candidate_rows_by_key: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    for path_id, pathnode_rows in pathnode_rows_by_path_id.items():
        for pathnode_row in pathnode_rows:
            key_value = (int(path_id), int(pathnode_row["node_index"]))
            candidate_rows_by_key[key_value].extend(
                find_navigation_point_candidate_rows(
                    int(pathnode_row.get("map_id") or 0),
                    float(pathnode_row.get("pos_x") or 0),
                    float(pathnode_row.get("pos_y") or 0),
                    ui_map_context,
                )
            )
    return candidate_rows_by_key


def enrich_navigation_taxi_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把 Taxi 原始数据集补齐为可直接消费的导航节点 / 边。"""

    node_rows = list(dataset_rows_by_name.get("nodes_raw", []))
    edge_rows = list(dataset_rows_by_name.get("edges_raw", []))
    if not node_rows or not edge_rows:
        dataset_rows_by_name["nodes"] = []
        dataset_rows_by_name["edges"] = []
        return dataset_rows_by_name

    ui_map_context = build_navigation_uimap_context(sqlite_conn)
    node_candidate_rows_by_taxi_node_id = fetch_navigation_taxi_node_candidate_rows(node_rows, ui_map_context)

    enriched_node_rows: list[dict[str, Any]] = []
    enriched_node_row_by_taxi_node_id: dict[int, dict[str, Any]] = {}
    for node_row in node_rows:
        taxi_node_id = int(node_row.get("taxi_node_id") or 0)
        if taxi_node_id <= 0:
            continue
        node_name = str(node_row.get("node_name") or "")
        if is_runtime_excluded_taxi_node_name(node_name):
            continue
        ui_map_id = choose_navigation_ui_map_id(
            node_candidate_rows_by_taxi_node_id.get(taxi_node_id, []),
            ui_map_context,
            hint_name=node_name,
        )
        if ui_map_id <= 0:
            continue
        is_transport = (
            "Transport" in node_name
            or "交通工具" in node_name
        )
        enriched_node_row = {
            "taxi_node_key": f"taxi_{taxi_node_id}",
            "taxi_node_id": taxi_node_id,
            "ui_map_id": ui_map_id,
            "map_id": int(node_row.get("map_id") or 0),
            "node_name": node_name,
            "walk_cluster_key": build_navigation_walk_cluster_key(ui_map_id, ui_map_context),
            "pos_x": float(node_row.get("pos_x") or 0),
            "pos_y": float(node_row.get("pos_y") or 0),
            "pos_z": float(node_row.get("pos_z") or 0),
            "node_flags": int(node_row.get("node_flags") or 0),
            "condition_id": int(node_row.get("condition_id") or 0),
            "visibility_condition_id": int(node_row.get("visibility_condition_id") or 0),
            "is_transport": is_transport,
        }
        enriched_node_rows.append(enriched_node_row)
        enriched_node_row_by_taxi_node_id[taxi_node_id] = enriched_node_row

    path_id_list = sorted({int(row.get("path_id") or 0) for row in edge_rows if int(row.get("path_id") or 0) > 0})
    pathnode_rows_by_path_id = fetch_navigation_taxi_pathnode_rows(sqlite_conn, path_id_list)
    pathnode_candidate_rows_by_key = fetch_navigation_taxi_pathnode_candidate_rows(pathnode_rows_by_path_id, ui_map_context)

    enriched_edge_rows: list[dict[str, Any]] = []
    for edge_row in edge_rows:
        path_id = int(edge_row.get("path_id") or 0)
        from_taxi_node_id = int(edge_row.get("from_taxi_node_id") or 0)
        to_taxi_node_id = int(edge_row.get("to_taxi_node_id") or 0)
        from_node_row = enriched_node_row_by_taxi_node_id.get(from_taxi_node_id)
        to_node_row = enriched_node_row_by_taxi_node_id.get(to_taxi_node_id)
        if path_id <= 0 or from_node_row is None or to_node_row is None:
            continue

        # 过滤：自环边（起点 == 终点）
        if from_taxi_node_id == to_taxi_node_id:
            continue

        traversed_ui_map_id_list = [int(from_node_row["ui_map_id"])]
        current_path_ui_map_id = int(from_node_row["ui_map_id"])
        for pathnode_row in pathnode_rows_by_path_id.get(path_id, []):
            candidate_key = (int(pathnode_row["path_id"]), int(pathnode_row["node_index"]))
            pathnode_ui_map_id = resolve_navigation_pathnode_ui_map_id(
                pathnode_candidate_rows_by_key.get(candidate_key, []),
                current_path_ui_map_id,
                int(to_node_row["ui_map_id"]),
                ui_map_context,
            )
            if pathnode_ui_map_id > 0 and pathnode_ui_map_id != current_path_ui_map_id:
                traversed_ui_map_id_list.append(pathnode_ui_map_id)
                current_path_ui_map_id = pathnode_ui_map_id
        if int(to_node_row["ui_map_id"]) != traversed_ui_map_id_list[-1]:
            traversed_ui_map_id_list.append(int(to_node_row["ui_map_id"]))
        traversed_ui_map_name_list = build_navigation_ui_map_names(traversed_ui_map_id_list, ui_map_context)

        enriched_edge_rows.append(
            {
                "edge_index": int(edge_row.get("edge_index") or 0),
                "path_id": path_id,
                "from_node_key": f"taxi_{from_taxi_node_id}",
                "to_node_key": f"taxi_{to_taxi_node_id}",
                "from_taxi_node_id": from_taxi_node_id,
                "to_taxi_node_id": to_taxi_node_id,
                "from_ui_map_id": int(from_node_row["ui_map_id"]),
                "to_ui_map_id": int(to_node_row["ui_map_id"]),
                "step_cost": 1,
                "mode": "transport" if (from_node_row.get("is_transport") or to_node_row.get("is_transport")) else "taxi",
                "edge_label": "乘坐" + str(to_node_row["node_name"]) if from_node_row.get("is_transport") or to_node_row.get("is_transport") else "飞行前往" + str(to_node_row["node_name"]),
                "traversed_ui_map_ids": traversed_ui_map_id_list,
                "traversed_ui_map_names": traversed_ui_map_name_list,
            }
        )

    dataset_rows_by_name["nodes"] = enriched_node_rows
    dataset_rows_by_name["edges"] = sorted(
        enriched_edge_rows,
        key=lambda row: (int(row["edge_index"]), int(row["path_id"])),
    )
    return dataset_rows_by_name


def fetch_navigation_portal_node_candidate_rows(
    sqlite_conn: sqlite3.Connection,
    portal_node_rows: list[dict[str, Any]],
) -> dict[int, list[dict[str, Any]]]:
    """批量抓取 waypoint portal 节点点位命中的 UiMap 候选。"""

    grouped_rows: dict[tuple[int, float, float], list[int]] = {}
    for node_row in portal_node_rows:
        map_id = int(node_row.get("map_id") or 0)
        world_x = float(node_row.get("world_x") or 0)
        world_y = float(node_row.get("world_y") or 0)
        key = (map_id, world_x, world_y)
        grouped_rows.setdefault(key, []).append(int(node_row.get("waypoint_node_id") or 0))

    candidate_rows_by_node_id: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for (map_id, world_x, world_y), node_id_list in grouped_rows.items():
        sql_text = """
SELECT
  CAST(a.UiMapID AS INTEGER) AS candidate_ui_map_id,
  COALESCE(NULLIF(TRIM(u.Name_lang), ''), 'UiMap #' || CAST(a.UiMapID AS TEXT)) AS candidate_name,
  CAST(COALESCE(u.Type, 0) AS INTEGER) AS candidate_type,
  ABS((CAST(a.Region_3 AS REAL) - CAST(a.Region_0 AS REAL)) * (CAST(a.Region_4 AS REAL) - CAST(a.Region_1 AS REAL))) AS candidate_area
FROM uimapassignment a, uimap u
WHERE CAST(a.UiMapID AS INTEGER) = CAST(u.ID AS INTEGER)
  AND CAST(a.MapID AS INTEGER) = ?
  AND CAST(a.Region_0 AS REAL) <= ?
  AND CAST(a.Region_3 AS REAL) >= ?
  AND CAST(a.Region_1 AS REAL) <= ?
  AND CAST(a.Region_4 AS REAL) >= ?
  AND CAST(COALESCE(u.System, 0) AS INTEGER) = 0
  AND CAST(COALESCE(u.Type, 0) AS INTEGER) >= 3
"""
        rows = sqlite_conn.execute(sql_text, (map_id, world_x, world_x, world_y, world_y)).fetchall()
        if not rows:
            continue
        candidate_rows = [dict(row) for row in rows]
        for node_id in node_id_list:
            candidate_rows_by_node_id[node_id].extend(candidate_rows)
    return candidate_rows_by_node_id


def is_runtime_excluded_taxi_node_name(node_name: str) -> bool:
    """判断 TaxiNode 是否属于明显不应进入运行时图的 Quest/Test 节点。"""

    normalized_name = str(node_name or "").strip()
    if normalized_name == "":
        return False
    return (
        normalized_name.startswith("Quest Path ")
        or normalized_name.startswith("Quest - ")
        or normalized_name.startswith("Test - ")
    )


def is_public_transport_waypoint_name(node_name: str) -> bool:
    """判断 waypoint Type=0 名称是否表达公共交通动作。"""

    normalized_name = str(node_name or "").strip()
    if normalized_name == "":
        return False
    transport_keyword_list = (
        "乘坐",
        "搭乘",
        "地铁",
        "飞艇",
        "潜水艇",
        "缆车",
        "岗哆拉",
        "Gondola",
        "Tram",
        "Zeppelin",
    )
    return any(keyword in normalized_name for keyword in transport_keyword_list)


def enrich_navigation_portal_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把 waypoint portal 原始数据集补齐为 public_portal 节点 / 边。"""

    portal_node_rows = list(dataset_rows_by_name.get("portal_nodes_raw", []))
    portal_edge_rows = list(dataset_rows_by_name.get("portal_edges_raw", []))
    if not portal_node_rows or not portal_edge_rows:
        dataset_rows_by_name["portal_nodes"] = []
        dataset_rows_by_name["portal_edges"] = []
        return dataset_rows_by_name

    ui_map_context = build_navigation_uimap_context(sqlite_conn)
    candidate_rows_by_node_id = fetch_navigation_portal_node_candidate_rows(sqlite_conn, portal_node_rows)

    # 内联的联盟/部落阵营条件 ID
    faction_condition_by_id = {924: "Alliance", 923: "Horde"}

    enriched_node_rows: list[dict[str, Any]] = []
    enriched_node_row_by_node_id: dict[int, dict[str, Any]] = {}
    for node_row in portal_node_rows:
        waypoint_node_id = int(node_row.get("waypoint_node_id") or 0)
        if waypoint_node_id <= 0:
            continue
        node_name = str(node_row.get("node_name") or "")
        node_type = int(node_row.get("node_type") or 0)
        if node_type not in (1, 2):
            continue
        ui_map_id = choose_navigation_ui_map_id(
            candidate_rows_by_node_id.get(waypoint_node_id, []),
            ui_map_context,
            hint_name=node_name,
        )
        if ui_map_id <= 0:
            continue
        enriched_node_row = {
            "portal_node_key": f"portal_{waypoint_node_id}",
            "waypoint_node_id": waypoint_node_id,
            "ui_map_id": ui_map_id,
            "map_id": int(node_row.get("map_id") or 0),
            "node_name": node_name,
            "walk_cluster_key": build_navigation_walk_cluster_key(ui_map_id, ui_map_context),
            "pos_x": float(node_row.get("world_x") or 0),
            "pos_y": float(node_row.get("world_y") or 0),
            "pos_z": float(node_row.get("world_z") or 0),
            "node_type": node_type,
            "player_condition_id": int(node_row.get("player_condition_id") or 0),
        }
        enriched_node_rows.append(enriched_node_row)
        enriched_node_row_by_node_id[waypoint_node_id] = enriched_node_row

    enriched_edge_rows: list[dict[str, Any]] = []
    for edge_index, edge_row in enumerate(portal_edge_rows):
        from_node_id = int(edge_row.get("from_waypoint_node_id") or 0)
        to_node_id = int(edge_row.get("to_waypoint_node_id") or 0)
        from_node_row = enriched_node_row_by_node_id.get(from_node_id)
        to_node_row = enriched_node_row_by_node_id.get(to_node_id)
        if from_node_row is None or to_node_row is None:
            continue

        # 自环边过滤
        if from_node_id == to_node_id:
            continue

        # PlayerConditionID 分层：0 无条件纳入；924/923 标 faction；其余暂不纳入
        from_condition_id = int(edge_row.get("player_condition_id") or 0)
        requirements_faction = faction_condition_by_id.get(from_condition_id)
        if from_condition_id != 0 and requirements_faction is None:
            continue

        traversed_ui_map_ids = [int(from_node_row["ui_map_id"]), int(to_node_row["ui_map_id"])]
        traversed_ui_map_names = build_navigation_ui_map_names(traversed_ui_map_ids, ui_map_context)

        from_node_name = str(from_node_row["node_name"])
        to_node_name = str(to_node_row["node_name"])

        edge_data = {
            "edge_index": edge_index,
            "route_source": "portal",
            "from_node_id": str(from_node_row["portal_node_key"]),
            "to_node_id": str(to_node_row["portal_node_key"]),
            "from_ui_map_id": int(from_node_row["ui_map_id"]),
            "to_ui_map_id": int(to_node_row["ui_map_id"]),
            "step_cost": 1,
            "mode": "public_portal",
            "edge_label": from_node_name + "\xe2\x86\x92" + to_node_name,
            "traversed_ui_map_ids": traversed_ui_map_ids,
            "traversed_ui_map_names": traversed_ui_map_names,
            "requirements_faction": requirements_faction,
        }
        enriched_edge_rows.append(edge_data)

    dataset_rows_by_name["portal_nodes"] = enriched_node_rows
    dataset_rows_by_name["portal_edges"] = sorted(
        enriched_edge_rows,
        key=lambda row: (int(row["edge_index"]), str(row["from_node_id"])),
    )
    return dataset_rows_by_name


def enrich_navigation_transport_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把 waypoint Type=0 的公共交通原始数据补齐为 transport 节点 / 边。"""

    transport_node_rows = list(dataset_rows_by_name.get("transport_nodes_raw", []))
    transport_edge_rows = list(dataset_rows_by_name.get("transport_edges_raw", []))
    if not transport_node_rows or not transport_edge_rows:
        dataset_rows_by_name["transport_nodes"] = []
        dataset_rows_by_name["transport_edges"] = []
        return dataset_rows_by_name

    ui_map_context = build_navigation_uimap_context(sqlite_conn)
    candidate_rows_by_node_id = fetch_navigation_portal_node_candidate_rows(sqlite_conn, transport_node_rows)
    faction_condition_by_id = {924: "Alliance", 923: "Horde"}

    enriched_node_rows: list[dict[str, Any]] = []
    enriched_node_row_by_node_id: dict[int, dict[str, Any]] = {}
    for node_row in transport_node_rows:
        waypoint_node_id = int(node_row.get("waypoint_node_id") or 0)
        if waypoint_node_id <= 0:
            continue
        node_name = str(node_row.get("node_name") or "")
        if not is_public_transport_waypoint_name(node_name):
            continue
        ui_map_id = choose_navigation_ui_map_id(
            candidate_rows_by_node_id.get(waypoint_node_id, []),
            ui_map_context,
            hint_name=node_name,
        )
        if ui_map_id <= 0:
            continue
        enriched_node_row = {
            "transport_node_key": f"transport_{waypoint_node_id}",
            "waypoint_node_id": waypoint_node_id,
            "ui_map_id": ui_map_id,
            "map_id": int(node_row.get("map_id") or 0),
            "node_name": node_name,
            "walk_cluster_key": build_navigation_walk_cluster_key(ui_map_id, ui_map_context),
            "pos_x": float(node_row.get("world_x") or 0),
            "pos_y": float(node_row.get("world_y") or 0),
            "pos_z": float(node_row.get("world_z") or 0),
            "node_type": int(node_row.get("node_type") or 0),
            "player_condition_id": int(node_row.get("player_condition_id") or 0),
        }
        enriched_node_rows.append(enriched_node_row)
        enriched_node_row_by_node_id[waypoint_node_id] = enriched_node_row

    enriched_edge_rows: list[dict[str, Any]] = []
    for edge_index, edge_row in enumerate(transport_edge_rows):
        from_node_id = int(edge_row.get("from_waypoint_node_id") or 0)
        to_node_id = int(edge_row.get("to_waypoint_node_id") or 0)
        from_node_row = enriched_node_row_by_node_id.get(from_node_id)
        to_node_row = enriched_node_row_by_node_id.get(to_node_id)
        if from_node_row is None or to_node_row is None:
            continue
        if from_node_id == to_node_id:
            continue

        edge_condition_id = int(edge_row.get("player_condition_id") or 0)
        requirements_faction = faction_condition_by_id.get(edge_condition_id)
        if edge_condition_id != 0 and requirements_faction is None:
            continue

        traversed_ui_map_ids = [
            int(from_node_row["ui_map_id"]),
            int(to_node_row["ui_map_id"]),
        ]
        traversed_ui_map_names = build_navigation_ui_map_names(traversed_ui_map_ids, ui_map_context)
        from_node_name = str(from_node_row["node_name"] or "")
        to_node_name = str(to_node_row["node_name"] or "")
        if not is_public_transport_waypoint_name(from_node_name) or not is_public_transport_waypoint_name(to_node_name):
            continue

        enriched_edge_rows.append(
            {
                "edge_index": edge_index,
                "waypoint_edge_id": int(edge_row.get("waypoint_edge_id") or 0),
                "route_source": "waypoint_transport",
                "from_node_id": str(from_node_row["transport_node_key"]),
                "to_node_id": str(to_node_row["transport_node_key"]),
                "from_ui_map_id": int(from_node_row["ui_map_id"]),
                "to_ui_map_id": int(to_node_row["ui_map_id"]),
                "step_cost": 1,
                "mode": "transport",
                "edge_label": from_node_name,
                "traversed_ui_map_ids": traversed_ui_map_ids,
                "traversed_ui_map_names": traversed_ui_map_names,
                "requirements_faction": requirements_faction,
            }
        )

    dataset_rows_by_name["transport_nodes"] = enriched_node_rows
    dataset_rows_by_name["transport_edges"] = sorted(
        enriched_edge_rows,
        key=lambda row: (int(row["edge_index"]), int(row["waypoint_edge_id"])),
    )
    return dataset_rows_by_name


def enrich_navigation_areatrigger_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把 AreaTrigger 原始数据集补齐为 areatrigger 节点 / 边。

    当前 wow.db 里只给出了 areatrigger 的触发点位；areatriggeractionset
    只有 ID / Flags，无法稳定恢复导航所需的目标地图与目标坐标。
    在补到独立的 destination 数据源前，这里保持空数据集，不参与构图。
    """

    trigger_node_rows = list(dataset_rows_by_name.get("trigger_nodes_raw", []))
    trigger_edge_rows = list(dataset_rows_by_name.get("trigger_edges_raw", []))
    if not trigger_node_rows or not trigger_edge_rows:
        dataset_rows_by_name["trigger_nodes"] = []
        dataset_rows_by_name["trigger_edges"] = []
        return dataset_rows_by_name

    # TODO：等表结构确认后实现完整 enrichment
    dataset_rows_by_name["trigger_nodes"] = []
    dataset_rows_by_name["trigger_edges"] = []
    return dataset_rows_by_name


def enrich_navigation_route_datasets(
    sqlite_conn: sqlite3.Connection,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """把 V1 导航静态骨架补齐为统一运行时节点 / 边。"""

    ui_map_context = build_navigation_uimap_context(sqlite_conn)
    dataset_rows_by_name = enrich_navigation_taxi_datasets(sqlite_conn, dataset_rows_by_name)
    dataset_rows_by_name = enrich_navigation_transport_datasets(sqlite_conn, dataset_rows_by_name)
    dataset_rows_by_name = enrich_navigation_portal_datasets(sqlite_conn, dataset_rows_by_name)
    dataset_rows_by_name = enrich_navigation_areatrigger_datasets(sqlite_conn, dataset_rows_by_name)

    route_node_rows: list[dict[str, Any]] = []
    for raw_anchor_row in dataset_rows_by_name.get("map_anchor_raw", []):
        ui_map_id = int(raw_anchor_row.get("ui_map_id") or 0)
        if ui_map_id <= 0:
            continue
        route_node_rows.append(
            {
                "node_id": f"uimap_{ui_map_id}",
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "ui_map_id": ui_map_id,
                "map_id": int(raw_anchor_row.get("map_id") or 0),
                "node_name": str(raw_anchor_row.get("node_name") or f"UiMap #{ui_map_id}"),
                "walk_cluster_key": build_navigation_walk_cluster_key(ui_map_id, ui_map_context),
                "taxi_node_id": None,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            }
        )

    for taxi_node_row in dataset_rows_by_name.get("nodes", []):
        route_node_rows.append(
            {
                "node_id": str(taxi_node_row.get("taxi_node_key")),
                "node_kind": "taxi",
                "route_source": "taxi",
                "ui_map_id": int(taxi_node_row.get("ui_map_id") or 0),
                "map_id": int(taxi_node_row.get("map_id") or 0),
                "node_name": str(taxi_node_row.get("node_name") or ""),
                "walk_cluster_key": str(taxi_node_row.get("walk_cluster_key") or ""),
                "taxi_node_id": int(taxi_node_row.get("taxi_node_id") or 0),
                "pos_x": float(taxi_node_row.get("pos_x") or 0),
                "pos_y": float(taxi_node_row.get("pos_y") or 0),
                "pos_z": float(taxi_node_row.get("pos_z") or 0),
            }
        )

    for portal_node_row in dataset_rows_by_name.get("portal_nodes", []):
        route_node_rows.append(
            {
                "node_id": str(portal_node_row.get("portal_node_key")),
                "node_kind": "portal",
                "route_source": "portal",
                "ui_map_id": int(portal_node_row.get("ui_map_id") or 0),
                "map_id": int(portal_node_row.get("map_id") or 0),
                "node_name": str(portal_node_row.get("node_name") or ""),
                "walk_cluster_key": str(portal_node_row.get("walk_cluster_key") or ""),
                "taxi_node_id": None,
                "pos_x": float(portal_node_row.get("pos_x") or 0),
                "pos_y": float(portal_node_row.get("pos_y") or 0),
                "pos_z": float(portal_node_row.get("pos_z") or 0),
            }
        )

    for transport_node_row in dataset_rows_by_name.get("transport_nodes", []):
        route_node_rows.append(
            {
                "node_id": str(transport_node_row.get("transport_node_key")),
                "node_kind": "transport",
                "route_source": "waypoint_transport",
                "ui_map_id": int(transport_node_row.get("ui_map_id") or 0),
                "map_id": int(transport_node_row.get("map_id") or 0),
                "node_name": str(transport_node_row.get("node_name") or ""),
                "walk_cluster_key": str(transport_node_row.get("walk_cluster_key") or ""),
                "taxi_node_id": None,
                "pos_x": float(transport_node_row.get("pos_x") or 0),
                "pos_y": float(transport_node_row.get("pos_y") or 0),
                "pos_z": float(transport_node_row.get("pos_z") or 0),
            }
        )

    for trigger_node_row in dataset_rows_by_name.get("trigger_nodes", []):
        route_node_rows.append(
            {
                "node_id": str(trigger_node_row.get("trigger_node_key")),
                "node_kind": "areatrigger",
                "route_source": "areatrigger",
                "ui_map_id": int(trigger_node_row.get("ui_map_id") or 0),
                "map_id": int(trigger_node_row.get("map_id") or 0),
                "node_name": str(trigger_node_row.get("node_name") or ""),
                "walk_cluster_key": str(trigger_node_row.get("walk_cluster_key") or ""),
                "taxi_node_id": None,
                "pos_x": float(trigger_node_row.get("pos_x") or 0),
                "pos_y": float(trigger_node_row.get("pos_y") or 0),
                "pos_z": float(trigger_node_row.get("pos_z") or 0),
            }
        )

    route_edge_rows: list[dict[str, Any]] = []
    for taxi_edge_row in dataset_rows_by_name.get("edges", []):
        route_edge_rows.append(
            {
                "edge_index": int(taxi_edge_row.get("edge_index") or 0),
                "path_id": int(taxi_edge_row.get("path_id") or 0),
                "route_source": "taxi",
                "from_node_id": str(taxi_edge_row.get("from_node_key") or ""),
                "to_node_id": str(taxi_edge_row.get("to_node_key") or ""),
                "from_ui_map_id": int(taxi_edge_row.get("from_ui_map_id") or 0),
                "to_ui_map_id": int(taxi_edge_row.get("to_ui_map_id") or 0),
                "from_taxi_node_id": int(taxi_edge_row.get("from_taxi_node_id") or 0),
                "to_taxi_node_id": int(taxi_edge_row.get("to_taxi_node_id") or 0),
                "step_cost": 1,
                "mode": str(taxi_edge_row.get("mode") or "taxi"),
                "edge_label": str(taxi_edge_row.get("edge_label") or ""),
                "traversed_ui_map_ids": list(taxi_edge_row.get("traversed_ui_map_ids") or []),
                "traversed_ui_map_names": list(taxi_edge_row.get("traversed_ui_map_names") or []),
                "requirements_faction": None,
            }
        )

    for portal_edge_row in dataset_rows_by_name.get("portal_edges", []):
        route_edge_rows.append(
            {
                "edge_index": int(portal_edge_row.get("edge_index") or 0),
                "path_id": 0,
                "route_source": "portal",
                "from_node_id": str(portal_edge_row.get("from_node_id") or ""),
                "to_node_id": str(portal_edge_row.get("to_node_id") or ""),
                "from_ui_map_id": int(portal_edge_row.get("from_ui_map_id") or 0),
                "to_ui_map_id": int(portal_edge_row.get("to_ui_map_id") or 0),
                "from_taxi_node_id": None,
                "to_taxi_node_id": None,
                "step_cost": 1,
                "mode": "public_portal",
                "edge_label": str(portal_edge_row.get("edge_label") or ""),
                "traversed_ui_map_ids": list(portal_edge_row.get("traversed_ui_map_ids") or []),
                "traversed_ui_map_names": list(portal_edge_row.get("traversed_ui_map_names") or []),
                "requirements_faction": str(portal_edge_row.get("requirements_faction") or "") or None,
            }
        )

    for transport_edge_row in dataset_rows_by_name.get("transport_edges", []):
        route_edge_rows.append(
            {
                "edge_index": int(transport_edge_row.get("edge_index") or 0),
                "path_id": int(transport_edge_row.get("waypoint_edge_id") or 0),
                "route_source": "waypoint_transport",
                "from_node_id": str(transport_edge_row.get("from_node_id") or ""),
                "to_node_id": str(transport_edge_row.get("to_node_id") or ""),
                "from_ui_map_id": int(transport_edge_row.get("from_ui_map_id") or 0),
                "to_ui_map_id": int(transport_edge_row.get("to_ui_map_id") or 0),
                "from_taxi_node_id": None,
                "to_taxi_node_id": None,
                "step_cost": 1,
                "mode": "transport",
                "edge_label": str(transport_edge_row.get("edge_label") or ""),
                "traversed_ui_map_ids": list(transport_edge_row.get("traversed_ui_map_ids") or []),
                "traversed_ui_map_names": list(transport_edge_row.get("traversed_ui_map_names") or []),
                "requirements_faction": str(transport_edge_row.get("requirements_faction") or "") or None,
            }
        )

    for trigger_edge_row in dataset_rows_by_name.get("trigger_edges", []):
        route_edge_rows.append(
            {
                "edge_index": int(trigger_edge_row.get("edge_index") or 0),
                "path_id": 0,
                "route_source": "areatrigger",
                "from_node_id": str(trigger_edge_row.get("from_node_id") or ""),
                "to_node_id": str(trigger_edge_row.get("to_node_id") or ""),
                "from_ui_map_id": int(trigger_edge_row.get("from_ui_map_id") or 0),
                "to_ui_map_id": int(trigger_edge_row.get("to_ui_map_id") or 0),
                "from_taxi_node_id": None,
                "to_taxi_node_id": None,
                "step_cost": 1,
                "mode": "areatrigger",
                "edge_label": str(trigger_edge_row.get("edge_label") or ""),
                "traversed_ui_map_ids": list(trigger_edge_row.get("traversed_ui_map_ids") or []),
                "traversed_ui_map_names": list(trigger_edge_row.get("traversed_ui_map_names") or []),
                "requirements_faction": None,
            }
        )

    sorted_route_edge_rows = sorted(
        route_edge_rows,
        key=lambda row: (
            int(row["edge_index"]),
            int(row["path_id"]),
            str(row["route_source"]),
            str(row["from_node_id"]),
            str(row["to_node_id"]),
        ),
    )

    deduped_route_edge_rows: list[dict[str, Any]] = []
    seen_runtime_edge_keys: set[tuple[int, str, str]] = set()
    for route_edge_row in sorted_route_edge_rows:
        runtime_edge_key = (
            int(route_edge_row["path_id"]),
            str(route_edge_row["from_node_id"]),
            str(route_edge_row["to_node_id"]),
        )
        if runtime_edge_key in seen_runtime_edge_keys:
            continue
        seen_runtime_edge_keys.add(runtime_edge_key)
        deduped_route_edge_rows.append(route_edge_row)

    for runtime_edge_index, route_edge_row in enumerate(deduped_route_edge_rows, start=1):
        route_edge_row["edge_index"] = runtime_edge_index

    dataset_rows_by_name["nodes"] = route_node_rows
    dataset_rows_by_name["edges"] = deduped_route_edge_rows
    return dataset_rows_by_name


def apply_supplemental_sources(
    sqlite_conn: sqlite3.Connection,
    contract_document,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
    *,
    questcompletist_dir: Path | None,
) -> dict[str, list[dict[str, Any]]]:
    """按契约配置应用补充数据源。"""

    source_data = contract_document.data.get("source", {})
    supplemental_sources = source_data.get("supplemental_sources", [])
    if not isinstance(supplemental_sources, list) or not supplemental_sources:
        return dataset_rows_by_name

    merged_datasets = {dataset_name: list(rows) for dataset_name, rows in dataset_rows_by_name.items()}
    for source_config in supplemental_sources:
        if not isinstance(source_config, dict):
            continue
        source_type = source_config.get("type")
        if source_type == "questcompletist":
            dataset_name = source_config.get("dataset")
            if not isinstance(dataset_name, str) or dataset_name not in merged_datasets:
                continue
            effective_addon_dir = questcompletist_dir
            if effective_addon_dir is None:
                env_var_name = source_config.get("env_var")
                if isinstance(env_var_name, str) and env_var_name.strip() != "":
                    env_path_text = os.environ.get(env_var_name)
                    if env_path_text:
                        effective_addon_dir = Path(env_path_text)
            if effective_addon_dir is None:
                continue

            merged_datasets[dataset_name] = merge_instance_questlines_with_questcompletist(
                sqlite_conn,
                merged_datasets[dataset_name],
                effective_addon_dir,
            )
        elif source_type == "navigation_taxi_enrichment":
            merged_datasets = enrich_navigation_taxi_datasets(sqlite_conn, merged_datasets)
        elif source_type == "navigation_route_enrichment":
            merged_datasets = enrich_navigation_route_datasets(sqlite_conn, merged_datasets)
        elif source_type == "navigation_ability_enrichment":
            merged_datasets = enrich_navigation_ability_datasets(sqlite_conn, merged_datasets)
    if (
        contract_document.contract.contract_id == "instance_questlines"
        and int(contract_document.contract.schema_version) >= 6
        and "core_links" in merged_datasets
    ):
        schema_v6_datasets = build_instance_questlines_schema_v6_datasets(
            sqlite_conn,
            merged_datasets["core_links"],
        )
        merged_datasets.update(schema_v6_datasets)

    return merged_datasets


def execute_contract_query(
    sqlite_conn: sqlite3.Connection,
    sql_text: str,
) -> tuple[list[dict[str, Any]], list[str]]:
    """执行 SQL，返回结果行与列名。"""

    cursor = sqlite_conn.execute(sql_text)
    column_names = [column[0] for column in (cursor.description or [])]
    rows = [dict(row) for row in cursor.fetchall()]
    return rows, column_names


def execute_contract_queries(
    sqlite_conn: sqlite3.Connection,
    contract_document,
) -> tuple[list[dict[str, Any]], list[str], dict[str, list[dict[str, Any]]] | None, dict[str, list[str]] | None]:
    """执行单契约查询；若定义 datasets，则返回 dataset 结果集映射。"""

    source_data = contract_document.data.get("source", {})
    datasets = source_data.get("datasets")
    if isinstance(datasets, dict) and datasets:
        dataset_rows_by_name: dict[str, list[dict[str, Any]]] = {}
        dataset_columns_by_name: dict[str, list[str]] = {}
        for dataset_name, dataset_config in datasets.items():
            require(isinstance(dataset_name, str) and dataset_name.strip() != "", "source.datasets key must be non-empty string")
            require(isinstance(dataset_config, dict), f"source.datasets.{dataset_name} must be object")
            sql_text = dataset_config.get("sql")
            require(isinstance(sql_text, str) and sql_text.strip() != "", f"source.datasets.{dataset_name}.sql must be non-empty string")
            rows, column_names = execute_contract_query(sqlite_conn, sql_text)
            dataset_rows_by_name[dataset_name] = rows
            dataset_columns_by_name[dataset_name] = column_names
        return [], [], dataset_rows_by_name, dataset_columns_by_name

    rows, column_names = execute_contract_query(sqlite_conn, contract_document.source.sql)
    return rows, column_names, None, None


def ensure_fields_exist(
    *,
    available_fields: list[str],
    required_fields: Iterable[str],
    label: str,
) -> None:
    available_field_set = set(available_fields)
    for field_name in required_fields:
        require(field_name in available_field_set, f"{label}: missing field {field_name}")


def validate_result_rows(
    contract_document,
    rows: list[dict[str, Any]],
    column_names: list[str],
) -> None:
    """按契约对结果集进行最小有效性校验。"""

    ensure_fields_exist(
        available_fields=column_names,
        required_fields=contract_document.validation.required_fields,
        label=f"{contract_document.contract.contract_id} validation.required_fields",
    )
    ensure_fields_exist(
        available_fields=column_names,
        required_fields=contract_document.validation.non_null_fields,
        label=f"{contract_document.contract.contract_id} validation.non_null_fields",
    )

    structure_data = contract_document.structure.data
    root_type = contract_document.structure.root_type
    if root_type in {"map_scalar", "map_array"}:
        ensure_fields_exist(
            available_fields=column_names,
            required_fields=[structure_data["key_field"], structure_data["value_field"]],
            label=f"{contract_document.contract.contract_id} structure",
        )
        comment_field = structure_data.get("comment_field")
        if isinstance(comment_field, str) and comment_field:
            ensure_fields_exist(
                available_fields=column_names,
                required_fields=[comment_field],
                label=f"{contract_document.contract.contract_id} structure",
            )
    elif root_type == "document":
        for block in structure_data.get("document_blocks", []):
            if block.get("name") == "metadata":
                continue
            ensure_fields_exist(
                available_fields=column_names,
                required_fields=[str(item) for item in block.get("required_fields", [])],
                label=f"{contract_document.contract.contract_id} document block {block.get('name')}",
            )
            key_field = block.get("key_field")
            if isinstance(key_field, str):
                ensure_fields_exist(
                    available_fields=column_names,
                    required_fields=[key_field],
                    label=f"{contract_document.contract.contract_id} document block {block.get('name')}",
                )
            value_field = block.get("value_field")
            if isinstance(value_field, str):
                ensure_fields_exist(
                    available_fields=column_names,
                    required_fields=[value_field],
                    label=f"{contract_document.contract.contract_id} document block {block.get('name')}",
                )
            value_template = block.get("value_template")
            if isinstance(value_template, dict):
                ensure_fields_exist(
                    available_fields=column_names,
                    required_fields=[str(item) for item in value_template.values()],
                    label=f"{contract_document.contract.contract_id} document block {block.get('name')}",
                )
            comment_template = block.get("comment_template")
            if isinstance(comment_template, dict):
                ensure_fields_exist(
                    available_fields=column_names,
                    required_fields=[str(item) for item in comment_template.values()],
                    label=f"{contract_document.contract.contract_id} document block {block.get('name')}",
                )
    else:
        raise ValueError(f"unsupported root_type: {root_type}")

    validate_rows_against_contract_validation(contract_document, rows)


def validate_rows_against_contract_validation(
    contract_document,
    rows: list[dict[str, Any]],
) -> None:
    """按 validation.non_null_fields / unique_keys 校验结果行。"""

    for row in rows:
        for field_name in contract_document.validation.non_null_fields:
            require(row.get(field_name) not in (None, ""), f"{contract_document.contract.contract_id}: non-null field {field_name} is empty")

    for unique_group in contract_document.validation.unique_keys:
        if not isinstance(unique_group, list):
            continue
        seen_markers: set[tuple[Any, ...]] = set()
        for row in rows:
            marker = tuple(row.get(field_name) for field_name in unique_group)
            require(marker not in seen_markers, f"{contract_document.contract.contract_id}: duplicate key group {unique_group}")
            seen_markers.add(marker)


def collect_contract_validation_fields(contract_document) -> set[str]:
    """收集 validation 中涉及的字段名。"""

    field_names: set[str] = set()
    field_names.update(str(item) for item in contract_document.validation.required_fields)
    field_names.update(str(item) for item in contract_document.validation.non_null_fields)
    for unique_group in contract_document.validation.unique_keys:
        if not isinstance(unique_group, list):
            continue
        field_names.update(str(item) for item in unique_group)
    return field_names


def validate_dataset_rows_against_contract_validation(
    contract_document,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
    dataset_columns_by_name: dict[str, list[str]],
) -> None:
    """在 datasets 导出路径中补齐 validation 行级约束。"""

    validation_fields = collect_contract_validation_fields(contract_document)
    if not validation_fields:
        return

    matched_dataset_names = [
        dataset_name
        for dataset_name, column_names in dataset_columns_by_name.items()
        if validation_fields.issubset(set(column_names))
    ]
    require(
        len(matched_dataset_names) > 0,
        f"{contract_document.contract.contract_id}: no dataset contains validation fields {sorted(validation_fields)}",
    )

    for dataset_name in matched_dataset_names:
        validate_rows_against_contract_validation(contract_document, dataset_rows_by_name.get(dataset_name, []))


def validate_document_datasets(
    contract_document,
    dataset_rows_by_name: dict[str, list[dict[str, Any]]],
    dataset_columns_by_name: dict[str, list[str]],
) -> None:
    """按 document block 校验命名 datasets。"""

    structure_data = contract_document.structure.data
    require(contract_document.structure.root_type == "document", "datasets only support document root_type")
    for block in structure_data.get("document_blocks", []):
        if block.get("name") == "metadata":
            continue
        dataset_name = block.get("dataset")
        require(isinstance(dataset_name, str) and dataset_name in dataset_rows_by_name, f"document block {block.get('name')} references missing dataset")
        block_columns = dataset_columns_by_name[dataset_name]
        ensure_fields_exist(
            available_fields=block_columns,
            required_fields=[str(item) for item in block.get("required_fields", [])],
            label=f"{contract_document.contract.contract_id} dataset {dataset_name} required_fields",
        )
        key_field = block.get("key_field")
        if isinstance(key_field, str):
            ensure_fields_exist(
                available_fields=block_columns,
                required_fields=[key_field],
                label=f"{contract_document.contract.contract_id} dataset {dataset_name} key_field",
            )
        value_field = block.get("value_field")
        if isinstance(value_field, str):
            ensure_fields_exist(
                available_fields=block_columns,
                required_fields=[value_field],
                label=f"{contract_document.contract.contract_id} dataset {dataset_name} value_field",
            )
        value_template = block.get("value_template")
        if isinstance(value_template, dict):
            ensure_fields_exist(
                available_fields=block_columns,
                required_fields=[str(item) for item in value_template.values()],
                label=f"{contract_document.contract.contract_id} dataset {dataset_name} value_template",
            )
        comment_template = block.get("comment_template")
        if isinstance(comment_template, dict):
            ensure_fields_exist(
                available_fields=block_columns,
                required_fields=[str(item) for item in comment_template.values()],
                label=f"{contract_document.contract.contract_id} dataset {dataset_name} comment_template",
            )


def resolve_target_selector(selector: str, contract_dir: Path | None = None) -> str:
    """将命令行选择器解析为 contract_id。"""

    selector_text = selector.strip()
    require(selector_text != "", "target cannot be empty")

    contract_path = (contract_dir or default_contract_dir()) / f"{selector_text}.json"
    if contract_path.exists():
        return selector_text

    contracts_root = contract_dir or default_contract_dir()
    for json_path in sorted(contracts_root.glob("*.json"), key=lambda item: item.name.lower()):
        contract_document = load_contract(json_path.stem, contracts_root)
        output_file_name = Path(contract_document.output.lua_file).name
        if selector_text.lower() == output_file_name.lower():
            return contract_document.contract.contract_id

    valid_values = ", ".join(sorted(path.stem for path in contracts_root.glob("*.json")))
    raise ValueError(f"unknown contract selector: {selector_text} (available: {valid_values})")


def active_contract_ids(contract_dir: Path | None = None) -> list[str]:
    """返回 active 契约 ID 列表。"""

    return [document.contract.contract_id for document in iter_active_contracts(contract_dir)]


def export_targets(
    *,
    target_ids: Iterable[str],
    db_path: Path,
    data_dir: Path,
    contract_dir: Path | None = None,
    snapshot_dir: Path | None = None,
    generated_by: str = "WoWPlugin/scripts/export/toolbox_db_export.py",
    generated_at: datetime | None = None,
    questcompletist_dir: Path | None = None,
) -> list[Path]:
    """执行一组契约导出，并返回已写入文件路径。"""

    if not db_path.exists():
        raise FileNotFoundError(f"database file does not exist: {db_path}")

    contracts_root = contract_dir or default_contract_dir()
    snapshots_root = snapshot_dir or default_snapshot_root()
    data_dir.mkdir(parents=True, exist_ok=True)

    sqlite_conn = sqlite3.connect(str(db_path))
    sqlite_conn.row_factory = sqlite3.Row

    written_files: list[Path] = []
    try:
        for target_id in target_ids:
            contract_document = load_contract(target_id, contracts_root)
            require(
                contract_document.contract.status in {"active", "deprecated"},
                f"{target_id}: contract status {contract_document.contract.status} is not exportable",
            )

            rows, column_names, dataset_rows_by_name, dataset_columns_by_name = execute_contract_queries(sqlite_conn, contract_document)
            if dataset_rows_by_name is not None and dataset_columns_by_name is not None:
                dataset_rows_by_name = apply_supplemental_sources(
                    sqlite_conn,
                    contract_document,
                    dataset_rows_by_name,
                    questcompletist_dir=questcompletist_dir,
                )
                dataset_columns_by_name = {
                    dataset_name: sorted(
                        {
                            *dataset_columns_by_name.get(dataset_name, []),
                            *{
                                key_name
                                for row in dataset_rows_by_name.get(dataset_name, [])
                                for key_name in row.keys()
                            },
                        }
                    )
                    for dataset_name in dataset_rows_by_name
                }
                validate_document_datasets(contract_document, dataset_rows_by_name, dataset_columns_by_name)
                validate_dataset_rows_against_contract_validation(contract_document, dataset_rows_by_name, dataset_columns_by_name)
            else:
                validate_result_rows(contract_document, rows, column_names)

            snapshot_path = write_contract_snapshot(
                contract_document,
                source_path=contract_document.path,
                snapshots_root=snapshots_root,
                timestamp=generated_at,
            )
            output_path = data_dir / Path(contract_document.output.lua_file).name
            output_text = render_contract_lua(
                contract_document,
                rows=rows,
                dataset_rows_by_name=dataset_rows_by_name,
                contract_file=to_contract_logical_path(contract_document.path),
                contract_snapshot=to_workspace_relative(snapshot_path),
                generated_at=generated_at,
                generated_by=generated_by,
            )
            output_path.write_text(output_text, encoding="utf-8", newline="\n")
            print(f"[OK] {target_id} -> {output_path} (rows={len(rows)})")
            written_files.append(output_path)
    finally:
        sqlite_conn.close()

    return written_files


def add_common_args(parser: argparse.ArgumentParser) -> None:
    """为入口脚本添加通用参数。"""

    parser.add_argument(
        "--db",
        type=Path,
        default=default_db_path(),
        help="SQLite database path (default: WoWTools/data/sqlite/wow.db)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=default_data_dir(),
        help="Output Data directory (default: WoWPlugin/Toolbox/Data)",
    )
    parser.add_argument(
        "--contract-dir",
        type=Path,
        default=default_contract_dir(),
        help="Contract directory (default: WoWPlugin/DataContracts)",
    )
    parser.add_argument(
        "--snapshot-dir",
        type=Path,
        default=default_snapshot_root(),
        help="Snapshot output directory (default: WoWTools/outputs/toolbox/contract_snapshots)",
    )
    parser.add_argument(
        "--questcompletist-dir",
        type=Path,
        default=None,
        help="QuestCompletist addon directory for supplemental questline import (optional)",
    )
