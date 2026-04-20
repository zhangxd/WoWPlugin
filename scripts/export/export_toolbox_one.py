#!/usr/bin/env python3
"""单独导出 Toolbox 指定数据库静态表。"""

from __future__ import annotations

import argparse
import sys

from toolbox_db_export import add_common_args, export_targets, resolve_target_selector


def main() -> int:
    parser = argparse.ArgumentParser(
        description="从 WoWTools/data/sqlite/wow.db 单独导出一个 WoWPlugin/Toolbox/Data 静态表。"
    )
    parser.add_argument(
        "target",
        help="导出目标（支持 contract_id，或兼容输出文件名，例如 instance_map_ids / InstanceMapIDs.lua）",
    )
    add_common_args(parser)
    args = parser.parse_args()
    target_id = resolve_target_selector(args.target, args.contract_dir)

    export_targets(
        target_ids=[target_id],
        db_path=args.db,
        data_dir=args.data_dir,
        contract_dir=args.contract_dir,
        snapshot_dir=args.snapshot_dir,
        generated_by="WoWPlugin/scripts/export/export_toolbox_one.py",
        questcompletist_dir=args.questcompletist_dir,
    )
    print("[DONE] 单项契约导出完成。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
