#!/usr/bin/env python3
"""Toolbox 数据契约 IO 与快照工具。"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

try:
    from .contract_model import ContractDocument, load_contract_document
except ImportError:  # pragma: no cover - script mode fallback
    from contract_model import ContractDocument, load_contract_document


def default_wowplugin_root() -> Path:
    """返回 WoWPlugin 根目录。"""

    return Path(__file__).resolve().parents[2]


def default_wowtools_root() -> Path:
    """返回 WoWTools 根目录。"""

    return default_wowplugin_root().parent / "WoWTools"


def default_contract_dir() -> Path:
    """返回默认的 WoWPlugin 契约目录。"""

    return default_wowplugin_root() / "DataContracts"


def default_snapshot_root() -> Path:
    """返回默认快照根目录。"""

    return default_wowtools_root() / "outputs" / "toolbox" / "contract_snapshots"


def resolve_contract_path(contract_id: str, contract_dir: Path | None = None) -> Path:
    contracts_root = contract_dir or default_contract_dir()
    return contracts_root / f"{contract_id}.json"


def load_contract(contract_id: str, contract_dir: Path | None = None) -> ContractDocument:
    contract_path = resolve_contract_path(contract_id, contract_dir)
    if not contract_path.exists():
        raise FileNotFoundError(f"contract file does not exist: {contract_path}")
    return load_contract_document(contract_path)


def iter_active_contracts(contract_dir: Path | None = None) -> Iterable[ContractDocument]:
    contracts_root = contract_dir or default_contract_dir()
    if not contracts_root.exists():
        return []

    documents: list[ContractDocument] = []
    for contract_path in sorted(contracts_root.glob("*.json"), key=lambda item: item.name.lower()):
        document = load_contract_document(contract_path)
        if document.contract.status == "active":
            documents.append(document)
    return documents


def format_snapshot_timestamp(timestamp: datetime | None = None) -> str:
    effective_timestamp = timestamp or datetime.now(timezone.utc)
    if effective_timestamp.tzinfo is None:
        effective_timestamp = effective_timestamp.replace(tzinfo=timezone.utc)
    else:
        effective_timestamp = effective_timestamp.astimezone(timezone.utc)
    return effective_timestamp.strftime("%Y%m%dT%H%M%SZ")


def write_contract_snapshot(
    contract_document: ContractDocument,
    *,
    source_path: Path,
    snapshots_root: Path | None = None,
    timestamp: datetime | None = None,
) -> Path:
    snapshots_dir = snapshots_root or default_snapshot_root()
    timestamp_text = format_snapshot_timestamp(timestamp)
    contract_id = contract_document.contract.contract_id
    schema_version = contract_document.contract.schema_version
    output_dir = snapshots_dir / contract_id
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot_path = output_dir / f"{contract_id}__schema_v{schema_version}__{timestamp_text}.json"
    snapshot_path.write_text(source_path.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    return snapshot_path
