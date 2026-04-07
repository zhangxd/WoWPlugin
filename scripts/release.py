#!/usr/bin/env python3
"""
Toolbox 插件发布脚本（跨平台）

功能：
  1. 从 Toolbox.toc 读取版本号
  2. 打包 Toolbox 文件夹为 zip
  3. 可选部署到游戏 AddOns 目录

用法：
  python scripts/release.py                    # 打包并部署
  python scripts/release.py --skip-deploy      # 仅打包
  python scripts/release.py --skip-zip         # 仅部署
  python scripts/release.py --addon-path <路径> # 指定 AddOns 目录
  python scripts/release.py --show-search      # 显示路径查找过程
"""

import argparse
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path
from typing import Optional


def find_repo_root() -> Path:
    """查找仓库根目录（scripts 的父目录）"""
    script_dir = Path(__file__).parent.resolve()
    return script_dir.parent


def read_version_from_toc(toc_path: Path) -> str:
    """从 TOC 文件读取版本号"""
    if not toc_path.exists():
        raise FileNotFoundError(f"未找到 TOC 文件: {toc_path}")

    content = toc_path.read_text(encoding='utf-8')
    match = re.search(r'^## Version:\s*(.+)\s*$', content, re.MULTILINE)
    if not match:
        raise ValueError("无法从 Toolbox.toc 解析 ## Version:")

    version = match.group(1).strip()
    if not version:
        raise ValueError("Toolbox.toc 中版本号为空")

    return version


def is_addons_directory(path: str) -> bool:
    """检查路径是否为有效的 AddOns 目录"""
    if not path:
        return False
    p = Path(path)
    return p.exists() and p.is_dir() and p.name.lower() == 'addons'


def find_retail_addons_windows(show_debug: bool = False) -> Optional[Path]:
    """Windows 平台查找正式服 AddOns 目录"""
    import winreg

    # 1. 环境变量
    env_path = os.environ.get('WOW_RETAIL_ADDONS')
    if show_debug:
        print(f"[AddOns] 环境变量 WOW_RETAIL_ADDONS: {env_path or '(未设置)'}")
    if env_path and is_addons_directory(env_path):
        if show_debug:
            print("[AddOns] 命中: 环境变量")
        return Path(env_path).resolve()

    # 2. 注册表
    reg_keys = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
        (winreg.HKEY_CURRENT_USER, r"Software\Blizzard Entertainment\World of Warcraft"),
    ]

    for hkey, subkey in reg_keys:
        try:
            with winreg.OpenKey(hkey, subkey) as key:
                try:
                    install_path, _ = winreg.QueryValueEx(key, "InstallPath")
                except FileNotFoundError:
                    try:
                        install_path, _ = winreg.QueryValueEx(key, "GamePath")
                    except FileNotFoundError:
                        install_path = None

                if show_debug:
                    print(f"[AddOns] {subkey} -> {install_path or '(无 InstallPath/GamePath)'}")

                if install_path:
                    install_path = install_path.rstrip('\\')
                    candidates = []
                    if install_path.endswith('_retail_'):
                        candidates.append(Path(install_path) / "Interface" / "AddOns")
                    else:
                        candidates.append(Path(install_path) / "_retail_" / "Interface" / "AddOns")

                    for candidate in candidates:
                        if show_debug:
                            print(f"[AddOns]   尝试: {candidate}")
                        if is_addons_directory(str(candidate)):
                            if show_debug:
                                print("[AddOns] 命中: 注册表")
                            return candidate.resolve()
        except OSError:
            if show_debug:
                print(f"[AddOns] 读取失败: {subkey}")

    # 3. Program Files
    program_files = [
        os.environ.get('ProgramFiles(x86)'),
        os.environ.get('ProgramFiles'),
    ]
    for pf in program_files:
        if pf:
            candidate = Path(pf) / "World of Warcraft" / "_retail_" / "Interface" / "AddOns"
            if show_debug:
                print(f"[AddOns] 尝试: {candidate}")
            if is_addons_directory(str(candidate)):
                if show_debug:
                    print("[AddOns] 命中: Program Files")
                return candidate.resolve()

    # 4. 其它盘符
    for drive in ['D:\\', 'E:\\', 'F:\\']:
        if not Path(drive).exists():
            continue
        for rel in [
            "World of Warcraft\\_retail_\\Interface\\AddOns",
            "Games\\World of Warcraft\\_retail_\\Interface\\AddOns",
            "Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns",
            "Program Files\\World of Warcraft\\_retail_\\Interface\\AddOns",
        ]:
            candidate = Path(drive) / rel
            if show_debug:
                print(f"[AddOns] 尝试: {candidate}")
            if is_addons_directory(str(candidate)):
                if show_debug:
                    print("[AddOns] 命中: 扩展盘符")
                return candidate.resolve()

    return None


