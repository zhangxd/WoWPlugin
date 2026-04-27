#!/usr/bin/env python3
"""Toolbox 契约驱动 Lua 写出器。"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping

try:
    from .contract_model import ContractDocument
except ImportError:  # pragma: no cover - script mode fallback
    from contract_model import ContractDocument


def format_generated_at(timestamp: datetime | None = None) -> str:
    effective_timestamp = timestamp or datetime.now(timezone.utc)
    if effective_timestamp.tzinfo is None:
        effective_timestamp = effective_timestamp.replace(tzinfo=timezone.utc)
    else:
        effective_timestamp = effective_timestamp.astimezone(timezone.utc)
    return effective_timestamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_path_text(path_value: Path | str) -> str:
    if isinstance(path_value, Path):
        return path_value.as_posix()
    return Path(path_value).as_posix()


def to_comment_text(raw_value: Any) -> str:
    if raw_value is None:
        return "Unknown"
    return str(raw_value).replace("\r", " ").replace("\n", " ").strip() or "Unknown"


def escape_lua_string(raw_value: Any) -> str:
    text_value = "" if raw_value is None else str(raw_value)
    return text_value.replace("\\", "\\\\").replace('"', '\\"')


def render_lua_literal(raw_value: Any) -> str:
    """将 Python 值渲染为 Lua 字面量。"""

    if raw_value is None:
        return "nil"
    if isinstance(raw_value, bool):
        return "true" if raw_value else "false"
    if isinstance(raw_value, (int, float)):
        return str(raw_value)
    return f'"{escape_lua_string(raw_value)}"'


def build_contract_header(
    contract_document: ContractDocument,
    *,
    contract_file: Path,
    contract_snapshot: Path,
    generated_at: datetime | None,
    generated_by: str,
) -> str:
    generated_at_text = format_generated_at(generated_at)
    lines = [
        "--[[",
        f"@contract_id {contract_document.contract.contract_id}",
        f"@schema_version {contract_document.contract.schema_version}",
        f"@contract_file {normalize_path_text(contract_file)}",
        f"@contract_snapshot {normalize_path_text(contract_snapshot)}",
        f"@generated_at {generated_at_text}",
        f"@generated_by {generated_by}",
        f"@data_source {contract_document.source.database}",
        f"@summary {contract_document.contract.summary}",
        "@overwrite_notice 此文件由工具生成，手改会被覆盖",
        "]]",
    ]
    return "\n".join(lines)


def parse_contract_header(header_text: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for raw_line in header_text.splitlines():
        stripped_line = raw_line.strip()
        if not stripped_line.startswith("@"):
            continue
        key_text, _, value_text = stripped_line.partition(" ")
        parsed[key_text[1:]] = value_text.strip()
    return parsed


def sorted_rows(rows: Iterable[Mapping[str, Any]], field_names: list[str]) -> list[Mapping[str, Any]]:
    if not field_names:
        return list(rows)

    def make_sort_value(row: Mapping[str, Any]) -> tuple[Any, ...]:
        values: list[Any] = []
        for field_name in field_names:
            values.append(row.get(field_name))
        return tuple(values)

    return sorted(rows, key=make_sort_value)


def render_map_scalar(contract_document: ContractDocument, rows: list[Mapping[str, Any]]) -> list[str]:
    structure = contract_document.structure.data
    key_field = structure["key_field"]
    value_field = structure["value_field"]
    comment_field = structure.get("comment_field")
    sort_fields = [str(rule["field"]) for rule in contract_document.validation.sort_rules]

    lines = [
        "Toolbox.Data = Toolbox.Data or {}",
        "",
        f"{contract_document.output.lua_table} = {{",
    ]
    for row in sorted_rows(rows, sort_fields):
        key_value = row[key_field]
        value_value = row[value_field]
        line_text = f"  [{key_value}] = {render_lua_literal(value_value)},"
        if comment_field:
            line_text += f" -- {to_comment_text(row.get(comment_field))}"
        lines.append(line_text)
    lines.extend(
        [
            "}",
            "",
        ]
    )
    return lines


def render_map_array(contract_document: ContractDocument, rows: list[Mapping[str, Any]]) -> list[str]:
    structure = contract_document.structure.data
    key_field = structure["key_field"]
    value_field = structure["value_field"]
    comment_field = structure.get("comment_field")
    sort_fields = [str(rule["field"]) for rule in contract_document.validation.sort_rules]

    grouped_values: dict[Any, dict[str, Any]] = {}
    for row in sorted_rows(rows, sort_fields):
        key_value = row[key_field]
        bucket = grouped_values.get(key_value)
        if bucket is None:
            bucket = {
                "comment": row.get(comment_field) if comment_field else None,
                "values": [],
                "seen": set(),
            }
            grouped_values[key_value] = bucket
        if row[value_field] in bucket["seen"]:
            continue
        bucket["seen"].add(row[value_field])
        bucket["values"].append(row[value_field])

    lines = [
        "Toolbox.Data = Toolbox.Data or {}",
        "",
        f"{contract_document.output.lua_table} = {{",
    ]
    for key_value in sorted(grouped_values):
        bucket = grouped_values[key_value]
        values_text = ", ".join(render_lua_literal(item) for item in sorted(bucket["values"]))
        line_text = f"  [{key_value}] = {{ {values_text} }},"
        if comment_field:
            line_text += f" -- {to_comment_text(bucket['comment'])}"
        lines.append(line_text)
    lines.extend(
        [
            "}",
            "",
        ]
    )
    return lines


def dedupe_rows(rows: list[Mapping[str, Any]], field_names: list[str]) -> list[Mapping[str, Any]]:
    if not field_names:
        return rows
    seen: set[tuple[Any, ...]] = set()
    deduped_rows: list[Mapping[str, Any]] = []
    for row in rows:
        marker = tuple(row.get(field_name) for field_name in field_names)
        if marker in seen:
            continue
        seen.add(marker)
        deduped_rows.append(row)
    return deduped_rows


def render_object_value_from_template(row: Mapping[str, Any], value_template: Mapping[str, Any]) -> str:
    value_parts: list[str] = []
    for output_key, source_field in value_template.items():
        source_value = row[source_field]
        if isinstance(source_value, list):
            rendered_items: list[str] = []
            for item in source_value:
                rendered_items.append(render_lua_literal(item))
            rendered_value = "{ " + ", ".join(rendered_items) + " }"
        else:
            rendered_value = render_lua_literal(source_value)
        value_parts.append(f"{output_key} = {rendered_value}")
    return "{ " + ", ".join(value_parts) + " }"


def render_comment_from_template(row: Mapping[str, Any], comment_template: Mapping[str, Any]) -> str:
    comment_parts: list[str] = []
    for output_key, source_field in comment_template.items():
        source_value = row[source_field]
        if isinstance(source_value, str):
            rendered_value = f'"{escape_lua_string(source_value)}"'
        else:
            rendered_value = str(source_value)
        comment_parts.append(f"{output_key} = {rendered_value}")
    return ", ".join(comment_parts)


def render_lua_table_key(key_value: Any) -> str:
    """渲染 Lua 表键，字符串键必须加引号以避免被当作全局变量。"""

    return f"[{render_lua_literal(key_value)}]"


def render_document(
    contract_document: ContractDocument,
    rows: list[Mapping[str, Any]],
    generated_at_text: str,
    dataset_rows_by_name: Mapping[str, list[Mapping[str, Any]]] | None = None,
) -> list[str]:
    structure = contract_document.structure.data
    document_blocks = structure.get("document_blocks", [])

    lines = [
        "Toolbox.Data = Toolbox.Data or {}",
        "",
        f"{contract_document.output.lua_table} = {{",
    ]

    for block_index, block in enumerate(document_blocks):
        block_name = block["name"]
        if block_name == "metadata":
            metadata = dict(block.get("metadata", {}))
            metadata["generatedAt"] = generated_at_text if metadata.get("generatedAt") == "@generated_at" else metadata.get("generatedAt")
            lines.append(f"  schemaVersion = {metadata['schemaVersion']},")
            lines.append(f'  sourceMode = "{escape_lua_string(metadata["sourceMode"])}",')
            lines.append(f'  generatedAt = "{escape_lua_string(metadata["generatedAt"])}",')
            if block_index != len(document_blocks) - 1:
                lines.append("")
            continue

        block_type = block.get("block_type")
        dataset_name = block.get("dataset")
        block_rows = (
            list(dataset_rows_by_name.get(dataset_name, []))
            if isinstance(dataset_name, str) and dataset_rows_by_name is not None
            else rows
        )
        required_fields = [str(item) for item in block.get("required_fields", [])]
        if required_fields:
            block_rows = [
                row for row in block_rows
                if all(row.get(field_name) not in (None, "") for field_name in required_fields)
            ]
        block_rows = sorted_rows(block_rows, [str(item) for item in block.get("sort_by", [])])
        block_rows = dedupe_rows(block_rows, [str(item) for item in block.get("dedupe_by", [])])

        lines.append(f"  {block_name} = {{")
        if block_type == "map_object":
            key_field = block["key_field"]
            value_template = dict(block["value_template"])
            comment_template = dict(block.get("comment_template", {}))
            for row in block_rows:
                key_value = row[key_field]
                rendered_object = render_object_value_from_template(row, value_template)
                line_text = f"    {render_lua_table_key(key_value)} = {rendered_object},"
                if comment_template:
                    line_text += f" -- {render_comment_from_template(row, comment_template)}"
                lines.append(line_text)
        elif block_type == "map_array_grouped":
            key_field = block["key_field"]
            value_field = block["value_field"]
            grouped: dict[Any, list[Any]] = defaultdict(list)
            seen_pairs: set[tuple[Any, Any]] = set()
            for row in block_rows:
                key_value = row[key_field]
                value_value = row[value_field]
                marker = (key_value, value_value)
                if marker in seen_pairs:
                    continue
                seen_pairs.add(marker)
                grouped[key_value].append(value_value)
            for key_value in sorted(grouped):
                values_text = ", ".join(str(item) for item in grouped[key_value])
                lines.append(f"    [{key_value}] = {{ {values_text} }},")
        elif block_type == "map_array_objects_grouped":
            key_field = block["key_field"]
            value_template = dict(block["value_template"])
            grouped_objects: dict[Any, list[str]] = defaultdict(list)
            for row in block_rows:
                key_value = row[key_field]
                grouped_objects[key_value].append(render_object_value_from_template(row, value_template))
            for key_value in sorted(grouped_objects):
                lines.append(f"    [{key_value}] = {{")
                for rendered_object in grouped_objects[key_value]:
                    lines.append(f"      {rendered_object},")
                lines.append("    },")
        else:
            raise ValueError(f"unsupported document block type: {block_type}")
        lines.append("  },")
        if block_index != len(document_blocks) - 1:
            lines.append("")

    lines.extend(
        [
            "}",
            "",
        ]
    )
    return lines


def render_contract_lua(
    contract_document: ContractDocument,
    *,
    rows: list[Mapping[str, Any]],
    dataset_rows_by_name: Mapping[str, list[Mapping[str, Any]]] | None = None,
    contract_file: Path,
    contract_snapshot: Path,
    generated_at: datetime | None,
    generated_by: str,
) -> str:
    generated_at_text = format_generated_at(generated_at)
    header_text = build_contract_header(
        contract_document,
        contract_file=contract_file,
        contract_snapshot=contract_snapshot,
        generated_at=generated_at,
        generated_by=generated_by,
    )

    root_type = contract_document.structure.root_type
    if root_type == "map_scalar":
        body_lines = render_map_scalar(contract_document, rows)
    elif root_type == "map_array":
        body_lines = render_map_array(contract_document, rows)
    elif root_type == "document":
        body_lines = render_document(contract_document, rows, generated_at_text, dataset_rows_by_name)
    else:
        raise ValueError(f"unsupported root_type: {root_type}")

    return "\n".join([header_text, "", *body_lines])
