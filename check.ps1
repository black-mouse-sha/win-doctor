<#
.SYNOPSIS
    WinDoctor 一键体检 —— 只读，不修改任何东西
.DESCRIPTION
    检查内存、页面文件、开机自启、系统服务、磁盘、显卡，
    并给出诊断结论。全程只读，不会改动你的电脑。
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\check.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'

function Line { param($c = 'Gray') Write-Host ('─' * 62) -ForegroundColor $c }
function Head { param($t) Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Line 'DarkGray' }
function KV   { param($k, $v, $c = 'White') Write-Host ("  {0,-16} {1}" -f $k, $v) -ForegroundColor $c }

Write-Host ''
Write-Host '  ╔══════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '  ║        WinDoctor · 电脑体检（只读，不改任何东西）      ║' -ForegroundColor Cyan
Write-Host '  ╚══════════════════════════════════════════════════════╝' -ForegroundColor Cyan

# ─────────────────────────────────────────────
Head '① 系统'
$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
KV '系统'   ($os.Caption -replace 'Microsoft ','')
KV '版本'   "build $($os.BuildNumber)"
KV '机型'   "$($cs.Manufacturer) $($cs.Model)"
KV 'CPU'    $cpu.Name.Trim()
KV '核心'   "$($cpu.NumberOfCores) 核 / $($cpu.NumberOfLogicalProcessors) 线程"
KV '开机'   $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm')

# ─────────────────────────────────────────────
Head '② 内存'
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 0)

KV '物理内存' "$totalGB GB"
$c = if ($freeGB -lt 2) { 'Red' } elseif ($freeGB -lt 4) { 'Yellow' } else { 'Green' }
KV '可用'     "$freeGB GB  (已用 $usedPct%)" $c

