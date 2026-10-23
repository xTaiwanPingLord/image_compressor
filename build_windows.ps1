# 檢查 Developer Mode 並建置 Windows 版；記錄寫到 build_windows.log
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$log = Join-Path $root 'build_windows.log'
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
function Log($m) { Write-Host $m; Add-Content -Path $log -Value $m -Encoding utf8 }
Remove-Item $log -ErrorAction SilentlyContinue

$dev = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
Log "DeveloperMode=$dev"
if ($dev -ne 1) {
  Log 'ERROR: Developer Mode is OFF (Settings > System > For developers)'
  exit 1
}

Set-Location (Join-Path $root 'app')
# 增量建置時圖示字型可能沒重新產生，改用完整字型（約 1.6 MB）
$sw = [Diagnostics.Stopwatch]::StartNew()
cmd /c "flutter pub get 2>&1" | ForEach-Object { Log $_ }
cmd /c "flutter build windows --release --no-tree-shake-icons 2>&1" | ForEach-Object { Log $_ }
$code = $LASTEXITCODE
Log "build exit=$code ($([int]$sw.Elapsed.TotalSeconds)s)"
$exe = Join-Path $root 'app\build\windows\x64\runner\Release\image_compressor.exe'
if ($code -eq 0 -and (Test-Path $exe)) {
  Log "EXE=$exe"
  Start-Process $exe
}
