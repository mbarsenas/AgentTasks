#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$root=Get-WickedOpsRoot $ConfigPath;$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$dest=Join-Path $root "Backups\$stamp";New-Item $dest -ItemType Directory -Force|Out-Null
$files=@($ConfigPath,(Join-Path $root 'Invoke-BusinessOpsTask.ps1'))+@(Get-ChildItem (Join-Path $root 'Jobs') -File|Select-Object -Expand FullName)+@(Get-ChildItem (Join-Path $root 'Launchers') -File|Select-Object -Expand FullName)
$manifest=@();foreach($f in $files|Select-Object -Unique){if(Test-Path $f){$target=Join-Path $dest ([IO.Path]::GetFileName($f));Copy-Item $f $target -Force;$manifest+=@{Name=[IO.Path]::GetFileName($f);SHA256=(Get-FileHash $target -Algorithm SHA256).Hash}}}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $dest 'manifest.json') -Encoding utf8;$verify=Get-Content (Join-Path $dest 'manifest.json') -Raw|ConvertFrom-Json;foreach($i in $verify){$actual=(Get-FileHash (Join-Path $dest $i.Name) -Algorithm SHA256).Hash;if($actual-ne$i.SHA256){throw "Backup verification failed for $($i.Name)"}};Write-WickedOpsLog $LogPath "Backup created and verified: $dest ($($manifest.Count) files)."
