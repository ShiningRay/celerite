param(
  [string]$Exe,
  [string]$ArgString,
  [string]$WorkDir
)
$outLog = Join-Path $WorkDir "out.log"
$errLog = Join-Path $WorkDir "err.log"
# launch via cmd: the inherited environment may contain duplicate keys that
# differ only in case (NO_PROXY/no_proxy), which Start-Process rejects
$p = Start-Process -PassThru -FilePath "$env:ComSpec" `
  -ArgumentList "/c", "`"$Exe`" $ArgString" `
  -WorkingDirectory $WorkDir -RedirectStandardOutput $outLog -RedirectStandardError $errLog -Wait -NoNewWindow
[math]::Round($p.PeakWorkingSet64 / 1KB)
