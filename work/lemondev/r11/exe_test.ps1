# r11: the exported EXE runs --autotest=dm and --autotest=r11 (all but the long sidewalk sweep) on Deathmatch and
# must exit with code 0 (no crash at exit).
$root = "A:\Python\aetherion-project"
$out = "$root\work\lemondev\r11\exe"
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($t in @(@("dm", "--autotest=dm", 27541), @("r11", "--autotest=r11 --r11_only=teams,pa,cage,haze,kerbs,stairs", 27542))) {
    $log = "$out\$($t[0]).log"
    $args = "-- --host --game_mode=deathmatch --bots=20 --autostart=1 $($t[1]) --shots=A:/Python/aetherion-project/work/lemondev/r11/exe --size=1600x900 --port=$($t[2]) --autotest_timeout=500"
    $p = Start-Process -FilePath "$root\builds\windows\Aetherion.exe" -ArgumentList $args -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru
    $null = $p.Handle
    if (-not $p.WaitForExit(600 * 1000)) {
        & taskkill /T /F /PID $p.Id | Out-Null
        Add-Content -Path $log -Value "[exe_test] killed after 600 s"
    }
    "$($t[0]) exit " + $p.ExitCode
}
