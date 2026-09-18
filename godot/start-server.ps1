param(
  [int]$StartPort = 8000
)
$ErrorActionPreference = 'Stop'
if ($PSCommandPath) {
  $root = Split-Path -Parent $PSCommandPath
} else {
  $root = $PWD.Path
}

$listener = New-Object System.Net.HttpListener
$port = $StartPort
$ok = $false
$attempts = 0
while ($attempts -lt 200 -and $port -le 65535) {
  $attempts++
  try {
    $listener.Prefixes.Clear()
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()
    $ok = $true
    break
  } catch {
    $port++
  }
}
if (-not $ok) {
  Write-Host ""
  Write-Host "ERROR: no free port found (tried $StartPort..$($port-1))." -ForegroundColor Red
  Write-Host ""
  Write-Host "This usually means another instance of the game (or other software)" -ForegroundColor Yellow
  Write-Host "is already using these ports." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "You can pick a different starting port by editing start.cmd" -ForegroundColor Cyan
  Write-Host "or running:  powershell -ExecutionPolicy Bypass -File start-server.ps1 -StartPort 9000" -ForegroundColor Cyan
  Read-Host "Press Enter to close"
  exit 1
}

$url = "http://localhost:$port/"
Write-Host ""
Write-Host "================================================================"
Write-Host " Tanchiki -- local server"
Write-Host " Game URL : $url"
Write-Host " Close this window to stop the server."
Write-Host "================================================================"
Write-Host ""

# Открываем браузер ТОЛЬКО после того, как сервер уже слушает порт.
Start-Process $url

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.mjs'  = 'text/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.txt'  = 'text/plain; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
  '.webp' = 'image/webp'
  '.woff'  = 'font/woff'
  '.woff2' = 'font/woff2'
  '.ttf'  = 'font/ttf'
  '.otf'  = 'font/otf'
  '.mp3'  = 'audio/mpeg'
  '.ogg'  = 'audio/ogg'
  '.wav'  = 'audio/wav'
}

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
  } catch {
    break
  }
  try {
    $path = $ctx.Request.Url.AbsolutePath
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
    $rel = $path.TrimStart('/')
    $rel = [System.Uri]::UnescapeDataString($rel)
    $rel = $rel -replace '/', [IO.Path]::DirectorySeparatorChar
    $file = Join-Path $root $rel
    if (Test-Path -LiteralPath $file -PathType Leaf) {
      $bytes = [IO.File]::ReadAllBytes($file)
      $ctx.Response.ContentLength64 = $bytes.Length
      $ext = [IO.Path]::GetExtension($file).ToLower()
      if ($types.ContainsKey($ext)) { $ctx.Response.ContentType = $types[$ext] }
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
      $ctx.Response.StatusDescription = 'Not Found'
    }
  } catch {
    $ctx.Response.StatusCode = 500
    $ctx.Response.StatusDescription = 'Server Error'
  } finally {
    $ctx.Response.OutputStream.Close()
    $ctx.Response.Close()
  }
}
$listener.Stop()
