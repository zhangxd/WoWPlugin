#!/usr/bin/env python3
"""[Internal] 生成任务线运行时预览 Lua（仅调试预览）。

生产任务导出入口已统一为：
`scripts/export/export_quest_achievement_merged_from_db.py`
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class QuestPreview:
    """轻量任务节点。"""

    quest_id: int
    quest_name: str
    quest_line_ids: list[int]
    ui_map_ids: list[int]
    faction_tags: list[str]
    faction_conditions: list[str]
    race_mask_values: list[int]
    content_expansion_id: int | None


@dataclass
class QuestLinePreview:
    """轻量任务线节点。"""

    quest_line_id: int
    quest_line_name: str
    quest_ids: list[int]
    ui_map_ids: list[int]
    primary_ui_map_id: int | None
    primary_ui_map_name: str
    primary_map_count: int
    primary_map_share: float
    faction_tags: list[str]
    race_mask_values: list[int]
    content_expansion_id: int | None


@dataclass
class RuntimePreviewModel:
    """运行时预览模型。"""

    generated_at: str
    quests: dict[int, QuestPreview]
    quest_lines: dict[int, QuestLinePreview]


def script_root() -> Path:
    """返回脚本目录。"""

    return Path(__file__).resolve().parent


def wowplugin_root() -> Path:
    """返回 WoWPlugin 根目录。"""

    return script_root().parents[1]


def wowtools_root() -> Path:
    """返回 WoWTools 根目录。"""

    return wowplugin_root().parent / "WoWTools"


def default_csv_path() -> Path:
    """返回默认 CSV 路径。"""

    return wowtools_root() / "outputs" / "toolbox" / "quest_expansion_map.csv"


def default_output_path() -> Path:
    """返回默认预览 Lua 路径。"""

    return wowtools_root() / "outputs" / "toolbox" / "InstanceQuestlines.runtime_preview.lua"


def open_csv_reader(csv_path: Path) -> tuple[csv.DictReader, object]:
    """按兼容编码打开 CSV。"""

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


def collect_positive_ints(values: list[str]) -> list[int]:
    """收集正整数并保持顺序去重。"""

    seen_values: set[int] = set()
    collected_values: list[int] = []
    for value_text in values:
        if value_text in ("", None):
            continue
        normalized_value = int(value_text)
        if normalized_value <= 0 or normalized_value in seen_values:
            continue
        seen_values.add(normalized_value)
        collected_values.append(normalized_value)
    return collected_values


def collect_non_empty_strings(values: list[str]) -> list[str]:
    """收集非空字符串并保持顺序去重。"""

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


def build_runtime_preview_model(csv_rows: list[dict[str, str]]) -> RuntimePreviewModel:
    """从 CSV 行构建轻量运行时模型。"""

    quest_aggregate: dict[int, dict[str, object]] = {}
    quest_line_aggregate: dict[int, dict[str, object]] = {}

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

        quest_line_ids = collect_positive_ints(quest_line_id_text.split("="))
        quest_line_names = collect_non_empty_strings((row.get("QuestLineNames") or "").split("="))

        quest_state = quest_aggregate.setdefault(
            quest_id,
            {
                "name": quest_name,
                "quest_line_ids": [],
                "ui_map_ids": [],
                "faction_tags": [],
                "faction_conditions": [],
                "race_mask_values": [],
                "content_expansion_id": content_expansion_id,
            },
        )
        quest_state["quest_line_ids"] = collect_positive_ints(
            [str(value) for value in quest_state["quest_line_ids"]] + [str(value) for value in quest_line_ids]
        )
        if ui_map_id > 0:
            quest_state["ui_map_ids"] = collect_positive_ints(
                [str(value) for value in quest_state["ui_map_ids"]] + [str(ui_map_id)]
            )
        quest_state["faction_tags"] = collect_non_empty_strings(quest_state["faction_tags"] + [faction_tag])
        quest_state["faction_conditions"] = collect_non_empty_strings(quest_state["faction_conditions"] + [faction_condition])
        if race_mask_value is not None:
            quest_state["race_mask_values"] = collect_positive_ints(
                [str(value) for value in quest_state["race_mask_values"]] + [str(race_mask_value)]
            )
        if quest_state["content_expansion_id"] is None and content_expansion_id is not None:
            quest_state["content_expansion_id"] = content_expansion_id

        for index, quest_line_id in enumerate(quest_line_ids):
            quest_line_name = quest_line_names[index] if index < len(quest_line_names) else ""
            line_state = quest_line_aggregate.setdefault(
                quest_line_id,
                {
                    "name": quest_line_name,
                    "quest_ids": [],
                    "ui_map_counter": Counter(),
                    "ui_map_name_by_id": {},
                    "faction_tags": [],
                    "race_mask_values": [],
                    "content_expansion_id": content_expansion_id,
                },
            )
            line_state["quest_ids"] = collect_positive_ints(
                [str(value) for value in line_state["quest_ids"]] + [str(quest_id)]
            )
            if ui_map_id > 0:
                line_state["ui_map_counter"][ui_map_id] += 1
                if ui_map_name:
                    line_state["ui_map_name_by_id"].setdefault(ui_map_id, ui_map_name)
            line_state["faction_tags"] = collect_non_empty_strings(line_state["faction_tags"] + [faction_tag])
            if race_mask_value is not None:
                line_state["race_mask_values"] = collect_positive_ints(
                    [str(value) for value in line_state["race_mask_values"]] + [str(race_mask_value)]
                )
            if line_state["content_expansion_id"] is None and content_expansion_id is not None:
                line_state["content_expansion_id"] = content_expansion_id

    quests = {
        quest_id: QuestPreview(
            quest_id=quest_id,
            quest_name=quest_state["name"],
            quest_line_ids=quest_state["quest_line_ids"],
            ui_map_ids=quest_state["ui_map_ids"],
            faction_tags=quest_state["faction_tags"],
            faction_conditions=quest_state["faction_conditions"],
            race_mask_values=quest_state["race_mask_values"],
            content_expansion_id=quest_state["content_expansion_id"],
        )
        for quest_id, quest_state in sorted(quest_aggregate.items())
    }

    quest_lines: dict[int, QuestLinePreview] = {}
    for quest_line_id, line_state in sorted(quest_line_aggregate.items()):
        ui_map_counter = line_state["ui_map_counter"]
        ui_map_ids = [ui_map_id for ui_map_id, _ in ui_map_counter.most_common()]
        if ui_map_counter:
            primary_ui_map_id, primary_map_count = ui_map_counter.most_common(1)[0]
            total_map_rows = sum(ui_map_counter.values())
            primary_map_share = primary_map_count / total_map_rows
            primary_ui_map_name = line_state["ui_map_name_by_id"].get(primary_ui_map_id, "")
        else:
            primary_ui_map_id = None
            primary_map_count = 0
            primary_map_share = 0.0
            primary_ui_map_name = ""
        quest_lines[quest_line_id] = QuestLinePreview(
            quest_line_id=quest_line_id,
            quest_line_name=line_state["name"],
            quest_ids=line_state["quest_ids"],
            ui_map_ids=ui_map_ids,
            primary_ui_map_id=primary_ui_map_id,
            primary_ui_map_name=primary_ui_map_name,
            primary_map_count=primary_map_count,
            primary_map_share=primary_map_share,
            faction_tags=line_state["faction_tags"],
            race_mask_values=line_state["race_mask_values"],
            content_expansion_id=line_state["content_expansion_id"],
        )

    return RuntimePreviewModel(
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        quests=quests,
        quest_lines=quest_lines,
    )


def format_int_array(values: list[int]) -> str:
    """格式化 Lua 整数数组。"""

    if not values:
        return "{}"
    return "{ " + ", ".join(str(value) for value in values) + " }"


def format_string_array(values: list[str]) -> str:
    """格式化 Lua 字符串数组。"""

    if not values:
        return "{}"
    return "{ " + ", ".join(f'"{value}"' for value in values) + " }"


def format_optional_number(value: int | None) -> str:
    """格式化可选数字。"""

    if value is None:
        return "nil"
    return str(value)


def write_runtime_preview_lua(output_path: Path, model: RuntimePreviewModel) -> None:
    """写入轻量运行时预览 Lua。"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_lines = [
        "--[[",
        "  轻量任务线运行时预览（临时文件）。",
        "  来源：quest_expansion_map.csv。",
        "  说明：任务名、任务线名、地图名只作为注释保留；运行时展示名应通过 API 获取。",
        "  说明：已过滤 QuestLineID 为空的任务行。",
        "]]",
        "",
        "Toolbox.Data = Toolbox.Data or {}",
        "",
        "Toolbox.Data.InstanceQuestlinesRuntimePreview = {",
        '  schemaVersion = "runtime_preview_v1",',
        '  sourceMode = "csv_preview",',
        f'  generatedAt = "{model.generated_at}",',
        "",
        "  quests = {",
    ]

    for quest_id, quest_entry in model.quests.items():
        comment_name = quest_entry.quest_name or "未命名任务"
        output_lines.extend(
            [
                f"    [{quest_id}] = {{ -- {comment_name}",
                f"      ID = {quest_id},",
                f"      QuestLineIDs = {format_int_array(quest_entry.quest_line_ids)},",
                f"      UiMapIDs = {format_int_array(quest_entry.ui_map_ids)},",
                f"      FactionTags = {format_string_array(quest_entry.faction_tags)},",
                f"      FactionConditions = {format_string_array(quest_entry.faction_conditions)},",
                f"      RaceMaskValues = {format_int_array(quest_entry.race_mask_values)},",
                f"      ContentExpansionID = {format_optional_number(quest_entry.content_expansion_id)},",
                "    },",
            ]
        )

    output_lines.extend(
        [
            "  },",
            "",
            "  questLines = {",
        ]
    )

    for quest_line_id, quest_line_entry in model.quest_lines.items():
        comment_name = quest_line_entry.quest_line_name or "未命名任务线"
        output_lines.extend(
            [
                f"    [{quest_line_id}] = {{ -- {comment_name}",
                f"      ID = {quest_line_id},",
                f"      QuestIDs = {format_int_array(quest_line_entry.quest_ids)},",
                f"      UiMapIDs = {format_int_array(quest_line_entry.ui_map_ids)},",
                f"      PrimaryUiMapID = {format_optional_number(quest_line_entry.primary_ui_map_id)}, -- {quest_line_entry.primary_ui_map_name or '无地图'}",
                f"      PrimaryMapCount = {quest_line_entry.primary_map_count},",
                f"      PrimaryMapShare = {quest_line_entry.primary_map_share:.4f},",
                f"      FactionTags = {format_string_array(quest_line_entry.faction_tags)},",
                f"      RaceMaskValues = {format_int_array(quest_line_entry.race_mask_values)},",
                f"      ContentExpansionID = {format_optional_number(quest_line_entry.content_expansion_id)},",
                "    },",
            ]
        )

    output_lines.extend(
        [
            "  },",
            "}",
            "",
        ]
    )
    output_path.write_text("\n".join(output_lines), encoding="utf-8")


def build_argument_parser() -> argparse.ArgumentParser:
    """构建命令行参数。"""

    parser = argparse.ArgumentParser(description="从 quest_expansion_map.csv 生成轻量任务线运行时预览 Lua。")
    parser.add_argument("--csv", type=Path, default=default_csv_path(), help="quest_expansion_map.csv path")
    parser.add_argument("--output", type=Path, default=default_output_path(), help="preview lua output path")
    return parser


def main() -> int:
    """命令行入口。"""

    print(
        "[INTERNAL] 该脚本仅用于预览调试；生产任务导出请使用 "
        "scripts/export/export_quest_achievement_merged_from_db.py",
        file=sys.stderr,
    )

    parser = build_argument_parser()
    args = parser.parse_args()

    reader, csv_file = open_csv_reader(args.csv)
    try:
        csv_rows = list(reader)
    finally:
        csv_file.close()

    model = build_runtime_preview_model(csv_rows)
    write_runtime_preview_lua(args.output, model)
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
