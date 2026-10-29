# r6: the exported EXE runs --autotest=r6 (fast landing) and must exit with code 0 (no crash at exit).
$root = "A:\Python\aetherion-project"
$out = "$root\work\lemondev\r6\exe"
New-Item -ItemType Directory -Force $out | Out-Null
$log = "$out\r6.log"
$p = Start-Process -FilePath "$root\builds\windows\Aetherion.exe" -ArgumentList "-- --host --bots=11 --autostart=1 --autotest=r6 --r6_fast=1 --shots=A:/Python/aetherion-project/work/lemondev/r6/exe --size=1600x900 --port=27540" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru
$null = $p.Handle
if (-not $p.WaitForExit(600 * 1000)) {
    & taskkill /T /F /PID $p.Id | Out-Null
    Add-Content -Path $log -Value "[exe_test] killed after 600 s"
}
"exit " + $p.ExitCode