def find_retail_addons_mac(show_debug: bool = False) -> Optional[Path]:
    """macOS 平台查找正式服 AddOns 目录"""
    # 1. 环境变量
    env_path = os.environ.get('WOW_RETAIL_ADDONS')
    if show_debug:
        print(f"[AddOns] 环境变量 WOW_RETAIL_ADDONS: {env_path or '(未设置)'}")
    if env_path and is_addons_directory(env_path):
        if show_debug:
            print("[AddOns] 命中: 环境变量")
        return Path(env_path).resolve()

    # 2. 常见路径
    home = Path.home()
    candidates = [
        home / "Applications" / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
        Path("/Applications/World of Warcraft/_retail_/Interface/AddOns"),
    ]

    for candidate in candidates:
        if show_debug:
            print(f"[AddOns] 尝试: {candidate}")
        if is_addons_directory(str(candidate)):
            if show_debug:
                print("[AddOns] 命中: macOS 常见路径")
            return candidate.resolve()

    return None


def find_retail_addons_linux(show_debug: bool = False) -> Optional[Path]:
    """Linux 平台查找正式服 AddOns 目录"""
    # 1. 环境变量
    env_path = os.environ.get('WOW_RETAIL_ADDONS')
    if show_debug:
        print(f"[AddOns] 环境变量 WOW_RETAIL_ADDONS: {env_path or '(未设置)'}")
    if env_path and is_addons_directory(env_path):
        if show_debug:
            print("[AddOns] 命中: 环境变量")
        return Path(env_path).resolve()

    # 2. Wine/Proton 常见路径
    home = Path.home()
    candidates = [
        home / ".wine" / "drive_c" / "Program Files (x86)" / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
        home / ".local" / "share" / "Steam" / "steamapps" / "compatdata" / "1922160" / "pfx" / "drive_c" / "Program Files (x86)" / "World of Warcraft" / "_retail_" / "Interface" / "AddOns",
    ]

    for candidate in candidates:
        if show_debug:
            print(f"[AddOns] 尝试: {candidate}")
        if is_addons_directory(str(candidate)):
            if show_debug:
                print("[AddOns] 命中: Linux Wine/Proton")
            return candidate.resolve()

    return None


def find_retail_addons(show_debug: bool = False) -> Optional[Path]:
    """跨平台查找正式服 AddOns 目录"""
    if sys.platform == 'win32':
        return find_retail_addons_windows(show_debug)
    elif sys.platform == 'darwin':
        return find_retail_addons_mac(show_debug)
    else:
        return find_retail_addons_linux(show_debug)


def create_zip(toolbox_dir: Path, output_dir: Path, version: str, no_clean: bool = False) -> Path:
    """创建 zip 包"""
    output_dir.mkdir(parents=True, exist_ok=True)

    zip_name = f"Toolbox-{version}.zip"
    zip_path = output_dir / zip_name

    if not no_clean and zip_path.exists():
        zip_path.unlink()

    print(f"打包: {toolbox_dir} -> {zip_path}")

    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for file_path in toolbox_dir.rglob('*'):
            if file_path.is_file():
                arcname = Path('Toolbox') / file_path.relative_to(toolbox_dir)
                zf.write(file_path, arcname)

    print(f"完成: {zip_path}")
    print(f"版本: {version}（来自 Toolbox.toc）")

    return zip_path