Write-Host ''
Write-Host '  内存条：' -ForegroundColor Gray
$slots = Get-CimInstance Win32_PhysicalMemory
foreach ($m in $slots) {
    $type = switch ($m.SMBIOSMemoryType) {
        26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } default { "type$($m.SMBIOSMemoryType)" }
    }
    Write-Host ("    {0,-28} {1,3} GB  {2}  {3} MT/s  {4}" -f `
        $m.DeviceLocator, ($m.Capacity/1GB), $type, $m.Speed, $m.Manufacturer) -ForegroundColor Gray
}
$emptySlots = (Get-CimInstance Win32_PhysicalMemoryArray).MemoryDevices - $slots.Count
if ($emptySlots -gt 0) {
    Write-Host "    （WMI 报告还有 $emptySlots 个空槽，但笔记本这个数字经常不准，建议拆机确认）" -ForegroundColor DarkGray
}

# ─────────────────────────────────────────────
Head '③ 页面文件（最容易出问题的地方）'
$commitGB = [math]::Round($os.TotalVirtualMemorySize / 1MB, 2)
$diffGB   = [math]::Round($commitGB - $totalGB, 2)

KV '提交上限' "$commitGB GB"
KV '差额'     "$diffGB GB  （= 页面文件给你的缓冲）"

$userPf = Get-CimInstance Win32_PageFileUsage
if ($userPf) {
    foreach ($p in $userPf) {
        KV '  活动' "$($p.Name)  分配 $($p.AllocatedBaseSize) MB  峰值 $($p.PeakUsage) MB"
    }
} else {
    KV '  活动' '（无）' 'Red'
}

$cfg = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles).PagingFiles
Write-Host '  配置：' -ForegroundColor Gray
if ($cfg) { foreach ($l in $cfg) { Write-Host "    $l" -ForegroundColor Gray } }
else { Write-Host '    （空）' -ForegroundColor Red }

$auto = (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
KV '自动管理' $auto

# 诊断
Write-Host ''
if ($diffGB -lt ($totalGB * 0.5)) {
    Write-Host '  ⚠ 诊断：页面文件太小' -ForegroundColor Red
    Write-Host "    你的物理内存有 $totalGB GB，但系统只敢承诺 $commitGB GB。" -ForegroundColor Yellow
    Write-Host '    内存一吃满就没地方周转，系统只能杀程序（表现：程序自己消失）。' -ForegroundColor Yellow
    Write-Host '    建议：页面文件给到物理内存的 1~1.5 倍 → 见 modules/03-页面文件.md' -ForegroundColor Green
} else {
    Write-Host '  ✓ 页面文件配置正常' -ForegroundColor Green
}

# 僵尸文件检测
Write-Host ''
Write-Host '  僵尸文件检测（文件在、配置里没有 = 白占硬盘）：' -ForegroundColor Gray
foreach ($dl in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3').DeviceID) {
    $f = "${dl}\pagefile.sys"
    $exists = Test-Path $f
    $inCfg  = $cfg -match [regex]::Escape($f)
    if ($exists -and -not $inCfg) {
        $sz = (Get-Item $f -Force).Length / 1GB
        Write-Host ("    {0}  {1:N1} GB   ← 僵尸！配置里没有它" -f $f, $sz) -ForegroundColor Red
    } elseif ($inCfg) {
        Write-Host ("    {0}  ← 配置中" -f $f) -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────
Head '④ 开机自启'
$hkcu = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run').PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
$hklm = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run').PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
$startup = @(Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -File)
$startupAll = @(Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -File)

KV 'HKCU Run'    "$(@($hkcu).Count) 项"
KV 'HKLM Run'    "$(@($hklm).Count) 项"
KV '启动文件夹'  "$($startup.Count + $startupAll.Count) 个"

if ($hkcu) {
    Write-Host ''
    Write-Host '  用户自启：' -ForegroundColor Gray
    foreach ($p in $hkcu) { Write-Host ("    ● {0,-22} {1}" -f $p.Name, $p.Value) -ForegroundColor Gray }
}

$tasks = @(Get-ScheduledTask | Where-Object {
    $_.State -ne 'Disabled' -and
    ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' })
})
$appTasks = @($tasks | Where-Object {
    $a = ($_.Actions | Select-Object -First 1).Execute
    $a -and $a -notmatch '\\Windows\\|\\system32\\' -and $a -notmatch '^%'
})
KV '任务计划(应用)' "$($appTasks.Count) 个"
if ($appTasks) {
    Write-Host ''
    foreach ($t in $appTasks) {
        Write-Host ("    ● {0}" -f $t.TaskName) -ForegroundColor Yellow
    }
}

$totalAuto = @($hkcu).Count + @($hklm).Count + $startup.Count + $startupAll.Count + $appTasks.Count
Write-Host ''
if ($totalAuto -gt 20) {
    Write-Host "  ⚠ 开机自启共 $totalAuto 项，偏多 → 见 modules/01-开机自启.md" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ 开机自启共 $totalAuto 项，还算克制" -ForegroundColor Green
}

# ─────────────────────────────────────────────
Head '⑤ 系统服务'
$svcAll = Get-CimInstance Win32_Service
$autoSvc = @($svcAll | Where-Object { $_.StartMode -eq 'Auto' })
KV '总服务数'   $svcAll.Count
KV '自动启动'   $autoSvc.Count
KV '正在运行'   (@($svcAll | Where-Object { $_.State -eq 'Running' })).Count

# 可疑的第三方自动服务
$thirdParty = @($autoSvc | Where-Object {
    $_.PathName -and $_.PathName -notmatch '\\Windows\\|\\system32\\' -and $_.PathName -notmatch '^%'
})
KV '第三方自动' $thirdParty.Count
if ($thirdParty.Count -gt 0) {
    Write-Host ''
    Write-Host '  第三方自启服务（前 15 个）：' -ForegroundColor Gray
    $thirdParty | Select-Object -First 15 | ForEach-Object {
        Write-Host ("    ● {0,-40} {1}" -f $_.Name, $_.DisplayName) -ForegroundColor Gray
    }
    if ($thirdParty.Count -gt 15) {
        Write-Host "    …… 还有 $($thirdParty.Count - 15) 个" -ForegroundColor DarkGray
    }
}

# ─────────────────────────────────────────────
Head '⑥ 磁盘'
foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
    $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    $pct = [math]::Round($d.FreeSpace / $d.Size * 100, 0)
    $c = if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Gray' }
    KV $d.DeviceID ("{0,6:N1} GB 可用 / {1,6:N1} GB  ({2}% 空闲)  {3}" -f $freeGB, $sizeGB, $pct, $d.VolumeName) $c
}

Write-Host ''
Write-Host '  盘符对应哪块物理盘（页面文件要放独立盘）：' -ForegroundColor Gray
foreach ($dl in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3').DeviceID) {
    $letter = $dl.TrimEnd(':')
    $p = Get-Partition -DriveLetter $letter
    if ($p) {
        $dk = Get-Disk -Number $p.DiskNumber
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $dk.Number }
        Write-Host ("    {0}:  Disk{1}  {2}  {3}" -f $letter, $dk.Number, $dk.FriendlyName, $pd.MediaType) -ForegroundColor Gray
    }
}

# ─────────────────────────────────────────────
Head '⑦ 显卡'
$gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Virtual|Basic' }
foreach ($g in $gpus) {
    KV $g.Name ("驱动 $($g.DriverVersion)")
}
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host '  NVIDIA 实况：' -ForegroundColor Gray
    nvidia-smi --query-gpu=name,memory.total,memory.used,temperature.gpu --format=csv,noheader | ForEach-Object {
        Write-Host "    $_" -ForegroundColor Gray
    }
}

# ─────────────────────────────────────────────
Head '⑧ 内存占用 Top 10'
Get-Process | Group-Object ProcessName | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        MB   = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
        N    = $_.Count
    }
} | Sort-Object MB -Descending | Select-Object -First 10 | ForEach-Object {
    Write-Host ("    {0,-24} {1,6} MB  ({2} 进程)" -f $_.Name, $_.MB, $_.N) -ForegroundColor Gray
}

# ─────────────────────────────────────────────
Write-Host ''
Write-Host ('═' * 62) -ForegroundColor Cyan
Write-Host '  体检完成。以上全是只读操作，你的电脑没有任何改动。' -ForegroundColor Green
Write-Host ''
Write-Host '  下一步：' -ForegroundColor Cyan
Write-Host '    · 页面文件有问题  → modules/03-页面文件.md' -ForegroundColor Gray
Write-Host '    · 开机自启太多    → modules/01-开机自启.md' -ForegroundColor Gray
Write-Host '    · 服务太多空转    → modules/02-系统服务.md' -ForegroundColor Gray
Write-Host '    · 或者把结果贴给 AI，让它帮你看' -ForegroundColor Gray
Write-Host ('═' * 62) -ForegroundColor Cyan
Write-Host ''
