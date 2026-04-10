from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_step(label: str, command: list[str], env_patch: dict[str, str] | None = None) -> int:
    env = os.environ.copy()
    if env_patch:
        env.update(env_patch)

    print(f"[tests] {label}: {' '.join(command)}")
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Toolbox static + logic tests.")
    parser.add_argument("--ci", action="store_true", help="CI mode: keep deterministic output.")
    parser.add_argument(
        "--update-golden",
        action="store_true",
        help="Allow logic tests to rewrite golden files.",
    )
    args = parser.parse_args()

    contract_ret = run_step(
        "validate_data_contracts",
        [sys.executable, "tests/validate_data_contracts.py"],
    )
    if contract_ret != 0:
        return contract_ret

    static_ret = run_step(
        "validate_settings_subcategories",
        [sys.executable, "tests/validate_settings_subcategories.py"],
    )
    if static_ret != 0:
        return static_ret

    busted_cmd = shutil.which("busted")
    if not busted_cmd:
      appdata = os.environ.get("APPDATA", "")
      fallback_cmd = Path(appdata) / "luarocks" / "bin" / "busted.cmd"
      if fallback_cmd.exists():
          busted_cmd = str(fallback_cmd)
    if not busted_cmd:
        print(
            "[tests] error: `busted` not found in PATH. Install busted first to run logic tests.",
            file=sys.stderr,
        )
        return 1

    env_patch: dict[str, str] = {}
    if args.update_golden:
        env_patch["UPDATE_GOLDEN"] = "1"
    if args.ci:
        env_patch["CI"] = "1"

    logic_ret = run_step(
        "logic_tests",
        [busted_cmd, "tests/logic/spec"],
        env_patch=env_patch,
    )
    return logic_ret


if __name__ == "__main__":
    raise SystemExit(main())