def deploy_to_addons(toolbox_dir: Path, addons_root: Path):
    """部署到游戏 AddOns 目录"""
    dest = addons_root / "Toolbox"
    print(f"部署到: {dest}")

    if dest.exists():
        shutil.rmtree(dest)

    shutil.copytree(toolbox_dir, dest)
    print("完成: 已复制 Toolbox 到游戏 AddOns 目录。")


def main():
    parser = argparse.ArgumentParser(
        description='Toolbox 插件发布脚本',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python scripts/release.py
  python scripts/release.py --skip-deploy
  python scripts/release.py --addon-path "<路径>/_retail_/Interface/AddOns"
  python scripts/release.py --show-search
        """
    )

    parser.add_argument('--output-dir', type=str, default='',
                        help='zip 输出目录（默认：仓库下 dist）')
    parser.add_argument('--no-clean', action='store_true',
                        help='不删除已存在的同版本 zip')
    parser.add_argument('--addon-path', type=str, default='',
                        help='手动指定 AddOns 目录')
    parser.add_argument('--skip-zip', action='store_true',
                        help='仅复制，不打 zip')
    parser.add_argument('--skip-deploy', action='store_true',
                        help='仅生成 zip，不复制到游戏目录')
    parser.add_argument('--show-search', action='store_true',
                        help='显示 AddOns 路径查找过程')

    args = parser.parse_args()

    # 查找仓库根目录
    repo_root = find_repo_root()
    toc_path = repo_root / "Toolbox" / "Toolbox.toc"
    toolbox_dir = repo_root / "Toolbox"

    if not toc_path.exists():
        print(f"错误: 未找到 TOC 文件: {toc_path}", file=sys.stderr)
        sys.exit(1)

    if not toolbox_dir.exists():
        print(f"错误: 未找到插件目录: {toolbox_dir}", file=sys.stderr)
        sys.exit(1)

    # 读取版本号
    try:
        version = read_version_from_toc(toc_path)
    except (FileNotFoundError, ValueError) as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)

    # 确定输出目录
    output_dir = Path(args.output_dir) if args.output_dir else repo_root / "dist"

    # 是否部署
    do_deploy = not args.skip_deploy

    print(f"发布: zip={not args.skip_zip}  复制到游戏={do_deploy}")

    # 打包
    if not args.skip_zip:
        create_zip(toolbox_dir, output_dir, version, args.no_clean)
    else:
        print("已跳过 zip（--skip-zip）。")

    # 部署
    if do_deploy:
        target_addons = None

        if args.addon_path:
            if not is_addons_directory(args.addon_path):
                print(f"错误: --addon-path 不是有效的 AddOns 目录: {args.addon_path}", file=sys.stderr)
                sys.exit(1)
            target_addons = Path(args.addon_path).resolve()
        else:
            target_addons = find_retail_addons(args.show_search)

        if not target_addons:
            print("""
警告: 未找到正式服 Interface/AddOns，已跳过复制（zip 若未 --skip-zip 则仍已生成）。
请任选其一：
  1) 设置环境变量 WOW_RETAIL_ADDONS = <你的路径>/_retail_/Interface/AddOns
  2) 运行: python scripts/release.py --addon-path "<你的路径>/_retail_/Interface/AddOns"
  3) 若只想打 zip 不需要复制: 加 --skip-deploy
            """, file=sys.stderr)
            if args.skip_zip:
                sys.exit(1)
        else:
            deploy_to_addons(toolbox_dir, target_addons)

    # 仅诊断路径
    if args.show_search and not do_deploy:
        print("--- AddOns 路径探测（仅诊断，未复制）---")
        diag = find_retail_addons(show_debug=True)
        if diag:
            print(f"找到: {diag}")
        else:
            print("未找到；请用 --addon-path 或设置环境变量 WOW_RETAIL_ADDONS。")


if __name__ == '__main__':
    main()
