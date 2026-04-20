#!/usr/bin/env python3
"""Toolbox 数据契约模型与基础校验。"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


CONTRACT_ID_PATTERN = re.compile(r"^[a-z0-9_]+$")
REQUIRED_TOP_LEVEL_SECTIONS = (
    "contract",
    "output",
    "source",
    "structure",
    "validation",
    "versioning",
)
ALLOWED_STATUS_VALUES = {"draft", "active", "deprecated", "retired"}


@dataclass(frozen=True)
class ContractMeta:
    contract_id: str
    schema_version: int
    summary: str
    source_of_truth: str
    status: str


@dataclass(frozen=True)
class OutputConfig:
    lua_file: str
    lua_table: str
    write_header: bool


@dataclass(frozen=True)
class SourceConfig:
    database: str
    tables: list[str]
    sql: str
    query: dict[str, Any]


@dataclass(frozen=True)
class StructureConfig:
    root_type: str
    lua_shape: str
    data: dict[str, Any]


@dataclass(frozen=True)
class ValidationConfig:
    required_fields: list[str]
    unique_keys: list[Any]
    non_null_fields: list[str]
    sort_rules: list[dict[str, Any]]
    data: dict[str, Any]


@dataclass(frozen=True)
class VersioningConfig:
    current_schema_version: int
    change_log: list[dict[str, Any]]


@dataclass(frozen=True)
class ContractDocument:
    path: Path
    contract: ContractMeta
    output: OutputConfig
    source: SourceConfig
    structure: StructureConfig
    validation: ValidationConfig
    versioning: VersioningConfig
    data: dict[str, Any]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def require_object(value: Any, label: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{label} must be object")
    return value


def require_string(value: Any, label: str) -> str:
    require(isinstance(value, str) and value.strip() != "", f"{label} must be non-empty string")
    return value


def require_positive_int(value: Any, label: str) -> int:
    require(isinstance(value, int) and value > 0, f"{label} must be positive integer")
    return value


def require_list(value: Any, label: str) -> list[Any]:
    require(isinstance(value, list), f"{label} must be array")
    return value


def load_contract_document(contract_path: Path) -> ContractDocument:
    raw_text = contract_path.read_text(encoding="utf-8")
    try:
        raw_data = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {contract_path}: {exc}") from exc

    require(isinstance(raw_data, dict), "contract file root must be object")
    for section_name in REQUIRED_TOP_LEVEL_SECTIONS:
        require(section_name in raw_data, f"missing top-level section: {section_name}")

    contract_block = require_object(raw_data["contract"], "contract")
    output_block = require_object(raw_data["output"], "output")
    source_block = require_object(raw_data["source"], "source")
    structure_block = require_object(raw_data["structure"], "structure")
    validation_block = require_object(raw_data["validation"], "validation")
    versioning_block = require_object(raw_data["versioning"], "versioning")

    contract_id = require_string(contract_block.get("contract_id"), "contract.contract_id")
    require(CONTRACT_ID_PATTERN.fullmatch(contract_id) is not None, "contract.contract_id has invalid format")
    require(contract_path.name == f"{contract_id}.json", "contract_id must match contract filename")

    schema_version = require_positive_int(contract_block.get("schema_version"), "contract.schema_version")
    summary = require_string(contract_block.get("summary"), "contract.summary")
    source_of_truth = require_string(contract_block.get("source_of_truth"), "contract.source_of_truth")
    require(source_of_truth == "WoWPlugin", "contract.source_of_truth must be WoWPlugin")
    status = require_string(contract_block.get("status"), "contract.status")
    require(status in ALLOWED_STATUS_VALUES, "contract.status has invalid value")

    lua_file = require_string(output_block.get("lua_file"), "output.lua_file")
    require(lua_file.startswith("Toolbox/Data/"), "output.lua_file must live under Toolbox/Data/")
    lua_table = require_string(output_block.get("lua_table"), "output.lua_table")
    require("." in lua_table, "output.lua_table must be dotted Lua table path")
    write_header = output_block.get("write_header")
    require(isinstance(write_header, bool), "output.write_header must be boolean")

    database = require_string(source_block.get("database"), "source.database")
    tables = require_list(source_block.get("tables"), "source.tables")
    require(all(isinstance(item, str) and item.strip() != "" for item in tables), "source.tables must contain non-empty strings")
    sql_text = require_string(source_block.get("sql"), "source.sql")
    query_block = require_object(source_block.get("query"), "source.query")

    root_type = require_string(structure_block.get("root_type"), "structure.root_type")
    lua_shape = require_string(structure_block.get("lua_shape"), "structure.lua_shape")

    required_fields = require_list(validation_block.get("required_fields"), "validation.required_fields")
    unique_keys = require_list(validation_block.get("unique_keys"), "validation.unique_keys")
    non_null_fields = require_list(validation_block.get("non_null_fields"), "validation.non_null_fields")
    sort_rules = require_list(validation_block.get("sort_rules"), "validation.sort_rules")

    current_schema_version = require_positive_int(
        versioning_block.get("current_schema_version"),
        "versioning.current_schema_version",
    )
    require(
        current_schema_version == schema_version,
        "versioning.current_schema_version must match contract.schema_version",
    )
    change_log = require_list(versioning_block.get("change_log"), "versioning.change_log")
    require(len(change_log) > 0, "versioning.change_log must not be empty")
    latest_change = require_object(change_log[-1], "versioning.change_log[-1]")
    require_positive_int(latest_change.get("schema_version"), "versioning.change_log[-1].schema_version")
    require(
        latest_change["schema_version"] == schema_version,
        "versioning.change_log latest schema_version must match contract.schema_version",
    )

    return ContractDocument(
        path=contract_path,
        contract=ContractMeta(
            contract_id=contract_id,
            schema_version=schema_version,
            summary=summary,
            source_of_truth=source_of_truth,
            status=status,
        ),
        output=OutputConfig(
            lua_file=lua_file,
            lua_table=lua_table,
            write_header=write_header,
        ),
        source=SourceConfig(
            database=database,
            tables=[str(item) for item in tables],
            sql=sql_text,
            query=query_block,
        ),
        structure=StructureConfig(
            root_type=root_type,
            lua_shape=lua_shape,
            data=structure_block,
        ),
        validation=ValidationConfig(
            required_fields=[str(item) for item in required_fields],
            unique_keys=unique_keys,
            non_null_fields=[str(item) for item in non_null_fields],
            sort_rules=[dict(item) for item in sort_rules],
            data=validation_block,
        ),
        versioning=VersioningConfig(
            current_schema_version=current_schema_version,
            change_log=[dict(item) for item in change_log],
        ),
        data=raw_data,
    )
