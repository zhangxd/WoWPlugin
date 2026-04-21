#!/usr/bin/env python3
"""单独导出 Toolbox 指定数据库静态表。"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from toolbox_db_export import add_common_args, export_targets, resolve_target_selector


def run_instance_questlines_export(db_path: Path, data_dir: Path) -> int:
    """走 instance_questlines 正式导出入口。"""

    script_path = Path(__file__).resolve().with_name("export_quest_achievement_merged_from_db.py")
    output_lua_path = data_dir / "InstanceQuestlines.lua"
    command = [
        sys.executable,
        str(script_path),
        "--db",
        str(db_path),
        "--output-lua",
        str(output_lua_path),
        "--skip-csv",
    ]
    print("[INFO] target=instance_questlines，切换为正式导出脚本：export_quest_achievement_merged_from_db.py")
    result = subprocess.run(command, check=False)
    return int(result.returncode)


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
    if target_id == "instance_questlines":
        return run_instance_questlines_export(args.db, args.data_dir)

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
