# r23: opens the mall editor scene in Godot, waits, saves a screenshot of the screen, closes the editor.
param([int]$wait = 110, [string]$out = "$PSScriptRoot\editor_shot.png")
$godot = "A:\Installer\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"
$proj = Resolve-Path "$PSScriptRoot\..\..\game"
$p = Start-Process -FilePath $godot -ArgumentList @("--path", "`"$proj`"", "-e", "res://editor/malasugue_mall_editor.tscn", "--windowed", "--resolution", "1920x1080") -PassThru
Start-Sleep -Seconds $wait
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force
"saved $out"
