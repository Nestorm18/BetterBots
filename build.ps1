# BetterBots - compila el mod y genera el zip
#
# 1. Copia el codigo de Src\BetterBots al SDK (Documentos\...\ROGame\Src\BetterBots)
# 2. Compila con el SDK sin abrir ventanas
# 3. Copia BetterBots.u a Mod\ y genera dist\BetterBots.zip
#
# Uso:  powershell -ExecutionPolicy Bypass -File build.ps1

$ErrorActionPreference = 'Stop'

$Version    = '0.9.0'

$Root       = $PSScriptRoot
$SdkEditor  = 'D:\SteamLibrary\steamapps\common\Rising Storm 2\Binaries\Win64\VNEditor.exe'
$GameUser   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Rising Storm 2\ROGame'
$SdkSrc     = Join-Path $GameUser 'Src\BetterBots'
$BuiltU     = Join-Path $GameUser 'Unpublished\CookedPC\Script\BetterBots.u'
$Log        = Join-Path $GameUser 'Logs\BBMake.log'

# 1. Sync source into the SDK's mod folder
New-Item -ItemType Directory -Force (Join-Path $SdkSrc 'Classes') | Out-Null
Remove-Item (Join-Path $SdkSrc 'Classes\*.uc') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root 'Src\BetterBots\Classes\*.uc') (Join-Path $SdkSrc 'Classes')

# 2. Compile. The editor waits for a key press when done, so watch the log and close it.
if (Test-Path $Log) { Remove-Item $Log }
$p = Start-Process -FilePath $SdkEditor -ArgumentList 'make','-useunpublished','-unattended','-LOG=BBMake.log' `
	-WorkingDirectory (Split-Path $SdkEditor) -WindowStyle Hidden -PassThru
for ($i = 0; $i -lt 300; $i++) {
	Start-Sleep 1
	if ((Test-Path $Log) -and (Select-String -Path $Log -Pattern 'error\(s\)' -Quiet)) { break }
}
Start-Sleep 2
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue

Select-String -Path $Log -Pattern 'Error,|BetterBots.*Warning,|Success -|Failure -' | ForEach-Object { $_.Line }
if (-not (Select-String -Path $Log -Pattern 'Success - 0 error' -Quiet)) {
	Write-Host 'COMPILACION FALLIDA' -ForegroundColor Red
	exit 1
}

# 3. Package
New-Item -ItemType Directory -Force (Join-Path $Root 'Mod') | Out-Null
Copy-Item $BuiltU (Join-Path $Root 'Mod') -Force
$Stage = Join-Path $env:TEMP 'BetterBots_dist'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force "$Stage\Mod", "$Stage\Source" | Out-Null
Copy-Item (Join-Path $Root 'Mod\BetterBots.u') "$Stage\Mod"
Copy-Item (Join-Path $Root 'Src\BetterBots\Classes\*.uc') "$Stage\Source"
Copy-Item (Join-Path $Root 'README.txt'), (Join-Path $Root 'LEEME.txt') $Stage
New-Item -ItemType Directory -Force (Join-Path $Root 'dist') | Out-Null
Compress-Archive -Path "$Stage\*" -DestinationPath (Join-Path $Root 'dist\BetterBots.zip') -Force
# Release asset with the version in the name
Copy-Item (Join-Path $Root 'dist\BetterBots.zip') (Join-Path $Root "dist\BetterBots-v$Version.zip") -Force
Remove-Item $Stage -Recurse -Force

Write-Host "OK: Mod\BetterBots.u, dist\BetterBots.zip y dist\BetterBots-v$Version.zip actualizados" -ForegroundColor Green
