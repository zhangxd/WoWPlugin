#!/usr/bin/env python3
"""一键导出 Toolbox 全部数据库静态表。"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from toolbox_db_export import active_contract_ids, add_common_args, export_targets


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
    print("[INFO] active contract contains instance_questlines，改走正式导出脚本。")
    result = subprocess.run(command, check=False)
    return int(result.returncode)


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

    contract_target_ids = [target_id for target_id in target_ids if target_id != "instance_questlines"]
    written_files: list[Path] = []
    if contract_target_ids:
        written_files = export_targets(
            target_ids=contract_target_ids,
            db_path=args.db,
            data_dir=args.data_dir,
            contract_dir=args.contract_dir,
            snapshot_dir=args.snapshot_dir,
            generated_by="WoWPlugin/scripts/export/export_toolbox_all.py",
            questcompletist_dir=args.questcompletist_dir,
        )

    if "instance_questlines" in target_ids:
        instance_export_code = run_instance_questlines_export(args.db, args.data_dir)
        if instance_export_code != 0:
            return instance_export_code
        written_files = written_files + [args.data_dir / "InstanceQuestlines.lua"]

    print(f"[DONE] 共覆盖 {len(written_files)} 个文件。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
