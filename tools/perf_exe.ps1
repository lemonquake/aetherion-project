# Runs the --autotest=perf benchmark on an exported Windows build (release template, as players run it).
#   powershell -ExecutionPolicy Bypass -File tools/perf_exe.ps1 -Exe builds\windows\Aetherion.exe -Tag new [-Bots 49]
# Logs and captures go to <OutDir>\perf_<Tag>.log and <OutDir>\perf_<Tag>\.
param(
    [string]$Exe = "builds\windows\Aetherion.exe",
    [string]$Tag = "exe",
    [int]$Seconds = 700,
    [string]$Pre = "",
    [string]$Extra = "",
    [int]$Bots = 11,
    [string]$OutDir = "work\lemondev\r3"
)
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "perf_$Tag.log"
$shots = (Join-Path $out "perf_$Tag") -replace '\\', '/'
$p = Start-Process -FilePath (Join-Path $root $Exe) -ArgumentList "$Pre -- $Extra --host --bots=$Bots --autostart=1 --autotest=perf --autotest_timeout=$($Seconds - 60) --shots=$shots --size=1600x900" -RedirectStandardOutput $log -PassThru
$null = $p.Handle  # keeps the exit code readable after the process ends
if (-not $p.WaitForExit($Seconds * 1000)) {
    & taskkill /T /F /PID $p.Id | Out-Null
    Add-Content -Path $log -Value "[perf_exe] killed after $Seconds s"
}
"exit " + $p.ExitCode
