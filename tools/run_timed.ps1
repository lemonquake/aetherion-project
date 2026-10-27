# Runs the Godot console build with a time limit and kills the whole process tree when it runs out (bash `timeout`
# only stops the console wrapper; the engine process it starts keeps running and holds the server port).
#   powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds 600 -Log work/x.log -ArgLine "--headless --path game -- --server ..."
param(
    [int]$Seconds = 600,
    [string]$Log = "godot.log",
    [string]$ArgLine = ""
)
$exe = "A:\Installer\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
$p = Start-Process -FilePath $exe -ArgumentList $ArgLine -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -PassThru -NoNewWindow
if (-not $p.WaitForExit($Seconds * 1000)) {
    & taskkill /T /F /PID $p.Id | Out-Null
    Start-Sleep -Milliseconds 500
    Add-Content -Path $Log -Value "[run_timed] killed after $Seconds s"
}
exit $p.ExitCode
