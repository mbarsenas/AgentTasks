#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$s=Get-WickedOpsSecrets $ConfigPath;$t=Get-GoogleAccessToken $s
$queries=[ordered]@{Bounces='newer_than:2d (from:mailer-daemon OR from:postmaster OR subject:(undelivered OR failure OR bounced))';Complaints='newer_than:2d ("spam complaint" OR "abuse report")';OptOuts='newer_than:2d (unsubscribe OR "remove me" OR "stop emailing")'}
$total=0
foreach($q in $queries.GetEnumerator()){$u='https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=100&q='+[uri]::EscapeDataString($q.Value);$r=Invoke-GoogleApi $t $u;$n=[int]($r.resultSizeEstimate);$total+=$n;Write-WickedOpsLog $LogPath "$($q.Key): $n signal(s)." $(if($n){'WARN'}else{'INFO'})}
if($total){throw "$total deliverability/suppression signal(s) require review."}
