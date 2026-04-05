<#
.SYNOPSIS
  将 Toolbox 打成 zip，并可选择复制到正式服 Interface\AddOns。

.DESCRIPTION
  从 Toolbox\Toolbox.toc 读取 ## Version:，打包整个 Toolbox 文件夹（zip 根目录为 Toolbox\）。
  默认会尝试复制到正式服 Interface\AddOns（找到则覆盖）；仅打 zip 请加 -SkipDeploy。

  查找 AddOns 路径顺序：
    1) 环境变量 WOW_RETAIL_ADDONS（完整路径到 ...\Interface\AddOns）
    2) 注册表 InstallPath + _retail_\Interface\AddOns
    3) Program Files 常见路径

.PARAMETER OutputDir
  zip 输出目录（默认：仓库下 dist）。

.PARAMETER NoClean
  不删除已存在的同版本 zip。

.PARAMETER AddonPath
  手动指定 ...\Interface\AddOns，优先于自动查找。

.PARAMETER SkipZip
  仅复制，不打 zip（本地快速迭代）。

.PARAMETER SkipDeploy
  仅生成 zip，不复制到游戏目录（发 Curse 等分发包时用）。

.PARAMETER ShowAddonSearch
  打印查找 AddOns 时检查了哪些路径（与 Compress-Archive 无关，便于排查「为什么找不到」）。

.EXAMPLE
  .\scripts\Release.ps1
  .\scripts\Release.ps1 -ShowAddonSearch -SkipDeploy
  .\scripts\Release.ps1 -SkipDeploy
  .\scripts\Release.ps1 -AddonPath "<你的路径>\_retail_\Interface\AddOns"
  .\scripts\Release.ps1 -SkipZip
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "",
    [switch]$NoClean,
    [string]$AddonPath = "",
    [switch]$SkipZip,
    [switch]$SkipDeploy,
    [switch]$ShowAddonSearch
)

$script:AddonSearchDebug = $ShowAddonSearch

$ErrorActionPreference = "Stop"

# 仓库根目录 = scripts 的上一级
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$TocPath = Join-Path $RepoRoot "Toolbox\Toolbox.toc"
$ToolboxDir = Join-Path $RepoRoot "Toolbox"

if (-not (Test-Path -LiteralPath $TocPath)) {
    Write-Error "未找到 TOC 文件: $TocPath"
}
if (-not (Test-Path -LiteralPath $ToolboxDir)) {
    Write-Error "未找到插件目录: $ToolboxDir"
}

$content = Get-Content -LiteralPath $TocPath -Raw
if ($content -notmatch '(?m)^## Version:\s*(.+)\s*$') {
    Write-Error "无法从 Toolbox.toc 解析 ## Version:"
}
$Version = $Matches[1].Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Error "Toolbox.toc 中版本号为空"
}

# --- 解析正式服 ...\Interface\AddOns ---
function Test-IsAddonsDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath $Path) -and ($Path -match '(?i)[\\/]AddOns$')
}

