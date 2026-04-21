#!/usr/bin/env python3
"""Toolbox Data 导出工具（从 data/sqlite/wow.db 按契约生成 Lua 静态表）。"""

from __future__ import annotations

import argparse
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
        dataset_name = source_config.get("dataset")
        if not isinstance(dataset_name, str) or dataset_name not in merged_datasets:
            continue
        if source_type != "questcompletist":
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
