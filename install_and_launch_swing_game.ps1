$ErrorActionPreference = "Stop"
$ProjectDir = Join-Path $env:USERPROFILE "OneDrive\Godot\SwingGameOptimized"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Creating optimized swinging project..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
Copy-Item (Join-Path $SourceDir "main.gd") (Join-Path $ProjectDir "main.gd") -Force

@'
[application]
config/name="Swing Game Optimized"
run/main_scene="res://main.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
anti_aliasing/quality/msaa_3d=0

[physics]
common/physics_ticks_per_second=60
'@ | Set-Content -Encoding UTF8 (Join-Path $ProjectDir "project.godot")

@'
[gd_scene load_steps=2 format=3]

[ext_resource path="res://main.gd" type="Script" id="1"]

[node name="SwingGame" type="Node3D"]
script = ExtResource("1")
'@ | Set-Content -Encoding UTF8 (Join-Path $ProjectDir "main.tscn")

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget was not found. Install or update App Installer from the Microsoft Store, then run this script again."
}

$GodotPackage = winget list --id GodotEngine.GodotEngine --exact 2>$null | Out-String
if ($GodotPackage -notmatch "GodotEngine.GodotEngine") {
    Write-Host "Installing Godot Engine..." -ForegroundColor Yellow
    winget install --id GodotEngine.GodotEngine --exact --source winget --accept-package-agreements --accept-source-agreements
}

$Candidates = @(
    (Get-Command godot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Get-Command godot4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $Candidates) {
    $Candidates = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:LOCALAPPDATA\Programs", "$env:ProgramFiles" `
        -Filter "Godot*.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "console" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName
}

$GodotExe = $Candidates | Select-Object -First 1
if (-not $GodotExe) {
    throw "Godot installed, but its executable was not found. Open Godot once from Start, then rerun this script."
}

Write-Host "Launching project from $ProjectDir" -ForegroundColor Green
Start-Process -FilePath $GodotExe -ArgumentList @("--editor", "--path", $ProjectDir)