function Get-RetailAddonsDirectory {
    # 1) 环境变量：AddOns 完整路径
    $envPath = [Environment]::GetEnvironmentVariable("WOW_RETAIL_ADDONS", "User")
    if (-not $envPath) { $envPath = [Environment]::GetEnvironmentVariable("WOW_RETAIL_ADDONS", "Machine") }
    if (-not $envPath) { $envPath = $env:WOW_RETAIL_ADDONS }
    if ($script:AddonSearchDebug) {
        Write-Host "[AddOns] 环境变量 WOW_RETAIL_ADDONS: $(if ($envPath) { $envPath } else { '(未设置)' })" -ForegroundColor DarkCyan
    }
    if ($envPath -and (Test-IsAddonsDirectory $envPath)) {
        if ($script:AddonSearchDebug) { Write-Host "[AddOns] 命中: 环境变量" -ForegroundColor DarkGreen }
        return (Resolve-Path -LiteralPath $envPath).Path
    }
    if ($envPath -and $script:AddonSearchDebug) {
        Write-Host "[AddOns] 环境变量已设置但目录无效: $envPath" -ForegroundColor DarkYellow
    }

    # 2) 注册表：InstallPath 可能为 ...\World of Warcraft 或已指向 ...\_retail_
    foreach ($regBase in @(
            "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"
            "HKCU:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"
            "HKCU:\Software\Blizzard Entertainment\World of Warcraft"
        )) {
        try {
            $props = Get-ItemProperty -LiteralPath $regBase -ErrorAction SilentlyContinue
            if (-not $props) {
                if ($script:AddonSearchDebug) { Write-Host "[AddOns] 注册表无键: $regBase" -ForegroundColor DarkGray }
                continue
            }
            $root = $props.InstallPath
            if (-not $root) { $root = $props.GamePath }
            if ($script:AddonSearchDebug) {
                Write-Host "[AddOns] $regBase -> $(if ($root) { $root } else { '(无 InstallPath/GamePath)' })" -ForegroundColor DarkCyan
            }
            if (-not $root) { continue }
            $root = $root.TrimEnd('\')
            $candidatesFromReg = @()
            if ($root -match '_retail_$') {
                $candidatesFromReg += (Join-Path $root "Interface\AddOns")
            } else {
                $candidatesFromReg += (Join-Path $root "_retail_\Interface\AddOns")
            }
            foreach ($addOns in $candidatesFromReg) {
                if ($script:AddonSearchDebug) { Write-Host "[AddOns]   尝试: $addOns" -ForegroundColor DarkGray }
                if (Test-IsAddonsDirectory $addOns) {
                    if ($script:AddonSearchDebug) { Write-Host "[AddOns] 命中: 注册表" -ForegroundColor DarkGreen }
                    return (Resolve-Path -LiteralPath $addOns).Path
                }
            }
        } catch {
            if ($script:AddonSearchDebug) { Write-Host "[AddOns] 读取失败: $regBase $_" -ForegroundColor DarkYellow }
        }
    }

    # 3) 系统盘常见路径
    $candidates = @(
        ${env:ProgramFiles(x86)} + "\World of Warcraft\_retail_\Interface\AddOns"
        $env:ProgramFiles + "\World of Warcraft\_retail_\Interface\AddOns"
    )
    foreach ($c in $candidates) {
        if ($script:AddonSearchDebug) { Write-Host "[AddOns] 尝试: $c" -ForegroundColor DarkGray }
        if (Test-IsAddonsDirectory $c) {
            if ($script:AddonSearchDebug) { Write-Host "[AddOns] 命中: Program Files" -ForegroundColor DarkGreen }
            return (Resolve-Path -LiteralPath $c).Path
        }
    }

    # 4) 其它盘符常见安装位置（战网常把游戏装到 D:\ 等）
    foreach ($driveRoot in @('D:\', 'E:\', 'F:\')) {
        if (-not (Test-Path -LiteralPath $driveRoot)) { continue }
        foreach ($rel in @(
                "World of Warcraft\_retail_\Interface\AddOns"
                "Games\World of Warcraft\_retail_\Interface\AddOns"
                "Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
                "Program Files\World of Warcraft\_retail_\Interface\AddOns"
            )) {
            $c = Join-Path $driveRoot $rel
            if ($script:AddonSearchDebug) { Write-Host "[AddOns] 尝试: $c" -ForegroundColor DarkGray }
            if (Test-IsAddonsDirectory $c) {
                if ($script:AddonSearchDebug) { Write-Host "[AddOns] 命中: 扩展盘符" -ForegroundColor DarkGreen }
                return (Resolve-Path -LiteralPath $c).Path
            }
        }
    }

    return $null
}

function Copy-ToolboxToAddons {
    param(
        [Parameter(Mandatory = $true)][string]$AddonsRoot
    )
    $dest = Join-Path $AddonsRoot "Toolbox"
    Write-Host "部署到: $dest"
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Copy-Item -LiteralPath $ToolboxDir -Destination $AddonsRoot -Recurse -Force
    Write-Host "完成: 已复制 Toolbox 到游戏 AddOns 目录。"
}

# --- 打 zip ---
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "dist"
}

# 默认部署到游戏目录；仅打 zip 请 -SkipDeploy
$doDeploy = -not $SkipDeploy

Write-Host "发布: zip=$([bool](-not $SkipZip))  复制到游戏=$doDeploy"

if (-not $SkipZip) {
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $ZipName = "Toolbox-$Version.zip"
    $ZipPath = Join-Path $OutputDir $ZipName

    if (-not $NoClean -and (Test-Path -LiteralPath $ZipPath)) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Push-Location $RepoRoot
    try {
        Compress-Archive -Path "Toolbox" -DestinationPath $ZipPath -Force
    }
    finally {
        Pop-Location
    }

    Write-Host "完成: $ZipPath"
    Write-Host "版本: $Version（来自 Toolbox.toc）"
} else {
    Write-Host "已跳过 zip（SkipZip）。"
}

# --- 部署到游戏目录 ---
if ($doDeploy) {
    $targetAddons = $null
    if (-not [string]::IsNullOrWhiteSpace($AddonPath)) {
        if (-not (Test-IsAddonsDirectory $AddonPath)) {
            Write-Error "AddonPath 不是有效的 AddOns 目录: $AddonPath"
        }
        $targetAddons = (Resolve-Path -LiteralPath $AddonPath).Path
    } else {
        $targetAddons = Get-RetailAddonsDirectory
    }

    if (-not $targetAddons) {
        Write-Warning @"
未找到正式服 Interface\AddOns，已跳过复制（zip 若未 SkipZip 则仍已生成）。
请任选其一：
  1) 设置用户环境变量 WOW_RETAIL_ADDONS = 你的 ...\_retail_\Interface\AddOns 完整路径
  2) 运行: .\scripts\Release.ps1 -AddonPath `"<你的路径>\_retail_\Interface\AddOns`"
  3) 若只想打 zip 不需要复制: 加 -SkipDeploy
"@
        if ($SkipZip) {
            exit 1
        }
    } else {
        Copy-ToolboxToAddons -AddonsRoot $targetAddons
    }
}

# 使用 -SkipDeploy 时不会进入上方部署逻辑，但仍可单独探测路径
if ($ShowAddonSearch -and -not $doDeploy) {
    Write-Host "--- AddOns 路径探测（仅诊断，未复制）---" -ForegroundColor Cyan
    $script:AddonSearchDebug = $true
    $diag = Get-RetailAddonsDirectory
    if ($diag) {
        Write-Host "找到: $diag" -ForegroundColor Green
    } else {
        Write-Host "未找到；请用 -AddonPath 或设置用户环境变量 WOW_RETAIL_ADDONS。" -ForegroundColor Yellow
    }
}
