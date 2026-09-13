<#
.SYNOPSIS
    WSL 배포판을 상시 실행 상태로 유지합니다.

.DESCRIPTION
    WSL2 는 마지막 클라이언트 세션이 끊기면 배포판을 종료합니다. 터미널을 닫거나
    로그오프하면 안에서 돌던 것이 전부 내려갑니다.

    이 스크립트는 두 가지를 설정합니다.

      1) 작업 스케줄러에 'sleep infinity' 세션을 상주시키는 작업을 등록합니다.
         부팅/로그온 트리거에 더해 N 분마다 시작을 재시도하는 반복 트리거를 겁니다.
         이미 살아있으면 MultipleInstancesPolicy=IgnoreNew 로 그냥 무시되므로,
         죽었을 때만 실제로 되살아납니다.

         작업 스케줄러의 '실패 시 다시 시작'(RestartCount) 은 쓰지 않습니다.
         액션이 0 이 아닌 코드로 끝나도 '실패'로 쳐주지 않는 경우가 있어
         조용히 동작하지 않습니다. 반복 트리거가 훨씬 확실합니다.

      2) %USERPROFILE%\.wslconfig 에 상주 운영에 필요한 키를 병합합니다.
         기존 설정은 보존하고 필요한 키만 갱신합니다.

.PARAMETER Distro
    대상 배포판. 생략하면 기본 배포판을 자동 감지합니다.

.PARAMETER IntervalMinutes
    되살리기 확인 주기(분). 기본 1. 최소 1.

.PARAMETER MemoryLimit
    .wslconfig 의 memory 상한 (예: 16GB). 생략하면 건드리지 않습니다.

.PARAMETER SkipWslConfig
    .wslconfig 를 수정하지 않습니다.

.PARAMETER Uninstall
    등록된 작업을 제거합니다. .wslconfig 는 건드리지 않습니다.

.PARAMETER Test
    wsl --shutdown 후 되살아나는지 실제로 측정합니다. 설치 없이 단독 실행 가능합니다.
    WSL 안에서 돌던 작업이 전부 종료되니 주의하세요.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wsl-keepalive.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wsl-keepalive.ps1 -Distro Ubuntu-24.04 -MemoryLimit 16GB

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wsl-keepalive.ps1 -Test

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\wsl-keepalive.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string] $Distro,
    [ValidateRange(1, 1440)]
    [int]    $IntervalMinutes = 1,
    [string] $TaskName = "WSL Keepalive",
    [string] $MemoryLimit,
    [switch] $SkipWslConfig,
    [switch] $Uninstall,
    [switch] $Test,
    [switch] $Elevated
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$env:WSL_UTF8 = "1"

$WslExe = Join-Path $env:SystemRoot "System32\wsl.exe"

