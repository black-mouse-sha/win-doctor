<#
.SYNOPSIS
    WinDoctor 备份 —— 把自启项、服务状态、页面文件配置全存一份
.DESCRIPTION
    生成一个带时间戳的备份目录，包含：
      - 注册表 Run 键的 .reg 导出
      - 启动文件夹的快捷方式副本
      - 任务计划清单（文本）
      - 第三方服务状态清单（JSON）
      - 页面文件配置（文本）
    只读取和复制，不修改任何现有配置。
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\backup.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bk = "$env:USERPROFILE\Documents\windoctor-backup-$stamp"

New-Item -ItemType Directory -Path $bk -Force | Out-Null
New-Item -ItemType Directory -Path "$bk\startup-lnk" -Force | Out-Null

Write-Host ''
Write-Host "  备份目录: $bk" -ForegroundColor Cyan
Write-Host ('─' * 60) -ForegroundColor DarkGray

# ① 注册表 Run 键
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$bk\HKCU-Run.reg" /y | Out-Null
reg export "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" "$bk\HKLM-Run.reg" /y | Out-Null
Write-Host '  ✓ 注册表 Run 键已导出' -ForegroundColor Green

# ② 启动文件夹
$su = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$suAll = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
$n = 0
Get-ChildItem $su -File | ForEach-Object { Copy-Item $_.FullName "$bk\startup-lnk\" -Force; $n++ }
Get-ChildItem $suAll -File | ForEach-Object { Copy-Item $_.FullName "$bk\startup-lnk\" -Force; $n++ }
Write-Host "  ✓ 启动文件夹已备份 $n 个文件" -ForegroundColor Green

# ③ 任务计划清单
Get-ScheduledTask | Where-Object {
    $_.State -ne 'Disabled' -and
    ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' })
} | ForEach-Object {
    $exe = ($_.Actions | Select-Object -First 1).Execute
    "{0}`t{1}`t{2}" -f $_.TaskName, $_.TaskPath, $exe
} | Out-File "$bk\scheduled-tasks.txt" -Encoding UTF8
Write-Host '  ✓ 任务计划清单已保存' -ForegroundColor Green

# ④ 服务状态（JSON，方便 restore.ps1 读）
Get-CimInstance Win32_Service |
  Select-Object Name, DisplayName, StartMode, State, PathName |
  ConvertTo-Json -Depth 3 |
  Out-File "$bk\services.json" -Encoding UTF8
Write-Host '  ✓ 服务状态已保存' -ForegroundColor Green

# ⑤ 页面文件配置
$pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles).PagingFiles
@(
  "PagingFiles:"
  ($pf | ForEach-Object { "  $_" })
  ""
  "AutomaticManagedPagefile: $((Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile)"
  ""
  "当前活动:"
  (Get-CimInstance Win32_PageFileUsage | ForEach-Object { "  $($_.Name)  分配 $($_.AllocatedBaseSize) MB" })
) | Out-File "$bk\pagefile.txt" -Encoding UTF8
Write-Host '  ✓ 页面文件配置已保存' -ForegroundColor Green

# ⑥ 体检快照
$os = Get-CimInstance Win32_OperatingSystem
@(
  "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  "物理内存: {0:N2} GB" -f ($os.TotalVisibleMemorySize/1MB)
  "可用内存: {0:N2} GB" -f ($os.FreePhysicalMemory/1MB)
  "提交上限: {0:N2} GB" -f ($os.TotalVirtualMemorySize/1MB)
) | Out-File "$bk\snapshot.txt" -Encoding UTF8

Write-Host ('─' * 60) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  备份完成。还原方法：' -ForegroundColor Cyan
Write-Host "    · 注册表 → 双击 .reg 文件" -ForegroundColor Gray
Write-Host "    · 快捷方式 → 拖回启动文件夹" -ForegroundColor Gray
Write-Host "    · 服务 → powershell -File .\restore.ps1 -BackupDir `"$bk`"" -ForegroundColor Gray
Write-Host ''
