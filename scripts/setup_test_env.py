#!/usr/bin/env python3
"""
Setup test dependencies for Toolbox (cross-platform).

Targets:
- Lua runtime
- LuaRocks
- busted test runner

Usage:
  python scripts/setup_test_env.py --check
  python scripts/setup_test_env.py --apply
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

WIN_LUA_PACKAGE = "DEVCOM.Lua"
WIN_MINGW_PACKAGE = "BrechtSanders.WinLibs.MCF.UCRT"


def run(
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    print(f"[setup] $ {' '.join(command)}")
    result = subprocess.run(
        command,
        cwd=str(cwd or ROOT),
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if check and result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}")
    return result


def exists(command: str, env: dict[str, str] | None = None) -> bool:
    path = (env or os.environ).get("PATH", "")
    return shutil.which(command, path=path) is not None


def resolve_command(command: str, env: dict[str, str] | None = None) -> str | None:
    path = (env or os.environ).get("PATH", "")
    return shutil.which(command, path=path)


def prepend_path(env: dict[str, str], path: Path) -> None:
    current = env.get("PATH", "")
    env["PATH"] = f"{path}{os.pathsep}{current}"


def find_winget_package_dir(prefix: str) -> Path | None:
    local_appdata = os.environ.get("LOCALAPPDATA", "")
    if not local_appdata:
        return None
    package_root = Path(local_appdata) / "Microsoft" / "WinGet" / "Packages"
    if not package_root.exists():
        return None
    matches = sorted([p for p in package_root.iterdir() if p.is_dir() and p.name.startswith(prefix)])
    return matches[-1] if matches else None


def find_windows_executable(executable_name: str) -> Path | None:
    local_appdata = os.environ.get("LOCALAPPDATA", "")
    if not local_appdata:
        return None
    package_root = Path(local_appdata) / "Microsoft" / "WinGet" / "Packages"
    if not package_root.exists():
        return None
    matches = list(package_root.rglob(executable_name))
    matches = [p for p in matches if p.is_file()]
    return sorted(matches)[-1] if matches else None


def ensure_windows_toolchain(env: dict[str, str], apply: bool) -> None:
    if not exists("winget"):
        raise RuntimeError("winget is required on Windows but was not found in PATH.")

    if apply:
        run(
            [
                "winget",
                "install",
                "--id",
                WIN_LUA_PACKAGE,
                "--source",
                "winget",
                "--scope",
                "user",
                "--accept-package-agreements",
                "--accept-source-agreements",
            ]
        )
        run(
            [
                "winget",
                "install",
                "--id",
                WIN_MINGW_PACKAGE,
                "--source",
                "winget",
                "--scope",
                "user",
                "--accept-package-agreements",
                "--accept-source-agreements",
            ]
        )

    lua_dir = find_winget_package_dir("DEVCOM.Lua_")
    if lua_dir:
        prepend_path(env, lua_dir / "bin")

    mingw_dir = find_winget_package_dir("BrechtSanders.WinLibs.MCF.UCRT_")
    if mingw_dir:
        prepend_path(env, mingw_dir / "mingw64" / "bin")

    appdata = Path(os.environ.get("APPDATA", "")) / "luarocks" / "bin"
    if appdata.exists():
        prepend_path(env, appdata)

    # 兜底：若包目录前缀未命中，按可执行文件递归定位。
    for executable_name in ["lua.exe", "luarocks.exe", "x86_64-w64-mingw32-gcc.exe"]:
        executable_path = find_windows_executable(executable_name)
        if executable_path:
            prepend_path(env, executable_path.parent)


def linux_install_commands() -> list[list[str]]:
    if exists("apt-get"):
        return [["sudo", "apt-get", "update"], ["sudo", "apt-get", "install", "-y", "lua5.4", "luarocks", "build-essential"]]
    if exists("dnf"):
        return [["sudo", "dnf", "install", "-y", "lua", "luarocks", "gcc", "gcc-c++", "make"]]
    if exists("pacman"):
        return [["sudo", "pacman", "-S", "--noconfirm", "lua", "luarocks", "base-devel"]]
    return []


def ensure_unix_toolchain(env: dict[str, str], apply: bool) -> None:
    system = platform.system().lower()
    if system == "darwin":
        if apply:
            if not exists("brew"):
                raise RuntimeError("Homebrew is required on macOS for automatic install.")
            run(["brew", "install", "lua"])
    elif system == "linux":
        commands = linux_install_commands()
        if apply and commands:
            for command in commands:
                run(command)
        elif apply and not commands:
            raise RuntimeError("No supported Linux package manager detected (apt/dnf/pacman).")

    # LuaRocks user bin (unix)
    home = Path.home()
    for candidate in [home / ".luarocks" / "bin", home / ".local" / "bin"]:
        if candidate.exists():
            prepend_path(env, candidate)


def ensure_busted(env: dict[str, str], apply: bool) -> None:
    if exists("busted", env):
        return
    if not exists("luarocks", env):
        raise RuntimeError("luarocks not found; cannot install busted.")
    if not apply:
        raise RuntimeError("busted is not installed. Re-run with --apply.")
    run(["luarocks", "install", "busted"], env=env)


def verify(env: dict[str, str]) -> None:
    lua_cmd = resolve_command("lua", env)
    luarocks_cmd = resolve_command("luarocks", env)
    busted_cmd = resolve_command("busted", env)

    if not lua_cmd:
        raise RuntimeError("lua not found in PATH after setup.")
    if not luarocks_cmd:
        raise RuntimeError("luarocks not found in PATH after setup.")
    if not busted_cmd:
        raise RuntimeError("busted not found in PATH after setup.")

    run([lua_cmd, "-v"], env=env, check=False)
    run([luarocks_cmd, "--version"], env=env, check=False)
    run([busted_cmd, "--version"], env=env, check=False)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Setup test dependencies for Toolbox.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Only verify dependencies, do not install.")
    mode.add_argument("--apply", action="store_true", help="Install missing dependencies.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    env = os.environ.copy()
    system = platform.system().lower()

    try:
        if system == "windows":
            ensure_windows_toolchain(env, apply=args.apply)
        elif system in {"linux", "darwin"}:
            ensure_unix_toolchain(env, apply=args.apply)
        else:
            raise RuntimeError(f"Unsupported platform: {platform.system()}")

        ensure_busted(env, apply=args.apply)
        verify(env)
    except RuntimeError as exc:
        print(f"[setup] error: {exc}", file=sys.stderr)
        return 1

    print("[setup] test environment is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
