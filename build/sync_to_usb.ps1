param(
    [string]$TargetDrive = "E:"
)

$dest = "$TargetDrive\Tanchiki-0.9.27"
if (!(Test-Path $TargetDrive)) {
    Write-Host "Диск $TargetDrive не найден. Вставьте флешку и повторите попытку." -ForegroundColor Yellow
    exit 1
}

if (!(Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

Copy-Item -Path "$PSScriptRoot\*" -Destination $dest -Recurse -Force -Exclude "*.ps1"
Write-Host "Файлы успешно синхронизированы в $dest" -ForegroundColor Green
Get-ChildItem -Path $dest | Select-Object Name, Length, LastWriteTime
