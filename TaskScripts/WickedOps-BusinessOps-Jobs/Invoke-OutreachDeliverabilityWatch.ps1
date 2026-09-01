#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$s=Get-WickedOpsSecrets $ConfigPath;$t=Get-GoogleAccessToken $s
$queries=[ordered]@{Bounces='newer_than:2d (from:mailer-daemon OR from:postmaster OR subject:(undelivered OR delivery failure OR bounced))';Complaints='in:inbox newer_than:2d -category:promotions -category:social ("spam complaint" OR "abuse report")';OptOuts='in:inbox newer_than:2d -category:promotions -category:social -category:updates ("remove me" OR "stop emailing me" OR "take me off" OR "do not contact")'}
$total=0
foreach($q in $queries.GetEnumerator()){$u='https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=100&q='+[uri]::EscapeDataString($q.Value);$r=Invoke-GoogleApi $t $u;$n=[int]($r.resultSizeEstimate);$total+=$n;Write-WickedOpsLog $LogPath "$($q.Key): $n signal(s)." $(if($n){'WARN'}else{'INFO'})}
if($total){
    $message="$total deliverability/suppression signal(s) require review. Check Gmail and update the suppression list before sending more outreach."
    Write-WickedOpsLog $LogPath $message WARN
    $alertScript=Join-Path $PSScriptRoot 'Send-WickedOpsGmailAlert.ps1'
    if(Test-Path -LiteralPath $alertScript){
        try{
            & $alertScript -ConfigPath $ConfigPath -Title 'WickedOps outreach suppression alert' -Message $message -TaskName 'OutreachDeliverabilityWatch'
            Write-WickedOpsLog $LogPath 'Suppression alert delivered to the configured owner.'
        }catch{
            Write-WickedOpsLog $LogPath "Suppression alert delivery failed: $($_.Exception.Message)" WARN
        }
    }
}else{Write-WickedOpsLog $LogPath 'No deliverability or suppression signals require review.'}