function Info($m)  { Write-Host "  $m" }
function Step($m)  { Write-Host "`n== $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Fail($m)  { Write-Host "  [XX] $m" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 관리자 권한이 없으면 같은 인자로 재실행한다. Elevated 플래그로 재귀를 막는다.
function Invoke-SelfElevate {
    if ($Elevated) { throw "권한 상승에 실패했습니다. 관리자 PowerShell 에서 직접 실행하세요." }
    Warn "관리자 권한이 필요합니다. UAC 창을 띄웁니다."
    $argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Elevated")
    foreach ($k in $PSBoundParameters.Keys) {
        if ($k -eq "Elevated") { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $argv += "-$k" } }
        else { $argv += "-$k"; $argv += "`"$v`"" }
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argv
}

function Get-DefaultDistro {
    # wsl -l -v 에서 * 표시가 붙은 줄이 기본 배포판이다.
    $lines = & $WslExe -l -v 2>$null
    foreach ($line in $lines) {
        $clean = ($line -replace "\0", "").Trim()
        if ($clean -match '^\*\s+(\S+)') { return $Matches[1] }
    }
    return $null
}

function Test-DistroExists([string]$name) {
    $lines = & $WslExe -l -q 2>$null
    foreach ($line in $lines) {
        if (($line -replace "\0", "").Trim() -eq $name) { return $true }
    }
    return $false
}

function Test-DistroRunning([string]$name) {
    $lines = & $WslExe -l --running -q 2>$null
    foreach ($line in $lines) {
        if (($line -replace "\0", "").Trim() -eq $name) { return $true }
    }
    return $false
}

# ---- .wslconfig 병합 -------------------------------------------------------
# 기존 파일의 다른 설정을 지우지 않도록 해당 키만 갈아끼운다.
function Set-IniValue {
    param(
        [string[]] $Lines,
        [string]   $Section,
        [string]   $Key,
        [string]   $Value,
        [string]   $Comment
    )
    $out = New-Object System.Collections.Generic.List[string]
    if ($Lines) { $Lines | ForEach-Object { $out.Add($_) } }

    $secStart = -1; $secEnd = $out.Count
    for ($i = 0; $i -lt $out.Count; $i++) {
        if ($out[$i] -match '^\s*\[(.+?)\]\s*$') {
            if ($Matches[1] -eq $Section) { $secStart = $i }
            elseif ($secStart -ge 0) { $secEnd = $i; break }
        }
    }

    if ($secStart -lt 0) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -ne "") { $out.Add("") }
        $out.Add("[$Section]")
        if ($Comment) { $out.Add("# $Comment") }
        $out.Add("$Key=$Value")
        return $out.ToArray()
    }

    for ($i = $secStart + 1; $i -lt $secEnd; $i++) {
        if ($out[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $out[$i] = "$Key=$Value"
            return $out.ToArray()
        }
    }

    $insert = $secEnd
    while ($insert -gt $secStart + 1 -and $out[$insert - 1].Trim() -eq "") { $insert-- }
    if ($Comment) { $out.Insert($insert, "# $Comment"); $insert++ }
    $out.Insert($insert, "$Key=$Value")
    return $out.ToArray()
}

function Update-WslConfig {
    $path = Join-Path $env:USERPROFILE ".wslconfig"
    $lines = @()
    if (Test-Path $path) {
        $lines = [IO.File]::ReadAllLines($path)
        $backup = "$path.bak"
        Copy-Item $path $backup -Force
        Info "기존 설정 백업: $backup"
    }

    $lines = Set-IniValue -Lines $lines -Section "wsl2" -Key "vmIdleTimeout" -Value "-1" `
             -Comment "keep the VM alive (paired with the keepalive task)"
    $lines = Set-IniValue -Lines $lines -Section "wsl2" -Key "autoMemoryReclaim" -Value "gradual" `
             -Comment "return cached memory to Windows when idle"
    if ($MemoryLimit) {
        $lines = Set-IniValue -Lines $lines -Section "wsl2" -Key "memory" -Value $MemoryLimit `
                 -Comment "hard cap on VM memory"
    }
    $lines = Set-IniValue -Lines $lines -Section "experimental" -Key "sparseVhd" -Value "true" `
             -Comment "reclaim freed space inside the vhdx"

    # WSL 은 BOM 없는 UTF-8 을 기대한다.
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $false))
    Ok "$path 갱신"
    $lines | ForEach-Object { Info "  | $_" }
}

# ---- 작업 XML --------------------------------------------------------------
# New-ScheduledTaskTrigger 로는 '무기한 반복' 을 표현할 수 없다.
#   -RepetitionDuration 생략          -> cmdlet 이 거부
#   [TimeSpan]::MaxValue              -> P99999999DT23H59M59S, 범위 초과로 거부
# XML 에서 <Duration> 을 아예 빼는 것이 유일한 방법이라 XML 로 등록한다.
#
# XML 선언부(<?xml ... encoding="UTF-8"?>) 도 넣으면 안 된다.
# Register-ScheduledTask -Xml 은 UTF-16 문자열을 받으므로 선언과 충돌한다.
function New-TaskXml {
    param([string]$DistroName, [string]$UserId, [int]$Minutes)
    return @"
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Keep WSL $DistroName running at all times</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT${Minutes}M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2000-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$UserId</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$UserId</UserId>
      <LogonType>S4U</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$WslExe</Command>
      <Arguments>-d $DistroName -u root --exec /usr/bin/sleep infinity</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

# ---- 동작 ------------------------------------------------------------------
function Invoke-Test {
    Step "복구 테스트 (WSL 안의 작업이 모두 종료됩니다)"
    if (-not $Distro) { $Distro = Get-DefaultDistro }
    if (-not $Distro) { Fail "배포판을 찾지 못했습니다."; return }
    Info "대상: $Distro"

    Info "wsl --shutdown 실행"
    & $WslExe --shutdown | Out-Null
    Start-Sleep -Seconds 5
    if (Test-DistroRunning $Distro) { Warn "종료되지 않았습니다. 다른 세션이 잡고 있을 수 있습니다." }

    Info "복구 대기 (최대 5분, 5초 간격)"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 300) {
        Start-Sleep -Seconds 5
        if (Test-DistroRunning $Distro) {
            $sw.Stop()
            Ok ("부활 확인 - {0:N0}초 경과" -f $sw.Elapsed.TotalSeconds)
            return
        }
        Write-Host ("     ... {0:N0}s" -f $sw.Elapsed.TotalSeconds)
    }
    $sw.Stop()
    Fail "5분 내 복구 실패. 작업 등록 상태를 확인하세요."
}

function Invoke-Uninstall {
    Step "제거"
    $t = Get-ScheduledTask -TaskName $TaskName -EA SilentlyContinue
    if (-not $t) { Warn "'$TaskName' 작업이 없습니다."; return }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Ok "'$TaskName' 작업 제거"
    Info ".wslconfig 는 그대로 두었습니다. 되돌리려면 vmIdleTimeout 줄을 지우세요."
}

function Invoke-Install {
    Step "대상 확인"
    if (-not $Distro) {
        $Distro = Get-DefaultDistro
        if (-not $Distro) { throw "WSL 배포판을 찾지 못했습니다. 'wsl -l -v' 로 확인하세요." }
        Info "기본 배포판 자동 감지: $Distro"
    } elseif (-not (Test-DistroExists $Distro)) {
        throw "'$Distro' 배포판이 없습니다. 'wsl -l -v' 로 확인하세요."
    }
    $userId = "$env:USERDOMAIN\$env:USERNAME"
    Info "배포판 : $Distro"
    Info "계정   : $userId"
    Info "주기   : ${IntervalMinutes}분"

    if (-not $SkipWslConfig) {
        Step ".wslconfig 병합"
        Update-WslConfig
    }

    Step "작업 등록"
    $xml = New-TaskXml -DistroName $Distro -UserId $userId -Minutes $IntervalMinutes
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -EA SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
    Ok "'$TaskName' 등록"

    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3

    Step "검증"
    $task = Get-ScheduledTask -TaskName $TaskName
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Info "State          : $($task.State)"
    Info "LastTaskResult : $($info.LastTaskResult)"

    $rep = $task.Triggers | Where-Object { $_.Repetition.Interval }
    if ($rep) {
        $dur = $rep.Repetition.Duration
        Info "Repetition     : $($rep.Repetition.Interval) / Duration='$dur'"
        if ([string]::IsNullOrEmpty($dur)) { Ok "무기한 반복 설정됨" }
        else { Warn "Duration 이 '$dur' 입니다. 무기한이 아닙니다." }
    } else {
        Warn "반복 트리거를 찾지 못했습니다."
    }

    if ($task.State -eq "Running" -and $info.LastTaskResult -eq 267009) {
        Ok "정상 동작 중"
    } else {
        Warn "State=Running / LastTaskResult=267009 이어야 정상입니다."
    }

    Write-Host ""
    Info "복구 테스트: 이 스크립트를 -Test 로 다시 실행하세요."
    Info "제거      : 이 스크립트를 -Uninstall 로 실행하세요."
}

# ---- 진입점 ----------------------------------------------------------------
Write-Host "WSL Keepalive" -ForegroundColor White

if (-not (Test-Path $WslExe)) { Fail "wsl.exe 를 찾을 수 없습니다: $WslExe"; exit 1 }

try {
    if ($Test) {
        Invoke-Test              # 테스트는 관리자 권한이 필요 없다
    } else {
        if (-not (Test-Admin)) { Invoke-SelfElevate; exit 0 }
        if ($Uninstall) { Invoke-Uninstall } else { Invoke-Install }
    }
    $code = 0
} catch {
    Write-Host ""
    Fail $_.Exception.Message
    $code = 1
}

if ($Elevated) { Write-Host "`n창을 닫으려면 Enter"; [void](Read-Host) }
exit $code
