# Installs the Aetherion game configuration for TrenchBroom (2024.1 or later: game config version 9).
# Then in TrenchBroom: Preferences > Aetherion > Game Path = <this repo>\game\assets\maps  (the folder holding
# "textures"), OK; File > Open > game\assets\maps\freight_delight.map.
#   powershell -ExecutionPolicy Bypass -File tools\trenchbroom\install.ps1
$src = Join-Path $PSScriptRoot "Aetherion"
$dst = Join-Path $env:APPDATA "TrenchBroom\games\Aetherion"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Force (Join-Path $src "*") $dst
$gamePath = (Resolve-Path (Join-Path $PSScriptRoot "..\..\game\assets\maps")).Path
Write-Output "Installed to $dst"
Write-Output "Set TrenchBroom's Game Path for Aetherion to: $gamePath"
