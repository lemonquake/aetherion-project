# r22 A/B: headless Deathmatch bot matches, the new mind (bot_mind.gd) against the reference brain (--brain=r22a), same
# map, seeds and settings as the r22 reference runs (12 bots, 2 teams, field off, Normal skill), all at once.
#   powershell -ExecutionPolicy Bypass -File work/r22/ai/ab_matches.ps1 -Map freight_delight -Seeds 41,42,43 [-Seconds 660] [-Port 27800]
# Logs: work/r22/ai/ab/<map>_<new|r22a>_<seed>.log; then round_stats.py over them.
param([string]$Map = "freight_delight", [string]$Seeds = "41,42,43", [int]$Seconds = 660, [int]$Port = 27800, [string]$Extra = "")
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
Set-Location $root
New-Item -ItemType Directory -Force work/r22/ai/ab | Out-Null
$procs = @()
$p = $Port
foreach ($seed in ($Seeds -split ",")) {
    foreach ($brain in @("new", "r22a")) {
        $p += 1
        $b = if ($brain -eq "r22a") { "--brain=r22a" } else { "" }
        $log = "work/r22/ai/ab/${Map}_${brain}_${seed}.log"
        $args = "--headless --path game -- --server --game_mode=deathmatch --map=$Map --teams=2 --team_size=6 --bots=12 --autostart=1 --expect_players=0 --match_seed=$seed --matchlog --quit_after_results=1 --port=$p $b $Extra"
        $procs += Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds $Seconds -Log $log -ArgLine `"$args`"" -PassThru -NoNewWindow
    }
}
$procs | ForEach-Object { $_.WaitForExit() }
$logs = Get-ChildItem "work/r22/ai/ab/${Map}_*.log" | Where-Object { $_.Name -notlike "*.err" } | Sort-Object Name | ForEach-Object { $_.FullName }
python -I work/r22/round_stats.py @logs
"script errors: " + (Select-String -Path $logs -Pattern "SCRIPT ERROR" | Measure-Object).Count
