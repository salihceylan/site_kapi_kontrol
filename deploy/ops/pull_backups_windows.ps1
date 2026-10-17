<#
.SYNOPSIS
  Sunucudaki SIFRELI yedekleri bu bilgisayara ceker (dis kopya: "ceken" yontem).

.DESCRIPTION
  Yalnizca ssh anahtari + scp kullanir. Sunucudaki ~/backups/scheduled/offsite klasorundeki
  kapi_*.sql.gz.enc, kapi_config_*.tgz.enc, kapi_firmware_*.tgz.enc ve kapi_documents_*.tgz.enc dosyalarini indirir (zaten sifreli, "Salted__"
  basligi dogrulanir), indirilen her dosyanin SHA-256 degerini sunucudakiyle karsilastirir. Var olan dosyalari yeniden
  indirmez. Sunucuya YAZMAZ, sunucuda hicbir seyi silmez. Sifre cozme anahtari (kapi-backup.key) bu betikle INDIRILMEZ
  (yalnizca -FetchKey ile, tek seferlik, bilincli olarak).

  Saklama: yerel dis kopyalar EN FAZLA 210 gun tutulur (varsayilan -PruneDays 210; 0 = hic silme). Firmware arsivleri
  (kapi_firmware_*) yas nedeniyle SILINMEZ (degismedikce tek yedek kopyadir). Belge deposu arsivlerinde (kapi_documents_*) EN YENISI
  yas nedeniyle SILINMEZ, ondan eskiler 210 gunu asinca silinir.

  Zamanlanmis gorev OLARAK KURMAK kullanicinin islemidir (docs/OPERASYON_YEDEK_IZLEME.md, "Windows tarafi").

.PARAMETER KeyPath
  Parolasiz (veya ssh-agent'ta yuklu) ozel anahtar. Bos birakilirsa ssh'in varsayilan anahtarlari kullanilir.

.PARAMETER PruneDays
  Varsayilan 210. N > 0 ise N gunden eski YEREL .enc dosyalari silinir (firmware HARIC). 0 = hic silme.

.PARAMETER FetchKey
  Tek seferlik: sifre cozme anahtarini -KeyDestination klasorune indirir (varsayilan: %LOCALAPPDATA%\kapi-anahtar-tasi).
  Bu klasor yedeklerin klasorunun DISINDADIR ve OneDrive/Dropbox gibi bir esitlemeye dahil OLMAMALIDIR (Belgeler/Masaustu
  klasorleri OneDrive ile esitleniyor olabilir). Dosyayi hemen parola yoneticisine tasiyin, sonra klasoru silin. Icerik
  ekrana yazdirilmaz.

.PARAMETER ListOnly
  Hicbir sey indirmeden sunucudaki dosyalari listeler.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\pull_backups_windows.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName = '178.210.161.55',
  [int]$Port = 22667,
  [string]$User = 'salihceylan',
  [string]$KeyPath = '',
  [string]$Destination = (Join-Path $env:USERPROFILE 'kapi-yedek'),
  [string]$KeyDestination = (Join-Path $env:LOCALAPPDATA 'kapi-anahtar-tasi'),
  [string]$RemoteDir = 'backups/scheduled/offsite',
  [int]$PruneDays = 210,
  [switch]$FetchKey,
  [switch]$ListOnly
)

# Yerel ssh/scp stderr yazdiginda (ornek: "Warning: Permanently added ...") PS 5.1 hata saymasin.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2

$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$scp = Get-Command scp.exe -ErrorAction SilentlyContinue
if (-not $ssh -or -not $scp) {
  Write-Error "ssh.exe / scp.exe bulunamadi. Windows Ayarlar > Uygulamalar > Istege bagli ozellikler > 'OpenSSH Istemcisi' ekleyin."
  exit 2
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$logFile = Join-Path $Destination 'pull.log'
function Write-Log([string]$msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  Add-Content -Path $logFile -Value $line -Encoding ASCII
}

$sshArgs = @('-p', "$Port", '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20', '-o', 'StrictHostKeyChecking=accept-new')
$scpArgs = @('-P', "$Port", '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20', '-o', 'StrictHostKeyChecking=accept-new')
if ($KeyPath -ne '') {
  $sshArgs += @('-i', $KeyPath, '-o', 'IdentitiesOnly=yes')
  $scpArgs += @('-i', $KeyPath, '-o', 'IdentitiesOnly=yes')
}
$remote = "$User@$HostName"
$namePattern = '^kapi(_config|_firmware|_documents)?_\d{8}_\d{4}\.(sql\.gz|tgz)\.enc$'

# Uzak komut: stderr AYRI dosyaya gider (ozet/ayristirma ciktisina karismaz); yalnizca stdout dondurulur.
function Invoke-Remote([string]$command) {
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $out = & $ssh.Source @sshArgs $remote $command 2>$errFile
    $code = $LASTEXITCODE
    if ($code -ne 0) {
      $err = ''
      if (Test-Path -LiteralPath $errFile) { $err = [string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) }
      throw ("uzak komut basarisiz (kod {0}): {1}" -f $code, $err.Trim())
    }
    return $out
  }
  finally {
    Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
  }
}

