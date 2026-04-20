#!/usr/bin/env python3
"""一键导出 Toolbox 全部数据库静态表。"""

from __future__ import annotations

import argparse
import sys

from toolbox_db_export import active_contract_ids, add_common_args, export_targets


def main() -> int:
    parser = argparse.ArgumentParser(
        description="从 WoWTools/data/sqlite/wow.db 一键导出 WoWPlugin/DataContracts 中全部 active 契约。"
    )
    add_common_args(parser)
    args = parser.parse_args()

    target_ids = active_contract_ids(args.contract_dir)
    if not target_ids:
        print("[DONE] 未发现 active 契约（0 个覆盖）。")
        return 0

    written_files = export_targets(
        target_ids=target_ids,
        db_path=args.db,
        data_dir=args.data_dir,
        contract_dir=args.contract_dir,
        snapshot_dir=args.snapshot_dir,
        generated_by="WoWPlugin/scripts/export/export_toolbox_all.py",
        questcompletist_dir=args.questcompletist_dir,
    )

    print(f"[DONE] 共覆盖 {len(written_files)} 个文件。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
