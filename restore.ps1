<#
.SYNOPSIS
    WinDoctor 还原 —— 从备份恢复服务状态和启动项
.DESCRIPTION
    读取 backup.ps1 生成的备份目录，把服务启动方式改回去，把快捷方式移回启动文件夹。
    注册表需要手动双击 .reg 文件（避免自动改注册表）。
.PARAMETER BackupDir
    备份目录路径。不填则自动找最新的一个。
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restore.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restore.ps1 -BackupDir "C:\Users\me\Documents\windoctor-backup-20260101-120000"
#>

param(
    [string]$BackupDir
)

$ErrorActionPreference = 'SilentlyContinue'

Write-Host ''
Write-Host '  WinDoctor · 还原' -ForegroundColor Cyan
Write-Host ('─' * 60) -ForegroundColor DarkGray

# 找备份目录
if (-not $BackupDir) {
    $latest = Get-ChildItem "$env:USERPROFILE\Documents\windoctor-backup-*" -Directory |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) {
        Write-Host '  ✗ 没找到任何备份。' -ForegroundColor Red
        Write-Host '    请用 -BackupDir 指定路径，或先跑一次 backup.ps1' -ForegroundColor Gray
        exit 1
    }
    $BackupDir = $latest.FullName
}

Write-Host "  使用备份: $BackupDir" -ForegroundColor Gray

if (-not (Test-Path $BackupDir)) {
    Write-Host "  ✗ 目录不存在: $BackupDir" -ForegroundColor Red
    exit 1
}

# ① 服务状态
$svcFile = Join-Path $BackupDir 'services.json'
if (Test-Path $svcFile) {
    Write-Host ''
    Write-Host '  ① 恢复服务启动方式' -ForegroundColor Yellow

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host '    ⚠ 需要管理员权限，跳过。请用管理员身份重跑本脚本。' -ForegroundColor Red
    } else {
        $backup = Get-Content $svcFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $changed = 0
        foreach ($s in $backup) {
            $cur = Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'"
            if ($cur -and $cur.StartMode -ne $s.StartMode) {
                Set-Service -Name $s.Name -StartupType $s.StartMode -ErrorAction SilentlyContinue
                $now = (Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'").StartMode
                Write-Host ("    {0,-40} {1} -> {2}" -f $s.Name, $cur.StartMode, $now) -ForegroundColor Gray
                $changed++
            }
        }
        if ($changed -eq 0) {
            Write-Host '    所有服务启动方式都和备份一致，无需修改' -ForegroundColor Green
        } else {
            Write-Host "    已恢复 $changed 个服务" -ForegroundColor Green
        }
    }
} else {
    Write-Host '  （没有 services.json，跳过服务恢复）' -ForegroundColor DarkGray
}

# ② 启动文件夹
Write-Host ''
Write-Host '  ② 恢复启动文件夹' -ForegroundColor Yellow
$lnkDir = Join-Path $BackupDir 'startup-lnk'
if (Test-Path $lnkDir) {
    $target = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $files = Get-ChildItem $lnkDir -File
    if ($files.Count -eq 0) {
        Write-Host '    备份里没有快捷方式' -ForegroundColor Gray
    } else {
        foreach ($f in $files) {
            $dest = Join-Path $target $f.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $f.FullName $dest -Force
                Write-Host "    恢复: $($f.Name)" -ForegroundColor Gray
            } else {
                Write-Host "    已存在，跳过: $($f.Name)" -ForegroundColor DarkGray
            }
        }
        Write-Host '    完成' -ForegroundColor Green
    }
} else {
    Write-Host '    （没有 startup-lnk 目录，跳过）' -ForegroundColor DarkGray
}

# ③ 注册表
Write-Host ''
Write-Host '  ③ 注册表（需手动）' -ForegroundColor Yellow
$hkcuReg = Join-Path $BackupDir 'HKCU-Run.reg'
$hklmReg = Join-Path $BackupDir 'HKLM-Run.reg'
if (Test-Path $hkcuReg) {
    Write-Host "    HKCU: 双击导入 $hkcuReg" -ForegroundColor Gray
}
if (Test-Path $hklmReg) {
    Write-Host "    HKLM: 双击导入 $hklmReg （需要管理员）" -ForegroundColor Gray
}

# ④ 页面文件
Write-Host ''
Write-Host '  ④ 页面文件（需手动）' -ForegroundColor Yellow
$pfFile = Join-Path $BackupDir 'pagefile.txt'
if (Test-Path $pfFile) {
    Write-Host '    备份里的原始配置：' -ForegroundColor Gray
    Get-Content $pfFile -Encoding UTF8 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '    要恢复的话，用管理员运行（把内容换成上面 PagingFiles 那几行）：' -ForegroundColor Gray
    Write-Host '    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v PagingFiles /t REG_MULTI_SZ /d "C:\pagefile.sys 2048 2048" /f' -ForegroundColor DarkGray
    Write-Host '    然后重启。' -ForegroundColor Gray
}

Write-Host ''
Write-Host ('─' * 60) -ForegroundColor DarkGray
Write-Host '  还原完成。部分改动需要重启才生效。' -ForegroundColor Green
Write-Host ''
