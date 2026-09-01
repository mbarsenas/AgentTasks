#requires -Version 7.2
#requires -RunAsAdministrator
[CmdletBinding()]param([string]$BusinessOpsRoot='C:\WickedAdmin\BusinessOps')
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
$jobs=Join-Path $BusinessOpsRoot 'Jobs';$configPath=Join-Path $BusinessOpsRoot 'BusinessOps.config.json';$runner=Join-Path $BusinessOpsRoot 'Invoke-BusinessOpsTask.ps1';$launchers=Join-Path $BusinessOpsRoot 'Launchers'
foreach($p in $jobs,(Join-Path $BusinessOpsRoot 'Reports'),(Join-Path $BusinessOpsRoot 'Backups')){New-Item $p -ItemType Directory -Force|Out-Null}
$map=[ordered]@{DailySalesOutreachReport='Invoke-DailySalesOutreachReport.ps1';OutreachDeliverabilityWatch='Invoke-OutreachDeliverabilityWatch.ps1';WeeklySeoIndexingReport='Invoke-WeeklySeoIndexingReport.ps1';ProspectFollowUpQueue='Invoke-ProspectFollowUpQueue.ps1';WeeklyProductActivityReport='Invoke-WeeklyProductActivityReport.ps1';BackupRecoveryValidation='Invoke-BackupRecoveryValidation.ps1'}
$files=@('WickedOps.Common.psm1','Set-WickedOpsBusinessSecrets.ps1','Authorize-WickedOpsGoogle.ps1','Send-WickedOpsGmailAlert.ps1')+@($map.Values)
foreach($f in $files){$source=Join-Path $PSScriptRoot $f;if(-not(Test-Path $source)){throw "Package file missing: $f"};Copy-Item $source (Join-Path $jobs $f) -Force}
if(-not(Test-Path $configPath)){throw "BusinessOps configuration not found: $configPath"};$cfg=Get-Content $configPath -Raw|ConvertFrom-Json;if(-not $cfg.JobScripts){$cfg|Add-Member NoteProperty JobScripts ([pscustomobject]@{})}
foreach($item in $map.GetEnumerator()){$value=Join-Path $jobs $item.Value;$p=$cfg.JobScripts.PSObject.Properties[$item.Key];if($p){$p.Value=$value}else{$cfg.JobScripts|Add-Member NoteProperty $item.Key $value}}
$cfg|ConvertTo-Json -Depth 12|Set-Content $configPath -Encoding utf8
if(Test-Path $runner){
    $c=Get-Content $runner -Raw
    $c=$c.Replace('if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {','if ((Test-Path variable:LASTEXITCODE) -and $LASTEXITCODE -ne 0) {')
    if($c -notmatch 'Send-WickedOpsGmailAlert\.ps1'){
        $alertFunction=@'
function Send-TaskAlert {
    param([string]$Title, [string]$Message)

    $GmailAlertScript = Join-Path $RootPath 'Jobs\Send-WickedOpsGmailAlert.ps1'
    if (Test-Path -LiteralPath $GmailAlertScript) {
        try {
            & $GmailAlertScript -ConfigPath $ConfigPath -Title $Title -Message $Message -TaskName $TaskName
            Write-TaskLog "Gmail alert delivered to $($script:Config.Alert.EmailTo)."
            return
        }
        catch {
            Write-TaskLog -Level WARN -Message "Gmail alert delivery failed: $($_.Exception.Message)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:Config.Alert.WebhookUrl)) {
        Write-TaskLog -Level WARN -Message "Alert not delivered because no working Gmail or webhook channel is configured: $Title - $Message"
        return
    }

    $Body = @{ title = $Title; message = $Message; task = $TaskName; computer = $env:COMPUTERNAME } |
        ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri $script:Config.Alert.WebhookUrl -ContentType 'application/json' -Body $Body |
        Out-Null
}
'@
        $pattern='(?s)function Send-TaskAlert \{.*?\r?\n\}\r?\n\r?\nif \(-not \(Test-Path -LiteralPath \$ConfigPath\)\)'
        $replacement=$alertFunction+"`r`n`r`nif (-not (Test-Path -LiteralPath `$ConfigPath))"
        $c=[regex]::Replace($c,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m)$replacement},1)
        if($c -notmatch 'Send-WickedOpsGmailAlert\.ps1'){throw 'Could not install Gmail alert support into Invoke-BusinessOpsTask.ps1.'}
    }
    Set-Content $runner $c -Encoding utf8
}
$pwsh='C:\Program Files\PowerShell\7\pwsh.exe';if(-not(Test-Path $pwsh)){throw "Machine-wide PowerShell 7 not found: $pwsh"}
Get-ChildItem $launchers -Filter '*.cmd'|ForEach-Object{$c=Get-Content $_.FullName -Raw;$c=$c-replace '"C:\\Program Files\\WindowsApps\\Microsoft\.PowerShell_[^"]+\\pwsh\.exe"','"C:\Program Files\PowerShell\7\pwsh.exe"';Set-Content $_.FullName $c -Encoding ascii}
$svc="$env:COMPUTERNAME\WickedOpsSvc";& icacls.exe $BusinessOpsRoot /grant:r "${svc}:(OI)(CI)M" /T /C|Out-Null
$secretDir=Join-Path $BusinessOpsRoot 'Secrets';if(Test-Path $secretDir){& icacls.exe $secretDir /inheritance:r|Out-Null;& icacls.exe $secretDir /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' "${svc}:(OI)(CI)RX" /T /C|Out-Null}
Write-Host 'Six BusinessOps job scripts installed and configured.' -ForegroundColor Green
Write-Host 'Immediately usable: Daily report, product activity, backup validation.'
Write-Host 'OAuth setup required: Deliverability, SEO, prospect follow-up.' -ForegroundColor Yellow
Write-Host (Join-Path $jobs 'Set-WickedOpsBusinessSecrets.ps1')
Write-Host 'Recommended guided setup:'
Write-Host (Join-Path $jobs 'Authorize-WickedOpsGoogle.ps1')
