param(
    [string]$Godot = '',
    [switch]$Editor
)
$ErrorActionPreference = 'Stop'
# The Steam edition of the editor ships its own steam_api64.dll. Windows
# loads that copy first, which can be older than the GodotSteam SDK.
# Use an isolated editor copy and the DLL shipped with this project.
if (-not $Godot) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $Godot = $command.Source }
}
if (-not $Godot) {
    $steamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steamRoot) {
        $candidate = Join-Path $steamRoot 'steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
        if (Test-Path -LiteralPath $candidate) { $Godot = $candidate }
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Specify the Godot editor: .\start-network.ps1 -Godot "C:\path\godot.exe"'
}
$runtime = Join-Path $PSScriptRoot '.network-tools'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $runtime '.gdignore') -Force | Out-Null
$executable = Join-Path $runtime 'godot.exe'
Copy-Item -LiteralPath $Godot -Destination $executable -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'addons\godotsteam\win64\steam_api64.dll') -Destination $runtime -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'steam_appid.txt') -Destination $runtime -Force
$launchArgs = @('--path', ('"' + $PSScriptRoot + '"'))
if ($Editor) { $launchArgs += '--editor' }
Start-Process -FilePath $executable -ArgumentList $launchArgs -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
