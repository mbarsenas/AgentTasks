#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$s=Get-WickedOpsSecrets $ConfigPath;$t=Get-GoogleAccessToken $s;$q='in:sent older_than:3d newer_than:21d (AgentLedger OR TenantIQ365 OR CommentHarbor)';$u='https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=100&q='+[uri]::EscapeDataString($q);$r=Invoke-GoogleApi $t $u;$queue=@()
foreach($m in @($r.messages)){$msg=Invoke-GoogleApi $t "https://gmail.googleapis.com/gmail/v1/users/me/messages/$($m.id)?format=metadata&metadataHeaders=To&metadataHeaders=Subject";$thread=Invoke-GoogleApi $t "https://gmail.googleapis.com/gmail/v1/users/me/threads/$($m.threadId)?format=metadata";if(@($thread.messages).Count -eq 1){$to=($msg.payload.headers|Where-Object name -eq 'To').value;$subject=($msg.payload.headers|Where-Object name -eq 'Subject').value;$queue+=@{To=$to;Subject=$subject;ThreadId=$m.threadId;Action='Review before follow-up'}}}
$path=Join-Path (Get-WickedOpsRoot $ConfigPath) 'Reports\ProspectFollowUpQueue.json';New-Item (Split-Path $path) -ItemType Directory -Force|Out-Null;$queue|ConvertTo-Json -Depth 5|Set-Content $path -Encoding utf8;Write-WickedOpsLog $LogPath "$($queue.Count) eligible thread(s) queued for human review. No follow-up was sent."
if($queue.Count){
    $items=($queue|Select-Object -First 20|ForEach-Object{"- $($_.To) | $($_.Subject)"}) -join "`n"
    $message=@"
$($queue.Count) prospect thread(s) are ready for human review.

$items

No follow-up email was sent automatically.
Queue file: $path
"@
    & (Join-Path $PSScriptRoot 'Send-WickedOpsGmailAlert.ps1') -ConfigPath $ConfigPath -Title "WickedOps prospect review queue - $($queue.Count) thread(s)" -Message $message -TaskName 'ProspectFollowUpQueue'
    Write-WickedOpsLog $LogPath 'Prospect-review notification emailed to the configured owner.'
}