$failed = 0
$pulled = 0
try {
  if ($FetchKey) {
    New-Item -ItemType Directory -Force -Path $KeyDestination | Out-Null
    $keyDest = Join-Path $KeyDestination 'kapi-backup.key'
    & $scp.Source @scpArgs "${remote}:.config/kapi-backup.key" $keyDest 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'anahtar indirilemedi' }
    & icacls.exe $keyDest /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
    Write-Log "Anahtar indirildi: $keyDest  (icerigi yazdirilmaz). HEMEN parola yoneticisine tasiyin, sonra klasoru silin; OneDrive/bulut esitlemesine ve yedeklerin klasorune KOYMAYIN."
    exit 0
  }

  $listing = Invoke-Remote "ls -1 $RemoteDir"
  $names = @($listing | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match $namePattern } | Sort-Object)
  Write-Log ("sunucuda {0} sifreli dosya var" -f $names.Count)
  if ($ListOnly) { $names | ForEach-Object { Write-Host "  $_" }; exit 0 }

  foreach ($name in $names) {
    $final = Join-Path $Destination $name
    if (Test-Path -LiteralPath $final) { continue }
    $part = "$final.part"
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    & $scp.Source @scpArgs "${remote}:$RemoteDir/$name" $part 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log "HATA: indirilemedi: $name"; $failed++; continue }

    # 1) sifreli mi? (OpenSSL "Salted__" basligi)
    $fs = [System.IO.File]::OpenRead($part)
    try { $buf = New-Object byte[] 8; [void]$fs.Read($buf, 0, 8) } finally { $fs.Dispose() }
    if ([System.Text.Encoding]::ASCII.GetString($buf) -ne 'Salted__') {
      Write-Log "HATA: $name sifreli gorunmuyor, SILINDI"; Remove-Item -LiteralPath $part -Force; $failed++; continue
    }
    # 2) sunucudaki SHA-256 ile karsilastir (yalnizca stdout; ilk 64 onaltilik hane)
    $hashLine = (Invoke-Remote "sha256sum $RemoteDir/$name") | Select-Object -First 1
    $remoteHash = ''
    if ("$hashLine" -match '^([0-9a-fA-F]{64})') { $remoteHash = $Matches[1].ToLower() }
    $localHash = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash.ToLower()
    if ($remoteHash -eq '' -or $remoteHash -ne $localHash) {
      Write-Log "HATA: $name ozet uyusmuyor (indirme bozuk veya ozet okunamadi), SILINDI"; Remove-Item -LiteralPath $part -Force; $failed++; continue
    }
    Move-Item -LiteralPath $part -Destination $final
    $pulled++
    Write-Log ("indirildi ve dogrulandi: {0} ({1:N0} bayt)" -f $name, (Get-Item -LiteralPath $final).Length)
  }

  if ($PruneDays -gt 0) {
    $limit = (Get-Date).AddDays(-$PruneDays)
    $newestDoc = Get-ChildItem -LiteralPath $Destination -File | Where-Object { $_.Name -match '^kapi_documents_' } |
      Sort-Object Name -Descending | Select-Object -First 1
    Get-ChildItem -LiteralPath $Destination -File | Where-Object {
      $_.Name -match $namePattern -and $_.Name -notmatch '^kapi_firmware_' -and $_.LastWriteTime -lt $limit -and
      -not ($newestDoc -and $_.Name -eq $newestDoc.Name)
    } | ForEach-Object {
      Write-Log "yerel temizlik ($PruneDays gunden eski): $($_.Name)"; Remove-Item -LiteralPath $_.FullName -Force
    }
  }
}
catch {
  Write-Log ("HATA: " + $_.Exception.Message)
  $failed++
}

if ($failed -gt 0) {
  Set-Content -Path (Join-Path $Destination 'LAST_FAILED.txt') -Value ("{0} hata={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $failed) -Encoding ASCII
  Write-Log "BITTI: $failed hata (indirilen: $pulled)"
  exit 1
}
Remove-Item -LiteralPath (Join-Path $Destination 'LAST_FAILED.txt') -Force -ErrorAction SilentlyContinue
Set-Content -Path (Join-Path $Destination 'LAST_OK.txt') -Value ("{0} indirilen={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $pulled) -Encoding ASCII
Write-Log "BITTI: basarili (yeni indirilen: $pulled)"
exit 0
